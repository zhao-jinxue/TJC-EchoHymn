# -*- coding: utf-8 -*-
"""为 Dart 测试计算 em 宽度期望值（规则与 hymn_ppt.dart 一致）"""
ZERO = set('"\'()*+,-089:<=IKLOP_ik{}~')
def wide(r):
    return (0x1100 <= r <= 0x115F) or r in (0x2329, 0x232A) or \
           (0x2E80 <= r <= 0xA4CF and r != 0x303F) or (0x3000 <= r <= 0x303E) or \
           (0xAC00 <= r <= 0xD7A3) or (0xF900 <= r <= 0xFAFF) or \
           (0xFE30 <= r <= 0xFE6F) or (0xFF00 <= r <= 0xFF60) or (0xFFE0 <= r <= 0xFFE6)
def score_em(s):
    e = 0.0
    for ch in s:
        if ch == ' ':
            e += 0.5
        elif ch not in ZERO:
            e += 1.0
    return e
def lyric_em(s):
    return sum(1.0 if wide(ord(ch)) else 0.5 for ch in s)

cases = [
    ("1  1    3  3 \\ 5/5/\\6/6  6\\5/3/\\", "  圣哉，圣哉，圣哉，全能大主宰！"),
    ("   5.t    5  5 \\ !/7  5\\2    5  6.t\\5///\\", " 天上、地下、海中万物，颂主高名；"),
    ("          !/5  5\\6/3/\\4  2  2.q\\1///|     ", "独一的真神，应当受赞美。"),
    ("  tiyi \\ 1  1  1  eq \\ 68  yiojk   yiti", "耶  稣尊名入  我耳  中，"),
    ("", "  (副歌)"),
    ("5///|", None),
]
for sc, ly in cases:
    print('scoreEm=%.1f lyricEm=%.1f | %r | %r' %
          (score_em(sc), lyric_em(ly) if ly else 0.0, sc[:40], (ly or '')[:20]))
