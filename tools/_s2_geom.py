"""任务②c：目标码位上下文渲染（每个 3 样本，bbox 四周扩 16pt 含相邻音符）"""
import os, sqlite3, collections
import fitz
from PIL import Image

DB = sqlite3.connect(r'e:\EchoHymn\data\tjc_hymn.db')
DB.row_factory = sqlite3.Row
TARGET = ['5d3d', '5d39', '600b', '601a', '5e61', '5e60', '5e62', '5e63', '5d49', '602a', '5e68', '5e6b']
T = set(TARGET)
found = collections.defaultdict(list)
for r in DB.execute('SELECT hymn_number, pdf_path FROM hymn_score'):
    if all(len(found[t]) >= 3 for t in TARGET):
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
                        if cp in T and len(found[cp]) < 3:
                            found[cp].append((r['hymn_number'], pno, tuple(ch['bbox'])))
    doc.close()

Z = fitz.Matrix(6, 6)
tiles = []
for cp in TARGET:
    for hn, pno, bbox in found[cp]:
        doc = fitz.open(os.path.join(r'e:\EchoHymn\data',
            DB.execute('SELECT pdf_path FROM hymn_score WHERE hymn_number=?', (hn,)).fetchone()[0]))
        x0, y0, x1, y1 = bbox
        clip = fitz.Rect(x0 - 16, y0 - 16, x1 + 16, y1 + 16)
        pix = doc[pno].get_pixmap(matrix=Z, clip=clip)
        fn = rf'e:\EchoHymn\tools\_s2c_{cp}_{hn}.png'
        pix.save(fn)
        tiles.append((cp, hn, fn))
        doc.close()
imgs = [Image.open(fn) for _, _, fn in tiles]
cw = max(i.width for i in imgs); chh = max(i.height for i in imgs)
COLS = 3
rows = (len(imgs) + COLS - 1) // COLS
sheet = Image.new('RGB', (COLS * (cw + 8) + 8, rows * (chh + 8) + 8), (240, 240, 240))
for k, im in enumerate(imgs):
    sheet.paste(im, (8 + (k % COLS) * (cw + 8), 8 + (k // COLS) * (chh + 8)))
sheet.save(r'e:\EchoHymn\tools\_s2c_sheet.png')
# 打印网格顺序（每行3个）
for k in range(0, len(tiles), COLS):
    print(' | '.join(f'{cp}@{hn}' for cp, hn, _ in tiles[k:k+COLS]))