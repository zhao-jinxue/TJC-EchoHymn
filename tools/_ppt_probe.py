# -*- coding: utf-8 -*-
"""PPT 字体编码方案取证：备份库 jianpu 表 + 简谱字体 cmap/字宽 + 001.ppt 文本原子。只读。"""
import sqlite3, struct, sys

BAK = r'e:\EchoHymn\data\tjc_hymn.bak-20260920_204722.db'
FONT = r'C:\Users\小蔡爱金雪\Downloads\简谱字体\简谱字体.ttf'
PPT = r'C:\Users\小蔡爱金雪\Downloads\001.ppt'

print('=== 1) 备份库 jianpu 表 ===')
db = sqlite3.connect(BAK)
tabs = [r[0] for r in db.execute("SELECT name FROM sqlite_master WHERE type='table' AND name LIKE '%jianpu%'")]
print('tables:', tabs)
for t in tabs:
    print('-- schema', t)
    print(db.execute("SELECT sql FROM sqlite_master WHERE name=?", (t,)).fetchone()[0])
if 'hymn_jianpu' in tabs:
    print('-- hymn_jianpu 前3行:')
    for r in db.execute('SELECT * FROM hymn_jianpu LIMIT 3'):
        print('   ', r)
if 'hymn_jianpu_line' in tabs:
    cols = [c[1] for c in db.execute('PRAGMA table_info(hymn_jianpu_line)')]
    print('-- cols:', cols)
    print('-- hymn_jianpu_line 前6行:')
    for r in db.execute('SELECT * FROM hymn_jianpu_line LIMIT 6'):
        print('   ', r)
    print('-- 行数:', db.execute('SELECT COUNT(*), COUNT(DISTINCT hymn_number) FROM hymn_jianpu_line').fetchone())
db.close()

print()
print('=== 2) 简谱字体.ttf cmap/字宽 ===')
data = open(FONT, 'rb').read()
numTables = struct.unpack('>H', data[4:6])[0]
tables = {}
for i in range(numTables):
    off = 12 + 16 * i
    tag = data[off:off+4].decode('latin1')
    toff, tlen = struct.unpack('>II', data[off+8:off+16])
    tables[tag] = (toff, tlen)
print('tables:', sorted(tables))

def parse_cmap4(b):
    segX2 = struct.unpack('>H', b[6:8])[0]
    seg = segX2 // 2
    ends = struct.unpack('>%dH' % seg, b[14:14+segX2])
    so = 16 + segX2
    starts = struct.unpack('>%dH' % seg, b[so:so+segX2])
    do = so + segX2
    deltas = struct.unpack('>%dh' % seg, b[do:do+segX2])
    ro = do + segX2
    ranges = struct.unpack('>%dH' % seg, b[ro:ro+segX2])
    m = {}
    for i in range(seg):
        for c in range(starts[i], ends[i]+1):
            if ranges[i] == 0:
                g = (c + deltas[i]) & 0xFFFF
            else:
                gi = ro + 2*i + ranges[i] + 2*(c - starts[i])
                g = struct.unpack('>H', b[gi:gi+2])[0]
                if g: g = (g + deltas[i]) & 0xFFFF
            if g: m[c] = g
    return m

def parse_cmap12(b):
    n = struct.unpack('>I', b[12:16])[0]
    m = {}
    for i in range(n):
        s, e, sg = struct.unpack('>III', b[16+12*i:28+12*i])
        for c in range(s, e+1): m[c] = sg + (c - s)
    return m

toff = tables['cmap'][0]
ver, n = struct.unpack('>HH', data[toff:toff+4])
cmap = {}
for i in range(n):
    pid, eid, off = struct.unpack('>HHI', data[toff+4+8*i:toff+12+8*i])
    sub = toff + off
    fmt = struct.unpack('>H', data[sub:sub+2])[0]
    m = parse_cmap4(data[sub:]) if fmt == 4 else (parse_cmap12(data[sub:]) if fmt == 12 else {})
    if m: cmap = m
    print('  cmap rec pid=%d eid=%d fmt=%d glyphs=%d' % (pid, eid, fmt, len(m)))
print('  映射码位数:', len(cmap))
# 字宽
head_off = tables['head'][0]
upem = struct.unpack('>H', data[head_off+18:head_off+20])[0]
hhea_off = tables['hhea'][0]
nhm = struct.unpack('>H', data[hhea_off+34:hhea_off+36])[0]
hm_off = tables['hmtx'][0]
adv = []
for i in range(nhm):
    adv.append(struct.unpack('>H', data[hm_off+4*i:hm_off+4*i+2])[0])
print('  upem=%d numHMetrics=%d' % (upem, nhm))
# 输出全部映射 + 字宽
lines = []
for c in sorted(cmap):
    g = cmap[c]
    w = adv[g] if g < len(adv) else adv[-1]
    ch = chr(c)
    lines.append('  U+%04X %r gid=%3d adv=%5d (%.2f em)' % (c, ch, g, w, w/upem))
print('\n'.join(lines))

print()
print('=== 3) 001.ppt 文本原子 ===')
pd = open(PPT, 'rb').read()
i = 0
cnt = 0
while i + 8 <= len(pd):
    verinst, rectype, reclen = struct.unpack('<HHI', pd[i:i+8])
    if rectype in (0x0FA0, 0x0FA8) and reclen < 100000:
        payload = pd[i+8:i+8+reclen]
        txt = payload.decode('utf-16-le', 'replace') if rectype == 0x0FA8 else payload.decode('latin1', 'replace')
        cnt += 1
        print('--- atom#%d type=%04X off=%d len=%d' % (cnt, rectype, i, reclen))
        print(repr(txt))
        i += 8 + reclen
        continue
    i += 1 if (rectype & 0x0FFF) != 0x00F or (verinst & 0xF) != 0xF else 8 + reclen
print('文本原子总数:', cnt)
