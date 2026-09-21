# 临时：OCR 验证校准结果（勿提交）
# 用法: python _verify_ocr.py [hymn...]  （默认 1..50）
import os, sys, json, re, time, sqlite3
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _crop_bands import build_band_image
from _ocr_score import ocr, normalize_line
from _rebuild_dryrun import DBMAP, SEED, sym_of

DB = sqlite3.connect(r'e:\EchoHymn\data\tjc_hymn.db')
DB.row_factory = sqlite3.Row

def db_notes(hn):
    out = []
    for r in DB.execute('SELECT line_no, notes FROM hymn_score_line WHERE hymn_number=? AND is_primary=1 ORDER BY page, y', (hn,)):
        out.append((r['line_no'], r['notes']))
    return out

def canon(s):
    return re.sub(r'\s+', '', s or '')

def main(hns):
    results = {}
    tot = {'pt': 0, 'ct': 0, 'it': 0}
    for hn in hns:
        band = rf'e:\EchoHymn\tools\_vb_{hn}.png'
        groups = build_band_image(hn, band)
        dbs = db_notes(hn)
        if not dbs:
            continue
        try:
            lines, usage, dt = ocr(band, len(dbs), high_res=True, model='qwen3-vl-plus')
        except Exception as e:
            print(f'hymn {hn}: OCR FAIL {e}')
            continue
        it = getattr(usage.prompt_tokens_details, 'image_tokens', None) if usage.prompt_tokens_details else None
        tot['pt'] += usage.prompt_tokens; tot['ct'] += usage.completion_tokens; tot['it'] += it or 0
        diffs = []
        if len(lines) != len(dbs):
            diffs.append(('LINECOUNT', len(dbs), len(lines)))
        for (ln, note), ocrln in zip(dbs, lines):
            a, b = canon(note), canon(ocrln)
            if a != b:
                diffs.append((ln, a, b))
        results[hn] = {'diffs': diffs, 'usage': [usage.prompt_tokens, usage.completion_tokens, it]}
        flag = 'OK ' if not diffs else 'DIFF'
        print(f'hymn {hn:>2}: {flag} {dt:.1f}s img={it} diffs={len(diffs)}')
        for d in diffs:
            print('    ', d)
    print(f'== TOKENS prompt={tot["pt"]} completion={tot["ct"]} image={tot["it"]} total={tot["pt"]+tot["ct"]}')
    with open(r'e:\EchoHymn\tools\_verify_results.json', 'w', encoding='utf-8') as f:
        json.dump(results, f, ensure_ascii=False, indent=1)
    ok = sum(1 for v in results.values() if not v['diffs'])
    print(f'完美曲目: {ok}/{len(results)}')

if __name__ == '__main__':
    main(sys.argv[1:] or [str(i) for i in range(1, 51)])
