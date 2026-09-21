# -*- coding: utf-8 -*-
import sqlite3, os
db = sqlite3.connect('e:/EchoHymn/data/tjc_hymn.db')
ns = [r[0] for r in db.execute('SELECT hymn_number FROM tjc_hymn ORDER BY 1')]
print('count:', len(ns), type(ns[0]))
print('special:', [n for n in ns if not str(n).isdigit()])
print('head:', ns[:5], 'tail:', ns[-5:])
ppts = sorted(os.path.splitext(f)[0] for f in os.listdir(r'E:\赞美诗\赞美诗--投影') if f.endswith('.ppt'))
def map_name(b):
    b = b.lower()
    if b[-1].isalpha():
        return str(int(b[:-1])) + '_' + b[-1]
    return str(int(b))
mapped = set(map_name(b) for b in ppts)
dbset = set(str(n) for n in ns)
print('PPT 数:', len(ppts), '| DB 数:', len(dbset))
print('PPT 有 DB 无:', sorted(mapped - dbset)[:20])
print('DB 有 PPT 无:', sorted(dbset - mapped)[:20])
