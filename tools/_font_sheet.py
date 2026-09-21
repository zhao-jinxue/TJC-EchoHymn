# -*- coding: utf-8 -*-
"""简谱字体字形表：每码位两格——单独渲染（空格+字符）与叠加渲染（5+字符）。"""
import fitz, struct

FONT = r'C:\Users\小蔡爱金雪\Downloads\简谱字体\简谱字体.ttf'
data = open(FONT, 'rb').read()
numTables = struct.unpack('>H', data[4:6])[0]
tables = {}
for i in range(numTables):
    off = 12 + 16 * i
    tag = data[off:off+4].decode('latin1')
    toff, tlen = struct.unpack('>II', data[off+8:off+16])
    tables[tag] = (toff, tlen)

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

toff = tables['cmap'][0]
ver, n = struct.unpack('>HH', data[toff:toff+4])
cmap = {}
for i in range(n):
    pid, eid, off = struct.unpack('>HHI', data[toff+4+8*i:toff+12+8*i])
    m = parse_cmap4(data[toff+off:])
    if m: cmap = m
cps = sorted(c for c in cmap if 0x20 <= c <= 0x7E)

# 字宽
hhea_off = tables['hhea'][0]
nhm = struct.unpack('>H', data[hhea_off+34:hhea_off+36])[0]
hm_off = tables['hmtx'][0]
adv = [struct.unpack('>H', data[hm_off+4*i:hm_off+4*i+2])[0] for i in range(nhm)]
zero = set()
for c in cps:
    g = cmap[c]
    if g < len(adv) and adv[g] == 0:
        zero.add(c)

doc = fitz.open()
page = doc.new_page(width=1180, height=1750)
page.insert_font(fontname='jp', fontfile=FONT)
page.insert_font(fontname='h', fontfile=None, fontbuffer=None) if False else None
# 标题用默认字体
COLS = 6
CW, CH = 190, 100
page.draw_rect(fitz.Rect(0, 0, 1180, 30), color=None, fill=(0.93, 0.93, 0.93))
labels = [chr(c) for c in cps]
for idx, c in enumerate(cps):
    col, row = idx % COLS, idx // COLS
    x0, y0 = 10 + col * CW, 34 + row * CH
    page.draw_rect(fitz.Rect(x0, y0, x0 + CW - 6, y0 + CH - 6), color=(0.85, 0.85, 0.85), width=0.5)
    ch = chr(c)
    tag = 'U+%04X %s%s' % (c, repr(ch), ' [0宽]' if c in zero else '')
    page.insert_text((x0 + 6, y0 + 14), tag, fontsize=10, fontname='helv')
    if c in zero:
        page.insert_text((x0 + 16, y0 + 62), '5' + ch, fontsize=34, fontname='jp')
        page.insert_text((x0 + 100, y0 + 62), '3' + ch, fontsize=34, fontname='jp')
    else:
        page.insert_text((x0 + 40, y0 + 62), ch, fontsize=34, fontname='jp')
doc.save(r'e:\EchoHymn\tools\_jpfont_sheet.pdf')
pix = page.get_pixmap(dpi=130)
pix.save(r'e:\EchoHymn\tools\_jpfont_sheet.png')
print('ok cps=', len(cps), 'zero-width=', len(zero), sorted(chr(c) for c in zero))
