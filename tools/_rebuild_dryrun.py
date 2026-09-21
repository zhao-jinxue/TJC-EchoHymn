# 临时：女高重建 dry-run（校准任务，勿提交）
# 逻辑：y-几何分块定出每系统女高行 → 与歌词挂靠行(旧is_primary)配对 →
#       元素数一致则沿用 note_index；不一致则按 PDF x 坐标重对位。
import os, re, sys, json, sqlite3, collections
import fitz

DB = sqlite3.connect(r'e:\EchoHymn\data\tjc_hymn.db')
DB.row_factory = sqlite3.Row

# 码位 → 记号（db_map + seed 合并）
SEED = dict(zip('4e52 4e53 4e56 4e58 4e59 4e5c 4e5d 4e4c 4ee4 4ee5 4ee8 4ef0 5d1f 5d26 4e3c 5d4c 5d42 4e43 4e42 4ed9 5d27 4ef1'.split(),
                '1 2 3 4 5 6 7 0 1 2 3 5 - 5 0 7 6 7 7 b 6'.split()))
DBMAP = {r['codepoint']: r['sym'] for r in DB.execute('SELECT codepoint, sym FROM hymn_codepoint_map')}
NEWMAP = {'4e5e': '1^', '5d29': '#', '5d2e': 'b', '531c': '3'}  # 本次 OCR 字形识别新增

def sym_of(cp):
    return DBMAP.get(cp) or NEWMAP.get(cp) or SEED.get(cp) or '?'

ONSET_RE = re.compile(r'^[0-7]')
def is_onset(cp):
    s = sym_of(cp)
    return bool(ONSET_RE.match(s)) and s != '?'

def pdf_lines_of(hn):
    pdf = DB.execute('SELECT pdf_path FROM hymn_score WHERE hymn_number=?', (hn,)).fetchone()[0]
    doc = fitz.open(os.path.join(r'e:\EchoHymn\data', pdf))
    rows = [dict(r) for r in DB.execute(
        'SELECT line_no, page, y, code_seq FROM hymn_score_line WHERE hymn_number=? ORDER BY page, y', (hn,))]
    score_chars, lyric_chars = collections.defaultdict(list), collections.defaultdict(list)
    for pno in range(len(doc)):
        for blk in doc[pno].get_text('rawdict')['blocks']:
            for ln in blk.get('lines', []):
                for sp in ln['spans']:
                    font = sp['font']
                    for ch in sp['chars']:
                        if not ch['c'].strip():
                            continue
                        cx = (ch['bbox'][0] + ch['bbox'][2]) / 2
                        cy = (ch['bbox'][1] + ch['bbox'][3]) / 2
                        cp = '%04x' % ord(ch['c'])
                        rec = (pno, cy, cx, cp, ch['c'])
                        if 'MMP' in font:
                            score_chars[pno].append(rec)
                        else:
                            lyric_chars[pno].append(rec)
    out = {}
    for r in rows:
        cps = (r['code_seq'] or '').split()
        cand = [c for c in score_chars[r['page']] if abs(c[1] - r['y']) < 16]
        cand.sort(key=lambda c: c[2])
        # 与爬虫同口径：白名单过滤（剔除 3021 全角空格 / 602d 小节线 / 5e61 附点等噪声）
        allow = (set(DBMAP) | set(SEED) | set(NEWMAP)) - {'602d', '4ed7', '4ed8', '4f4f', '4f50'}
        cand = [c for c in cand if c[3] in allow]
        out[r['line_no']] = {'page': r['page'], 'y': r['y'], 'code_seq': cps,
                             'chars': cand, 'match': [c[3] for c in cand] == cps}
    return out, lyric_chars, rows

def lyric_line_chars(lyric_chars, page, y_top, y_bot):
    band = [c for c in lyric_chars[page] if y_top < c[1] < y_bot]
    if not band:
        return []
    band.sort(key=lambda c: c[1])
    first_y = band[0][1]
    row1 = [c for c in band if abs(c[1] - first_y) < 6]
    row1.sort(key=lambda c: c[2])
    return row1

def align(sop, syll):
    onsets = [(i, x) for i, (cp, x) in enumerate(sop) if is_onset(cp)]
    idxs, last = [], -1
    for x, ch in syll:
        best, bd, nlast = None, 1e9, last
        for k, (i, ex) in enumerate(onsets):
            if k < last:
                continue
            d = abs(ex - x)
            if d < bd:
                best, bd, nlast = i, d, k
        if best is None:
            return None
        idxs.append(best)
        last = nlast
    return idxs

def align_seq(target, stream):
    """把 PDF 字符流对齐到 code_seq 目标序列（允许跳过噪声字符）→ 返回与 target 等长的 x 列表"""
    out, j = [], 0
    for cp in target:
        k = j
        while k < len(stream) and stream[k][3] != cp:
            k += 1
        if k < len(stream):
            out.append(stream[k][2])
            j = k + 1
        else:
            # 目标码位在流中不存在（如 code_seq 混入的小节线 602d）→ 占位 None
            out.append(None)
    # 二次：None 用左邻 x + 平均步距外推
    xs = [x for x in out if x is not None]
    step = (xs[-1] - xs[0]) / max(1, len(xs) - 1) if len(xs) > 1 else 12.0
    last = xs[0] if xs else 0.0
    for i, x in enumerate(out):
        if x is None:
            x = last + step
            out[i] = x
        last = x
    return out

def cluster_lines(vals, gap):
    vals = sorted(vals)
    out = []
    for v in vals:
        if out and v - out[-1][-1] <= gap:
            out[-1].append(v)
        else:
            out.append([v])
    return out

def systems_from_lyrics(lyric_chars, rows, m):
    """通用系统检测：歌词字符按 y 聚行→聚组（自适应行距阈值），组数==m 时成功。
    返回 [(sop_line_dict, 第一行歌词[(x,ch)])]；失败返回 None"""
    bypage = collections.defaultdict(list)
    for c in [c for p in lyric_chars for c in lyric_chars[p]]:
        bypage[c[0]].append(c)

    def chars_near(pno, y):
        return sorted([c for c in lyric_chars[pno] if abs(c[1] - y) < 3], key=lambda c: c[2])

    def run(thr):
        groups = []
        for pno in sorted(bypage):
            page_lines = [r for r in rows if r['page'] == pno]
            if not page_lines:
                continue
            first_staff_y = min(r['y'] for r in page_lines)
            ys = cluster_lines([c[1] for c in bypage[pno]], 4)
            ys = [y for y in ys if len(y) >= 4 and y[0] > first_staff_y + 5]
            if not ys:
                continue
            gl = [[ys[0]]]
            for y in ys[1:]:
                if y[0] - gl[-1][-1][-1] <= thr:
                    gl[-1].append(y)
                else:
                    gl.append([y])
            for g in gl:
                y1 = g[0][0]
                syl = [(c[2], c[4]) for c in chars_near(pno, y1) if '\u4e00' <= c[4] <= '\u9fff']
                above = sorted([r['y'] for r in page_lines if r['y'] < y1 - 5])
                if not above:
                    return None
                chain = [above[-1]]
                for yy in reversed(above[:-1]):
                    if chain[-1] - yy < 35:
                        chain.append(yy)
                    else:
                        break
                sop_y = chain[-1]
                sop = next(r for r in page_lines if r['y'] == sop_y)
                groups.append((sop, syl))
        return groups if len(groups) >= m else None

    # 收集全页行距样本，阈值取"行距上界"与"组间距下界"之间
    gaps = []
    for pno in sorted(bypage):
        page_lines = [r for r in rows if r['page'] == pno]
        if not page_lines:
            continue
        first_staff_y = min(r['y'] for r in page_lines)
        ys = cluster_lines([c[1] for c in bypage[pno]], 4)
        ys = [y for y in ys if len(y) >= 4 and y[0] > first_staff_y + 5]
        gaps += [ys[k + 1][0] - ys[k][-1] for k in range(len(ys) - 1)]
    cand = sorted(set([17, 20, 25, 30] + [g + 0.5 for g in gaps if 5 < g < 80]))
    for thr in cand:
        g = run(thr)
        if g is not None:
            return g
    return None

def process(hn, verbose=False):
    lines, lyric_chars, rows = pdf_lines_of(hn)
    m = DB.execute('SELECT COUNT(*) c FROM hymn_score_lyric WHERE hymn_number=? AND stanza_no=1', (hn,)).fetchone()['c']
    n = len(rows)
    report = {'hymn': hn, 'm': m, 'rows': []}
    systems = systems_from_lyrics(lyric_chars, rows, m)
    by_text = systems is not None
    if systems is None:
        if not m or n % m or n // m not in (2, 3, 4):
            return {'hymn': hn, 'skip': f'n={n} m={m}'}
        per = n // m
        ordered = sorted(rows, key=lambda r: (r['page'], r['y']))
        systems = [(ordered[i * per], []) for i in range(m)]
    old_lines = [r['line_no'] for r in DB.execute(
        'SELECT line_no FROM hymn_score_char WHERE hymn_number=? GROUP BY line_no', (hn,))]
    old_info = {}
    for ln in old_lines:
        chars = [dict(r) for r in DB.execute(
            'SELECT char_no, syllable, note_index FROM hymn_score_char WHERE hymn_number=? AND line_no=? ORDER BY char_no', (hn, ln))]
        old_info[ln] = chars
    pair = {}
    used = set()
    if by_text:
        for i, (sop, syl) in enumerate(systems):
            txt = ''.join(s[1] for s in syl)
            if not txt:
                continue
            for ln, chars in old_info.items():
                if ln in used:
                    continue
                if ''.join(c['syllable'] for c in chars) == txt:
                    pair[i] = ln
                    used.add(ln)
                    break
    # 未配对的系统 × 未配对的旧行：按 y 序一对一补
    free_sys = [i for i in range(len(systems)) if i not in pair]
    free_old = sorted([ln for ln in old_lines if ln not in used], key=lambda ln: lines[ln]['y'])
    for k, i in enumerate(free_sys):
        if k < len(free_old):
            pair[i] = free_old[k]
            used.add(free_old[k])
    for i, (sop, syl) in enumerate(systems):
        sop_ln = sop['line_no']
        if any(r['sop'] == sop_ln for r in report['rows']):
            continue
        sopd = lines[sop_ln]
        if i not in pair:
            report['rows'].append({'old': None, 'sop': sop_ln, 'status': 'nopair',
                                   'sop_elems': len(sopd['code_seq']), 'chars': len(syl)})
            continue
        old_ln = pair[i]
        old = lines[old_ln]
        chars = old_info[old_ln]
        status = 'same' if sop_ln == old_ln else 'move'
        n_idx = None
        if len(sopd['code_seq']) == len(old['code_seq']):
            n_idx = [c['note_index'] for c in chars]
            status += '/shift'
        else:
            want = ''.join(c['syllable'] for c in chars)
            if len(syl) == len(chars) and ''.join(s[1] for s in syl) == want:
                xs = align_seq(sopd['code_seq'], sopd['chars'])
                sopx = list(zip(sopd['code_seq'], xs))
                n_idx = align(sopx, syl)
                status += '/realign' if n_idx else '/realignFAIL'
            else:
                status += '/lyricMISMATCH(%d vs %d)' % (len(syl), len(chars))
        report['rows'].append({'old': old_ln, 'sop': sop_ln, 'status': status,
                               'sop_elems': len(sopd['code_seq']), 'old_elems': len(old['code_seq']),
                               'chars': len(chars), 'idx': n_idx})
    return report

if __name__ == '__main__':
    if '--all' in sys.argv:
        hns = [r[0] for r in DB.execute(
            'SELECT hymn_number FROM hymn_score ORDER BY LENGTH(hymn_number), hymn_number')]
    else:
        hns = [a for a in sys.argv[1:] if not a.startswith('--')] or [str(i) for i in range(1, 51)]
    stat = collections.Counter()
    problems = []
    for hn in hns:
        rep = process(hn)
        if 'skip' in rep:
            stat['skip'] += 1
            problems.append((hn, rep['skip']))
            continue
        for r in rep['rows']:
            base = r['status'].split('/')[0]
            sub = r['status'].split('/')[1] if '/' in r['status'] else ''
            stat[f'{base}/{sub}'] += 1
            if 'FAIL' in sub or 'MISMATCH' in sub or base == 'nopair':
                problems.append((hn, r['old'], r['sop'], r['status']))
        if hn in ('1', '2'):
            print(json.dumps(rep, ensure_ascii=False, default=str)[:1500])
    print('\n== 统计 ==')
    for k, v in sorted(stat.items()):
        print(f'  {k}: {v}')
    print('问题行数:', len(problems))
    for p in problems[:25]:
        print(' ', p)

