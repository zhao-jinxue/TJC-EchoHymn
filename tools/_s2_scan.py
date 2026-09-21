"""任务②a：primary 行 y±12 带内全部 PDF 字符码位盘点（不看白名单），
找出 notes 中缺失的记号（小节线/附点/时值线等），并渲染字形拼图。"""
import os, sqlite3, collections
import fitz
from PIL import Image

DB = sqlite3.connect(r'e:\EchoHymn\data\tjc_hymn.db')
DB.row_factory = sqlite3.Row
SEED = set('4e52 4e53 4e56 4e58 4e59 4e5c 4e5d 4e4c 4ee4 4ee5 4ee8 4ef0 5d1f 5d26 4e3c 5d4c 5d42 4e43 4e42 4ed9 5d27 4ef1'.split())
DBMAP = {r['codepoint']: r['sym'] for r in DB.execute('SELECT codepoint, sym FROM hymn_codepoint_map')}
KNOWN = SEED | set(DBMAP)

cnt = collections.Counter()
sample = {}   # cp -> (hn, page, bbox)
for r in DB.execute('SELECT hymn_number, pdf_path FROM hymn_score'):
    doc = fitz.open(os.path.join(r'e:\EchoHymn\data', r['pdf_path']))
    prim = [dict(p) for p in DB.execute(
        'SELECT line_no, page, y FROM hymn_score_line WHERE hymn_number=? AND is_primary=1', (r['hymn_number'],))]
    for p in prim:
        for blk in doc[p['page']].get_text('rawdict')['blocks']:
            for ln in blk.get('lines', []):
                for sp in ln['spans']:
                    if 'MMP' not in sp['font']:
                        continue
                    for ch in sp['chars']:
                        if not ch['c'].strip():
                            continue
                        cy = (ch['bbox'][1] + ch['bbox'][3]) / 2
                        if abs(cy - p['y']) > 12:
                            continue
                        cp = '%04x' % ord(ch['c'])
                        cnt[cp] += 1
                        if cp not in KNOWN and cp not in sample:
                            sample[cp] = (r['hymn_number'], p['page'], tuple(ch['bbox']))
    doc.close()

unk = {cp: n for cp, n in cnt.items() if cp not in KNOWN}
print('primary 带内未知码位（按频次）:')
for cp, n in sorted(unk.items(), key=lambda x: -x[1]):
    print(f'  {cp} x{n}')
print('未知种类:', len(unk), ' 未知实例总数:', sum(unk.values()))

# 渲染字形拼图（每码位取首个样本）
Z = fitz.Matrix(4, 4)
tiles = []
for cp in sorted(unk, key=lambda c: -unk[c])[:40]:
    hn, pno, bbox = sample[cp]
    pdf = DB.execute('SELECT pdf_path FROM hymn_score WHERE hymn_number=?', (hn,)).fetchone()[0]
    doc = fitz.open(os.path.join(r'e:\EchoHymn\data', pdf))
    x0, y0, x1, y1 = bbox
    pix = doc[pno].get_pixmap(matrix=Z, clip=fitz.Rect(x0-2, y0-2, x1+2, y1+2))
    fn = rf'e:\EchoHymn\tools\_s2_{cp}.png'
    pix.save(fn)
    doc.close()
    tiles.append((cp, unk[cp], fn))
imgs = [(Image.open(fn), cp, n) for cp, n, fn in tiles]
COLS = 8
cw = max(i.width for i, _, _ in imgs)
ch = max(i.height for i, _, _ in imgs)
sheet = Image.new('RGB', (COLS * (cw + 6), ((len(imgs) + COLS - 1) // COLS) * (ch + 6)), 'white')
for k, (im, cp, n) in enumerate(imgs):
    sheet.paste(im, ((k % COLS) * (cw + 6), (k // COLS) * (ch + 6)))
sheet.save(r'e:\EchoHymn\tools\_s2_sheet.png')
print('sheet order:', [cp for cp, n, _ in tiles])