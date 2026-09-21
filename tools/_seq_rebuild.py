# 临时：任务② 完整记号 code_seq 重建 v2（校准任务，勿提交）
# 用法: python _seq_rebuild.py [--apply] [hymn...|--all]
# 策略：增量插入——旧 code_seq（已视觉验证的音符主流程）为骨架，
# 从 PDF 字符流（texttrace，行基线 origin=row.y+8.7）提取白名单外记号插入：
#   | 小节线（附前一元素）  . 附点(5d3d系)  , 低音点(5d39系,dy∈[1,8]消歧)
#   _ 时值单线(5d49系)  = 时值双线(5e6b)
#   数字+线组合字形(5e66-5e6f) 作为新音符头插入
# 字母别名码位(t/y/e/j/a/g/h/d/s…)一律不动（旧口径已验证）。
# code_seq 元素 = '+' 连接多码位（旧数据无 '+'，向后兼容）。
import os, sys, re, bisect, sqlite3, collections, shutil, datetime
import fitz
sys.path.insert(0, r'e:\EchoHymn\tools')
import _rebuild_dryrun as RD
from _rebuild_dryrun import DB

ALIAS = {}
for _i, _d in enumerate('1234567'):
    ALIAS['qwertyu'[_i]] = f'{_d}-'
    ALIAS['QWERTYU'[_i]] = f'{_d}^-'
    ALIAS['adfghjs'[_i]] = f'{_d}^---'
    ALIAS['ADFGHJS'[_i]] = f'{_d}^---'

def norm_sym(s):
    return ALIAS.get(s, s)

MODCP = {'5d3d': 'D', '5e60': 'D', '5e63': 'D',
         '5d39': 'L', '5e61': 'L', '5e62': 'L',
         '5d49': 'U', '5e6c': 'U', '5e6b': 'W'}
MODSYM = {'D': '.', 'L': ',', 'U': '_', 'W': '='}
NEWHEAD = {'5e66': '6_', '5e67': '1_', '5e68': '3_', '5e69': '5_', '5e6a': '2_',
           '5e6d': '5_', '5e6e': '4_', '5e6f': '4_'}
BAR = {'602d', '4edc', '5d3a', '5e28', '601d', '6032', '6047'}
DROP = {'600b', '601a', '602a', '600c', '601b', '602f',
        '4ed7', '4ed8', '4f4f', '4f50', '3021', '0020',
        '5e5b', '5e5c', '5e5d', '5e5f', '5c6f', '5e80', '5d4a'}

FULLMAP = dict(RD.SEED)
FULLMAP.update(RD.DBMAP)

def oldsym(cp):
    """旧口径元素符号（与库内 notes 一致）"""
    s = FULLMAP.get(cp)
    if s is None:
        return None
    return norm_sym(s)

def extract(doc, pno, y):
    """返回 (heads, newheads, marks, bars)，均按 x 排序。
    heads=旧白名单音符头（含延音线/升降）；newheads=数字+线组合字形。"""
    base = y + 8.7
    heads, newheads, marks, bars = [], [], [], []
    for sp in doc[pno].get_texttrace():
        if 'MMP' not in sp['font']:
            continue
        for uni, glyph, origin, bb in sp['chars']:
            cp = '%04x' % uni
            x = (bb[0] + bb[2]) / 2
            dy = origin[1] - base
            if cp in DROP:
                continue
            if cp in BAR:
                if 0 <= dy <= 6:   # 女高行小节线 origin 比音符基线低 ~4pt（墨迹顶对齐）
                    bars.append(x)
                continue
            if cp in MODCP:
                m = MODCP[cp]
                if m == 'D' and abs(dy) <= 3:
                    marks.append((x, m))
                elif m in ('U', 'W') and 1 <= dy <= 8:
                    marks.append((x, m))
                continue
            if cp in NEWHEAD:
                if abs(dy) <= 3:
                    newheads.append((x, cp))
                continue
            s = oldsym(cp)
            if s is None or s == '?':
                if '-x-' in sys.argv and abs(dy) <= 8:
                    print(f'    UNK {cp} x={x:.0f} dy={dy:+.1f} sym={RD.DBMAP.get(cp)}')
                continue
            if abs(dy) <= 3:
                heads.append((x, cp))
    for lst in (heads, newheads, marks):
        lst.sort(key=lambda c: c[0])
    bars.sort()
    return heads, newheads, marks, bars

def merge_line(old_cps, heads, newheads, marks, bars):
    """旧 seq + 新记号 → 新元素列表 [{'cps':[], 'x':float}]；不齐返回 None"""
    if len(heads) != len(old_cps):
        return None
    elems = [{'cps': [cp], 'x': h[0]} for cp, h in zip(old_cps, heads)]
    for x, cp in newheads:
        pos = bisect.bisect_left([e['x'] for e in elems], x)
        elems.insert(pos, {'cps': [cp], 'x': x})
    # marks：挂 x 最近的「音符头」元素（延音线列不挂 . ,）
    for x, m in marks:
        best, bd = None, 1e9
        for e in elems:
            s = oldsym(e['cps'][0]) or NEWHEAD.get(e['cps'][0], '')
            if m in ('D', 'L') and (s.startswith('-') or s.startswith('#') or s.startswith('b')):
                continue
            d = abs(e['x'] - x)
            if d < bd:
                best, bd = e, d
        if best is not None and bd < 12:
            best.setdefault('mods', []).append(m)
    # bars：挂到 bar 左侧最后一个元素
    for x in bars:
        pos = bisect.bisect_left([e['x'] for e in elems], x) - 1
        if pos >= 0:
            elems[pos].setdefault('bar', True)
    # 生成 seq/notes/onsets
    seq, notes, onsets = [], [], []
    m2cp = {'D': '5d3d', 'L': '5d39', 'U': '5d49', 'W': '5e6b'}
    for i, e in enumerate(elems):
        s0 = oldsym(e['cps'][0]) or NEWHEAD[e['cps'][0]]
        sym = s0 + ''.join(MODSYM[m] for m in e.get('mods', []))
        if e.get('bar'):
            sym += '|'
        cps = list(e['cps'])
        for m in e.get('mods', []):
            cps.append(m2cp[m])
        if e.get('bar'):
            cps.append('602d')
        seq.append('+'.join(cps))
        notes.append(sym)
        if not s0.startswith('-'):
            onsets.append(i)
    return seq, notes, onsets, elems

APPLY = '--apply' in sys.argv
if '--all' in sys.argv:
    hns = [r[0] for r in DB.execute(
        'SELECT hymn_number FROM hymn_score ORDER BY LENGTH(hymn_number), hymn_number')]
else:
    hns = [a for a in sys.argv[1:] if not a.startswith('-')]
DBPATH = r'e:\EchoHymn\data\tjc_hymn.db'

def is_cjk(ch):
    return '\u4e00' <= ch <= '\u9fff'

def page_lyric_cjk(doc, pno, y_ref):
    """该谱行下方第一条歌词行的汉字 [(x, ch)]"""
    spans = []
    for blk in doc[pno].get_text('rawdict')['blocks']:
        for ln in blk.get('lines', []):
            for sp in ln['spans']:
                if 'MMP' in sp['font']:
                    continue
                for ch in sp['chars']:
                    c0 = ch['c']
                    if not c0.strip() or '\ue000' <= c0 <= '\uf8ff' or c0 in '①②⑤⑥⑧⑨⑩⑫⑬⑭⑯⑰⑱⑳':
                        continue
                    bb = ch['bbox']
                    cy = (bb[1] + bb[3]) / 2
                    if y_ref + 5 < cy < y_ref + 110:
                        spans.append((cy, (bb[0] + bb[2]) / 2, c0))
    if not spans:
        return None
    spans.sort(key=lambda s: s[0])
    row_y = spans[0][0]
    row = sorted([s for s in spans if abs(s[0] - row_y) < 4], key=lambda s: s[1])
    return [(x, c) for _, x, c in row if is_cjk(c)]

def align_cols(onset_cols, syll):
    idxs, last = [], -1
    for x, ch in syll:
        best, bd, nlast = None, 1e9, last
        for k in range(last + 1, len(onset_cols)):
            ci, ex = onset_cols[k]
            d = abs(ex - x)
            if d < bd:
                best, bd, nlast = ci, d, k
        if best is None:
            return None
        idxs.append(best)
        last = nlast
    return idxs

STAT = collections.Counter()

def process(hn, cur, wconn):
    row0 = DB.execute('SELECT pdf_path FROM hymn_score WHERE hymn_number=?', (hn,)).fetchone()
    if not row0:
        return
    doc = fitz.open(os.path.join(r'e:\EchoHymn\data', row0['pdf_path']))
    prim = [dict(r) for r in DB.execute(
        'SELECT line_no, page, y, code_seq, notes FROM hymn_score_line WHERE hymn_number=? AND is_primary=1', (hn,))]
    if not prim:
        doc.close()
        return
    cur.execute('BEGIN')
    for p in prim:
        old_cps = (p['code_seq'] or '').split()
        if not old_cps:
            STAT['noseq'] += 1
            continue
        heads, newheads, marks, bars = extract(doc, p['page'], p['y'])
        merged = merge_line(old_cps, heads, newheads, marks, bars)
        if merged is None:
            STAT['headsmis'] += 1
            if '-x-' in sys.argv:
                print(f'  MIS L{p["line_no"]}: old={len(old_cps)} heads={len(heads)} new={len(newheads)}')
                print('    old :', ' '.join(old_cps))
                print('    head:', ' '.join(cp for _, cp in heads))
            continue
        seq, notes, onsets, elems = merged
        notes_str = ''.join(notes)
        chars = [dict(r) for r in cur.execute(
            'SELECT char_no, syllable FROM hymn_score_char WHERE hymn_number=? AND line_no=? ORDER BY char_no',
            (hn, p['line_no'])).fetchall()]
        cjk = [c for c in chars if is_cjk(c['syllable'][0:1])]
        onset_cols = [(i, elems[i]['x']) for i in onsets]
        newidx = None
        if cjk:
            syll = page_lyric_cjk(doc, p['page'], p['y'])
            if syll and len(syll) == len(cjk):
                newidx = align_cols(onset_cols, syll)
            if newidx is None:
                STAT['nolyr'] += 1
                continue
        core = re.sub(r'[._|=b#\-\s]', '', notes_str)
        nc = len(onsets)
        hc = sum(1 for i, e in enumerate(elems) if (oldsym(e['cps'][0]) or '').startswith('-'))
        STAT['rebuilt'] += 1
        if not APPLY:
            print(f'  L{p["line_no"]:3d} {notes_str[:70]}')
        else:
            cur.execute('UPDATE hymn_score_line SET code_seq=?, notes=?, notes_core=?, note_count=?, hold_count=? '
                        'WHERE hymn_number=? AND line_no=?',
                        (' '.join(seq), notes_str, core, nc, hc, hn, p['line_no']))
            k = 0
            for c in chars:
                if is_cjk(c['syllable'][0:1]):
                    ni = newidx[k] if k < len(newidx) else -1
                    k += 1
                    elem = notes[ni] if ni >= 0 else ''
                else:
                    ni, elem = -1, ''
                cur.execute('UPDATE hymn_score_char SET note_index=?, note=?, align_ok=? '
                            'WHERE hymn_number=? AND line_no=? AND char_no=?',
                            (ni, elem, 1 if ni >= 0 else 0, hn, p['line_no'], c['char_no']))
    if APPLY:
        wconn.commit()
    else:
        cur.execute('ROLLBACK')
    doc.close()

if __name__ == '__main__':
    if APPLY:
        ts = datetime.datetime.now().strftime('%Y%m%d_%H%M%S')
        bak = DBPATH.replace('.db', f'.bak-{ts}-pre-seq.db')
        shutil.copy2(DBPATH, bak)
        print('backup ->', bak)
        wconn = sqlite3.connect(DBPATH)
    else:
        wconn = DB
    wconn.row_factory = sqlite3.Row
    cur = wconn.cursor()
    if APPLY:
        MAPROWS = [('5d3d', '.'), ('5e60', '.'), ('5e63', '.'),
                   ('5d39', ','), ('5e61', ','), ('5e62', ','),
                   ('5d49', '_'), ('5e6c', '_'), ('5e6b', '='),
                   ('5e66', '6_'), ('5e67', '1_'), ('5e68', '3_'), ('5e69', '5_'),
                   ('5e6a', '2_'), ('5e6d', '5_'), ('5e6e', '4_'), ('5e6f', '4_'),
                   ('4edc', '|'), ('5d3a', '|'), ('5e28', '|'), ('601d', '|'),
                   ('6032', '|'), ('6047', '|'), ('602d', '|')]
        for cp, s in MAPROWS:
            cur.execute('INSERT OR REPLACE INTO hymn_codepoint_map (codepoint,sym,font,votes,total,source) VALUES (?,?,?,?,?,?)',
                        (cp, s, 'MMP2005', 0, 0, 'glyph-20260920'))
        wconn.commit()
    print('MODE =', 'APPLY' if APPLY else 'DRY', 'songs =', len(hns))
    for hn in hns:
        process(hn, cur, wconn)
    print(dict(STAT))

