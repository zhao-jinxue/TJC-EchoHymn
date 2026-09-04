# -*- coding: utf-8 -*-
"""组装安装载荷暂存区：release 程序文件 + 按 DB 引用清单过滤的素材

用法: python prepare_staging.py <release目录> <staging输出目录>
- release 根下 data\ 之外的程序文件全量收录（排除 logs\、state.json 运行产物）
- data\ 内只收录 payload_manifest.txt（小写相对路径）列出的文件，保留原始大小写
"""
import os
import shutil
import sys

INST_DIR = os.path.dirname(os.path.abspath(__file__))
MANIFEST = os.path.join(INST_DIR, "payload_manifest.txt")
SKIP_ROOT = {"logs", "state.json"}


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__)
        return 2
    rel_dir, stage = os.path.abspath(sys.argv[1]), os.path.abspath(sys.argv[2])
    # 清单行是相对 data/ 的路径；统一归一化为 "data/xxx"（小写、正斜杠）再比对
    refs = set()
    for ln in open(MANIFEST, encoding="utf-8"):
        s = ln.strip().lower().replace("\\", "/")
        if s:
            refs.add(s if s.startswith("data/") else "data/" + s)
    print(f"清单条目: {len(refs)}")

    if os.path.exists(stage):
        shutil.rmtree(stage)
    os.makedirs(stage)

    n = size = 0
    for root, _, files in os.walk(rel_dir):
        for f in files:
            src = os.path.join(root, f)
            rel = os.path.relpath(src, rel_dir).replace("\\", "/")
            top = rel.split("/", 1)[0].lower()
            if top == "data":
                # 只有 Hymn_Downloads 素材按 manifest 过滤；数据库与 Flutter 运行时资产全收
                sub = rel[len("data/"):]
                if sub.lower().startswith("hymn_downloads/") and rel.lower() not in refs:
                    continue
            else:
                if top in {s.lower() for s in SKIP_ROOT}:
                    continue
            dst = os.path.normpath(os.path.join(stage, rel))
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            shutil.copy2(src, dst)
            n += 1
            size += os.path.getsize(src)
    print(f"STAGING_OK 文件数: {n}  合计: {size / 2**30:.2f} GB -> {stage}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
