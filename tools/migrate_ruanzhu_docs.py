"""软著辅助文档「跨版本迁移」工具（docs/ruanzhu/v<旧> → docs/ruanzhu/v<新>）。

背景：软著申请材料的辅助文档（受理建议 / 署名核对 / 材料清单）随版本递交时要整体归入
新版本目录，并把「材料版本」引用换成新版本号。2026-09-24 之前这一步由**仓库外**的一次性
脚本（`E:\\apk_re_tjc\\ruanzhu_migrate.py`）完成 —— 脚本没入库、不可复现、路径全部写死。
本工具把该流程固化进仓库，与 `tools/make_ruanzhu_source.py` / `make_ruanzhu_manual.py`
同处维护（生成器负责正文产物，本工具负责辅助文档迁移）。

行为：
1. 三份辅助文档：**以目标版本目录已有文件为基底**（无则取源目录文件）做版本引用替换
   `V<旧>` / `v<旧>` / `<旧>` → 新版本号，写入目标版本目录；源版本目录保持原样（历史留档）；
   **含「历史留档 / 历史版本 / 上一版」字样的行整行不替换**（这类行刻意指向旧版本目录，
   如「`docs/ruanzhu/v1.7.4/` 为上一版材料（历史留档）」，改掉就会变成错误说明）；
2. 《版本变更说明_<起始>至<旧>.md》**只改名不改内容** → 《…至<新>.md》：
   历史变更条目照旧保留，新版本要点由人工补充（避免把历史版本号替换掉）；
3. 幂等：可重复执行；`--dry-run` 只打印计划不写盘。

用法：
    python tools/migrate_ruanzhu_docs.py --from 1.7.4 --to 1.8.0
    python tools/migrate_ruanzhu_docs.py --from 1.7.4 --to 1.8.0 --dry-run
    python tools/migrate_ruanzhu_docs.py --from 1.7.4 --to 1.8.0 --root docs/ruanzhu
"""
import argparse
import pathlib
import re
import shutil

ROOT = pathlib.Path(__file__).resolve().parent.parent
AUX_DOCS = (
    '受理中申请的处理建议.md',
    '署名与版本一致性核对.md',
    '材料清单与待补项.md',
)
CHANGELOG_PREFIX = '版本变更说明_'
KEEP_LINE = re.compile(r'历史留档|历史版本|上一版|历史档')


def replace_version(text: str, old: str, new: str) -> tuple[str, int, int]:
    """把「材料版本」引用整体换为新版本号（V/v 前缀与裸版本号三种写法）。

    逐行处理，谓词 = KEEP_LINE：命中「历史留档 / 历史版本 / 上一版」的行**整行保留**
    （这些行刻意指向旧版本目录，替换会把说明改错），其余行全量替换。
    返回（替换后的文本, 替换处数, 保留处数）；处数按版本号出现次数计（含 V/v 前缀形式）。
    """
    replaced = 0
    kept = 0
    lines = []
    for line in text.split('\n'):
        count = line.count(old)
        if KEEP_LINE.search(line):
            kept += count
        else:
            replaced += count
            for src, dst in ((f'V{old}', f'V{new}'), (f'v{old}', f'v{new}'), (old, new)):
                line = line.replace(src, dst)
        lines.append(line)
    return '\n'.join(lines), replaced, kept


def migrate_aux_docs(src_dir: pathlib.Path, dst_dir: pathlib.Path,
                     old: str, new: str, dry_run: bool) -> int:
    total = 0
    for name in AUX_DOCS:
        base = dst_dir / name
        if not base.exists():
            base = src_dir / name
        if not base.exists():
            print(f'  跳过（源/目标目录都没有）：{name}')
            continue
        text, replaced, kept = replace_version(
            base.read_text(encoding='utf-8'), old, new)
        print(f'  {name}：基底 = {base.parent.name}/ → 写入 v{new}，'
              f'替换版本引用 {replaced} 处，保留历史引用 {kept} 处')
        total += replaced
        if not dry_run:
            dst_dir.mkdir(parents=True, exist_ok=True)
            dst_dir.joinpath(name).write_text(text, encoding='utf-8', newline='\n')
    return total


def migrate_changelog(src_dir: pathlib.Path, dst_dir: pathlib.Path,
                      old: str, new: str, dry_run: bool) -> None:
    for path in sorted(src_dir.glob(CHANGELOG_PREFIX + '*.md')):
        target_name = re.sub(r'至' + re.escape(old) + r'\.md$', f'至{new}.md', path.name)
        if target_name == path.name:
            print(f'  跳过（文件名不含旧版本号）：{path.name}')
            continue
        target = dst_dir / target_name
        if target.exists():
            print(f'  {path.name} → {target_name}：目标已存在，无需改名')
            continue
        same_name = dst_dir / path.name
        if same_name.exists():
            print(f'  {path.name} → {target_name}：就地改名')
            if not dry_run:
                same_name.rename(target)
            continue
        print(f'  {path.name} → {target_name}：复制到目标目录并改名（内容不动）')
        if not dry_run:
            dst_dir.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, target)


def main() -> int:
    ap = argparse.ArgumentParser(description='软著辅助文档跨版本迁移（材料版本引用替换 + 变更说明改名）')
    ap.add_argument('--from', dest='old', required=True, help='旧版本号，如 1.7.4')
    ap.add_argument('--to', dest='new', required=True, help='新版本号，如 1.8.0')
    ap.add_argument('--root', default=str(ROOT / 'docs' / 'ruanzhu'),
                    help='软著材料根目录（默认 docs/ruanzhu，测试可指向临时目录）')
    ap.add_argument('--dry-run', action='store_true', help='只打印计划，不写盘')
    args = ap.parse_args()

    root = pathlib.Path(args.root)
    src_dir = root / f'v{args.old}'
    dst_dir = root / f'v{args.new}'
    if not src_dir.is_dir():
        raise SystemExit(f'源版本目录不存在：{src_dir}')

    print(f'迁移 v{args.old} → v{args.new}（root = {root}）'
          + ('【dry-run】' if args.dry_run else ''))
    total = migrate_aux_docs(src_dir, dst_dir, args.old, args.new, args.dry_run)
    migrate_changelog(src_dir, dst_dir, args.old, args.new, args.dry_run)
    print(f'完成：共替换版本引用 {total} 处；'
          f'提示 —— 新版本目录的《材料清单与待补项》《版本变更说明》仍需人工补该版本要点。')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
