# -*- coding: utf-8 -*-
"""全库拟合：简谱行与歌词行的字号比 R（em 位置模型，含残差评估）。"""
import sqlite3, statistics, sys, io
sys.stdout = io.TextIOWrapper(open(r'e:\EchoHymn\tools\_fit3_out.txt', 'wb'), encoding='utf-8', errors='replace')

ZERO = set('"\'()*+,-089:<=IKLOP_ik{}~')
BAR = set('\\|?[]/')
PUNCT = set('，。、！？；：（）「」『』《》—…·,.;:!?()')

def score_em(s):
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

def lyric_em(l):
    out, x = [], 0.0
    for ch in l:
        if ch == ' ':
            x += 0.5
        elif ch in PUNCT:
            x += 1.0
        else:
            out.append(x)
            x += 1.0
    return out

db = sqlite3.connect('e:/EchoHymn/data/tjc_hymn.db')
db.row_factory = sqlite3.Row
rs, res2 = [], []
per_hymn = {}
for r in db.execute('SELECT hymn_number, score_enc, lyric FROM hymn_ppt_line'):
    sc, lyr = r['score_enc'], r['lyric'] or ''
    if not sc.strip() or not lyr.strip():
        continue
    a, b = score_em(sc), lyric_em(lyr)
    if len(a) != len(b) or len(a) < 4:
        continue
    mx, my = statistics.mean(b), statistics.mean(a)
    sxx = sum((x - mx) ** 2 for x in b)
    if sxx == 0:
        continue
    R = sum((x - mx) * (y - my) for x, y in zip(b, a)) / sxx
    rs.append(R)
    per_hymn.setdefault(r['hymn_number'], []).append(R)
    # 以 R=2.0 预测每个字的位置，残差（单位：歌词 em）
    res = [y - 2.0 * x for x, y in zip(b, a)]
    res2.append(statistics.mean(res))
print('样本数:', len(rs))
print('R: mean=%.3f median=%.3f pstdev=%.3f  p10=%.2f p90=%.2f' %
      (statistics.mean(rs), statistics.median(rs), statistics.pstdev(rs),
       sorted(rs)[len(rs)//10], sorted(rs)[len(rs)*9//10]))
med = [statistics.median(v) for v in per_hymn.values() if len(v) >= 3]
print('各首中位 R: n=%d median-of-medians=%.3f pstdev=%.3f' %
      (len(med), statistics.median(med), statistics.pstdev(med)))
print('R=2.0 时每行整体偏移(歌词em) 分布: mean=%.2f pstdev=%.2f' %
      (statistics.mean(res2), statistics.pstdev(res2)))
