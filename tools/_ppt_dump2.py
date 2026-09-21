# -*- coding: utf-8 -*-
"""001.ppt 全原子双解码对照（utf-16le / gbk），定稿解析规则"""
import struct, sys, io
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8', errors='replace')

PPT = r'C:\Users\小蔡爱金雪\Downloads\001.ppt'
pd = open(PPT, 'rb').read()
i = 0
cnt = 0
while i + 8 <= len(pd):
    verinst, rectype, reclen = struct.unpack('<HHI', pd[i:i+8])
    if rectype in (0x0FA0, 0x0FA8) and 0 < reclen < 100000:
        payload = pd[i+8:i+8+reclen]
        cnt += 1
        print('===== atom#%d type=%04X off=%d len=%d' % (cnt, rectype, i, reclen))
        u = payload.decode('utf-16-le', 'replace')
        g = payload.decode('gbk', 'replace')
        print('-- utf16le:')
        for ln in u.replace('\r', '\n').split('\n'):
            print('   |' + ln)
        print('-- gbk:')
        for ln in g.replace('\r', '\n').split('\n'):
            print('   |' + ln)
        i += 8 + reclen
        continue
    i += 1
print('atoms:', cnt)
