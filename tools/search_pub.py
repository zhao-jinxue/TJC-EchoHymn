# -*- coding: utf-8 -*-
"""查询 pub.dev 搜索指定关键词的包名，用于选择真实存在的依赖"""
import json
import sys
import urllib.request
import urllib.parse

q = sys.argv[1] if len(sys.argv) > 1 else 'opencc'
url = 'https://pub.dev/api/search?q=' + urllib.parse.quote(q)
with urllib.request.urlopen(url, timeout=30) as resp:
    data = json.load(resp)
for p in data.get('packages', [])[:15]:
    print(p['package'])