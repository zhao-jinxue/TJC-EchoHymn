# -*- coding: utf-8 -*-
"""递归扫描 001.ppt 全部记录类型（含压缩容器解压后），统计并打印字号记录。"""
import struct, sys, io, collections
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8', errors='replace')
src = open(r'e:\EchoHymn\tools\extract_ppt.py', encoding='utf-8').read()
ns = {}
exec(src.split('report = {')[0], ns)
# exec 里再次包裹了 stdout（旧包裹器被 GC 时关闭底层 buffer），此处重新绑定
sys.stdout = io.TextIOWrapper(open(r'e:\EchoHymn\tools\_fs_out.txt', 'wb'), encoding='utf-8', errors='replace')

data = ns['read_ppt_stream'](r'C:\Users\小蔡爱金雪\Downloads\001.ppt')
print('stream len:', len(data))
counter = collections.Counter()
sizes_records = []

def scan(data, depth=0):
    i, n = 0, len(data)
    while i + 8 <= n:
        vi, rt, rl = struct.unpack('<HHI', data[i:i+8])
        ver = vi & 0xF
        if rl > n - i - 8:
            break
        body = data[i+8:i+8+rl]
        counter[rt] += 1
        if rt == 0x0FBA and ver == 0xF:
            scan(ns['decomp_chunks'](body), depth + 1)
        elif ver == 0xF:
            scan(body, depth + 1)
        elif rt in (0x0FA1, 0x0FA9):
            sizes_records.append((rt, body))
        i += 8 + rl

scan(data)
print('全部记录类型:', sorted(counter.items()))
allsz = []
def scan2(d):
    i, n = 0, len(d)
    while i + 8 <= n:
        vi, rt, rl = struct.unpack('<HHI', d[i:i+8])
        ver = vi & 0xF
        if rl > n - i - 8:
            break
        b = d[i+8:i+8+rl]
        if rt == 0x0FBA and ver == 0xF:
            scan2(ns['decomp_chunks'](b))
        elif ver == 0xF:
            scan2(b)
        elif rt == 0x0FA1:
            u16 = list(struct.unpack('<%dH' % (len(b) // 2), b[:len(b) // 2 * 2]))
            # 结构：run 长度(1) + 0 + fontSize(1/100pt) + ...
            for k in range(len(u16) - 3):
                if u16[k] in (1, 2, 3) and u16[k + 1] == 0 and u16[k + 2] == 0:
                    v = u16[k + 3]
                    if 600 <= v <= 7200:
                        allsz.append(v)
        i += 8 + rl
scan2(data)
seen = sorted(set(allsz))
print('全部字号候选(1/100pt):', seen)
print('换算字号(pt):', [round(v / 100, 2) for v in seen])


for b in sizes_records[:6]:
    u16 = list(struct.unpack('<%dH' % (len(b) // 2), b[:len(b) // 2 * 2]))
    print('0x0FA1 len=%d u16=%s' % (len(b), u16[:50]))
    print('   字号候选:', sorted(set(v for v in u16 if 800 <= v <= 7200)))

