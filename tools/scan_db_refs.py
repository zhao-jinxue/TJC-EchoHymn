# -*- coding: utf-8 -*-
"""临时扫描脚本：统计数据库实际引用的 Hymn_Downloads 文件（用完即删）"""
import os, re, sqlite3
from collections import defaultdict

ROOT = r"E:\EchoHymn"
DB = os.path.join(ROOT, "data", "tjc_hymn.db")
DL = os.path.join(ROOT, "data", "Hymn_Downloads")

con = sqlite3.connect(DB)
cur = con.cursor()
tables = [r[0] for r in cur.execute("SELECT name FROM sqlite_master WHERE type='table'")]
print("tables:", tables)

exts = "m4a|mp3|jpg|jpeg|png|pdf|xml|musicxml|mid|midi|wav|flac|txt|json"
pat = re.compile(r'[\w\u4e00-\u9fff\-\\/. ()（）\[\]，,、&#+%-]+?\.(?:' + exts + r')', re.I)
refs = set()
for t in tables:
    cols = [r[1] for r in cur.execute(f"PRAGMA table_info('{t}')")]
    for row in cur.execute(f"SELECT * FROM '{t}'"):
        for v in row:
            if isinstance(v, str) and "." in v:
                for m in pat.finditer(v):
                    refs.add(m.group(0))
print("raw ref count:", len(refs))
for s in sorted(refs)[:8]:
    print("  sample:", s)

def norm_ref(s):
    s = s.replace("\\", "/").lower().strip().lstrip("./")
    return s if s.startswith("data/") else "data/" + s

files = {}
for root, ds, fs in os.walk(DL):
    for f in fs:
        p = os.path.join(root, f)
        rel = os.path.relpath(p, ROOT).replace("\\", "/").lower()
        try:
            files[rel] = os.path.getsize(p)
        except OSError:
            pass

ref_norm = {norm_ref(r) for r in refs}
G = 1024 ** 3
matched = {k: v for k, v in files.items() if k in ref_norm}
unref = {k: v for k, v in files.items() if k not in matched}
miss = sorted(ref_norm - set(files.keys()))

print(f"\n== 总体统计 ==")
print(f"磁盘文件总数: {len(files)}  总大小: {sum(files.values())/G:.2f} GB")
print(f"被DB引用     : {len(matched)}  {sum(matched.values())/G:.2f} GB")
print(f"未被引用     : {len(unref)}  {sum(unref.values())/G:.2f} GB")

# 输出打包清单（相对 data/ 的路径，供构建脚本复制）
with open(os.path.join(ROOT, "installer", "payload_manifest.txt"), "w", encoding="utf-8") as f:
    for k in sorted(matched.keys()):
        f.write(k[len("data/"):].replace("/", os.sep) + "\n")
print(f"\n打包清单已写出: installer/payload_manifest.txt ({len(matched)} 条)")

bt, bu = defaultdict(lambda: [0, 0]), defaultdict(lambda: [0, 0])
for k, v in files.items():
    e = os.path.splitext(k)[1] or "(无扩展名)"
    bt[e][0] += 1; bt[e][1] += v
for k, v in unref.items():
    e = os.path.splitext(k)[1] or "(无扩展名)"
    bu[e][0] += 1; bu[e][1] += v
print(f"\n== 按扩展名（总数/大小 | 未引用数/大小）==")
for e in sorted(bt, key=lambda x: -bt[x][1]):
    u = bu.get(e, [0, 0])
    print(f"  {e}: {bt[e][0]}个 {bt[e][1]/G:.2f}GB | 未引用 {u[0]}个 {u[1]/G:.2f}GB")

print(f"\n引用串未匹配到磁盘的样本数: {len(miss)}")
for m in miss[:12]:
    print("  ?", m)

for t, c in (("tjc_hymn", "staff_1"), ("tjc_hymn", "numbered_1")):
    try:
        v = cur.execute(f"SELECT {c} FROM {t} WHERE {c} IS NOT NULL LIMIT 1").fetchone()
        if v:
            s = str(v[0] or "")
            print(f"\n{c}: len={len(s)} head={s[:100]!r}")
    except sqlite3.Error as ex:
        print(f"\n{c}: ERR {ex}")
print("\nSCAN_DONE")
