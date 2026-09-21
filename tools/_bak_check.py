import sqlite3, glob, os
for f in glob.glob('e:/EchoHymn/data/*.db*'):
    if os.path.getsize(f) == 0:
        print(f, 'EMPTY')
        continue
    db = sqlite3.connect(f)
    tabs = [r[0] for r in db.execute("SELECT name FROM sqlite_master WHERE type='table'")]
    jp = [t for t in tabs if 'jianpu' in t]
    print(f, 'jianpu:', jp if jp else '无', '| tables:', len(tabs))
    db.close()
