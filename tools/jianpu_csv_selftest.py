# -*- coding: utf-8 -*-
"""简谱数据自测：`jianpu_*` 表 ↔ APK 原始 CSV ↔ 实机无障碍树（三级交叉验证）。

层级：
  L0  DB ↔ CSV      逐行 raw 文本 + 逐格 kind/sym 完全一致（全库 474 首）
  L1  列对齐不变式   同一块（同一次 <table>）内各行单元格数一致
  L2  可读网格        指定一首按「行 × 列」打印（人眼复核）
  L3  实机交叉验证    与 `uiautomator dump`（WebView 元素级快照）逐元素比对
                     —— `<img>` 的 text = 图片文件名（MEN→E / MDN→D / L6→L6），
                        文本节点 = 单元格文字；证据文件见 `E:\\apk_re_tjc\\ui8.xml`

用法：
    python tools/jianpu_csv_selftest.py                       # L0 + L1（全库）
    python tools/jianpu_csv_selftest.py --hymn 009             # 追加 L2
    python tools/jianpu_csv_selftest.py --hymn 009 --ui <ui8.xml 路径>   # 追加 L3
"""
import argparse
import os
import re
import sqlite3
import sys
import zipfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from import_apk_csv import DB, DEFAULT_APK, build_hymn, hymn_number_of  # noqa: E402


def load_db(hymn):
    con = sqlite3.connect(f'file:{DB}?mode=ro', uri=True)
    con.row_factory = sqlite3.Row
    rows = [dict(r) for r in con.execute(
        'SELECT line_no, block_no, kind, stanza_no, col_count, raw'
        ' FROM jianpu_row WHERE hymn_number=? ORDER BY line_no', (hymn,))]
    cells = {}
    for r in con.execute(
            'SELECT line_no, col, kind, sym, degree, accidental, dot_len,'
            ' octave, dots, beams, fermata, rowspan, text FROM jianpu_cell'
            ' WHERE hymn_number=?', (hymn,)):
        cells.setdefault(r[0], {})[r[1]] = dict(
            kind=r[2], sym=r[3], degree=r[4], accidental=r[5], dot_len=r[6],
            octave=r[7], dots=r[8], beams=r[9], fermata=r[10], rowspan=r[11],
            text=r[12])
    con.close()
    return rows, cells


def expected_rows(apk, csv_name):
    z = zipfile.ZipFile(apk)
    text = z.read(f'assets/{csv_name}.csv').decode('utf-8-sig')
    meta, rows, cells, _lens, _warn = build_hymn(csv_name, text)
    cell_map = {}
    for c in cells:
        cell_map.setdefault(c['line_no'], {})[c['col']] = c
    return meta, rows, cell_map


def check_all(apk, limit_report=5):
    z = zipfile.ZipFile(apk)
    names = sorted(os.path.basename(n)[:-4] for n in z.namelist()
                   if re.match(r'assets/[\w\-]+\.csv$', n))
    bad_rows, bad_cells, bad_align, missing = [], [], [], []
    n_rows = n_cells = 0
    for name in names:
        hn = hymn_number_of(name)
        meta, rows, cell_map = expected_rows(apk, name)
        db_rows, db_cells = load_db(hn)
        if not db_rows:
            missing.append(hn)
            continue
        if len(db_rows) != len(rows):
            bad_rows.append((hn, 'row_count', len(rows), len(db_rows)))
            continue
        for r, dbr in zip(rows, db_rows):
            n_rows += 1
            if r['raw'] != dbr['raw']:
                bad_rows.append((hn, 'raw', r['line_no'], r['raw'], dbr['raw']))
            if r['col_count'] != dbr['col_count'] or r['kind'] != dbr['kind']:
                bad_rows.append((hn, 'meta', r['line_no'], r))
        for ln, cols in cell_map.items():
            for col, c in cols.items():
                if c['kind'] in ('empty', 'covered'):
                    continue
                d = db_cells.get(ln, {}).get(col)
                n_cells += 1
                if (d is None or d['sym'] != c['sym'] or d['kind'] != c['kind']
                        or d['degree'] != c['degree'] or d['beams'] != c['beams']
                        or d['dots'] != c['dots'] or d['fermata'] != c['fermata']
                        or d['rowspan'] != c['rowspan']):
                    bad_cells.append((hn, ln, col, c, d))
        if meta['align_ok'] == 0:
            bad_align.append((name, meta['block_bad']))
    print('L0  DB↔CSV  : 行 %d、格 %d；行差异 %d、格差异 %d、缺曲 %d'
          % (n_rows, n_cells, len(bad_rows), len(bad_cells), len(missing)))
    for b in bad_rows[:limit_report]:
        print('    行差异:', b)
    for b in bad_cells[:limit_report]:
        print('    格差异:', b)
    print('L1  列对齐   : 块内行宽不一致的文件 %d 个（源数据自身差异，渲染按块宽处理）'
          % len(bad_align))
    for b in bad_align[:limit_report]:
        print('    ', b)
    return not bad_rows and not bad_cells and not missing


def dump_grid(hymn, rows, cells, max_cols=80):
    print(f'\nL2  {hymn} 网格（{len(rows)} 行；块/行类型/节号 → 各列内容）')
    for r in rows:
        cols = cells.get(r['line_no'], {})
        out = []
        for col in range(min(r['col_count'], max_cols)):
            c = cols.get(col)
            if c is None:
                out.append('·')
            elif c['kind'] == 'note':
                s = str(c['degree'])
                if c['accidental']:
                    s = c['accidental'] + s
                if c['dot_len']:
                    s += '.' * c['dot_len']
                if c['octave']:
                    s += ('↑' * c['octave']) if c['octave'] > 0 else ('↓' * -c['octave'])
                out.append(s)
            elif c['kind'] == 'mark':
                out.append('<' + (c['text'] or '') + '>')
            elif c['kind'] == 'barline':
                out.append('|' + str(c['rowspan']))
            elif c['kind'] == 'text':
                out.append(c['text'] or '')
            else:
                out.append(c['sym'] or c['kind'])
        label = f"b{r['block_no']} L{r['line_no']:>2} {r['kind'][:9]:<9}"
        stanza = f" S{r['stanza_no']}" if r['stanza_no'] else '   '
        print('%s%s  %s' % (label, stanza, ' '.join(out)))


def check_ui(hymn, rows, cells, ui_path):
    """L3：与 uiautomator 快照逐元素比对（按 y 分组 → 行；行内按 x 排序 → 列）"""
    raw = open(ui_path, 'rb').read().decode('utf-8', 'replace')
    nodes = []
    for m in re.finditer(r'<node\b(.*?)/?>', raw, re.S):
        a = m.group(1)
        cls = re.search(r'class="([^"]*)"', a)
        txt = re.search(r'text="([^"]*)"', a)
        bd = re.search(r'bounds="\[(-?\d+),(-?\d+)\]\[(-?\d+),(-?\d+)\]"', a)
        if not (cls and txt and bd):
            continue
        t = txt.group(1).strip()
        t = (t.replace('&#10;', '\n').replace('&amp;', '&')
              .replace('&lt;', '<').replace('&gt;', '>')).strip()
        if not t:
            continue
        x1, y1, x2, y2 = (int(v) for v in bd.groups())
        if x2 - x1 <= 0 or y2 - y1 <= 0:
            continue          # 零宽/零高节点 = 布局产物（如 <br> 的 View）
        c = cls.group(1).split('.')[-1]
        if c not in ('Image', 'View', 'TextView'):
            continue
        if y1 <= 300:          # 标题栏等非曲谱区
            continue
        nodes.append((y1, x1, t))
    bands = {}
    for y1, x1, t in nodes:
        key = next((k for k in bands if abs(k - y1) <= 14), y1)
        bands.setdefault(key, []).append((x1, t))
    ui_rows = [(k, [t for _, t in sorted(bands[k])]) for k in sorted(bands)]

    exp = []
    for r in rows:
        if r['kind'] == 'blank':
            continue
        cols = cells.get(r['line_no'], {})
        seq = []
        for col in sorted(cols):
            c = cols[col]
            if c['kind'] == 'mark':
                seq.append(c['text'] or '')
            elif c['kind'] == 'barline':
                seq.append('L%d' % c['rowspan'])
            elif c['kind'] == 'note':
                seq.append(str(c['degree']))
            elif c['kind'] == 'rest':
                seq.append('0')
            elif c['kind'] == 'dash':
                seq.append('-')
            elif c['kind'] in ('text', 'stanza'):
                seq.append(c['text'] or c['sym'])
        if seq:
            exp.append((r['line_no'], r['kind'], seq))

    print('\nL3  实机快照交叉验证：%s' % ui_path)
    print('    实测 y 行带 %d 个／DB 非空行 %d 个' % (len(ui_rows), len(exp)))
    # 行带归并：同一 CSV 行可能被拆成多条 y 带（记号图与文字基线不同、图高不同），
    # 因此按「内容累加」贪心配对，而非按序号 zip。
    i, ok, pairs = 0, 0, 0
    for ln, kind, eseq in exp:
        acc = []
        while i < len(ui_rows) and len(acc) < len(eseq):
            acc += ui_rows[i][1]
            i += 1
        pairs += 1
        same = acc == eseq
        ok += 1 if same else 0
        print('    DB L%-2d %-9s %s  %s'
              % (ln, kind, 'OK  ' if same else 'DIFF', ' '.join(acc)))
        if not same:
            print('        期望: %s' % ' '.join(eseq))
    leftover = len(ui_rows) - i
    print('    逐行一致：%d / %d；剩余未消费行带 %d' % (ok, pairs, leftover))
    return ok == pairs and leftover == 0


def main():
    try:                      # 终端为 GBK 时避免非 GBK 字符（↔ ↑ ↓）报错
        sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    except Exception:
        pass
    ap = argparse.ArgumentParser()
    ap.add_argument('--apk', default=DEFAULT_APK)
    ap.add_argument('--hymn', default='')
    ap.add_argument('--ui', default='')
    args = ap.parse_args()

    ok = check_all(args.apk)
    if args.hymn:
        hn = hymn_number_of(args.hymn)
        rows, cells = load_db(hn)
        dump_grid(hn, rows, cells)
        if args.ui:
            ok = check_ui(hn, rows, cells, args.ui) and ok
    print('\n结论：%s' % ('PASS' if ok else 'FAIL'))
    return 0 if ok else 1


if __name__ == '__main__':
    sys.exit(main())

