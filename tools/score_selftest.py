"""曲谱输出全库自测（程序版简谱 ↔ 印刷 PDF）

方案见 `docs/Windows/SCORE_SELFTEST.md`。三阶段：

  L0  数据级：库内 `code_seq` 码位 ↔ PDF 文本层 MMP2005 字形码位（逐元素），全库
  L1  渲染自检：用与 App **同一份字体 + 同一份度量 + 同一套版式常量**在 Python 侧重绘每行，
      校验「缺字 / 元素无墨迹 / 覆盖元素宽度」（渲染管线的回归护栏）
  L2  版式级：PDF 页 300dpi 栅格化 → 定位该行音符行带 → 反推印刷字号 → 逐元素局部模板匹配，
      输出命中/未命中（候选差异）+ 并排对照图

用法：
  python tools/score_selftest.py --stage l0
  python tools/score_selftest.py --stage l1 --limit 30 --save-images
  python tools/score_selftest.py --stage l2 --limit 5
  python tools/score_selftest.py --stage all --hymn 1,2,111
  --limit N  只跑前 N 首（0/省略=全库）；--hymn a,b,c 指定诗歌号
产出：tools/_selftest/{report_l*.json, summary.md, rows/, diffs/, run.log}
"""
import argparse
import collections
import difflib
import glob
import json
import os
import re
import sqlite3
import sys
import time

import numpy as np
import pymupdf
from fontTools.ttLib import TTFont
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DB = os.path.join(ROOT, 'data', 'tjc_hymn.db')
DATA = os.path.join(ROOT, 'data')
MAT = os.path.join(DATA, 'Hymn_Downloads')
FONT = os.path.join(ROOT, 'hymn_app', 'assets', 'fonts', 'jianpu_mmp2005.ttf')
METRICS_DART = os.path.join(ROOT, 'hymn_app', 'lib', 'data', 'jianpu_metrics.dart')
OUT = os.path.join(ROOT, 'tools', '_selftest')

# 文本层填充符：空格 + 分隔竖线（不入 code_seq，比对前统一过滤）
FILLER = {'0020', '3021'}
# 版式常量（与 score_lyric_view.dart 对齐）
SLOT_EM = 1.0
LYRIC_EM = 0.50
GLYPH_GAP_EM = 0.10


def log(msg):
    print(msg, flush=True)


# ---------------- 共享数据 ----------------

def load_metrics():
    """解析 lib/data/jianpu_metrics.dart（与 App 同源，避免两套度量漂移）"""
    out = {}
    pat = re.compile(r"'([0-9a-f]{4})':\s*\[\s*([0-9.]+),\s*([-0-9.]+),\s*([-0-9.]+),\s*([-0-9.]+)\]")
    with open(METRICS_DART, encoding='utf-8') as fh:
        for m in pat.finditer(fh.read()):
            out[m.group(1)] = tuple(float(x) for x in m.groups()[1:])
    return out


def load_codebook(con):
    """库内 hymn_codepoint_map（App 侧优先用它，种子表兜底）"""
    return {r[0]: r[1] for r in con.execute('SELECT codepoint, sym FROM hymn_codepoint_map')}


def parse_tokens(code_seq, codebook):
    """token → 码位列表；元素解码记号（空串 = 纯装饰/覆盖元素）"""
    out = []
    for tok in (code_seq or '').split():
        cps = tok.split('+')
        sym = ''.join(codebook.get(cp, '') for cp in cps if cp in codebook)
        out.append({'token': tok, 'cps': cps, 'sym': sym, 'overlay': sym == ''})
    return out


def load_rows(con, hymns=None):
    """全部谱行（含 4 声部），按 hymn, line 排序"""
    q = ('SELECT hymn_number, line_no, page, phrase_no, part, is_primary, y, code_seq '
         'FROM hymn_score_line ORDER BY hymn_number, line_no')
    rows = [dict(r) for r in con.execute(q)]
    if hymns:
        rows = [r for r in rows if r['hymn_number'] in hymns]
    return rows


def hymn_pdf(con, hymn):
    q = con.execute('SELECT pdf_path, page_count FROM hymn_score WHERE hymn_number=?', (hymn,))
    r = q.fetchone()
    if r and r[0]:
        p = os.path.join(DATA, r[0].replace('\\', '/'))
        if os.path.exists(p):
            return p, r[1] or 1
    cands = glob.glob(os.path.join(MAT, '*_%s%s' % (hymn, os.sep), '*简谱.pdf'))
    if not cands:
        cands = [p for p in glob.glob(os.path.join(MAT, '*', '*简谱.pdf'))
                 if os.path.basename(p) == '%s_简谱.pdf' % hymn]
    return (cands[0] if cands else None), (r[1] if r else 1) or 1


# ---------------- L0：数据级码位比对 ----------------

def trace_bands(pdf_path):
    """按 y 聚合 MMP2005 字形 → [{y, cps(左→右、已过滤填充符)}]（y 容差 6pt 合并）"""
    doc = pymupdf.open(pdf_path)
    items = []
    for page in doc:
        for sp in page.get_texttrace():
            if 'MMP2005' not in (sp.get('font') or ''):
                continue
            for c in sp['chars']:
                hexs = '%04x' % c[0]
                if hexs in FILLER:
                    continue
                items.append((float(c[2][1]), float(c[2][0]), hexs))
    doc.close()
    items.sort(key=lambda t: (t[0], t[1]))
    bands = []
    for y, x, cp in items:
        if bands and abs(y - bands[-1]['y']) <= 6.0:
            bands[-1]['cps'].append(cp)
            bands[-1]['ys'].append(y)
        else:
            bands.append({'y': y, 'cps': [cp], 'ys': [y]})
    for b in bands:
        b['y'] = sum(b['ys']) / len(b['ys'])
        b.pop('ys', None)
    return bands


def l0_hymn(con, hymn):
    """单首 L0：每行「库内 code_seq 码位序列」vs「PDF 文本层同 y 字形序列」"""
    pdf, _ = hymn_pdf(con, hymn)
    res = {'hymn': hymn, 'pdf': pdf, 'bands': 0, 'rows': []}
    if not pdf:
        res['rows'].append({'line': 0, 'verdict': 'no_pdf'})
        return res
    bands = trace_bands(pdf)
    res['bands'] = len(bands)
    if not bands:
        # 非标版式件（无 MMP2005 文本层，如第 349 首的 Type3 版上传件）→
        # 由 tools/extract_score_nonstd.py 另行补录；L0 不做码位比对（白名单）
        res['rows'].append({'line': 0, 'verdict': 'nonstd_pdf'})
        return res
    for r in load_rows(con, {hymn}):
        exp = [cp for tok in (r['code_seq'] or '').split() for cp in tok.split('+')]
        best, best_ratio = None, -1.0
        for b in bands:
            if abs(b['y'] - r['y']) > 12:
                continue
            ratio = difflib.SequenceMatcher(None, b['cps'], exp).ratio()
            if ratio > best_ratio:
                best, best_ratio = b, ratio
        item = {'line': r['line_no'], 'part': r['part'], 'primary': r['is_primary'],
                'n_exp': len(exp), 'ratio': round(max(best_ratio, 0.0), 4),
                'band_y': (round(best['y'], 2) if best else None)}
        if best is None:
            item['verdict'] = 'band_missing'
        elif best_ratio >= 0.9999:
            item['verdict'] = 'equal'
        else:
            item['verdict'] = 'diff'
            item['band_n'] = len(best['cps'])
            sm = difflib.SequenceMatcher(None, best['cps'], exp)
            for tag, i1, i2, j1, j2 in sm.get_opcodes():
                if tag != 'equal':
                    item['first_diff'] = {'tag': tag, 'at_band': i1, 'at_db': j1,
                                          'band': best['cps'][i1:i2][:6],
                                          'db': exp[j1:j2][:6]}
                    break
        res['rows'].append(item)
    return res


def stage_l0(rows_sel, con, out_dir):
    rep, t0 = {'hymns': []}, time.time()
    seen = sorted({r['hymn_number'] for r in rows_sel})
    counts, notes = collections.Counter(), collections.Counter()
    for i, hn in enumerate(seen, 1):
        r = l0_hymn(con, hn)
        rep['hymns'].append(r)
        for it in r['rows']:
            counts[it['verdict']] += 1
            if it['verdict'] != 'equal' and it.get('primary'):
                notes['melody_' + it['verdict']] += 1
        if i % 50 == 0 or i == len(seen):
            log('  L0 %d/%d 首 %s %.0fs' % (i, len(seen), dict(counts), time.time() - t0))
    rep['counts'] = dict(counts)
    rep['melody_bad'] = dict(notes)
    rep['elapsed_s'] = round(time.time() - t0, 1)
    with open(os.path.join(out_dir, 'report_l0.json'), 'w', encoding='utf-8') as fh:
        json.dump(rep, fh, ensure_ascii=False, indent=1)
    log('L0 完成：%s（%d 首，%.0fs）' % (dict(counts), len(seen), rep['elapsed_s']))
    return rep


# ---------------- 渲染（L1/L2 共用；版式常量与 score_lyric_view.dart 对齐） ----------------

def layout_row(tokens, metrics, size, base_x=0.0):
    """按 App 版式算元素/字形位置：返回 (elements, y_top, y_bot, nslots)"""
    slot = size * SLOT_EM
    out, slot_i = [], 0
    y_top = max([metrics[cp][3] for t in tokens for cp in t['cps'] if cp in metrics] or [0.61])
    y_bot = min([metrics[cp][2] for t in tokens for cp in t['cps'] if cp in metrics] or [0.10])
    for t in tokens:
        gs = [(cp, metrics[cp]) for cp in t['cps'] if cp in metrics]
        anchor = base_x + slot_i * slot
        if not gs:
            if not t['overlay']:
                slot_i += 1
            out.append({'token': t, 'slot': slot_i - (0 if t['overlay'] else 1),
                        'anchor': anchor, 'glyphs': []})
            continue
        ink = sum(g[1][0] for g in gs) + GLYPH_GAP_EM * (len(gs) - 1)
        start = anchor if t['overlay'] else anchor + (slot - ink * size) / 2.0
        glyphs, pen = [], start
        for cp, m in gs:
            glyphs.append((cp, pen - m[1] * size))
            pen += (m[0] + GLYPH_GAP_EM) * size
        out.append({'token': t, 'slot': slot_i, 'anchor': anchor, 'glyphs': glyphs})
        if not t['overlay']:
            slot_i += 1
    return out, y_top, y_bot, slot_i


def element_template(el, metrics, size, margin_em=0.20):
    """把单个非覆盖元素渲染成模板图（黑字白底），返回 (np.bool_ mask, 元素墨迹左边界相对偏移)"""
    if not el['glyphs']:
        return None, 0.0
    w_em = sum(metrics[cp][0] for cp, _ in el['glyphs']) + GLYPH_GAP_EM * (len(el['glyphs']) - 1)
    y_top = max(metrics[cp][3] for cp, _ in el['glyphs'])
    y_bot = min(metrics[cp][2] for cp, _ in el['glyphs'])
    w = int(size * w_em) + 4
    h = int(size * (y_top - y_bot + margin_em * 2)) + 4
    img = Image.new('L', (max(w, 2), max(h, 2)), 255)
    d = ImageDraw.Draw(img)
    font = ImageFont.truetype(FONT, int(round(size)))
    baseline = margin_em * size + y_top * size + 2
    x0 = 2.0
    for cp, _ in el['glyphs']:
        d.text((x0, baseline), chr(int(cp, 16)), font=font, fill=0, anchor='ls')
        x0 += (metrics[cp][0] + GLYPH_GAP_EM) * size
    arr = np.array(img) < 128
    ys, xs = np.nonzero(arr)
    if len(xs) == 0:
        return None, 0.0
    return arr[ys.min():ys.max() + 1, xs.min():xs.max() + 1], float(xs.min())


def render_row_image(tokens, metrics, size, save=None, margin_em=0.20):
    """整行渲染（L1 自检 + 差异对照图用）"""
    layout, y_top, y_bot, nslots = layout_row(tokens, metrics, size)
    h = int(size * (y_top - y_bot + margin_em * 2)) + 4
    w = int(size * SLOT_EM * max(nslots, 1) + size * 0.6) + 4
    img = Image.new('L', (w, h), 255)
    d = ImageDraw.Draw(img)
    font = ImageFont.truetype(FONT, int(round(size)))
    baseline = margin_em * size + y_top * size + 2
    for el in layout:
        for cp, pen_x in el['glyphs']:
            d.text((pen_x + 2, baseline), chr(int(cp, 16)), font=font, fill=0, anchor='ls')
    if save:
        img.save(save)
    return img, layout, y_top, y_bot, nslots


# ---------------- L1：渲染自检 ----------------

def l1_hymn(con, hymn, metrics, codebook, save_images, size=64.0):
    """缺字 / 无墨迹 / 覆盖元素宽度（渲染管线回归护栏）"""
    lyric_lines = {r[0] for r in con.execute(
        'SELECT DISTINCT line_no FROM hymn_score_lyric WHERE hymn_number=?', (hymn,))}
    rows = [r for r in load_rows(con, {hymn})
            if r['is_primary'] == 1 and r['line_no'] in lyric_lines]
    res = {'hymn': hymn, 'rows': []}
    for r in rows:
        tokens = parse_tokens(r['code_seq'], codebook)
        miss = sorted({cp for t in tokens for cp in t['cps'] if cp not in metrics})
        img, layout, _, _, nslots = render_row_image(tokens, metrics, size)
        arr = np.array(img) < 128
        empty = []
        for el in layout:
            if el['token']['overlay'] or not el['glyphs']:
                continue
            x0, x1 = int(el['anchor']), int(el['anchor'] + size * SLOT_EM)
            if not arr[:, max(x0, 0):max(x1, 1)].any():
                empty.append(el['token']['token'])
        ovl_bad = [t['token'] for t in tokens
                   if t['overlay'] and any(cp in metrics for cp in t['cps'])
                   and sum(metrics[cp][0] for cp in t['cps'] if cp in metrics) <= 0.0]
        item = {'line': r['line_no'], 'tokens': len(tokens), 'slots': nslots,
                'missing_cp': miss, 'empty_slots': empty, 'overlay_zero': ovl_bad}
        item['verdict'] = 'ok' if not (miss or empty or ovl_bad) else 'bad'
        if save_images:
            os.makedirs(os.path.join(OUT, 'rows'), exist_ok=True)
            img.save(os.path.join(OUT, 'rows', '%s_%d.png' % (hymn, r['line_no'])))
        res['rows'].append(item)
    return res


def stage_l1(rows_sel, con, metrics, codebook, out_dir, save_images, limit):
    seen = sorted({r['hymn_number'] for r in rows_sel})
    rep, counts, t0 = {'hymns': []}, collections.Counter(), time.time()
    for i, hn in enumerate(seen, 1):
        r = l1_hymn(con, hn, metrics, codebook, save_images)
        rep['hymns'].append(r)
        for it in r['rows']:
            counts[it['verdict']] += 1
        if i % 50 == 0 or i == len(seen):
            log('  L1 %d/%d 首 %s %.0fs' % (i, len(seen), dict(counts), time.time() - t0))
    rep['counts'] = dict(counts)
    rep['elapsed_s'] = round(time.time() - t0, 1)
    with open(os.path.join(out_dir, 'report_l1.json'), 'w', encoding='utf-8') as fh:
        json.dump(rep, fh, ensure_ascii=False, indent=1)
    log('L1 完成：%s（%.0fs）' % (dict(counts), rep['elapsed_s']))
    return rep
