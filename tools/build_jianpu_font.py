"""重建「简谱记谱字体」资产：从印刷 PDF 内嵌 MMP2005 字体跨文件合并字形

产出（--apply 时写入）：
  1. `hymn_app/assets/fonts/jianpu_mmp2005.ttf` —— App 内置字体（family `EchoJianpu`）
  2. `hymn_app/lib/data/jianpu_metrics.dart`    —— 码位 → [墨迹宽, xMin, yMin, yMax]（em）

为什么能这样做（2026-09-21 取证结论）：
  - 印刷 PDF 的乐谱是**位图**（页内 27 张 image），其上盖一层**隐藏文本层**用于检索，
    该文本层的 advance 被压平成 0.25em（不可用于排版）；
  - 但**字体字形本身是预合成装饰**：`5̲`(4ef0)、`低音5`(4e4d)、`连音弧`(5e66~5e6e, 宽 1.7~3.7em)
    各自都是单个字形 —— 因此「库内 code_seq 码位序列 + 该字体」原生渲染即等于印刷记号，
    无需再自绘点/线/弧；
  - 每页子集只含该页用到的字形（第 1 首页 0 覆盖 74/80 个码位），故需**跨 PDF 合并**；
  - 合并后 advance 仍不可信 → 同表输出**字形墨迹宽度**，App 侧据此排列表宽。

用法：
  python tools/build_jianpu_font.py            # 只体检（覆盖率 + 宽度表预览）
  python tools/build_jianpu_font.py --apply    # 写字体资产与 Dart 度量表
"""
import copy
import glob
import io
import os
import sqlite3
import sys

import pymupdf
from fontTools.ttLib import TTFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DB = os.path.join(ROOT, 'data', 'tjc_hymn.db')
PDFS = os.path.join(ROOT, 'data', 'Hymn_Downloads')
FONT_OUT = os.path.join(ROOT, 'hymn_app', 'assets', 'fonts', 'jianpu_mmp2005.ttf')
METRICS_OUT = os.path.join(ROOT, 'hymn_app', 'lib', 'data', 'jianpu_metrics.dart')
APPLY = '--apply' in sys.argv


def used_codepoints():
    """需要保留的码位（十进制）。

    2026-09-22 谱面数据源切换（`hymn_score*` 已删除）后的兜底口径：
    **直接以当前内置字体自身的 cmap 为准**（字体已是跨 PDF 合并子集，
    再去按用量裁剪没有收益）；若老库仍在，则沿用 code_seq 用量口径。
    """
    if os.path.exists(DB):
        con = sqlite3.connect(DB)
        try:
            rows = con.execute(
                'SELECT name FROM sqlite_master WHERE type=? AND name=?',
                ('table', 'hymn_score_line')).fetchall()
            if rows:
                raw = [r[0] for r in con.execute(
                    'SELECT code_seq FROM hymn_score_line WHERE is_primary=1')]
                out = set()
                for seq in raw:
                    for tok in seq.split():
                        for cp in tok.split('+'):
                            out.add(int(cp, 16))
                if out:
                    return out, len(raw)
        finally:
            con.close()
    if os.path.exists(FONT_OUT):
        font = TTFont(FONT_OUT)
        cps = {cp for cp in font.getBestCmap()}
        return cps, 0
    raise SystemExit('既无 hymn_score_line 也无内置字体，无法确定码位集合')


def subsets_of(pdf):
    """取一份 PDF 里的全部 MMP2005 子集字体字节"""
    doc = pymupdf.open(pdf)
    seen, out = set(), []
    for page in doc:
        for f in page.get_fonts(full=True):
            if 'MMP2005' not in f[3]:
                continue
            buf = doc.extract_font(f[0])[3]
            if not buf:
                continue
            key = (len(buf), hash(buf))
            if key in seen:
                continue
            seen.add(key)
            out.append(buf)
    doc.close()
    return out


def collect(want):
    """遍历 PDF 收集子集字体，按覆盖率降序返回 [(覆盖率, 字节, cmap)]"""
    variants, covered = [], set()
    pdfs = sorted(glob.glob(os.path.join(PDFS, '*', '*简谱.pdf')))
    print('候选 PDF %d 个' % len(pdfs))
    for pdf in pdfs:
        if want <= covered:
            break
        for buf in subsets_of(pdf):
            try:
                f = TTFont(io.BytesIO(buf), recalcBBoxes=False, lazy=True)
                cmap = f.getBestCmap()
            except Exception:
                continue
            hit = want & set(cmap)
            if not hit:
                continue
            variants.append((len(hit), buf, cmap))
            covered |= hit
    variants.sort(key=lambda v: -v[0])
    return variants, covered


def merge(variants, want):
    """以覆盖最优的子集为基底，把其余子集的缺失字形并进来"""
    base = TTFont(io.BytesIO(variants[0][1]))
    upm = base['head'].unitsPerEm
    base_cmap = base.getBestCmap()
    glyphs = base['glyf'].glyphs
    order = list(base.getGlyphOrder())
    names = set(order)
    added = []

    def ensure(src_glyf, gname):
        if gname in names:
            return
        g = src_glyf[gname]
        if g.isComposite():
            for comp in g.components:
                ensure(src_glyf, comp.glyphName)
        glyphs[gname] = copy.deepcopy(g)
        base['hmtx'].metrics[gname] = src['hmtx'].metrics[gname]
        names.add(gname)
        added.append(gname)

    for hit, buf, cmap in variants[1:]:
        if want <= set(base_cmap):
            break
        src = TTFont(io.BytesIO(buf))
        for cp in sorted(want - set(base_cmap)):
            gname = cmap.get(cp)
            if gname is None:
                continue
            ensure(src['glyf'].glyphs, gname)
            for table in base['cmap'].tables:
                if table.isUnicode():
                    table.cmap[cp] = gname
            base_cmap[cp] = gname
        src.close()

    new_order = order + added
    base.setGlyphOrder(new_order)
    base['maxp'].numGlyphs = len(new_order)
    base['hhea'].numberOfHMetrics = len(new_order)
    base['post'].formatType = 3.0          # 合并后字形名不可信，去名字表
    return base, upm, base_cmap, len(added), len(new_order)


def measure(base, upm, base_cmap, want):
    """字形度量：墨迹宽 / xMin / yMin / yMax（em）"""
    from fontTools.pens.boundsPen import BoundsPen
    gs = base.getGlyphSet()
    out = {}
    for cp in sorted(want & set(base_cmap)):
        bp = BoundsPen(gs)
        try:
            gs[base_cmap[cp]].draw(bp)
        except Exception:
            bp.bounds = None
        b = bp.bounds or (0, 0, upm // 4, upm // 2)
        out[cp] = ((b[2] - b[0]) / upm, b[0] / upm, b[1] / upm, b[3] / upm)
    return out


def write_assets(base, upm, metrics):
    os.makedirs(os.path.dirname(FONT_OUT), exist_ok=True)
    base.save(FONT_OUT)
    with open(METRICS_OUT, 'w', encoding='utf-8') as fh:
        fh.write('// 由 tools/build_jianpu_font.py 生成，**请勿手改**（重跑脚本即可）\n')
        fh.write('// 数据源：印刷 PDF 内嵌 MMP2005 字体（跨 PDF 合并字形）\n')
        fh.write('//\n')
        fh.write('// 值 = [墨迹宽, xMin, yMin, yMax]，单位 em（相对 upm=%d；负值表示基线之下）\n' % upm)
        fh.write('// 用途：曲谱视图「字体原生渲染」的列宽与行盒高度（advance 已压平不可用）\n')
        fh.write('library;\n\n')
        fh.write('const Map<String, List<double>> kJianpuGlyphMetrics = {\n')
        for cp in sorted(metrics):
            w, x0, y0, y1 = metrics[cp]
            fh.write("  '%04x': [%.4f, %.4f, %.4f, %.4f],\n" % (cp, w, x0, y0, y1))
        fh.write('};\n')


def main():
    want, nlines = used_codepoints()
    print('库内主旋律谱行 %d 行，用到码位 %d 个' % (nlines, len(want)))
    variants, covered = collect(want)
    if not variants:
        print('未找到任何 MMP2005 子集')
        return 1
    print('收集子集 %d 份，最优覆盖 %d/%d，累计 %d/%d'
          % (len(variants), variants[0][0], len(want), len(covered & want), len(want)))
    base, upm, base_cmap, nadd, ntotal = merge(variants, want)
    missing = sorted(want - set(base_cmap))
    print('合并完成：新增字形 %d，总计 %d；仍缺码位 %d %s'
          % (nadd, ntotal, len(missing), ['%04x' % c for c in missing]))
    metrics = measure(base, upm, base_cmap, want)
    print('\n码位  墨迹宽   xMin    yMin   yMax')
    for cp in sorted(metrics):
        print('  %04x %.3f %+.3f %+.3f %+.3f' % (cp, *metrics[cp]))
    if not APPLY:
        print('\n[dry-run] 未写文件；加 --apply 生成资产。')
        return 0
    write_assets(base, upm, metrics)
    print('已写入 %s (%.1f KB)' % (FONT_OUT, os.path.getsize(FONT_OUT) / 1024))
    print('已写入 %s (%d 条)' % (METRICS_OUT, len(metrics)))
    return 0


if __name__ == '__main__':
    sys.exit(main())
