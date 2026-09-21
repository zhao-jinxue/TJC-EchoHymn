# -*- coding: utf-8 -*-
import sys, re
sys.path.insert(0, r'e:\EchoHymn\tools')
import importlib.util
spec = importlib.util.spec_from_file_location('ep', r'e:\EchoHymn\tools\extract_ppt.py')
# 不执行模块主体（会跑全库）：手动复制关键正则
SCORE_RE = re.compile(r'^[ -~]*$')
CJK_RE = re.compile('[\u3000-\u30ff\u4e00-\u9fff\uff00-\uffef]')
import struct, zlib
src = open(r'e:\EchoHymn\tools\extract_ppt.py', encoding='utf-8').read()
ns = {}
head = src.split('report = {')[0]
exec(head, ns)
atoms = ns['atoms']; norm_line = ns['norm_line']; PAGE_RE = ns['PAGE_RE']
for payload in atoms(r'E:\赞美诗\赞美诗--投影\359.ppt'):
    if len(payload) < 100:
        continue
    txt = ns['decode'](payload)
    if '单击此处编辑' in txt[:40]:
        continue
    for ln in txt.replace('\r', '\n').replace('\x0b', '\n').replace('\x0c', '\n').split('\n'):
        ln2 = norm_line(ln)
        s = ln2.strip()
        if not s:
            continue
        is_cjk = bool(CJK_RE.search(s))
        is_page = bool(PAGE_RE.match(s)) and not is_cjk
        is_score = bool(SCORE_RE.match(ln2)) and bool(re.search(r'[0-7`!#$%&@A-Z_a-z]', s))
        if not is_cjk and not is_page and not is_score:
            print('UNC full hex:', [hex(ord(c)) for c in ln2])
