"""任务②d：低频码位纯字形大倍率渲染（bbox 紧裁 + 12x）"""
import os, sqlite3, collections
import fitz
from PIL import Image

DB = sqlite3.connect(r'e:\EchoHymn\data\tjc_hymn.db')
DB.row_factory = sqlite3.Row
TARGET = ['5e66', '5e67', '5e68', '5e69', '5e6a', '5e6b', '5e6c', '5e6d', '5e6e', '5e6f',
          '5e5b', '5e5c', '5e5d', '5e5f', '5d4a', '602f', '5c6f', '5e80', '601b', '600c', '602a']
T = set(TARGET)
found = collections.defaultdict(list)
for r in DB.execute('SELECT hymn_number, pdf_path FROM hymn_score'):
    if all(len(found[t]) >= 2 for t in TARGET if t in found) and len(found) >= len(TARGET):
        break
    doc = fitz.open(os.path.join(r'e:\EchoHymn\data', r['pdf_path']))
    for pno in range(len(doc)):
        for blk in doc[pno].get_text('rawdict')['blocks']:
            for ln in blk.get('lines', []):
                for sp in ln['spans']:
                    if 'MMP' not in sp['font']:
                        continue
                    for ch in sp['chars']:
                        cp = '%04x' % ord(ch['c'])
                        if cp in T and len(found[cp]) < 2:
                            found[cp].append((r['hymn_number'], pno, tuple(ch['bbox'])))
    doc.close()

# 用 glyph bbox（ink 范围）而非 em box：page.get_text 的 char bbox 即 ink box
Z = fitz.Matrix(12, 12)
tiles = []
for cp in TARGET:
    for hn, pno, bbox in found[cp]:
        doc = fitz.open(os.path.join(r'e:\EchoHymn\data',
            DB.execute('SELECT pdf_path FROM hymn_score WHERE hymn_number=?', (hn,)).fetchone()[0]))
        x0, y0, x1, y1 = bbox
        clip = fitz.Rect(x0 - 1.5, y0 - 1.5, x1 + 1.5, y1 + 1.5)
        pix = doc[pno].get_pixmap(matrix=Z, clip=clip)
        fn = rf'e:\EchoHymn\tools\_s2d_{cp}_{hn}.png'
        pix.save(fn)
        tiles.append((cp, hn, fn))
        doc.close()
if not tiles:
    print('no tiles')
    raise SystemExit
imgs = [Image.open(fn) for _, _, fn in tiles]
cw = max(i.width for i in imgs); chh = max(i.height for i in imgs)
COLS = 4
rows = (len(imgs) + COLS - 1) // COLS
sheet = Image.new('RGB', (COLS * (cw + 10) + 10, rows * (chh + 10) + 10), (230, 230, 230))
for k, im in enumerate(imgs):
    sheet.paste(im, (10 + (k % COLS) * (cw + 10), 10 + (k // COLS) * (chh + 10)))
sheet.save(r'e:\EchoHymn\tools\_s2d_sheet.png')
for k in range(0, len(tiles), COLS):
    print(' | '.join(f'{cp}@{hn}' for cp, hn, _ in tiles[k:k+COLS]))