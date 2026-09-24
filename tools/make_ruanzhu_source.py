"""软著「源程序鉴别材料」生成器（V 版本取自 hymn_app/pubspec.yaml 单源）。

口径（中国版权保护中心实务）：
- 源程序提交**前、后各连续 30 页**（共 60 页），**每页不少于 50 行**；
  全部源程序不足 60 页时提交全部；
- 页眉标注**软件名称 + 版本号**（与申请表一致），本脚本另加页码域；
- 源程序范围 = 著作权人自写的 `hymn_app/lib/**/*.dart`（按路径排序拼接为连续文本）；
  第三方依赖（pub 包/引擎代码）与素材数据**不**纳入鉴别材料。

产物（docs/ruanzhu/v<版本>/）：
- 源程序鉴别材料_V<版本>.txt   （纯文本，含页眉与分页符，便于核对行数）
- 源程序鉴别材料_V<版本>.docx  （Word：真页眉 = 名称+版本+页码域；等宽字体；每页分页符）

用法：python tools/make_ruanzhu_source.py
"""
import math
import pathlib
from typing import cast

from docx import Document
from docx.enum.text import WD_BREAK
from docx.oxml import OxmlElement
from docx.shared import Pt
from docx.styles.style import ParagraphStyle

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC_ROOT = ROOT / 'hymn_app' / 'lib'
LINES_PER_PAGE = 50
HALF_PAGES = 30
APP_NAME = 'EchoHymn · 聆听赞美诗'


def app_version():
    for line in (ROOT / 'hymn_app' / 'pubspec.yaml').read_text(encoding='utf-8').splitlines():
        if line.startswith('version:'):
            return line.split(':', 1)[1].strip().split('+')[0].strip()
    raise SystemExit('无法解析 pubspec 版本')


def collect_lines():
    files = sorted(SRC_ROOT.rglob('*.dart'), key=lambda p: p.as_posix())
    lines = []
    for f in files:
        lines.extend(f.read_text(encoding='utf-8').splitlines())
    return files, lines


def paginate(lines):
    total_pages = math.ceil(len(lines) / LINES_PER_PAGE)
    if total_pages <= HALF_PAGES * 2:
        idx = list(range(total_pages))
    else:
        idx = list(range(HALF_PAGES)) + list(range(total_pages - HALF_PAGES, total_pages))
    pages = []
    for p in idx:
        pages.append(lines[p * LINES_PER_PAGE:(p + 1) * LINES_PER_PAGE])
    return pages, total_pages


W = '{http://schemas.openxmlformats.org/wordprocessingml/2006/main}'


def _fld_run(instr):
    """WORD 域运行：begin + instrText + separate + end（打开文档时自动计算）"""
    r = OxmlElement('w:r')
    fc = OxmlElement('w:fldChar')
    fc.set(W + 'fldCharType', 'begin')
    r.append(fc)
    it = OxmlElement('w:instrText')
    it.set(W + 'space', 'preserve')
    it.text = instr
    r.append(it)
    fs = OxmlElement('w:fldChar')
    fs.set(W + 'fldCharType', 'separate')
    r.append(fs)
    fe = OxmlElement('w:fldChar')
    fe.set(W + 'fldCharType', 'end')
    r.append(fe)
    return r


def add_page_field(paragraph):
    """在页眉段落追加：第 {PAGE} 页 / 共 {NUMPAGES} 页"""
    paragraph.add_run('第 ')
    paragraph._p.append(_fld_run(' PAGE '))
    paragraph.add_run(' 页 / 共 ')
    paragraph._p.append(_fld_run(' NUMPAGES '))
    paragraph.add_run(' 页')


def build_docx(pages, version, out):
    doc = Document()
    sec = doc.sections[0]
    header = sec.header.paragraphs[0]
    header.text = f'{APP_NAME}  V{version}    '
    add_page_field(header)
    for run in header.runs:
        run.font.size = Pt(9)
    # 样式对象的静态类型是 BaseStyle，font 属性只在 ParagraphStyle 上声明 → 显式 cast
    style = cast(ParagraphStyle, doc.styles['Normal'])
    style.font.name = 'Consolas'
    style.font.size = Pt(9)
    style.element.get_or_add_rPr().get_or_add_rFonts().set(
        W + 'eastAsia', '宋体')
    for i, page in enumerate(pages):
        if i > 0:
            doc.add_paragraph().add_run().add_break(WD_BREAK.PAGE)
        for ln in page:
            p = doc.add_paragraph(ln if ln.strip() else ' ')
            p.paragraph_format.space_after = Pt(0)
            p.paragraph_format.space_before = Pt(0)
            p.paragraph_format.line_spacing = 1.0
    doc.save(str(out))


def main():
    version = app_version()
    files, lines = collect_lines()
    pages, total_pages = paginate(lines)
    outdir = ROOT / 'docs' / 'ruanzhu' / f'v{version}'
    outdir.mkdir(parents=True, exist_ok=True)

    txt = outdir / f'源程序鉴别材料_V{version}.txt'
    with open(txt, 'w', encoding='utf-8', newline='\n') as fh:
        for i, page in enumerate(pages):
            fh.write(f'【页眉】{APP_NAME}  V{version}   第 {i + 1} 页 / 共 {len(pages)} 页'
                     f'（源程序第 {i * LINES_PER_PAGE + 1}~'
                     f'{i * LINES_PER_PAGE + len(page)} 行 / 全程序共 {len(lines)} 行）\n')
            fh.write('\n'.join(page) + '\n')
            fh.write('\f')
    docx = outdir / f'源程序鉴别材料_V{version}.docx'
    build_docx(pages, version, docx)

    print(f'版本 V{version}；源文件 {len(files)} 个；总行数 {len(lines)}；'
          f'全程序页数 {total_pages}；提交页数 {len(pages)}（每页 {LINES_PER_PAGE} 行）')
    print('产物：')
    print(' ', txt)
    print(' ', docx)


if __name__ == '__main__':
    main()
