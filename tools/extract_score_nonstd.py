# -*- coding: utf-8 -*-
"""非标「简谱」PDF 补录器：把与全库统一生成件不同版式的印刷简谱，还原成库内 `hymn_score*` 数据

## 背景（2026-09-21 取证，详见 docs/sessions/2026-09-21_21-03-18.md 任务 6）

第 349 首（奇妙的耶穌）的简谱 PDF 是官网**后补的上传件**（哈希命名 `score/c4639330….pdf`），
与全库 473 首统一生成的 `score/num/<首号>.pdf` 版式不同：

| 内容 | 全库统一件 | 本首非标件 |
| --- | --- | --- |
| 音符/附点/八度点 | 预合成字形（MMP2005 字体文本层） | **裸字符隐藏文本层**（数字 + `·` 附点 + `•` 八度点） |
| 时值线（减时线） | 字形自带 | **矢量绘制**（0.75pt 高矩形，单/双线各一条） |
| 小节线 | 码位 `602d` | **矢量绘制**（高 21.7pt 直线） |
| 连音弧 | 字形 `5e66`… | **矢量绘制**（贝塞尔曲线，本器不还原） |
| 歌词 | 文本层（標楷體） | **Type3 轮廓字体**（字形码 = Unicode 码位，可直接还原文字） |

主爬虫管线只认 MMP2005 → 抽不到内容 → 该首没有 `hymn_score` 行（全库唯一 1 首）。

## 记号 → 码位对照（2026-09-21 用 App 内置字体逐字形渲染核对）

| 记号 | 码位 | 记号 | 码位 |
| --- | --- | --- | --- |
| 中音 1-7 | `4e52 4e53 4e56 4e58 4e59 4e5c 4e5d` | 低音 1-7 | `4e45 4e47 4e48 4e4b 4e4d 4e4e 4e4f` |
| 中音+单线 | `4ee4 4ee5 4ee8 4ee9 4ef0 4ef1 4ef2` | 低音+单线 | `4eda 4edc 4edd 4ede 4edf 4ee1 4ee3` |
| 中音+双线 | `4f59 4f5a 4f5b 4f5c 4f5d 4f5e 4f5f` | 低音+双线 | `4f52 4f53 4f54 4f55 4f56 4f57 4f58` |
| 高音 1-4 | `4e5e 4e5f 4e69 4e73` | 高音+单线 1-3 | `4ef3 4ef4 4ef5` |
| 附点 | `5d3d` | 小节线 | `602d` |
| 休止 0 / 0+线 | `5d4c` / `5d4e` | 升 / 降（独立 token） | `5d26` / `5d27` |
| 延长 `-` | `5d1f` | 连音弧等纯装饰 | 不还原 |

## 用法

    python tools/extract_score_nonstd.py --hymn 349              # 解析 + 打印结构（不写库）
    python tools/extract_score_nonstd.py --hymn 349 --apply      # 备份数据库后写库
    python tools/extract_score_nonstd.py --hymn 349 --report out.txt
"""
import argparse
import collections
import io
import json
import os
import shutil
import sqlite3
import sys
import unicodedata

import pymupdf

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DB = os.path.join(ROOT, 'data', 'tjc_hymn.db')
DATA = os.path.join(ROOT, 'data')
JP = chr(0x7B80) + chr(0x8C31)          # 简谱（文件名后缀，避免源码出现 CJK 字面量）

DIG = '1234567'
MID = dict(zip(DIG, ['4e52', '4e53', '4e56', '4e58', '4e59', '4e5c', '4e5d']))
LOW = dict(zip(DIG, ['4e45', '4e47', '4e48', '4e4b', '4e4d', '4e4e', '4e4f']))
MID_LINE = dict(zip(DIG, ['4ee4', '4ee5', '4ee8', '4ee9', '4ef0', '4ef1', '4ef2']))
LOW_LINE = dict(zip(DIG, ['4eda', '4edc', '4edd', '4ede', '4edf', '4ee1', '4ee3']))
MID_EQ = dict(zip(DIG, ['4f59', '4f5a', '4f5b', '4f5c', '4f5d', '4f5e', '4f5f']))
LOW_EQ = dict(zip(DIG, ['4f52', '4f53', '4f54', '4f55', '4f56', '4f57', '4f58']))
HIGH = dict(zip('1234', ['4e5e', '4e5f', '4e69', '4e73']))
HIGH_LINE = dict(zip('123', ['4ef3', '4ef4', '4ef5']))
DOT, BAR, REST, REST_LINE = '5d3d', '602d', '5d4c', '5d4e'
SHARP, FLAT, HOLD = '5d26', '5d27', '5d1f'
CH_ACC_DOT = 0x00B7        # 附点（右侧小点）
CH_OCT_DOT = 0x2022        # 八度点（数字上/下方）
CH_SHARP = 0x266F          # ♯
CH_FLAT = 0x266D           # ♭
# CJK 部首补充块（U+2E80–U+2EFF）无 NFKC 映射，按字形语义补表（按实际出现增补）
RADICAL_FIX = {0x2ED1: chr(0x9577), 0x2ED2: chr(0x9577), 0x2EB6: chr(0x9577)}
LOG = io.StringIO()


def fix_char(code, ch):
    """字形码位 -> 规范汉字（康熙部首走 NFKC，部首补充块走补表）"""
    if code in RADICAL_FIX:
        return RADICAL_FIX[code]
    return ch


def log(*a):
    print(*a)
    print(*a, file=LOG)


def dbmap():
    """sym -> 码位（库内 hymn_codepoint_map + 上方核对表，后者优先）"""
    m = {}
    con = sqlite3.connect(DB)
    for cp, sym in con.execute('SELECT codepoint, sym FROM hymn_codepoint_map'):
        m.setdefault(sym, cp)
    con.close()
    for table, sym_tpl in ((MID, '%s'), (LOW, '%s,'), (MID_LINE, '%s_'), (LOW_LINE, '%s,_'),
                           (MID_EQ, '%s='), (LOW_EQ, '%s,='), (HIGH, '%s^'),
                           (HIGH_LINE, '%s^_')):
        for d, cp in table.items():
            m[sym_tpl % d] = cp
    m['.'] = DOT
    m['|'] = BAR
    m['0'] = REST
    m['0_'] = REST_LINE
    m['#'] = SHARP
    m['b'] = FLAT
    m['-'] = HOLD
    return m


def locate_pdf(con, hymn):
    row = con.execute('SELECT numbered_png_path FROM tjc_hymn WHERE hymn_number=?', (hymn,)).fetchone()
    if not row or not row[0]:
        raise SystemExit('hymn %s 没有 numbered_png_path' % hymn)
    p = os.path.join(DATA, row[0][:-4] + '.pdf')
    if not os.path.exists(p):
        raise SystemExit('素材缺失: %s' % p)
    return p


def font_kind(doc):
    """版式判定：标准件必有 MMP2005 字形；非标件是 Type3 轮廓（Type3 在 get_fonts 里名为空，故用文本层扫）"""
    names, has_t3 = set(), False
    for pg in doc:
        for sp in pg.get_texttrace():
            fn = sp.get('font') or ''
            if fn.startswith('Type3'):
                has_t3 = True
            else:
                names.add(fn)
    return {'mmp2005': any('MMP2005' in n for n in names), 'type3': has_t3,
            'fonts': sorted(names)}


def collect_page(page):
    """收集一页的全部记号（按 y 分行：谱行 / 歌词行 / 矢量绘制）"""
    chars, t3 = [], []
    for sp in page.get_texttrace():
        fname = sp.get('font') or ''
        size = round(sp['size'], 2)
        for c in sp['chars']:
            code, ox, oy, bbox = c[0], c[2][0], c[2][1], c[3]
            rec = {'code': code,
                   'ch': fix_char(code, unicodedata.normalize('NFKC', chr(code)))
                   if code < 0x110000 else '',
                   'x': ox, 'y': oy, 'size': size,
                   'bbox': tuple(round(v, 2) for v in bbox)}
            (t3 if fname.startswith('Type3') else chars).append(rec)
    draws = []
    for d in page.get_drawings():
        r = d['rect']
        draws.append({'type': d['type'], 'rect': r, 'w': r.x1 - r.x0, 'h': r.y1 - r.y0,
                      'items': [it[0] for it in d['items']]})
    digit_rows = collections.defaultdict(list)
    for c in chars:
        if '0' <= c['ch'] <= '7' and c['size'] >= 10.4:
            digit_rows[round(c['y'] / 2) * 2].append(c)
    rows = [sorted(grp, key=lambda c: c['x'])
            for _k, grp in sorted(digit_rows.items()) if len(grp) >= 4]
    return chars, t3, draws, rows


def build_system(chars, draws, note_chars):
    """一个谱行 -> 元素序列（音符 + 八度 + 时值线数 + 附点 + 升降 + 小节线）"""
    y = sum(c['y'] for c in note_chars) / len(note_chars)
    els = [{'x': c['x'], 'y': c['y'], 'digit': c['ch'], 'octave': '', 'lines': 0,
            'dot': False, 'acc': '', 'bar': False} for c in note_chars]
    for c in chars:
        if c['code'] == CH_ACC_DOT and abs(c['y'] - y) < 4:
            cand = [e for e in els if 4.5 <= c['x'] - e['x'] <= 12.0]
            if cand:
                min(cand, key=lambda e: c['x'] - e['x'])['dot'] = True
        elif c['code'] == CH_OCT_DOT and abs(c['y'] - y) <= 12:
            cand = sorted(els, key=lambda e: abs(e['x'] - (c['x'] - 2.4)))
            if cand and abs(cand[0]['x'] - (c['x'] - 2.4)) < 4.5:
                cand[0]['octave'] = ',' if c['y'] > y + 3 else ('^' if c['y'] < y - 3 else '')
        elif c['code'] in (CH_SHARP, CH_FLAT, 0x23, 0x62) and abs(c['y'] - y) < 6:
            after = [e for e in els if 0 < e['x'] - c['x'] <= 6]
            if after:
                after[0]['acc'] = '#' if c['code'] in (CH_SHARP, 0x23) else 'b'
    for d in draws:                                  # 时值线（0.75pt 高矩形）
        if d['type'] != 'f' or d['h'] > 2 or not (3 <= d['w'] <= 14):
            continue
        if not (y + 1.5 <= d['rect'].y0 <= y + 12):
            continue
        cand = sorted(els, key=lambda e: abs(e['x'] - d['rect'].x0))
        if cand and abs(cand[0]['x'] - d['rect'].x0) <= 5:
            cand[0]['lines'] += 1
    bars = sorted({round(d['rect'].x0, 1) for d in draws
                   if d['items'] == ['l'] and d['h'] > 14 and abs(d['rect'].y0 - (y - 12)) < 12})
    for bx in bars:
        before = [e for e in els if e['x'] < bx - 0.5]
        if before:
            before[-1]['bar'] = True
    return {'y': y, 'elements': els, 'bars': bars}


def element(sym_map, e):
    """元素 -> (token 码位串, 记号文本, 仅音级的 core 文本)"""
    d = e['digit']
    if d == '0':
        cp = sym_map['0_'] if e['lines'] else sym_map['0']
        sym = '0' + ('_' if e['lines'] else '')
        return cp, sym, '0'
    if e['octave'] == '^':
        tbl = HIGH_LINE if e['lines'] == 1 else HIGH
        if d not in tbl:
            raise SystemExit('高音 音级 %s 无对应码位（本器未覆盖）' % d)
        sym = d + '^' + ('_' if e['lines'] == 1 else ('=' if e['lines'] >= 2 else ''))
        cp = tbl[d] if e['lines'] <= 1 else sym_map.get(sym)
        if not cp:
            raise SystemExit('高音+双线 无对应码位: %s' % sym)
    else:
        low = (e['octave'] == ',')
        n = min(e['lines'], 2)
        tbl = (LOW, LOW_LINE, LOW_EQ) if low else (MID, MID_LINE, MID_EQ)
        cp = tbl[n][d]
        sym = d + (',' if low else '') + ('' if n == 0 else ('_' if n == 1 else '='))
    core = d if e['octave'] != '^' else d + '^'
    toks = []
    if e['acc']:
        toks.append(sym_map[e['acc']])
    toks.append(cp)
    if e['dot']:
        toks.append(sym_map['.'])
    sym = (e['acc'] or '') + sym + ('.' if e['dot'] else '')
    text = (e['acc'] or '') + core + ('.' if e['dot'] else '')
    if e['bar']:
        toks.append(sym_map['|'])
        sym += '|'
        text += '|'
    return '+'.join(toks), sym, text


def lyric_rows(t3):
    """歌词行：Type3 12pt 字形（字形码 = Unicode 码位；康熙部首/兼容表意字经 NFKC 归一）"""
    pts = sorted((c for c in t3 if 11.5 <= c['size'] <= 12.5), key=lambda c: c['y'])
    clusters = []
    for c in pts:
        if clusters and c['y'] - clusters[-1][-1]['y'] <= 3.5:
            clusters[-1].append(c)
        else:
            clusters.append([c])
    out = []
    for grp in clusters:
        grp = sorted(grp, key=lambda c: c['x'])
        text = ''.join(c['ch'] for c in grp if is_text_char(c['code']))
        out.append({'y': sum(c['y'] for c in grp) / len(grp), 'chars': grp, 'text': text})
    return out


def is_text_char(code):
    """歌词字形码位：汉字 / 康熙部首 / 兼容表意 / 全角标点 / ASCII"""
    return (0x3400 <= code <= 0x9FFF or 0x2E80 <= code <= 0x2FDF or 0xF900 <= code <= 0xFAFF
            or 0x3000 <= code <= 0x303F or 0xFF00 <= code <= 0xFFEF or 0x20 <= code <= 0x7E
            or 0xF081 == code)


def norm_text(s):
    """比较用归一化：去空白与标点"""
    out = []
    for ch in s:
        if ch.isspace():
            continue
        if ch in ',.!?;:()[]{}<>-"\'`~':
            continue
        if 0x3000 <= ord(ch) <= 0x303F or 0xFF01 <= ord(ch) <= 0xFF20 or ord(ch) == 0xFF0C:
            continue
        out.append(ch)
    return ''.join(out)


def api_lyrics(con, hymn):
    """官网歌词（api_raw）：正歌各节 + 副歌"""
    raw = con.execute('SELECT api_raw FROM tjc_hymn WHERE hymn_number=?', (hymn,)).fetchone()
    data = json.loads(raw[0]) if raw and raw[0] else {}
    verses = [v['text'] for v in (data.get('lyrics') or [])]
    return verses, (data.get('lyrics_chorus') or '')


def match_line(text, verses, chorus):
    """歌词行 -> 节号（0 = 副歌）"""
    import difflib
    n = norm_text(text)
    best, score = -1, 0.0
    for i, v in enumerate(verses):
        r = difflib.SequenceMatcher(None, n, norm_text(v)).ratio()
        if r > score:
            best, score = i + 1, r
    if chorus:
        r = difflib.SequenceMatcher(None, n, norm_text(chorus)).ratio()
        if r > score:
            best, score = 0, r
    return best, score


def reconcile_row(chars, expect):
    """用官网歌词把字形码位自校正到规范汉字（返回 最终文本, 未对齐字数）

    印刷件里少数汉字用「康熙部首 / CJK 部首补充块」码位呈现（如 ⽇、⻑），
    这里按「该行文本应等于官网歌词的某个连续切片」这一事实做确定性校正。
    """
    picked = [c for c in chars if is_text_char(c['code'])]
    got = ''.join(c['ch'] for c in picked)
    if not got or not expect:
        return got, -1
    if got in expect:
        return got, 0
    n = len(got)
    best_i, best_run = 0, -1
    for i in range(max(1, len(expect) - n + 1)):
        run = sum(1 for a, b in zip(got, expect[i:i + n]) if a == b)
        if run > best_run:
            best_i, best_run = i, run
    if n and best_run >= n * 0.8:
        fixed = expect[best_i:best_i + n]
        for c, ch in zip(picked, fixed):
            c['ch'] = ch
        return fixed, n - best_run
    return got, -1


def assign_chars(chars, els, sym_map):
    """逐字对位：字 -> 元素序号（标点 = -1）"""
    centers = [e['x'] + 3.0 for e in els]
    out = []
    for i, c in enumerate(chars):
        ch = c['ch']
        cx = c['x'] + 6.0
        idx = min(range(len(centers)), key=lambda k: abs(centers[k] - cx)) if centers else -1
        delta = round(cx - centers[idx], 2) if idx >= 0 else 0.0
        is_cjk = 0x3400 <= ord(ch) <= 0x9FFF
        if not is_cjk:
            idx, delta = -1, 0.0
        out.append({'char_no': i + 1, 'syllable': ch, 'note_index': idx,
                    'delta': delta, 'align_ok': 1 if (idx >= 0 and abs(delta) <= 4.5) else 0})
    return out


def extract(con, hymn, verbose=True):
    """解析非标简谱 PDF -> 逐行结构（元素/记号/歌词/逐字对位）"""
    pdf = locate_pdf(con, hymn)
    doc = pymupdf.open(pdf)
    kind = font_kind(doc)
    log('[PDF] %s' % os.path.relpath(pdf, ROOT))
    log('  字体: %s' % kind['fonts'][:8])
    if kind['mmp2005']:
        raise SystemExit('该首是标准件（含 MMP2005），应由主爬虫管线处理；本器只处理非标版式')
    if not kind['type3']:
        raise SystemExit('既无 MMP2005 也无 Type3，版式未知，请人工取证后再扩展本器')
    sym_map = dbmap()
    verses, chorus = api_lyrics(con, hymn)
    log('  官网歌词 %d 节；副歌 %d 字' % (len(verses), len(chorus)))
    lines, pages = [], set()
    for pno, page in enumerate(doc):
        chars, t3, draws, rows = collect_page(page)
        lyrs = lyric_rows(t3)
        pages.add(pno)
        log('[page %d] 谱行 %d；歌词行 %d；矢量 %d' % (pno, len(rows), len(lyrs), len(draws)))
        for si, note_chars in enumerate(rows):
            sys_ = build_system(chars, draws, note_chars)
            y_lo = sys_['y']
            y_hi = rows[si + 1][0]['y'] - 8 if si + 1 < len(rows) else y_lo + 52
            sys_lyrs = [r for r in lyrs if y_lo + 2 < r['y'] < y_hi]
            toks, syms, texts = [], [], []
            for e in sys_['elements']:
                tk, sym, txt = element(sym_map, e)
                toks.append(tk)
                syms.append(sym)
                texts.append(txt)
            entry = {'page': pno, 'y': round(sys_['y'], 2),
                     'x0': round(sys_['elements'][0]['x'], 2),
                     'tokens': toks, 'syms': syms, 'texts': texts, 'lyrics': [], 'chars': []}
            for r in sys_lyrs:
                verse, score = match_line(r['text'], verses, chorus)
                expect = chorus if verse == 0 else (
                    verses[verse - 1] if 1 <= verse <= len(verses) else '')
                fixed, miss = reconcile_row(r['chars'], expect)
                r['text'] = fixed
                r['miss'] = miss
                entry['lyrics'].append({'verse': verse, 'score': round(score, 3),
                                        'text': fixed, 'chars': r['chars'],
                                        'y': round(r['y'], 2)})
            body = [L for L in entry['lyrics'] if L['verse'] != 0]
            pick = min(body, key=lambda L: L['verse']) if body else (
                entry['lyrics'][0] if entry['lyrics'] else None)
            if pick:
                entry['chars'] = assign_chars(pick['chars'], sys_['elements'], sym_map)
                entry['chars_verse'] = pick['verse']
            lines.append(entry)
            if verbose:
                log('  [行 %d] y=%.1f 元素 %d  %s' % (len(lines), sys_['y'], len(toks),
                                                      ' '.join(syms)[:110]))
                for L in entry['lyrics']:
                    log('        歌词(节 %s 相似度 %.2f 未对齐 %s): %s' % (
                        '副歌' if L['verse'] == 0 else L['verse'], L['score'],
                        L.get('miss', '-'), L['text'][:58]))
    doc.close()
    return {'pdf': pdf, 'lines': lines, 'verses': len(verses), 'chorus': chorus,
            'kind': kind, 'page_count': len(pages)}


def plain_text(txt):
    """库内 notes 口径：去八度点/时值线（保留 升降、高音 ^、附点、小节线）"""
    return txt.replace(',', '').replace('_', '').replace('=', '')


def write_db(con, hymn, data, backup=True):
    """写入 hymn_score / hymn_score_line / hymn_score_char / hymn_score_lyric"""
    if backup:
        dst = DB + '.bak-nonstd'
        shutil.copy2(DB, dst)
        log('[备份] %s' % os.path.relpath(dst, ROOT))
    cur = con.cursor()
    for t in ('hymn_score_char', 'hymn_score_lyric', 'hymn_score_line', 'hymn_score'):
        cur.execute('DELETE FROM %s WHERE hymn_number=?' % t, (hymn,))
    lines = data['lines']
    lyric_count = beat_total = syllable_total = 0
    for i, L in enumerate(lines, start=1):
        syl = sum(1 for c in L['chars'] if c['note_index'] >= 0)
        syl_ok = [c['align_ok'] for c in L['chars'] if c['note_index'] >= 0]
        line_ok = 1 if (syl_ok and all(syl_ok)) else 0
        beats = len(L['tokens'])
        cur.execute(
            'INSERT INTO hymn_score_line (hymn_number, line_no, page, phrase_no, part, '
            'is_primary, y, x0, beat_count, notes, notes_core, code_seq, note_count, hold_count, '
            'rest_count, syllable_count, count_delta, align_ok) '
            'VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
            (hymn, i, L['page'], i, 'melody', 1, L['y'], L['x0'], beats,
             ''.join(plain_text(t) for t in L['texts']),
             ''.join(d for t in L['texts'] for d in t if d.isdigit() or d in '^'),
             ' '.join(L['tokens']), len(L['tokens']),
             sum(1 for t in L['tokens'] if t == HOLD),
             sum(1 for s in L['syms'] if s.startswith('0')),
             syl, len(L['tokens']) - syl, line_ok))
        beat_total += beats
        syllable_total += syl
        for c in L['chars']:
            cur.execute(
                'INSERT INTO hymn_score_char (hymn_number, line_no, char_no, syllable, '
                'note_index, note, beat, delta, span, align_ok) VALUES (?,?,?,?,?,?,?,?,?,?)',
                (hymn, i, c['char_no'], c['syllable'], c['note_index'], '', 0, c['delta'], 1,
                 c['align_ok']))
        for L2 in L['lyrics']:
            verse = 1 if L2['verse'] in (0, -1) else L2['verse']
            text = (chr(0xF081) if verse == 1 else '') + L2['text']
            cur.execute(
                'INSERT INTO hymn_score_lyric (hymn_number, line_no, stanza_no, text, '
                'syllable_count, align_ok) VALUES (?,?,?,?,?,?)',
                (hymn, i, verse, text, len(text), 1))
            lyric_count += 1
    cur.execute(
        'INSERT INTO hymn_score (hymn_number, pdf_path, pdf_md5, page_count, phrase_count, '
        'line_count, lyric_count, beat_total, syllable_total, align_ok, review_reason, extractor) '
        'VALUES (?,?,?,?,?,?,?,?,?,?,?,?)',
        (hymn, os.path.relpath(data['pdf'], DATA).replace('\\', '/'), '', data['page_count'],
         len(lines), len(lines), lyric_count, beat_total, syllable_total, 1,
         '非标版式件（Type3 轮廓 + 隐藏文本层）机器补录：单声部；连音弧未还原；时值线由矢量还原',
         'extract_score_nonstd/1.0'))
    con.commit()
    log('[写入] hymn_score 1 行；line %d 行；char %d 行；lyric %d 行'
        % (len(lines), sum(len(L['chars']) for L in lines), lyric_count))


def main():
    ap = argparse.ArgumentParser(description='非标简谱 PDF 补录器（见文件头说明）')
    ap.add_argument('--hymn', default='349', help='诗歌号（默认 349）')
    ap.add_argument('--apply', action='store_true', help='写库（默认只解析并打印）')
    ap.add_argument('--report', default='', help='把解析日志写入指定文件')
    args = ap.parse_args()
    try:
        sys.stdout.reconfigure(errors='replace')      # 楷体部首等罕用字不因控制台编码中断
    except Exception:
        pass
    con = sqlite3.connect(DB)
    data = extract(con, args.hymn)
    if args.apply:
        write_db(con, args.hymn, data)
    if args.report:
        with open(args.report, 'w', encoding='utf-8') as fh:
            fh.write(LOG.getvalue())
        print('[报告] %s' % args.report)
    con.close()


if __name__ == '__main__':
    main()
