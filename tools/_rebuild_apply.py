# 临时：女高重建落库（校准任务，勿提交）
# 用法: python _rebuild_apply.py [--apply] [hymn...]
import os, sys, re, shutil, sqlite3, datetime
sys.path.insert(0, r'e:\EchoHymn\tools')
from _rebuild_dryrun import (pdf_lines_of, systems_from_lyrics, DB, sym_of,
                             is_onset, align_seq, align)

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
    bak = DBPATH.replace('.db', '.bak-20260919.db')
    if not os.path.exists(bak):
        shutil.copy2(DBPATH, bak)
        print('backup ->', bak)
wdb = sqlite3.connect(DBPATH) if APPLY else None
if wdb:
    wdb.row_factory = sqlite3.Row
    from _rebuild_dryrun import NEWMAP
    _c = wdb.cursor()
    for cp, sym in NEWMAP.items():
        _c.execute('INSERT OR REPLACE INTO hymn_codepoint_map (codepoint,sym,font,votes,total,source) VALUES (?,?,"MMP2005",0,0,"ocr-vision-20260919")', (cp, sym))
    wdb.commit()
    print('codepoint map updated:', NEWMAP)

def decode_notes(code_seq):
    return ''.join(sym_of(cp) for cp in code_seq.split())

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
    tgts = [t for _, t, ix in moves if ix is not None]
    if len(tgts) != len(set(tgts)):
        return None, 'duplicate targets'
    return (lines, moves), None


ALIAS = {}
for _i, _d in enumerate('1234567'):
    ALIAS['qwertyu'[_i]] = f'{_d}-'
    ALIAS['QWERTYU'[_i]] = f'{_d}^-'
    ALIAS['adfghjs'[_i]] = f'{_d}^---'
    ALIAS['ADFGHJS'[_i]] = f'{_d}^---'

def norm_sym(s):
    return ALIAS.get(s, s)

def apply_hymn(hn):
    got, err = build_moves(hn)
    if got is None:
        print(f'hymn {hn}: SKIP {err}')
        return 0
    lines, moves = got
    done = sum(1 for _, _, ix in moves if ix is not None)
    if not APPLY:
        print(f'hymn {hn}: {done} 行待迁 ' + ' '.join(f'{o}->{t}' for o, t, ix in moves if ix is not None and o != t))
        return done
    cur = wdb.cursor()
    cur.execute('BEGIN')
    cur.execute('UPDATE hymn_score_line SET is_primary=0, part="harmony" WHERE hymn_number=?', (hn,))
    for old_ln, sop_ln, idx in moves:
        if idx is None:
            continue
        cps = lines[sop_ln]['code_seq']
        notes = ''.join(norm_sym(sym_of(cp)) for cp in cps)
        core = notes.replace('-', '').replace('|', '')
        note_count = sum(1 for cp in cps if is_onset(cp))
        hold_count = sum(1 for cp in cps if sym_of(cp) == '-')
        cur.execute('UPDATE hymn_score_line SET is_primary=1, part="melody", notes=?, notes_core=?, note_count=?, hold_count=? WHERE hymn_number=? AND line_no=?',
                    (notes, core, note_count, hold_count, hn, sop_ln))
    allchars = [dict(r) for r in cur.execute('SELECT * FROM hymn_score_char WHERE hymn_number=?', (hn,)).fetchall()]
    cur.execute('DELETE FROM hymn_score_char WHERE hymn_number=?', (hn,))
    idx_map = {o: (t, ix) for o, t, ix in moves if ix is not None}
    targets = {t for _, t, ix in moves if ix is not None}
    for c in allchars:
        if c['line_no'] in idx_map:
            t, ix = idx_map[c['line_no']]
            k = c['char_no'] - 1
            ni = ix[k] if k < len(ix) else -1
            cs = lines[t]['code_seq']
            note = sym_of(cs[ni]) if 0 <= ni < len(cs) else ''
            cur.execute('INSERT INTO hymn_score_char (hymn_number,line_no,char_no,syllable,note_index,note,beat,delta,span,align_ok) VALUES (?,?,?,?,?,?,?,?,?,?)',
                        (hn, t, c['char_no'], c['syllable'], ni, note, c['beat'], c['delta'], c['span'], 1 if ni >= 0 else 0))
        else:
            if c['line_no'] in targets:
                continue   # 该系统的 chars 已由配对旧行迁入，丢弃残留
            cur.execute('INSERT INTO hymn_score_char (hymn_number,line_no,char_no,syllable,note_index,note,beat,delta,span,align_ok) VALUES (?,?,?,?,?,?,?,?,?,?)',
                        tuple(c[k] for k in ('hymn_number', 'line_no', 'char_no', 'syllable', 'note_index', 'note', 'beat', 'delta', 'span', 'align_ok')))
    remap = {o: t for o, t, ix in moves if ix is not None}
    lyr = [dict(r) for r in cur.execute('SELECT * FROM hymn_score_lyric WHERE hymn_number=?', (hn,)).fetchall()]
    cur.execute('DELETE FROM hymn_score_lyric WHERE hymn_number=?', (hn,))
    for r in lyr:
        ln = remap.get(r['line_no'], r['line_no'])
        if r['line_no'] not in remap and r['line_no'] in targets:
            continue   # 残留歌词行与迁移目标冲突，丢弃
        cur.execute('INSERT INTO hymn_score_lyric (hymn_number,line_no,stanza_no,text,syllable_count,align_ok) VALUES (?,?,?,?,?,?)',
                    (hn, ln, r['stanza_no'], r['text'], r['syllable_count'], r['align_ok']))
    wdb.commit()
    print(f'hymn {hn}: {done} 行已迁移')
    return done

if __name__ == '__main__':
    print('MODE =', 'APPLY' if APPLY else 'DRY')
    total = sum(apply_hymn(hn) for hn in hns)
    print('TOTAL migrated rows:', total)
