# -*- coding: utf-8 -*-
"""001.ppt 文本原子 → UTF-8 文件"""
import struct

PPT = r'C:\Users\小蔡爱金雪\Downloads\001.ppt'
OUT = r'e:\EchoHymn\tools\_ppt001.txt'
pd = open(PPT, 'rb').read()
i = 0
cnt = 0
out = []
while i + 8 <= len(pd):
    verinst, rectype, reclen = struct.unpack('<HHI', pd[i:i+8])
    if rectype in (0x0FA0, 0x0FA8) and 0 < reclen < 100000:
        payload = pd[i+8:i+8+reclen]
        txt = payload.decode('utf-16-le', 'replace') if rectype == 0x0FA8 else payload.decode('latin1', 'replace')
        cnt += 1
        out.append('--- atom#%d type=%04X off=%d len=%d\n%s' % (cnt, rectype, i, reclen, txt))
        i += 8 + reclen
        continue
    i += 1
open(OUT, 'w', encoding='utf-8').write('\n'.join(out))
print('atoms:', cnt, '->', OUT)
