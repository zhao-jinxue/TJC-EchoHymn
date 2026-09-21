import fitz, os, sqlite3
import numpy as np
DB = sqlite3.connect(r'e:\EchoHymn\data\tjc_hymn.db')
p = DB.execute("SELECT pdf_path FROM hymn_score WHERE hymn_number='1'").fetchone()[0]
doc = fitz.open(os.path.join(r'e:\EchoHymn\data', p))
Z = 8
# 列 x=88-104（首音：女高1 / 女低5̣），y 150-230
pix = doc[0].get_pixmap(matrix=fitz.Matrix(Z, Z), clip=fitz.Rect(88, 150, 104, 230))
arr = np.frombuffer(pix.samples, dtype=np.uint8).reshape(pix.height, pix.width, pix.n)
g = arr[:, :, :3].mean(axis=2)
segs = []
for r in range(g.shape[0]):
    cnt = int((g[r] < 100).sum())
    if cnt > 0:
        y = 150 + r / Z
        if segs and y - segs[-1][1] < 1.0:
            segs[-1][1] = y; segs[-1][2] = max(segs[-1][2], cnt)
        else:
            segs.append([y, y, cnt])
print('col x88-104 ink segs:')
for s in segs:
    print(f'  {s[0]:.1f}-{s[1]:.1f} h={s[1]-s[0]:.1f} w={s[2]}')
# 该列所有字符
for sp in doc[0].get_texttrace():
    if 'MMP' not in sp['font']:
        continue
    for uni, glyph, origin, bb in sp['chars']:
        if 86 <= bb[0] <= 100 and 140 < origin[1] < 235:
            print(f'  ch cp=%04x' % uni, f'x={bb[0]:.1f} origin={origin[1]:.1f} bbox=({bb[1]:.1f},{bb[3]:.1f})')