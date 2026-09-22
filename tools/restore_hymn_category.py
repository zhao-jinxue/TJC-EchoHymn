# -*- coding: utf-8 -*-
"""恢复 hymn_category 的「一级/二级 + 诗歌清单」三列。

背景（2026-09-21 定位）
----------------------
`hymn_category` 现为 API 原始字段版 `(id, name, slug, hymn_count, updated_at)`，
缺 `category`(一级) / `subcategory`(二级) / `hymns`(JSON 诗歌清单) 三列 —— 这是
`f00fc43` 那次建库时被换掉的（该提交前 `b0ef0ac` 的库还是完整结构）。
App 侧 `HymnCategory.fromDbRow` 读的正是这三列，缺失导致「默认歌单」面板：
一级分组名为空（47 个二级挤在一个无名组里）、每个二级点开都是「暂无诗歌」。

恢复来源（本机 git 内即有，无需外部备份）
--------------------------------------
* 参照库：`git show <ref-rev>:data/tjc_hymn.db`（默认 1899e44，含完整 45 条：
  一级 13 类 + 二级 45 个 + 完整 hymns 清单），用于取「一级 ↔ 二级」归属关系
  与清单交叉校验。
* 清单重建：`data/Hymn_Downloads/api_cache/page_*.json`（48 页，站方分类快照；
  实测其分类计数与库内 `hymn_count` 完全一致、0 处差异），按编号排序写入。
* 编号形态：保留站方原样字符串，含 `51_a` / `51_b` 这类甲乙变体编号；写库时
  纯数字编号写整数（沿用老库格式），变体编号写字符串 —— App 侧
  `hymn_ref.dart` 两种都读得懂（读取端统一归一化为字符串）。
* 繁→简：复用 App 的逐字映射 `hymn_app/lib/data/chinese_convert_map.dart`
  （`kToSimplifiedByChar`），与界面显示完全一致。

安全设计
--------
* 纯**增加**列（ALTER TABLE ADD COLUMN），不改/不删任何既有列与既有数据；
* 默认预演，只打印报告；`--apply` 才写库，且单事务提交；
* 写前自动把当前库另存一份到 `%TEMP%\echohymn_backup\`（带时间戳），随时可回退。

用法
----
    python tools/restore_hymn_category.py                 # 预演（不改库）
    python tools/restore_hymn_category.py --apply         # 落库
    python tools/restore_hymn_category.py --ref-rev 0e01514
    python tools/restore_hymn_category.py --ref-db <某个 tjc_hymn.db 路径>
"""

import argparse
import glob
import json
import os
import re
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEF_DB = os.path.join(ROOT, 'data', 'tjc_hymn.db')
DEF_REF_REV = '1899e44'          # 「保存」提交：hymn_category 仍是完整结构
CONVERT_MAP = os.path.join(ROOT, 'hymn_app', 'lib', 'data', 'chinese_convert_map.dart')

# 老库里没有、或在库里被合并/拆分的二级：显式指定（一级, 二级）
# 键为「繁→简换算后」的二级名（与 App 的 kToSimplifiedByChar 结果一致）
SPECIAL = {
    '婚仪': ('婚丧礼仪', '婚仪'),      # 老库：一级「婚丧礼仪」+ 二级空，5 首合一
    '丧仪': ('婚丧礼仪', '丧仪'),
    '岁首': ('其他', '岁首'),          # 老库：一级「其他」/ 二级「岁首年终」2 首
    '岁末': ('其他', '岁末'),
    '附录': ('附录', '附录'),          # 老库：一级「附录」+ 二级空
}


def log(msg=''):
    print(msg, flush=True)


def load_convert_map():
    """从 App 的 Dart 映射表解析「繁体单字 → 简体单字」（只取 kToSimplifiedByChar）。"""
    src = open(CONVERT_MAP, encoding='utf-8').read()
    start = src.index('kToSimplifiedByChar')
    block = src[start:]
    end = block.find('};')
    block = block[:end if end > 0 else len(block)]
    pairs = re.findall(r"'(.+?)':\s*'(.+?)'", block)
    table = {k: v for k, v in pairs if len(k) == 1 and len(v) == 1}
    if len(table) < 500:
        sys.exit('繁简表解析异常（仅 %d 字），请检查 %s' % (len(table), CONVERT_MAP))
    return table


def t2s(text, table):
    return ''.join(table.get(ch, ch) for ch in (text or ''))


def fetch_ref_db(ref_rev, ref_db):
    """取得参照库路径（--ref-db 优先，否则从 git 历史导出到临时文件）。"""
    if ref_db:
        if not os.path.exists(ref_db):
            sys.exit('参照库不存在: %s' % ref_db)
        return ref_db, '文件 %s' % ref_db
    tmp = os.path.join(tempfile.gettempdir(), 'ref_%s.db' % ref_rev)
    with open(tmp, 'wb') as fh:
        r = subprocess.run(['git', '-C', ROOT, 'show', '%s:data/tjc_hymn.db' % ref_rev],
                           stdout=fh, stderr=subprocess.PIPE)
    if r.returncode != 0:
        sys.exit('无法从 git 导出参照库（rev=%s）：%s' % (ref_rev, r.stderr.decode('utf-8', 'replace')))
    return tmp, 'git %s:data/tjc_hymn.db' % ref_rev



def read_current(con):
    """当前库的分类行（id, name/二级名）。"""
    return list(con.execute('SELECT id, name FROM hymn_category ORDER BY id'))


def read_ref(path):
    """读参照库，返回 {简体二级: (一级, 简体二级)} 与 {简体二级: {编号...}}。"""
    con = sqlite3.connect(path)
    cols = [c[1] for c in con.execute('PRAGMA table_info(hymn_category)')]
    if not {'category', 'subcategory', 'hymns'} <= set(cols):
        sys.exit('参照库不含完整结构（列=%s），请换 --ref-rev / --ref-db' % cols)
    owner, lists = {}, {}
    for _id, cat, sub, hymns in con.execute(
            'SELECT id, category, subcategory, hymns FROM hymn_category ORDER BY id'):
        if not sub:
            continue
        owner[sub] = (cat, sub)
        try:
            items = json.loads(hymns)
        except Exception:
            items = []
        nums = set()
        for it in items:
            if isinstance(it, dict):
                nums.update(int(v) for v in it.values())
        lists[sub] = nums
    con.close()
    return owner, lists


def load_cache_lists(table, valid_numbers):
    """从 api_cache 列表页构建 {category_id: [(编号字符串, 简体名)]}（与库内 hymn_count 同源）。

    列表页为站方分类快照，实测与 `hymn_category.hymn_count` 完全一致。
    编号保留原样字符串（含 `51_a` / `124_b` 这类甲乙变体编号）—— App 侧
    `HymnCategory.fromDbRow` 已支持字符串编号（`hymn_ref.dart`）。

    返回 (分组, 用到的缓存文件, [(编号, 原因), ...])。
    """
    cache_dir = os.path.join(ROOT, 'data', 'Hymn_Downloads', 'api_cache')
    files = sorted(glob.glob(os.path.join(cache_dir, '*.json')))
    groups, skipped = {}, []
    for f in files:
        try:
            items = json.load(open(f, encoding='utf-8'))['data']
        except Exception:
            continue
        for it in items:
            cid, no, nm = it.get('category_id'), it.get('no'), it.get('name') or ''
            if cid is None or no is None:
                continue
            key = str(no)
            if key not in valid_numbers:
                skipped.append((key, '本库无此编号（如已移出）'))
                continue
            groups.setdefault(int(cid), []).append((key, t2s(nm, table)))
    for cid in groups:
        groups[cid].sort(key=_number_sort_key)
    return groups, files, skipped


def _number_sort_key(item):
    """编号排序：数字部分升序，变体后缀（_a/_b）排在数字之后。"""
    m = re.match(r'(\d+)(.*)$', item[0])
    return (int(m.group(1)), m.group(2)) if m else (10 ** 9, item[0])


def build_hymn_lists(con, table):
    """兜底：按 tjc_hymn.api_raw.category_id 归组，返回 ({cid: [(编号, 简体名)]}, 无分类的编号)。"""
    groups, no_cat = {}, []
    for hn, title, raw in con.execute(
            'SELECT hymn_number, title, api_raw FROM tjc_hymn '
            'ORDER BY CAST(hymn_number AS INTEGER)'):
        try:
            d = json.loads(raw) if raw else {}
            cid, nm = d.get('category_id'), (d.get('name') or title)
        except Exception:
            cid, nm = None, title
        if cid is None:
            no_cat.append(hn)
            continue
        groups.setdefault(int(cid), []).append((hn, t2s(nm, table)))
    return groups, no_cat


def plan_rows(cur_rows, owner, table, groups):
    """生成每条的 (id, 一级, 二级, 清单, 归属来源)。"""
    plan, warn = [], []
    for cid, name in cur_rows:
        key = t2s(name, table)
        if key in SPECIAL:
            cat, sub = SPECIAL[key]
            why = '显式规则'
        elif key in owner:
            cat, sub = owner[key]
            why = '同参照库'
        else:
            cat, sub = '其他', key
            why = '[注意] 参照库无此项'
            warn.append('二级「%s」(id=%s) 参照库中不存在，暂归「其他」' % (key, cid))
        lst = groups.get(cid, [])
        if not lst:
            warn.append('一级「%s」/ 二级「%s」(id=%s) 重算清单为空' % (cat, sub, cid))
        plan.append((cid, cat, sub, lst, why))
    return plan, warn


def report(plan, ref_lists, old_counts, warn):
    log('  %-9s %-11s %5s  %s' % ('一级', '二级', '首数', '与库内 hymn_count / 参照库对比'))
    log('  ' + '-' * 82)
    for cid, cat, sub, lst, why in plan:
        nums = {int(n) for n, _t in lst if n.isdigit()}
        variants = [n for n, _t in lst if not n.isdigit()]
        note = []
        if cid in old_counts and old_counts[cid] != len(lst):
            note.append('hymn_count %s→%d' % (old_counts[cid], len(lst)))
        if sub in ref_lists:
            add, rm = sorted(nums - ref_lists[sub]), sorted(ref_lists[sub] - nums)
            if add:
                note.append('较参照库 +%s' % add)
            if rm:
                note.append('较参照库 -%s' % rm)
        elif why.startswith('[注意]'):
            note.append(why)
        if variants:
            note.append('含甲乙变体编号 %s' % variants)
        log('  %-9s %-11s %5d  %s' % (cat, sub, len(lst), ' '.join(note)))
    one_level = len({p[1] for p in plan})
    log('  ' + '-' * 82)
    log('  合计：一级 %d 类 / 二级 %d 个 / 清单覆盖 %d 首'
        % (one_level, len(plan), sum(len(p[3]) for p in plan)))
    for w in warn:
        log('  [!] ' + w)



def ensure_columns(con):
    have = {c[1] for c in con.execute('PRAGMA table_info(hymn_category)')}
    added = []
    for col in ('category', 'subcategory', 'hymns'):
        if col not in have:
            con.execute('ALTER TABLE hymn_category ADD COLUMN %s TEXT NOT NULL DEFAULT ""' % col)
            added.append(col)
    return added


def apply_plan(con, plan):
    for cid, cat, sub, lst, _why in plan:
        # 纯数字编号写整数（沿用老库格式），甲乙变体编号写字符串
        payload = json.dumps([{t: (int(n) if n.isdigit() else n)} for n, t in lst],
                             ensure_ascii=False)
        con.execute('UPDATE hymn_category SET category=?, subcategory=?, hymns=?, hymn_count=? '
                    'WHERE id=?', (cat, sub, payload, len(lst), cid))


def verify(con):
    """用 App `HymnCategory.fromDbRow` 的等价逻辑复读，返回 (行, 覆盖首数, 问题)。"""
    rows, bad, total = [], [], 0
    for cid, cat, sub, raw in con.execute(
            'SELECT id, category, subcategory, hymns FROM hymn_category ORDER BY id'):
        if not cat or not sub:
            bad.append('id=%s 一级/二级为空' % cid)
        try:
            items = json.loads(raw or '[]')
        except Exception as e:
            bad.append('id=%s hymns JSON 解析失败: %s' % (cid, e))
            continue
        if not isinstance(items, list):
            bad.append('id=%s hymns 不是数组' % cid)
            continue
        if not items:
            bad.append('id=%s 清单为空' % cid)
        total += len(items)
        rows.append((cid, cat, sub, len(items)))
    return rows, total, bad


def backup(db):
    dst_dir = os.path.join(tempfile.gettempdir(), 'echohymn_backup')
    os.makedirs(dst_dir, exist_ok=True)
    dst = os.path.join(dst_dir, 'tjc_hymn_%s.db' % time.strftime('%Y%m%d-%H%M%S'))
    shutil.copy2(db, dst)
    return dst


def main():
    ap = argparse.ArgumentParser(
        description='恢复 hymn_category 的一级/二级/诗歌清单三列（默认只预演，加 --apply 才写库）')
    ap.add_argument('--db', default=DEF_DB, help='目标库（默认 data/tjc_hymn.db）')
    ap.add_argument('--ref-rev', default=DEF_REF_REV,
                    help='参照库的 git 版本（默认 %s）' % DEF_REF_REV)
    ap.add_argument('--ref-db', default='', help='直接指定参照库文件（优先于 --ref-rev）')
    ap.add_argument('--apply', action='store_true', help='真正写库（默认仅预演）')
    args = ap.parse_args()

    if not os.path.exists(args.db):
        sys.exit('目标库不存在: %s' % args.db)
    table = load_convert_map()
    ref_path, ref_desc = fetch_ref_db(args.ref_rev, args.ref_db)
    owner, ref_lists = read_ref(ref_path)

    log('目标库 : %s（%.1f MB）' % (args.db, os.path.getsize(args.db) / 1e6))
    log('参照库 : %s' % ref_desc)
    log('繁简表 : %s（%d 字）' % (os.path.relpath(CONVERT_MAP, ROOT), len(table)))

    try:
        con = sqlite3.connect(args.db)
        cur_rows = read_current(con)
        old_counts = dict(con.execute('SELECT id, hymn_count FROM hymn_category'))
        valid = {str(r[0]) for r in con.execute('SELECT hymn_number FROM tjc_hymn')}
        groups, files, skipped = load_cache_lists(table, valid)
        covered = sum(len(v) for v in groups.values())
        if files and covered >= len(valid) * 0.96:
            log('清单来源: api_cache 列表页（%d 个文件；覆盖 %d/%d 首）'
                % (len(files), covered, len(valid)))
            extra = []
            if skipped:
                extra.append('未进清单 %d 个编号：%s'
                             % (len(skipped), '、'.join('%s(%s)' % s for s in skipped)))
        else:
            groups, no_cat = build_hymn_lists(con, table)
            log('清单来源: tjc_hymn.api_raw 兜底（覆盖 %d/%d 首）'
                % (sum(len(v) for v in groups.values()), len(valid)))
            extra = (['api_raw 中未带 category_id 的诗歌：%s' % no_cat] if no_cat else [])
        plan, warn = plan_rows(cur_rows, owner, table, groups)
        warn = extra + warn
        orphan = sorted(set(groups) - {r[0] for r in cur_rows})
        if orphan:
            warn.append('清单中出现库里没有的分类 id: %s' % orphan)

        log('\n=== 恢复方案 ===')
        report(plan, ref_lists, old_counts, warn)

        if not args.apply:
            log('\n[预演] 未改动任何数据；确认无误后加 --apply 落库。')
            return

        bpath = backup(args.db)
        with con:
            added = ensure_columns(con)
            apply_plan(con, plan)
        con.commit()
        rows, total, bad = verify(con)
        log('\n=== 已落库 ===')
        log('  新增列     : %s' % (added or '（已存在，无需新增）'))
        log('  备份       : %s' % bpath)
        log('  一级/二级   : %d / %d' % (len({r[1] for r in rows}), len(rows)))
        log('  清单覆盖   : %d 首' % total)
        log('  校验       : %s' % ('全部通过' if not bad else '；'.join(bad)))
        log('  回退       : copy "%s" "%s"  或  git checkout <rev> -- data/tjc_hymn.db'
            % (bpath, args.db))
    except sqlite3.OperationalError as e:
        sys.exit('数据库被占用或不可写（请先退出 EchoHymn）：%s' % e)


if __name__ == '__main__':
    main()
