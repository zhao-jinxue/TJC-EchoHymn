"""任务②e：DBMAP 中字母 sym（qwertyu…/大写）码位的 primary 带内字形渲染"""
import os, sqlite3, collections
import fitz
from PIL import Image

DB = sqlite3.connect(r'e:\EchoHymn\data\tjc_hymn.db')
DB.row_factory = sqlite3.Row
DBMAP = {r['codepoint']: r['sym'] for r in DB.execute('SELECT codepoint, sym FROM hymn_codepoint_map')}
LETTER = {cp for cp, s in DBMAP.items() if len(s) == 1 and s.isalpha()}
print('字母 sym 码位:', sorted(LETTER))
cnt = collections.Counter()
sample = {}
for r in DB.execute('SELECT hymn_number, pdf_path FROM hymn_score LIMIT 120'):
    doc = fitz.open(os.path.join(r'e:\EchoHymn\data', r['pdf_path']))
    prim = [dict(p) for p in DB.execute(
        'SELECT line_no, page, y FROM hymn_score_line WHERE hymn_number=? AND is_primary=1', (r['hymn_number'],))]
    for p in prim:
        base = p['y'] + 8.7
        for sp in doc[p['page']].get_texttrace():
            if 'MMP' not in sp['font']:
                continue
            for uni, glyph, origin, bb in sp['chars']:
                if abs(origin[1] - base) > 3:
                    continue
                cp = '%04x' % uni
                if cp in LETTER:
                    cnt[cp] += 1
                    if cp not in sample:
                        sample[cp] = (r['hymn_number'], p['page'], tuple(bb))
    doc.close()
print('频次:', dict(cnt.most_common()))
Z = fitz.Matrix(10, 10)
tiles = []
for cp, n in cnt.most_common(24):
    hn, pno, bbox = sample[cp]
    doc = fitz.open(os.path.join(r'e:\EchoHymn\data',
        DB.execute('SELECT pdf_path FROM hymn_score WHERE hymn_number=?', (hn,)).fetchone()[0]))
    x0, y0, x1, y1 = bbox
    pix = doc[pno].get_pixmap(matrix=Z, clip=fitz.Rect(x0 - 1, y0 - 7, x1 + 7, y1))
    fn = rf'e:\EchoHymn\tools\_s2e_{cp}.png'
    pix.save(fn)
    doc.close()
    tiles.append((cp, DBMAP[cp], n, fn))
if tiles:
    imgs = [Image.open(fn) for _, _, _, fn in tiles]
    cw = max(i.width for i in imgs); chh = max(i.height for i in imgs)
    COLS = 6
    sheet = Image.new('RGB', (COLS * (cw + 6), ((len(imgs) + COLS - 1) // COLS) * (chh + 6)), 'white')
    for k, im in enumerate(imgs):
        sheet.paste(im, ((k % COLS) * (cw + 6), (k // COLS) * (chh + 6)))
    sheet.save(r'e:\EchoHymn\tools\_s2e_sheet.png')
    print('sheet order (cp=sym):', [f'{cp}={s} x{n}' for cp, s, n, _ in tiles])