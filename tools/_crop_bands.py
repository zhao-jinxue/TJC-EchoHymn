# 临时：按 PDF 几何裁剪女高谱带并堆叠（校准任务用，勿提交）
import os, sys, sqlite3
import fitz  # pymupdf

def systems_of(hn):
    db = sqlite3.connect(r'e:\EchoHymn\data\tjc_hymn.db')
    db.row_factory = sqlite3.Row
    # 校准后口径：is_primary=1 行即女高行
    prim = [dict(r) for r in db.execute(
        'SELECT line_no, page, y, x0, notes FROM hymn_score_line WHERE hymn_number=? AND is_primary=1 ORDER BY page, y', (hn,))]
    groups = [[r] for r in prim]
    return prim, groups, 'primary-rows'

def build_band_image(hn, out_png):
    db = sqlite3.connect(r'e:\EchoHymn\data\tjc_hymn.db')
    pdf_rel = db.execute('SELECT pdf_path FROM hymn_score WHERE hymn_number=?', (hn,)).fetchone()[0]
    doc = fitz.open(os.path.join(r'e:\EchoHymn\data', pdf_rel))
    prim, groups, how = systems_of(hn)
    ZOOM = 9.0
    pixmaps = []
    for g in groups:
        r = g[0]
        y1, x0 = r['y'], r['x0'] or 96.0
        page = doc[r['page']]
        W = page.rect.width
        clip = fitz.Rect(max(0, x0 - 10), y1 - 1.05 * 23, W, y1 - 0.10 * 23)
        pixmaps.append(page.get_pixmap(matrix=fitz.Matrix(ZOOM, ZOOM), clip=clip))
    from PIL import Image
    import io
    imgs = [Image.open(io.BytesIO(pm.tobytes('png'))) for pm in pixmaps]
    if not imgs:
        return groups
    w = max(im.width for im in imgs)
    pad = 40
    h_total = sum(im.height for im in imgs) + pad * (len(imgs) + 1)
    canvas = Image.new('L', (w, h_total), 255)
    yy = pad
    for im in imgs:
        canvas.paste(im.convert('L'), (0, yy)); yy += im.height + pad
    canvas.convert('RGB').save(out_png)
    for i, im in enumerate(imgs):
        im.convert('RGB').save(rf'e:\EchoHymn\tools\_band_{hn}_{i+1}.png')
    print(f'hymn {hn}: [{how}] lines={len(groups)} -> {out_png}')
    return groups

if __name__ == '__main__':
    for hn in sys.argv[1:] or ['1']:
        build_band_image(hn, rf'e:\EchoHymn\tools\_bands_{hn}.png')
