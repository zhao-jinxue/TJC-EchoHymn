# -*- coding: utf-8 -*-
"""判定歌词行空格宽度（0.25/0.5/1.0 em）与简谱行的对齐关系，看哪个假设让 R≈字号比(1.03)。"""
import sqlite3, statistics, sys, io
sys.stdout = io.TextIOWrapper(open(r'e:\EchoHymn\tools\_fit2_out.txt', 'wb'), encoding='utf-8', errors='replace')

ZERO = set('"\'()*+,-089:<=IKLOP_ik{}~')
BAR = set('\\|?[]/')
PUNCT = set('，。、！？；：（）「」『』《》—…·,.;:!?()')

def score_em_positions(s):
    """音符起始位置（单位：简谱字号 em；数字/延音/小节线=1em，空格=0.5em，零宽=0）"""
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

def lyric_em_positions(l, space_em):
    """字起始位置（单位：歌词字号 em；汉字=1em，空格=space_em）"""
    out, x = [], 0.0
    for ch in l:
        if ch == ' ':
            x += space_em
        elif ch in PUNCT:
            x += 1.0
        else:
            out.append(x)
            x += 1.0
    return out

db = sqlite3.connect('e:/EchoHymn/data/tjc_hymn.db')
db.row_factory = sqlite3.Row
rows = {}
for r in db.execute('SELECT hymn_number, slide_no, pair_no, score_enc, lyric FROM hymn_ppt_line'):
    rows.setdefault((r['hymn_number'], r['slide_no']), []).append((r['pair_no'], r['score_enc'], r['lyric'] or ''))

for space_em in (0.25, 0.5, 1.0):
    ratios = []
    for hn in ['1', '5', '90']:
        for key in sorted(k for k in rows if k[0] == hn):
            for p_sc, sc, lyr in rows[key]:
                if not sc.strip() or not lyr.strip():
                    continue
                npos = score_em_positions(sc)
                spos = lyric_em_positions(lyr, space_em)
                k = min(len(npos), len(spos))
                if k < 4 or len(npos) != len(spos):
                    continue
                xs, ys = spos[:k], npos[:k]
                mx, my = statistics.mean(xs), statistics.mean(ys)
                sxx = sum((x - mx) ** 2 for x in xs)
                if sxx == 0:
                    continue
                R = sum((x - mx) * (y - my) for x, y in zip(xs, ys)) / sxx
                C = my - R * mx
                ratios.append(R)
    if ratios:
        print('space=%.2fem: n=%d R mean=%.3f median=%.3f pstdev=%.3f' %
              (space_em, len(ratios), statistics.mean(ratios), statistics.median(ratios), statistics.pstdev(ratios)))
    else:
        print('space=%.2fem: 无样本' % space_em)
