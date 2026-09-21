# -*- coding: utf-8 -*-
"""判定 PPT 两行的水平定位模型：左对齐(offset=0) vs 同一文本框内居中。"""
import sqlite3, statistics, sys, io
sys.stdout = io.TextIOWrapper(open(r'e:\EchoHymn\tools\_pos_out.txt', 'wb'), encoding='utf-8', errors='replace')

ZERO = set('"\'()*+,-089:<=IKLOP_ik{}~')
BAR = set('\\|?[]/')
PUNCT = set('，。、！？；：（）「」『』《》—…·,.;:!?()')

def score_em(s):
    e = 0.0
    for ch in s:
        if ch == ' ':
            e += 0.5
        elif ch not in ZERO:
            e += 1.0
    return e

def score_notes(s):
    out, x = [], 0.0
    for ch in s:
        if ch == ' ':
            x += 0.5
        elif ch in ZERO:
            pass
        else:
            if ch not in BAR and ch != '.':
                out.append(x)
            x += 1.0
    return out

def lyric_em(s):
    return sum(0.5 if ord(ch) < 0x2E80 or ord(ch) in (0x303F,) else 1.0 for ch in s)

def lyric_syls(s):
    out, x = [], 0.0
    for ch in s:
        w = 0.5 if ord(ch) < 0x2E80 else 1.0
        if ch in PUNCT:
            x += w
        else:
            out.append(x)
            x += w
    return out

db = sqlite3.connect('e:/EchoHymn/data/tjc_hymn.db')
db.row_factory = sqlite3.Row
left_res, cen_res, diff = [], [], []
for r in db.execute('SELECT score_enc, lyric FROM hymn_ppt_line'):
    sc, ly = r['score_enc'], r['lyric'] or ''
    if not sc.strip() or not ly.strip():
        continue
    a, b = score_notes(sc), lyric_syls(ly)
    if len(a) != len(b) or len(a) < 4:
        continue
    Sc, L = score_em(sc), lyric_em(ly)
    # 模型 1：左对齐 → note = 2*syl
    left_res += [y - 2.0 * x for x, y in zip(b, a)]
    # 模型 2：同一框内居中 → note = 2*syl + Sc/2 - L
    off = Sc / 2.0 - L
    cen_res += [y - 2.0 * x - off for x, y in zip(b, a)]
print('样本:', len(left_res))
print('左对齐残差: mean=%+.2f pstdev=%.2f' % (statistics.mean(left_res), statistics.pstdev(left_res)))
print('居中  残差: mean=%+.2f pstdev=%.2f' % (statistics.mean(cen_res), statistics.pstdev(cen_res)))
