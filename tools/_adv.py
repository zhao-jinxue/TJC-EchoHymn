# -*- coding: utf-8 -*-
"""量简谱字体 / 歌词字体的真实 advance（em 单位）"""
import pymupdf, sys, io
sys.stdout = io.TextIOWrapper(open(r'e:\EchoHymn\tools\_adv_out.txt', 'wb'), encoding='utf-8', errors='replace')

for label, path in [('简谱字体', r'C:\Users\小蔡爱金雪\Downloads\简谱字体\简谱字体.ttf'),
                    ('歌词字体', r'C:\Users\小蔡爱金雪\Downloads\简谱字体\歌词字体.ttf'),
                    ('系统標楷體', r'C:\Windows\Fonts\kaiu.ttf')]:
    try:
        f = pymupdf.Font(fontfile=path)
        print('=== %s (%s)' % (label, path))
        for ch in [' ', '1', '5', 't', '/', '\\', '+', '圣', '，', '！', 'A']:
            try:
                adv = f.glyph_advance(ord(ch))
            except Exception as e:
                adv = 'ERR:%s' % e
            print('   %r -> %s' % (ch, adv))
    except Exception as e:
        print('=== %s 打开失败: %s' % (label, e))
