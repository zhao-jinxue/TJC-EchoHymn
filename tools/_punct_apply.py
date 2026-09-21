# 临时：任务① 歌词标点入库（校准任务，勿提交）
# 用法: python _punct_apply.py [--apply] [hymn...|--all]
# 逻辑：对每条挂有 chars 的 primary 行，取 PDF 文本层该行下方歌词带字符（含标点），
#       以汉字子序列与 DB syllable 串比对校验；一致则重建 chars：
#       标点作为独立 char 行（note_index=-1），汉字按原列位映射 note_index。
import sys, sqlite3, collections
import fitz
sys.path.insert(0, r'e:\EchoHymn\tools')
from _rebuild_dryrun import DB

APPLY = '--apply' in sys.argv
if '--all' in sys.argv:
    hns = [r['hymn_number'] for r in DB.execute(
        'SELECT hymn_number FROM hymn_score ORDER BY LENGTH(hymn_number), hymn_number')]
else:
    hns = [a for a in sys.argv[1:] if not a.startswith('--')] or ['1']
DBPATH = r'e:\EchoHymn\data\tjc_hymn.db'

def is_cjk(ch):
    return '\u4e00' <= ch <= '\u9fff'

def page_lyric_rows(doc, pno, y_ref):
    """PDF 该页 y_ref 下方最近的歌词字符行（含标点），按 x 排序"""
    best, bestdy = None, 1e9
    spans = []
    for blk in doc[pno].get_text('rawdict')['blocks']:
        for ln in blk.get('lines', []):
            for sp in ln['spans']:
                if 'MMP' in sp['font']:
                    continue
                for ch in sp['chars']:
                    if not ch['c'].strip():
                        continue
                    cy = (ch['bbox'][1] + ch['bbox'][3]) / 2
                    if ch['c'] in '①②③④⑤⑥⑦⑧⑨⑩⑪⑫⑬⑭⑮⑯⑰⑱⑲⑳':
                        continue
                    if y_ref + 5 < cy < y_ref + 110:
                        spans.append((cy, (ch['bbox'][0] + ch['bbox'][2]) / 2, ch['c']))
    if not spans:
        return None
    spans.sort(key=lambda s: s[0])
    row_y = spans[0][0]
    row = [s for s in spans if abs(s[0] - row_y) < 4]
    row.sort(key=lambda s: s[1])
    return [(x, c) for _, x, c in row]

def rebuild_chars(chars, pdf_row):
    """chars: DB 行 [{char_no,syllable,note_index,...}]；pdf_row: [(x,ch)] 含标点。
    返回新 chars 列表或 None（汉字数不一致）"""
    want = [c['syllable'] for c in chars if is_cjk(c['syllable'][0:1])]
    got = [c for _, c in pdf_row if is_cjk(c)]
    if want != got and len(want) != len(got):
        return None
    # 标点归属：出现在两个汉字之间的标点，插在前一个汉字之后
    new, k = [], 0
    for x, c in pdf_row:
        if is_cjk(c):
            if k < len(chars):
                new.append((c if want == got else chars[k]['syllable'], chars[k]['note_index']))
                k += 1
        else:
            new.append((c, -1))
    if k != len(chars):
        return None
    return new

STAT = collections.Counter()
def process(hn):
    row0 = DB.execute('SELECT pdf_path FROM hymn_score WHERE hymn_number=?', (hn,)).fetchone()
    if not row0:
        STAT['noscore'] += 1
        return
    doc = fitz.open(DBPATH.replace('tjc_hymn.db', '') + row0['pdf_path'])
    lines = {r['line_no']: dict(r) for r in DB.execute(
        'SELECT line_no, page, y FROM hymn_score_line WHERE hymn_number=?', (hn,))}
    prim = [r['line_no'] for r in DB.execute(
        'SELECT line_no FROM hymn_score_line WHERE hymn_number=? AND is_primary=1', (hn,))]
    cur.execute('BEGIN')
    for ln in prim:
        chars = [dict(r) for r in cur.execute(
            'SELECT char_no, syllable, note_index, beat, delta, span, align_ok FROM hymn_score_char '
            'WHERE hymn_number=? AND line_no=? ORDER BY char_no', (hn, ln))]
        if not chars:
            continue
        if any(not is_cjk(c['syllable'][0:1]) for c in chars):
            STAT['has_punct_already'] += 1
            continue
        info = lines[ln]
        prow = page_lyric_rows(doc, info['page'], info['y'])
        if prow is None:
            STAT['norow'] += 1
            continue
        new = rebuild_chars(chars, prow)
        if new is None:
            STAT['cjk_diff'] += 1
            continue
        npunct = sum(1 for s, _ in new if not is_cjk(s))
        if npunct == 0:
            STAT['nopunct'] += 1
            continue
        STAT['updated'] += 1
        STAT['punct_added'] += npunct
        if APPLY:
            cur.execute('DELETE FROM hymn_score_char WHERE hymn_number=? AND line_no=?', (hn, ln))
            for i, (s, ni) in enumerate(new):
                cur.execute('INSERT INTO hymn_score_char (hymn_number,line_no,char_no,syllable,note_index,beat,delta,span,align_ok) '
                            'VALUES (?,?,?,?,?,?,0,1,?)',
                            (hn, ln, i + 1, s, ni, 0, 1 if ni >= 0 else 0))
            # 同步 lyric.text（stanza 1..n 全部加标点：按 PDF 第1行文本替换 stanza1，其他节沿用 DB 文本）
            lyr = [dict(r) for r in cur.execute(
                'SELECT stanza_no, text FROM hymn_score_lyric WHERE hymn_number=? AND line_no=?', (hn, ln)).fetchall()]
            pdf_text = ''.join(s for s, _ in new)
            for r in lyr:
                if r['stanza_no'] == 1:
                    cur.execute('UPDATE hymn_score_lyric SET text=?, syllable_count=? WHERE hymn_number=? AND line_no=? AND stanza_no=1',
                                (pdf_text, sum(1 for s, _ in new if is_cjk(s)), hn, ln))
                else:
                    # 其他节：若 DB 文本汉字序列与 PDF 一致则同位置插标点（保守：不一致保持原样）
                    pass
    if APPLY:
        wdb.commit()
    else:
        cur.execute('ROLLBACK')
    doc.close()

wdb = sqlite3.connect(DBPATH) if APPLY else DB
if APPLY:
    import shutil, datetime
    ts = datetime.datetime.now().strftime('%Y%m%d_%H%M%S')
    bak = DBPATH.replace('.db', f'.bak-{ts}-pre-punct.db')
    shutil.copy2(DBPATH, bak)
    print('backup ->', bak)
    wdb.row_factory = sqlite3.Row
cur = wdb.cursor()
if __name__ == '__main__':
    print('MODE =', 'APPLY' if APPLY else 'DRY')
    for hn in hns:
        process(hn)
    print(dict(STAT))