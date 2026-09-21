# -*- coding: utf-8 -*-
"""验算第 1 首的网格单位数（与 Dart hymn_ppt.dart 同规则），用于写测试断言。"""
import sqlite3
ZERO = set('"\'()*+,-089:<=IKLOP_ik{}~')
def wide(r):
    return (0x1100 <= r <= 0x115F) or r in (0x2329, 0x232A) or \
           (0x2E80 <= r <= 0xA4CF and r != 0x303F) or (0x3000 <= r <= 0x303E) or \
           (0xAC00 <= r <= 0xD7A3) or (0xF900 <= r <= 0xFAFF) or \
           (0xFE30 <= r <= 0xFE6F) or (0xFF00 <= r <= 0xFF60) or (0xFFE0 <= r <= 0xFFE6)
def score_units(s):
    u = 0
    for ch in s:
        if ch == ' ':
            u += 1
        elif ch in ZERO:
            pass
        else:
            u += 2
    return u
def lyric_units(s):
    u = 0
    for ch in s:
        u += 1 if ch == ' ' else (2 if wide(ord(ch)) else 1)
    return u

db = sqlite3.connect('e:/EchoHymn/data/tjc_hymn.db')
db.row_factory = sqlite3.Row
for hn, sn in [('1', 1), ('1', 3), ('12', 1)]:
    print('=== hymn %s slide %s' % (hn, sn))
    for r in db.execute('SELECT pair_no, score_enc, lyric FROM hymn_ppt_line WHERE hymn_number=? AND slide_no=? ORDER BY pair_no', (hn, sn)):
        s, l = r['score_enc'], r['lyric'] or ''
        print('  p%d su=%3d lu=%3d | %s | %s' % (r['pair_no'], score_units(s), lyric_units(l), s[:56], l[:40]))
# 位置校验：第 1 音（去前导空格后第一个非空格字符）的列 vs 歌词第一个非空格字符列
print('=== 首音列位 vs 首字列位（第 1 首）')
rows = list(db.execute("SELECT pair_no, score_enc, lyric FROM hymn_ppt_line WHERE hymn_number='1' AND slide_no=1 ORDER BY pair_no"))
for i in range(0, len(rows), 2):
    s = rows[i]['score_enc']
    l = (rows[i]['lyric'] or '') if i < len(rows) else ''
    if i + 1 < len(rows):
        l = rows[i + 1]['lyric'] or ''
    su = score_units(s[:len(s) - len(s.lstrip(' '))])
    lu = lyric_units(l[:len(l) - len(l.lstrip(' '))])
    print('  scoreLead=%d lyricLead=%d' % (su, lu))
