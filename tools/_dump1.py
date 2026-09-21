import sqlite3
DB = sqlite3.connect(r'e:\EchoHymn\data\tjc_hymn.db')
DB.row_factory = sqlite3.Row
for r in DB.execute("SELECT line_no, code_seq, notes FROM hymn_score_line WHERE hymn_number='12' AND is_primary=1 ORDER BY line_no"):
    print('L', r['line_no'], 'notes=', r['notes'][:60])
    print('   seq:', r['code_seq'][:110])
print()
for cp in ('4ee1', '4ee2', '4ef8', '4ee9', '4ee3'):
    row = DB.execute('SELECT sym, source FROM hymn_codepoint_map WHERE codepoint=?', (cp,)).fetchone()
    print(cp, dict(row) if row else None)
T = set(TARGET)
found = collections.defaultdict(list)
for r in DB.execute('SELECT hymn_number, pdf_path FROM hymn_score'):
    if all(len(found[t]) >= 3 for t in TARGET):
        break
    doc = fitz.open(os.path.join(r'e:\EchoHymn\data', r['pdf_path']))
    for pno in range(len(doc)):
        for sp in doc[pno].get_texttrace():
            if 'MMP' not in sp['font']:
                continue
            for uni, glyph, origin, bb in sp['chars']:
                cp = '%04x' % uni
                if cp in T and len(found[cp]) < 3:
                    found[cp].append((r['hymn_number'], pno, tuple(bb), origin[1]))
    doc.close()
DBMAP = {r['codepoint']: r['sym'] for r in DB.execute('SELECT codepoint, sym FROM hymn_codepoint_map')}
Z = fitz.Matrix(10, 10)
tiles = []
for cp in TARGET:
    for hn, pno, bbox, oy in found[cp][:2]:
        doc = fitz.open(os.path.join(r'e:\EchoHymn\data',
            DB.execute('SELECT pdf_path FROM hymn_score WHERE hymn_number=?', (hn,)).fetchone()[0]))
        x0, y0, x1, y1 = bbox
        # 墨迹在 em 底上方：裁 origin-24 到 origin+2
        pix = doc[pno].get_pixmap(matrix=Z, clip=fitz.Rect(x0 + 1, oy - 22, x0 + 14, oy + 2))
        fn = rf'e:\EchoHymn\tools\_gl_{cp}_{hn}.png'
        pix.save(fn)
        tiles.append((cp, hn, fn))
        doc.close()
imgs = [Image.open(fn) for _, _, fn in tiles]
cw = max(i.width for i in imgs); chh = max(i.height for i in imgs)
COLS = 6
sheet = Image.new('RGB', (COLS * (cw + 4), ((len(imgs) + COLS - 1) // COLS) * (chh + 4)), (235, 235, 235))
for k, im in enumerate(imgs):
    sheet.paste(im, ((k % COLS) * (cw + 4), (k // COLS) * (chh + 4)))
sheet.save(r'e:\EchoHymn\tools\_gl_sheet.png')
print('order:', [f'{cp}@{hn}' for cp, hn, _ in tiles])
print('DBMAP:', {cp: DBMAP.get(cp) for cp in TARGET})