# -*- coding: utf-8 -*-
"""探查 tjc_hymn.db 数据库结构，用于 UI 设计确认"""
import sqlite3

DB = r'e:\EchoHymn\data\tjc_hymn.db'
conn = sqlite3.connect(DB)
cur = conn.cursor()

cur.execute("SELECT name FROM sqlite_master WHERE type='table'")
tables = [r[0] for r in cur.fetchall()]
print('TABLES:', tables)
print('=' * 60)

for t in tables:
    cur.execute(f'PRAGMA table_info({t})')
    cols = cur.fetchall()
    print(f'\n[{t}] columns:')
    for c in cols:
        print(f'  - {c[1]} ({c[2]}) {"PK" if c[5] else ""} {"NN" if c[3] else ""}')
    cur.execute(f'SELECT COUNT(*) FROM {t}')
    print(f'[{t}] rows: {cur.fetchone()[0]}')

# 分类明细（一级 → 二级 → 包含数量）
print('\n' + '=' * 60)
print('分类明细（category → subcategory）:')
cur.execute('SELECT category, subcategory, COUNT(*) FROM hymn_category GROUP BY category, subcategory ORDER BY category, subcategory')
for a, b, d in cur.fetchall():
    print(f'  {a}  <--  {b}  ({d}首)')

# 查看歌曲表前几行示例（若有）
print('\n' + '=' * 60)
for t in tables:
    cur.execute(f'PRAGMA table_info({t})')
    cols = [c[1] for c in cur.fetchall()]
    if any('hymn' in c.lower() or 'title' in c.lower() or 'number' in c.lower() for c in cols):
        try:
            cur.execute(f'SELECT * FROM {t} LIMIT 2')
            rows = cur.fetchall()
            print(f'\n[{t}] 示例数据（前2行）:')
            print('  列名:', cols)
            for r in rows:
                print(' ', r)
        except Exception as e:
            print(f'[{t}] 读取示例失败: {e}')

conn.close()