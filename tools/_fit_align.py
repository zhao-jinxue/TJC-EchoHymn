# -*- coding: utf-8 -*-
"""拟合 PPT 简谱行与歌词行的对齐模型：note_pos ≈ R * syllable_pos + C ?"""
import sqlite3, statistics, sys, io
sys.stdout = io.TextIOWrapper(open(r'e:\EchoHymn\tools\_fit_out.txt', 'wb'), encoding='utf-8', errors='replace')

ZERO = set('"\'()*+,-089:<=IKLOP_ik{}~')
BAR = set('\\|?[]/')
PUNCT = set('，。、！？；：（）「」『』《》—…·,.;:!?()')
def note_positions(s):
    """音符起始单位位置（不含小节线/延音线/附点/零宽修饰）"""
    out, x = [], 0
    for ch in s:
        if ch == ' ':
            x += 1
        elif ch in ZERO:
            pass
        else:
            if ch not in BAR and ch != '.':
                out.append(x)
            x += 2
    return out
def syl_positions(l):
    """歌词字起始单位位置（去标点；标点不占位）"""
    out, x = [], 0
    for ch in l:
        if ch == ' ':
            x += 1
        elif ord(ch) in (0x3000,):
            x += 2
        else:
            if ord(ch) > 0x2000 and ch in PUNCT:
                pass
            else:
                if ch not in PUNCT:
                    out.append(x)
                x += 2 if ord(ch) > 0x2000 else 1
    return out

db = sqlite3.connect('e:/EchoHymn/data/tjc_hymn.db')
db.row_factory = sqlite3.Row
rows = {}
for r in db.execute('SELECT hymn_number, slide_no, pair_no, score_enc, lyric FROM hymn_ppt_line'):
    rows.setdefault((r['hymn_number'], r['slide_no']), []).append((r['pair_no'], r['score_enc'], r['lyric'] or ''))

ratios = []
per_pair = []
for hn in ['1', '12', '5', '90']:
    print('=== hymn', hn)
    for key in sorted(k for k in rows if k[0] == hn):
        pairs = rows[key]
        for p_sc, sc, lyr in pairs:
            if not sc.strip() or not lyr.strip():
                continue
            np_ = note_positions(sc)
            sp = syl_positions(lyr)
            k = min(len(np_), len(sp))
            if k < 3:
                continue
            # 最小二乘 R, C
            xs, ys = sp[:k], np_[:k]
            mx, my = statistics.mean(xs), statistics.mean(ys)
            sxx = sum((x - mx) ** 2 for x in xs)
            if sxx == 0:
                continue
            R = sum((x - mx) * (y - my) for x, y in zip(xs, ys)) / sxx
            C = my - R * mx
            ratios.append(R)
            per_pair.append((hn, key[1], p_sc, R, C, len(np_), len(sp)))
            print('  s%d p%d notes=%2d syls=%2d R=%.2f C=%+5.2f | %s | %s' %
                  (key[1], p_sc, len(np_), len(sp), R, C, sc[:38], lyr.strip()[:20]))
print()
print('R 统计: n=%d mean=%.3f median=%.3f stdev=%.3f min=%.2f max=%.2f' %
      (len(ratios), statistics.mean(ratios), statistics.median(ratios),
       statistics.pstdev(ratios), min(ratios), max(ratios)))
