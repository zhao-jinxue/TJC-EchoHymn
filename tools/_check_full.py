"""全库一致性检查（apply 后验收）：
1) 每个 hymn_score_char.line_no 必须属于 is_primary=1 行（或明确孤儿统计）
2) note_index 在 code_seq 长度内
3) primary 行 notes 不含 ?/@/未解码别名（t,y,d,s,g,h,j,a,e,S）
4) 第1节 hymn_score_lyric.line_no 与 char 行一致
5) 每首歌至少 1 个 primary 行且有词
"""
import sqlite3, collections, re

DB = sqlite3.connect(r'e:\EchoHymn\data\tjc_hymn.db')
DB.row_factory = sqlite3.Row

bad_ref = 0
punct_rows = 0
bad_idx = 0
seqs = {}
for r in DB.execute('SELECT hymn_number, line_no, code_seq FROM hymn_score_line WHERE is_primary=1'):
    seqs[(r['hymn_number'], r['line_no'])] = (r['code_seq'] or '').split()
for c in DB.execute('SELECT hymn_number, line_no, note_index, syllable FROM hymn_score_char'):
    k = (c['hymn_number'], c['line_no'])
    if k not in seqs:
        bad_ref += 1
        continue
    if c['note_index'] < 0:
        punct_rows += 1   # 标点行（note_index=-1），2026-09-20 起合法
        continue
    if not (0 <= c['note_index'] < len(seqs[k])):
        bad_idx += 1
print('char 挂在非 primary 行:', bad_ref)
print('note_index 越界:', bad_idx)

BADSYM = re.compile(r'[?@tysghaej]')  # 未解码/别名残留（注意 b/# 合法）
bad_notes = []
for r in DB.execute('SELECT hymn_number, line_no, notes FROM hymn_score_line WHERE is_primary=1'):
    if BADSYM.search(r['notes'] or ''):
        bad_notes.append((r['hymn_number'], r['line_no'], (r['notes'] or '')[:40]))
print('notes 含未解码/别名残留行:', len(bad_notes))
for b in bad_notes[:10]:
    print('  ', b)

lyr1 = {(r['hymn_number'], r['line_no']) for r in DB.execute(
    'SELECT hymn_number, line_no FROM hymn_score_lyric WHERE stanza_no=1')}
orphan_lyr = [k for k in lyr1 if k not in seqs]
print('第1节歌词挂非 primary 行:', len(orphan_lyr), orphan_lyr[:8])

noprimary = [r['hymn_number'] for r in DB.execute(
    'SELECT hymn_number FROM hymn_score WHERE hymn_number NOT IN '
    '(SELECT hymn_number FROM hymn_score_line WHERE is_primary=1)')]
print('无 primary 行曲目:', len(noprimary), noprimary[:10])

# 显示可用性：app 视角（primary 且有词）行数
usable = len(lyr1 & set(seqs))
print('primary∧有词 可显示行:', usable, '/ primary 行总数:', len(seqs))
