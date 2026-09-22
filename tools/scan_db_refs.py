# -*- coding: utf-8 -*-
"""素材引用扫描器：统计数据库实际引用的 Hymn_Downloads 文件，并生成安装包素材清单

用途（`docs/Windows/INSTALLER.md` / `RELEASE_RULES.md` 规则 6 / `README.md`）：
  诗歌/音频/谱图素材更新后运行本脚本 → 重写 `installer/payload_manifest.txt`
  （仅保留**被数据库引用**的素材，未引用的不进安装包，控制外置数据包体积）→ 再执行构建。

    python tools/scan_db_refs.py      # 打印统计并写出 installer/payload_manifest.txt
"""
import os, re, sqlite3
from collections import defaultdict

ROOT = r"E:\EchoHymn"
DB = os.path.join(ROOT, "data", "tjc_hymn.db")
DL = os.path.join(ROOT, "data", "Hymn_Downloads")

# ── 手工保留项（DB 未引用、但需随安装包分发的素材）────────────────────────────
# 清单默认只收「被数据库引用」的素材；下列目录前缀（相对 data/、正斜杠、大小写不敏感）
# 会显式保留，用于历史遗留但用户要求继续随包分发的素材。
#   354_349救主正在等候/ = 官网旧版「349」诗歌的素材（该曲目已不在库内，2026-09-21 用户要求保留）
MANUAL_KEEP = [
    "data/hymn_downloads/354_349救主正在等候",
]

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
manual = [p.replace("\\", "/").lower() for p in MANUAL_KEEP]
G = 1024 ** 3
matched = {k: v for k, v in files.items()
           if k in ref_norm or any(k.startswith(m) for m in manual)}
kept_manual = {k: v for k, v in matched.items() if k not in ref_norm}
unref = {k: v for k, v in files.items() if k not in matched}
miss = sorted(ref_norm - set(files.keys()))

print(f"\n== 总体统计 ==")
print(f"磁盘文件总数: {len(files)}  总大小: {sum(files.values())/G:.2f} GB")
print(f"被DB引用     : {len(matched) - len(kept_manual)}  "
      f"{(sum(matched.values()) - sum(kept_manual.values()))/G:.2f} GB")
print(f"手工保留     : {len(kept_manual)}  {sum(kept_manual.values())/G:.2f} GB  {MANUAL_KEEP}")
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
