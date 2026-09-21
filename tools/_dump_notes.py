import sqlite3
DB = sqlite3.connect(r'e:\EchoHymn\data\tjc_hymn.db')
DB.row_factory = sqlite3.Row
for hn in ['240', '124_a', '90']:
    print(f'===== hymn {hn} =====')
    for r in DB.execute(
            "SELECT l.line_no, l.notes, "
            "(SELECT text FROM hymn_score_lyric y WHERE y.hymn_number=l.hymn_number AND y.line_no=l.line_no AND y.stanza_no=1) t "
            "FROM hymn_score_line l WHERE l.hymn_number=? AND l.is_primary=1 ORDER BY l.page, l.y", (hn,)):
        print(f"L{r['line_no']:3d} | {r['notes'][:52]:52s} | {(r['t'] or '')[:18]}")