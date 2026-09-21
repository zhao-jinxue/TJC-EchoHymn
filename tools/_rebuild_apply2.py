# 临时：女高重建落库 v2·增量式（校准任务，勿提交）
# 与 v1 区别：① 不整体清 primary——只翻转有迁移配对的行，nopair/mismatch 保守保留；
#            ② 全库 primary 行 notes 重解码（消除旧 map 时代的 ?/@）；
#            ③ chars.note 列按最终 primary 行 code_seq 统一重解码。
# 用法: python _rebuild_apply2.py [--apply] [--all | hymn...]
import os, sys, re, shutil, sqlite3, datetime
sys.path.insert(0, r'e:\EchoHymn\tools')
import _rebuild_dryrun as RD
from _rebuild_dryrun import (pdf_lines_of, systems_from_lyrics, DB, sym_of,
                             is_onset, align_seq, align)

# 本次扩量新增的罕见组合字形（人工目视 PDF 字形定案：均含高音点，时值短线不表征）
NEWMAP2 = {'4ef6': '4^', '4f62': '3^', '4e73': '4^'}

APPLY = '--apply' in sys.argv
if '--all' in sys.argv:
    _c = sqlite3.connect(r'e:\EchoHymn\data\tjc_hymn.db')
    hns = [r[0] for r in _c.execute(
        'SELECT hymn_number FROM hymn_score ORDER BY LENGTH(hymn_number), hymn_number')]
    _c.close()
else:
    hns = [a for a in sys.argv[1:] if not a.startswith('--')] or [str(i) for i in range(1, 51)]
DBPATH = r'e:\EchoHymn\data\tjc_hymn.db'
if APPLY:
    ts = datetime.datetime.now().strftime('%Y%m%d_%H%M%S')
    bak = DBPATH.replace('.db', f'.bak-{ts}.db')
    shutil.copy2(DBPATH, bak)
    print('backup ->', bak)
wdb = sqlite3.connect(DBPATH) if APPLY else None
if wdb:
    wdb.row_factory = sqlite3.Row
    _c = wdb.cursor()
    for cp, sym in NEWMAP2.items():
        _c.execute('INSERT OR REPLACE INTO hymn_codepoint_map (codepoint,sym,font,votes,total,source) VALUES (?,?,?,?,?,?)',
                   (cp, sym, 'MMP2005', 0, 0, 'glyph-20260919'))
    wdb.commit()
    RD.DBMAP.update(NEWMAP2)   # 让 sym_of 立即生效
    print('codepoint map updated:', NEWMAP2)

ALIAS = {}
for _i, _d in enumerate('1234567'):
    ALIAS['qwertyu'[_i]] = f'{_d}-'
    ALIAS['QWERTYU'[_i]] = f'{_d}^-'
    ALIAS['adfghjs'[_i]] = f'{_d}^---'
    ALIAS['ADFGHJS'[_i]] = f'{_d}^---'

def norm_sym(s):
    return ALIAS.get(s, s)

def decode_line(cps):
    notes = ''.join(norm_sym(sym_of(cp)) for cp in cps)
    core = notes.replace('-', '').replace('|', '')
    note_count = sum(1 for cp in cps if is_onset(cp))
    hold_count = sum(1 for cp in cps if sym_of(cp) == '-')
    return notes, core, note_count, hold_count

def build_moves(hn):
    lines, lyric_chars, rows = pdf_lines_of(hn)
    m = DB.execute('SELECT COUNT(*) c FROM hymn_score_lyric WHERE hymn_number=? AND stanza_no=1', (hn,)).fetchone()['c']
    n = len(rows)
    systems = systems_from_lyrics(lyric_chars, rows, m)
    if systems is None:
        if not m or n % m or n // m not in (2, 3, 4):
            return None, f'n={n} m={m}'
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
    pair, used = {}, set()
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
    free_sys = [i for i in range(len(systems)) if i not in pair]
    free_old = sorted([ln for ln in old_lines if ln not in used], key=lambda ln: lines[ln]['y'])
    for k, i in enumerate(free_sys):
        if k < len(free_old):
            pair[i] = free_old[k]
            used.add(free_old[k])
    moves, seen = [], set()
    for i, (sop, syl) in enumerate(systems):
        sop_ln = sop['line_no']
        if sop_ln in seen or i not in pair:
            continue
        seen.add(sop_ln)
        old_ln = pair[i]
        old = lines[old_ln]
        sopd = lines[sop_ln]
        chars = old_info[old_ln]
        idx = None
        if len(sopd['code_seq']) == len(old['code_seq']):
            idx = [c['note_index'] for c in chars]
        else:
            want = ''.join(c['syllable'] for c in chars)
            if len(syl) == len(chars) and ''.join(s[1] for s in syl) == want:
                xs = align_seq(sopd['code_seq'], sopd['chars'])
                idx = align(list(zip(sopd['code_seq'], xs)), syl)
        moves.append((old_ln, sop_ln, idx))
    return (lines, moves), None


STAT = {'moved': 0, 'same': 0, 'kept': 0, 'redecoded': 0, 'skip': 0}

def apply_hymn(hn):
    got, err = build_moves(hn)
    if got is None:
        STAT['skip'] += 1
        lines, moves = None, []
        print(f'hymn {hn}: SKIP {err} (仅重解码)')
    else:
        lines, moves = got
    todo = [(o, t, ix) for o, t, ix in moves if ix is not None]
    moved = [(o, t, ix) for o, t, ix in todo if o != t]
    same = [(o, t, ix) for o, t, ix in todo if o == t]
    if not APPLY:
        if moved:
            print(f'hymn {hn}: move {len(moved)} ' + ' '.join(f'{o}->{t}' for o, t, _ in moved))
        return len(moved)
    cur = wdb.cursor()
    cur.execute('BEGIN')
    # 1) 增量翻转：仅动确认迁移的行对
    for o, t, ix in moved:
        cur.execute('UPDATE hymn_score_line SET is_primary=0, part="harmony" WHERE hymn_number=? AND line_no=?', (hn, o))
        notes, core, nc, hc = decode_line(lines[t]['code_seq'])
        cur.execute('UPDATE hymn_score_line SET is_primary=1, part="melody", notes=?, notes_core=?, note_count=?, hold_count=? WHERE hymn_number=? AND line_no=?',
                    (notes, core, nc, hc, hn, t))
    # 2) chars 重建：moved 旧行 chars 迁到目标行，其余原样保留
    allchars = [dict(r) for r in cur.execute('SELECT * FROM hymn_score_char WHERE hymn_number=?', (hn,)).fetchall()]
    idx_map = {o: (t, ix) for o, t, ix in moved}
    targets = {t for _, t, _ in moved}
    cur.execute('DELETE FROM hymn_score_char WHERE hymn_number=?', (hn,))
    for c in allchars:
        if c['line_no'] in idx_map:
            t, ix = idx_map[c['line_no']]
            k = c['char_no'] - 1
            ni = ix[k] if k < len(ix) else -1
            cur.execute('INSERT INTO hymn_score_char (hymn_number,line_no,char_no,syllable,note_index,note,beat,delta,span,align_ok) VALUES (?,?,?,?,?,?,?,?,?,?)',
                        (hn, t, c['char_no'], c['syllable'], ni, '', c['beat'], c['delta'], c['span'], 1 if ni >= 0 else 0))
        else:
            if c['line_no'] in targets:
                continue   # 迁移目标行上的残留 chars 丢弃（已被配对行取代）
            cur.execute('INSERT INTO hymn_score_char (hymn_number,line_no,char_no,syllable,note_index,note,beat,delta,span,align_ok) VALUES (?,?,?,?,?,?,?,?,?,?)',
                        tuple(c[k] for k in ('hymn_number', 'line_no', 'char_no', 'syllable', 'note_index', 'note', 'beat', 'delta', 'span', 'align_ok')))
    # 3) lyric 行号 remap（仅 moved）
    remap = {o: t for o, t, _ in moved}
    lyr = [dict(r) for r in cur.execute('SELECT * FROM hymn_score_lyric WHERE hymn_number=?', (hn,)).fetchall()]
    cur.execute('DELETE FROM hymn_score_lyric WHERE hymn_number=?', (hn,))
    for r in lyr:
        ln = remap.get(r['line_no'], r['line_no'])
        if r['line_no'] not in remap and r['line_no'] in targets:
            continue
        cur.execute('INSERT INTO hymn_score_lyric (hymn_number,line_no,stanza_no,text,syllable_count,align_ok) VALUES (?,?,?,?,?,?)',
                    (hn, ln, r['stanza_no'], r['text'], r['syllable_count'], r['align_ok']))
    # 4) 全 primary 行 notes 重解码（含 same/未迁移行/skip 曲兜底）
    for r in cur.execute('SELECT line_no, code_seq FROM hymn_score_line WHERE hymn_number=? AND is_primary=1', (hn,)).fetchall():
        cps = (r['code_seq'] or '').split()
        if not cps:
            continue
        notes, core, nc, hc = decode_line(cps)
        cur.execute('UPDATE hymn_score_line SET notes=?, notes_core=?, note_count=?, hold_count=? WHERE hymn_number=? AND line_no=?',
                    (notes, core, nc, hc, hn, r['line_no']))
        STAT['redecoded'] += 1
    # 5) chars.note 列按最终 code_seq 重解码
    seqs = {r['line_no']: (r['code_seq'] or '').split() for r in cur.execute(
        'SELECT line_no, code_seq FROM hymn_score_line WHERE hymn_number=?', (hn,)).fetchall()}
    for c in cur.execute('SELECT line_no, char_no, note_index FROM hymn_score_char WHERE hymn_number=?', (hn,)).fetchall():
        cs = seqs.get(c['line_no']) or []
        ni = c['note_index']
        note = norm_sym(sym_of(cs[ni])) if cs and 0 <= ni < len(cs) else ''
        cur.execute('UPDATE hymn_score_char SET note=? WHERE hymn_number=? AND line_no=? AND char_no=?',
                    (note, hn, c['line_no'], c['char_no']))
    wdb.commit()
    STAT['moved'] += len(moved)
    STAT['same'] += len(same)
    STAT['kept'] += len(moves) - len(todo)
    if moved:
        print(f'hymn {hn}: move {len(moved)} same {len(same)} kept {len(moves)-len(todo)}')
    return len(moved)

if __name__ == '__main__':
    print('MODE =', 'APPLY' if APPLY else 'DRY', ' songs =', len(hns))
    total = sum(apply_hymn(hn) for hn in hns)
    print('TOTAL moved:', total, STAT)
