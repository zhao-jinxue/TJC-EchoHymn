# -*- coding: utf-8 -*-
"""歌词字体.ttf name 表 + cmap 覆盖检查"""
import struct
FONT = r'C:\Users\小蔡爱金雪\Downloads\简谱字体\歌词字体.ttf'
data = open(FONT, 'rb').read()
numTables = struct.unpack('>H', data[4:6])[0]
tables = {}
for i in range(numTables):
    off = 12 + 16 * i
    tag = data[off:off+4].decode('latin1')
    toff, tlen = struct.unpack('>II', data[off+8:off+16])
    tables[tag] = (toff, tlen)
no = tables['name'][0]
cnt, stroff = struct.unpack('>HH', data[no+2:no+6])
for i in range(cnt):
    e = no + 6 + 12 * i
    pid, eid, lid, nid, ln, off = struct.unpack('>HHHHHH', data[e:e+12])
    if nid in (1, 2, 4, 6) and pid in (0, 1, 3):
        raw = data[no+stroff+off:no+stroff+off+ln]
        try:
            s = raw.decode('utf-16-be') if pid in (0, 3) else raw.decode('latin1')
        except Exception:
            s = repr(raw[:40])
        print('nameID=%d pid=%d: %s' % (nid, pid, s))
# cmap 码位数
toff = tables['cmap'][0]
ver, n = struct.unpack('>HH', data[toff:toff+4])
info = []
for i in range(n):
    pid, eid, off = struct.unpack('>HHI', data[toff+4+8*i:toff+12+8*i])
    fmt = struct.unpack('>H', data[toff+off:toff+off+2])[0]
    info.append((pid, eid, fmt))
print('cmap recs:', info)
# 检查关键汉字是否在 cmap（颂赞独一真神）
def cmap4(b):
    segX2 = struct.unpack('>H', b[6:8])[0]; seg = segX2//2
    ends = struct.unpack('>%dH' % seg, b[14:14+segX2])
    so = 16+segX2; starts = struct.unpack('>%dH' % seg, b[so:so+segX2])
    do = so+segX2; deltas = struct.unpack('>%dh' % seg, b[do:do+segX2])
    ro = do+segX2; ranges = struct.unpack('>%dH' % seg, b[ro:ro+segX2])
    m = {}
    for i in range(seg):
        for c in range(starts[i], ends[i]+1):
            if ranges[i] == 0: g = (c+deltas[i]) & 0xFFFF
            else:
                gi = ro+2*i+ranges[i]+2*(c-starts[i])
                g = struct.unpack('>H', b[gi:gi+2])[0]
                if g: g = (g+deltas[i]) & 0xFFFF
            if g: m[c] = g
    return m
def cmap12(b):
    n2 = struct.unpack('>I', b[12:16])[0]; m = {}
    for i in range(n2):
        s, e, sg = struct.unpack('>III', b[16+12*i:28+12*i])
        for c in range(s, e+1): m[c] = sg+(c-s)
    return m
allm = {}
for pid, eid, off in info:
    sub = toff+off
    fmt = struct.unpack('>H', data[sub:sub+2])[0]
    m = cmap4(data[sub:]) if fmt == 4 else (cmap12(data[sub:]) if fmt == 12 else {})
    if len(m) > len(allm): allm = m
print('总码位:', len(allm))
for ch in '颂讚獨一真神詩歌哈利路亞':
    print('  %s U+%04X: %s' % (ch, ord(ch), '有' if ord(ch) in allm else '无'))
