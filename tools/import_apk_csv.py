# -*- coding: utf-8 -*-
"""把 TJC 赞美诗 APK 的 `assets/NNN.csv` 谱面网格导入 EchoHymn 数据库。

背景（2026-09-22 逆向结论，见 `docs/knowledge/TJC_APK_JIANPU_RENDER.md`）：
- APK 的谱面数据 = 二维网格，**同一列 = 同一拍点**；音符、记号（减时线/低·高音点/
  延长记号）、小节线（跨行）、歌词音节全部写在同一列 → 对齐在数据里完成；
- 该网格比旧的 PDF 抽取管线（`hymn_score*` + `hymn_codepoint_map`）更规整，故整体替换。

本脚本职责（唯一数据入口）：
  1. 读 APK 里的 474 份 CSV（不落盘 CSV 文件）；
  2. 解析为「行 / 列 / 单元格」结构化数据；
  3. 写入新表 `jianpu_score` / `jianpu_row` / `jianpu_cell`；
  4. 删除旧表 `hymn_score*` 与 `hymn_codepoint_map`（`--keep-old` 可保留）。

编号映射：CSV `001` → 库内 `1`；CSV `051a` → 库内 `51_a`（与 tjc_hymn.hymn_number 对齐）。

用法：
    python tools/import_apk_csv.py --check          # 只解析并体检（不写库）
    python tools/import_apk_csv.py                  # 导入（默认删旧表）
    python tools/import_apk_csv.py --keep-old       # 导入但保留旧表
    python tools/import_apk_csv.py --hymn 009       # 只导一首（调试）
"""
import argparse
import datetime
import os
import re
import sqlite3
import sys
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DB = os.path.join(ROOT, 'data', 'tjc_hymn.db')
DEFAULT_APK = os.path.join(os.path.expanduser('~'), 'Downloads',
                           'com.tinanlin.tjc_hymn_cn_v2.4.2.apk')

OLD_TABLES = ['hymn_score', 'hymn_score_line', 'hymn_score_lyric',
              'hymn_score_char', 'hymn_codepoint_map']

SCHEMA = """
CREATE TABLE IF NOT EXISTS jianpu_score (
  hymn_number  TEXT PRIMARY KEY,
  source       TEXT NOT NULL,
  row_count    INTEGER NOT NULL,
  col_count    INTEGER NOT NULL,
  block_count  INTEGER NOT NULL,
  note_rows    INTEGER NOT NULL,
  mark_up_rows INTEGER NOT NULL,
  mark_dn_rows INTEGER NOT NULL,
  lyric_rows   INTEGER NOT NULL,
  stanza_count INTEGER NOT NULL,
  align_ok     INTEGER NOT NULL,
  updated_at   TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS jianpu_row (
  hymn_number TEXT NOT NULL,
  line_no     INTEGER NOT NULL,
  block_no    INTEGER NOT NULL,
  kind        TEXT NOT NULL,
  stanza_no   INTEGER,
  col_count   INTEGER NOT NULL,
  raw         TEXT NOT NULL,
  PRIMARY KEY (hymn_number, line_no)
);
CREATE TABLE IF NOT EXISTS jianpu_cell (
  hymn_number TEXT NOT NULL,
  line_no     INTEGER NOT NULL,
  col         INTEGER NOT NULL,
  kind        TEXT NOT NULL,
  sym         TEXT NOT NULL,
  degree      INTEGER,
  accidental  TEXT,
  dot_len     INTEGER,
  octave      INTEGER,
  dots        INTEGER,
  beams       INTEGER,
  fermata     INTEGER,
  rowspan     INTEGER,
  text        TEXT,
  PRIMARY KEY (hymn_number, line_no, col)
);
CREATE INDEX IF NOT EXISTS idx_jianpu_cell_line
  ON jianpu_cell (hymn_number, line_no);
"""

NOTE_RE = re.compile(r'^([#b]?)([0-7])(\.{0,2})$')      # 1 / 1. / 1.. / #1 / b3
ACC_RE = re.compile(r'^[#b]$')                           # 单独出现的升降号
MARK_RE = re.compile(r'^M([A-Z]+)N$')                    # M…N = 符号插图
BAR_RE = re.compile(r'^L([2-7])$')                       # 小节线（前导逗号是分隔符）
STANZA_RE = re.compile(r'^\((\d+)\)$')                   # 歌词行的节号标记 (1)
CJK_RE = re.compile(r'[\u3400-\u9fff\uf900-\ufaff]')


def hymn_number_of(csv_name):
    """CSV 名 → 库内编号：'001'→'1'，'051a'→'51_a'"""
    m = re.match(r'^0*(\d+)([a-z]?)$', csv_name)
    if not m:
        return None
    num, suffix = m.group(1), m.group(2)
    return f'{num}_{suffix}' if suffix else num


def is_note_row(cells):
    return any(NOTE_RE.match(c) or c == '-' for c in cells if c)


def is_mark_only_row(cells):
    """只含记号/占位/小节线（无音符、无文字）"""
    seen = False
    for c in cells:
        if not c:
            continue
        seen = True
        if MARK_RE.match(c) or c == 'X' or BAR_RE.match(c):
            continue
        return False
    return seen


def is_lyric_row(cells):
    return any(CJK_RE.search(c) for c in cells if c)


def parse_csv(text):
    """→ [(tokens, cells, block_break)]；cells 已去掉行首 T / 行尾 R[K]，col 0 起"""
    out = []
    for raw in text.splitlines():
        if not raw.strip():
            continue
        toks = [t.strip() for t in raw.split(',')]
        if toks and toks[0] == 'T':
            toks = toks[1:]
        # 行尾可能是 `R` / `RK` / `K`，其前可能还有一个空单元（`,R`）——
        # 先剥尾部空单元再剥行尾标记，避免把 R 当成单元格（否则行宽+1）
        while toks and toks[-1] == '':
            toks.pop()
        block_break = False
        if toks and re.match(r'^(R+K?|K)$', toks[-1]):
            block_break = toks[-1].endswith('K')
            toks.pop()
        out.append((toks, toks, block_break))
    return out


def classify(parsed):
    """行分类 → [kind]，kind ∈ note | mark_up | mark_down | lyric | blank | other"""
    kinds = []
    for _, cells, _ in parsed:
        if not any(cells):
            kinds.append('blank')
        elif is_note_row(cells):
            kinds.append('note')
        elif is_lyric_row(cells):
            kinds.append('lyric')
        elif is_mark_only_row(cells):
            kinds.append('mark?')
        else:
            kinds.append('other')

    for i, k in enumerate(kinds):
        if k != 'mark?':
            continue
        glyphs = ''.join(MARK_RE.match(c).group(1) for c in parsed[i][1]
                         if MARK_RE.match(c))
        looks_up = ('U' in glyphs) or ('E' in glyphs)
        looks_down = 'B' in glyphs
        prev_note = i > 0 and kinds[i - 1] == 'note'
        next_note = i + 1 < len(kinds) and kinds[i + 1] == 'note'
        if next_note and not prev_note:
            kinds[i] = 'mark_up'
        elif prev_note and not next_note:
            kinds[i] = 'mark_down'
        elif prev_note and next_note:      # 夹在两条音符行之间：按字形判
            kinds[i] = 'mark_down' if looks_down and not looks_up else 'mark_up'
        else:                              # 不邻音符行
            kinds[i] = 'mark_up' if looks_up else 'mark_down'
    return kinds


def parse_cell(tok, kind):
    """单元格解析 → dict"""
    c = dict(kind='empty', sym=tok, degree=None, accidental=None, dot_len=None,
             octave=None, dots=None, beams=None, fermata=None, rowspan=None,
             text=None)
    if tok == '':
        return c
    m = MARK_RE.match(tok)
    if m:
        g = m.group(1)
        c.update(kind='mark', beams=g.count('B'), dots=g.count('D'),
                 fermata=g.count('E'), text=g)
        return c
    m = BAR_RE.match(tok)
    if m:
        c.update(kind='barline', rowspan=int(m.group(1)))
        return c
    if tok == 'X':
        c.update(kind='covered')
        return c
    m = NOTE_RE.match(tok)
    if m:
        deg = int(m.group(2))
        c.update(kind='rest' if deg == 0 else 'note', accidental=m.group(1),
                 degree=deg, dot_len=len(m.group(3)))
        return c
    if tok == '-':
        c.update(kind='dash')
        return c
    if tok == '.' or tok == '..':
        c.update(kind='dot_len', dot_len=len(tok))
        return c
    if ACC_RE.match(tok):
        c.update(kind='accidental', accidental=tok)
        return c
    if STANZA_RE.match(tok):
        c.update(kind='stanza', text=tok)
        return c
    if not tok.isascii():
        c.update(kind='text', text=tok)      # 汉字 / 全角标点（，！；、）
        return c
    c.update(kind='unknown')
    return c


def build_hymn(csv_name, text):
    """解析一首 → (meta, rows, cells)"""
    parsed = parse_csv(text)
    kinds = classify(parsed)

    # 块号（K = 换表）与歌词节号
    rows, cells_out = [], []
    block_no = 0
    stanza_seq = {}
    warn = []
    lens = {len(cells) for _, cells, _ in parsed}
    for i, (_, cells, brk) in enumerate(parsed):
        kind = kinds[i]
        stanza_no = None
        if kind == 'lyric':
            found = None
            for c in cells:
                m = STANZA_RE.match(c)
                if m:
                    found = int(m.group(1))
                    break
            if found is None:
                stanza_seq[block_no] = stanza_seq.get(block_no, 0) + 1
                found = stanza_seq[block_no]
            else:
                stanza_seq[block_no] = max(stanza_seq.get(block_no, 0), found)
            stanza_no = found
        row = dict(line_no=i, block_no=block_no, kind=kind,
                   stanza_no=stanza_no, col_count=len(cells),
                   raw=','.join(cells))
        rows.append(row)
        for col, tok in enumerate(cells):
            cc = parse_cell(tok, kind)
            if cc['kind'] == 'unknown':
                warn.append((i, col, tok))
            cc['line_no'] = i
            cc['col'] = col
            cells_out.append(cc)
        if brk:
            block_no += 1

    # 列对齐不变式：**按块（同一次 <table>）**核对每行单元格数是否一致
    # （K 换表后新表的列宽可以不同，故不能按整文件核对；空行不计入）
    widths_by_block = {}
    for i, (_, cells, _) in enumerate(parsed):
        if rows[i]['kind'] == 'blank':
            continue
        widths_by_block.setdefault(rows[i]['block_no'], set()).add(len(cells))
    block_bad = {b: sorted(w) for b, w in widths_by_block.items() if len(w) > 1}
    block_width = {b: max(w) for b, w in widths_by_block.items()}

    # 派生：音符格 → 八度（来自上/下记号行的同列点数）+ 延长记号
    by_row = {}
    for c in cells_out:
        by_row.setdefault(c['line_no'], {})[c['col']] = c
    for r in rows:
        if r['kind'] != 'note':
            continue
        up = rows[r['line_no'] - 1] if r['line_no'] > 0 else None
        dn = rows[r['line_no'] + 1] if r['line_no'] + 1 < len(rows) else None
        for col, c in by_row[r['line_no']].items():
            if c['kind'] != 'note':
                continue
            if up and up['kind'] == 'mark_up':
                m = by_row[up['line_no']].get(col)
                if m and m['kind'] == 'mark':
                    c['octave'] = (m['dots'] or 0)
                    c['fermata'] = m['fermata'] or 0
            if dn and dn['kind'] == 'mark_down':
                m = by_row[dn['line_no']].get(col)
                if m and m['kind'] == 'mark' and m['dots']:
                    c['octave'] = -(m['dots'] or 0)

    meta = dict(
        hymn_number=hymn_number_of(csv_name),
        source=f'apk_csv:{csv_name}',
        row_count=len(rows),
        col_count=max(lens) if lens else 0,
        block_count=block_no + 1,
        note_rows=sum(1 for k in kinds if k == 'note'),
        mark_up_rows=sum(1 for k in kinds if k == 'mark_up'),
        mark_dn_rows=sum(1 for k in kinds if k == 'mark_down'),
        lyric_rows=sum(1 for k in kinds if k == 'lyric'),
        stanza_count=len({r['stanza_no'] for r in rows if r['stanza_no']}),
        align_ok=0 if block_bad else 1,
        block_width=block_width,
        block_bad=block_bad,
    )
    return meta, rows, cells_out, sorted(lens), warn


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--apk', default=DEFAULT_APK)
    ap.add_argument('--db', default=DB)
    ap.add_argument('--check', action='store_true', help='只解析体检，不写库')
    ap.add_argument('--keep-old', action='store_true', help='保留旧表 hymn_score*/hymn_codepoint_map')
    ap.add_argument('--hymn', default='', help='只处理指定 CSV 名（如 009）')
    args = ap.parse_args()

    if not os.path.exists(args.apk):
        sys.exit(f'找不到 APK：{args.apk}（用 --apk 指定）')

    z = zipfile.ZipFile(args.apk)
    names = sorted(os.path.basename(n)[:-4] for n in z.namelist()
                   if re.match(r'assets/[\w\-]+\.csv$', n))
    if args.hymn:
        names = [n for n in names if n == args.hymn or n.lstrip('0') == args.hymn.lstrip('0')]
    print(f'CSV 文件数 = {len(names)}')

    metas, all_rows, all_cells = [], [], []
    stats = dict(cell_kinds={}, bad_lens=[], warns=[], align_bad=[])
    for name in names:
        text = z.read(f'assets/{name}.csv').decode('utf-8-sig')
        meta, rows, cells, lens, warn = build_hymn(name, text)
        if meta['hymn_number'] is None:
            stats['bad_lens'].append((name, '编号无法解析'))
            continue
        metas.append(meta)
        all_rows.extend((meta['hymn_number'], r) for r in rows)
        all_cells.extend((meta['hymn_number'], c) for c in cells)
        for c in cells:
            stats['cell_kinds'][c['kind']] = stats['cell_kinds'].get(c['kind'], 0) + 1
        if meta['align_ok'] == 0:
            stats['align_bad'].append((name, meta['block_bad']))
        if warn:
            stats['warns'].append((name, warn[:5], len(warn)))

    print('行数合计 = %d，单元格合计 = %d' % (len(all_rows), len(all_cells)))
    print('单元格类型分布:', dict(sorted(stats['cell_kinds'].items(),
                                        key=lambda kv: -kv[1])))
    print('块内列宽不一致的文件 %d 个：%s' % (len(stats['align_bad']), stats['align_bad'][:5]))
    print('含未知 token（`?` 等）的文件 %d 个：%s' % (len(stats['warns']), stats['warns'][:3]))
    print('主旋律行(note) 合计 = %d；歌词行 = %d；记号行 = %d'
          % (sum(m['note_rows'] for m in metas),
             sum(m['lyric_rows'] for m in metas),
             sum(m['mark_up_rows'] + m['mark_dn_rows'] for m in metas)))
    from collections import Counter
    wdist = Counter(w for m in metas for w in m['block_width'].values())
    print('块列宽分布（列数 → 块数）:', dict(sorted(wdist.items())))
    kdist = Counter(m['block_count'] for m in metas)
    print('每首块数分布:', dict(sorted(kdist.items())))

    if args.check:
        print('\n--check 模式：未写入数据库')
        return

    con = sqlite3.connect(args.db)
    cur = con.cursor()
    # 新表每次整体重建（纯派生数据，重跑即得；同时避免历史 schema 漂移）
    cur.executescript('DROP TABLE IF EXISTS jianpu_cell;'
                      'DROP TABLE IF EXISTS jianpu_row;'
                      'DROP TABLE IF EXISTS jianpu_score;')
    cur.executescript(SCHEMA)
    if not args.keep_old:
        for t in OLD_TABLES:
            cur.execute(f'DROP TABLE IF EXISTS {t}')
        print('已删除旧表:', ', '.join(OLD_TABLES))
    now = datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    for m in metas:
        cur.execute(
            'INSERT INTO jianpu_score (hymn_number, source, row_count, col_count,'
            ' block_count, note_rows, mark_up_rows, mark_dn_rows, lyric_rows,'
            ' stanza_count, align_ok, updated_at)'
            ' VALUES (?,?,?,?,?,?,?,?,?,?,?,?)',
            (m['hymn_number'], m['source'], m['row_count'], m['col_count'],
             m['block_count'], m['note_rows'], m['mark_up_rows'],
             m['mark_dn_rows'], m['lyric_rows'], m['stanza_count'],
             m['align_ok'], now))
    for hn, r in all_rows:
        cur.execute(
            'INSERT INTO jianpu_row (hymn_number, line_no, block_no, kind,'
            ' stanza_no, col_count, raw) VALUES (?,?,?,?,?,?,?)',
            (hn, r['line_no'], r['block_no'], r['kind'], r['stanza_no'],
             r['col_count'], r['raw']))
    keep = [(hn, c) for hn, c in all_cells
            if c.get('kind') not in ('empty', 'covered')]
    cur.executemany(
        'INSERT INTO jianpu_cell (hymn_number, line_no, col, kind, sym, degree,'
        ' accidental, dot_len, octave, dots, beams, fermata, rowspan, text)'
        ' VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
        [(hn, c['line_no'], c['col'], c['kind'], c['sym'], c['degree'],
          c['accidental'], c['dot_len'], c['octave'], c['dots'], c['beams'],
          c['fermata'], c['rowspan'], c['text'])
         for hn, c in all_cells
         if c.get('kind') not in ('empty', 'covered')])
    con.commit()
    cur.execute('VACUUM')
    con.commit()
    con.close()
    print(f'\n已写入 {args.db}')
    print('  jianpu_score: %d 首' % len(metas))
    print('  jianpu_row  : %d 行' % len(all_rows))
    print('  jianpu_cell : %d 格（空/占位格不落库，共 %d 格）'
          % (len(keep), len(all_cells)))


if __name__ == '__main__':
    main()

