# -*- coding: utf-8 -*-
"""解析 PPT 形状锚点（ClientAnchor 0xF010）与文本框内容，判定谱行/歌词行的框位置。"""
import struct, sys, io
sys.stdout = io.TextIOWrapper(open(r'e:\EchoHymn\tools\_shape_out.txt', 'wb'), encoding='utf-8', errors='replace')
src = open(r'e:\EchoHymn\tools\extract_ppt.py', encoding='utf-8').read()
ns = {}
exec(src.split('report = {')[0], ns)
sys.stdout = io.TextIOWrapper(open(r'e:\EchoHymn\tools\_shape_out.txt', 'wb'), encoding='utf-8', errors='replace')

PPT = sys.argv[1] if len(sys.argv) > 1 else r'C:\Users\小蔡爱金雪\Downloads\001.ppt'
EMU = 914400.0

def fmt(anchor):
    flags = struct.unpack('<4H', anchor[:8])
    xl, yt, xr, yb = struct.unpack('<4i', anchor[8:24])
    return 'flags=%s rect=(%.2f,%.2f)-(%.2f,%.2f)cm size=%.2fx%.2fcm' % (
        flags, xl / EMU * 2.54, yt / EMU * 2.54, xr / EMU * 2.54, yb / EMU * 2.54,
        (xr - xl) / EMU * 2.54, (yb - yt) / EMU * 2.54)

def walk(d, depth=0, state=None):
    if state is None:
        state = {'anchor': None, 'texts': []}
    i, n = 0, len(d)
    while i + 8 <= n:
        vi, rt, rl = struct.unpack('<HHI', d[i:i+8])
        ver = vi & 0xF
        if rl > n - i - 8:
            break
        body = d[i+8:i+8+rl]
        if rt == 0x0FBA and ver == 0xF:
            walk(ns['decomp_chunks'](body), depth + 1, state)
        elif rt in (0x0F004 & 0xFFFF,) or rt == 0xF004:  # SpContainer
            sub = {'anchor': None, 'texts': []}
            walk(body, depth + 1, sub)
            if sub['anchor'] or sub['texts']:
                print('%sSpContainer anchor=%s texts=%d' % ('  ' * depth,
                      fmt(sub['anchor']) if sub['anchor'] else 'None', len(sub['texts'])))
                for t in sub['texts'][:2]:
                    try:
                        txt = t.decode('utf-16-le', 'replace')
                    except Exception:
                        txt = '?'
                    lines = [x for x in txt.replace('\r', '\n').split('\n') if x.strip()]
                    print('%s   | %s' % ('  ' * depth, ' / '.join(lines[:3])[:90]))
        else:
            if rt == 0xF010 and rl >= 24:
                state['anchor'] = body[:24]
            elif rt in (0x0FA0, 0x0FA8):
                state['texts'].append(body)
            elif ver == 0xF:
                walk(body, depth + 1, state)
        i += 8 + rl
    return state

data = ns['read_ppt_stream'](PPT)
print('=== %s (stream %d bytes)' % (PPT, len(data)))
walk(data, 0, None)
