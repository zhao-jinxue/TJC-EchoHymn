# -*- coding: utf-8 -*-
"""组装安装载荷暂存区（双区拆分）：release 程序文件 + 按 DB 引用清单过滤的素材

用法: python prepare_staging.py <release目录> <staging主程序目录> <staging素材目录>
- 主程序区: release 根下 data 之外的程序文件全量收录（排除 logs、state.json 运行产物），
  另含 data 内非 Hymn_Downloads 的数据库与 Flutter 运行时资产
- 素材区: data/Hymn_Downloads 内只收录 payload_manifest.txt（小写相对路径）列出的文件，
  保留原始大小写；单独打包为外置数据文件，不并入安装包
"""
import os
import shutil
import sys

INST_DIR = os.path.dirname(os.path.abspath(__file__))
MANIFEST = os.path.join(INST_DIR, "payload_manifest.txt")
SKIP_ROOT = {"logs", "state.json"}


def main() -> int:
    if len(sys.argv) != 4:
        print(__doc__)
        return 2
    rel_dir = os.path.abspath(sys.argv[1])
    stage_main = os.path.abspath(sys.argv[2])
    stage_data = os.path.abspath(sys.argv[3])
    # 清单行是相对 data/ 的路径；统一归一化为 "data/xxx"（小写、正斜杠）再比对
    refs = set()
    for ln in open(MANIFEST, encoding="utf-8"):
        s = ln.strip().lower().replace("\\", "/")
        if s:
            refs.add(s if s.startswith("data/") else "data/" + s)
    print(f"清单条目: {len(refs)}")

    for d in (stage_main, stage_data):
        if os.path.exists(d):
            shutil.rmtree(d)
        os.makedirs(d)

    n = size = 0
    nd = sd = 0
    for root, _, files in os.walk(rel_dir):
        for f in files:
            src = os.path.join(root, f)
            rel = os.path.relpath(src, rel_dir).replace("\\", "/")
            top = rel.split("/", 1)[0].lower()
            if top == "data":
                # 只有 Hymn_Downloads 素材按 manifest 过滤；数据库与 Flutter 运行时资产全收
                sub = rel[len("data/"):]
                if sub.lower().startswith("hymn_downloads/"):
                    if rel.lower() not in refs:
                        continue
                    dst = os.path.normpath(os.path.join(stage_data, rel))  # 保留 data/Hymn_Downloads 层级
                    os.makedirs(os.path.dirname(dst), exist_ok=True)
                    shutil.copy2(src, dst)
                    nd += 1
                    sd += os.path.getsize(src)
                    continue
            else:
                if top in {s.lower() for s in SKIP_ROOT}:
                    continue
            dst = os.path.normpath(os.path.join(stage_main, rel))
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            shutil.copy2(src, dst)
            n += 1
            size += os.path.getsize(src)
    print(f"STAGING_OK 主程序 文件数: {n}  合计: {size / 2**20:.1f} MB -> {stage_main}")
    print(f"STAGING_OK 素材   文件数: {nd}  合计: {sd / 2**30:.2f} GB -> {stage_data}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
