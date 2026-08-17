"""从 data/tjc_hymn.db 全量字符生成简繁映射 Dart 文件（纯 Dart，无原生依赖）

用法：python tools/gen_convert_map.py (需先 pip install zhconv)
"""
import os
import sqlite3
from zhconv import convert

# 基于脚本自身位置解析路径（不依赖运行目录）
_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DB = os.path.join(_ROOT, 'data', 'tjc_hymn.db')
OUT = os.path.join(_ROOT, 'hymn_app', 'lib', 'data', 'chinese_convert_map.dart')


def main() -> None:
    conn = sqlite3.connect(DB)
    cur = conn.cursor()
    texts: list[str] = []
    cur.execute('SELECT title, lyricist, composer, source_info FROM tjc_hymn')
    for r in cur.fetchall():
        texts.extend(x for x in r if x)
    cur.execute('SELECT category, subcategory FROM hymn_category')
    for r in cur.fetchall():
        texts.extend(x for x in r if x)
    cur.execute('SELECT name FROM playlist_hymn')
    for r in cur.fetchall():
        if r[0]:
            texts.append(r[0])
    cur.execute('SELECT hymns FROM playlist_hymn')
    for r in cur.fetchall():
        if r[0]:
            texts.append(r[0])
    conn.close()

    all_chars: set[str] = set()
    for t in texts:
        all_chars.update(t)

    t2s: dict[str, str] = {}
    s2t: dict[str, str] = {}
    for ch in sorted(all_chars):
        if len(ch) != 1 or ord(ch) < 128:
            continue  # 跳过 ASCII/符号
        s = convert(ch, 'zh-cn')
        if s != ch:  # 繁体
            t2s[ch] = s
            if s not in s2t:  # 一简对多繁取首现
                s2t[s] = ch

    with open(OUT, 'w', encoding='utf-8') as f:
        f.write('// 由 data/tjc_hymn.db 全量字符生成的简繁映射表（纯 Dart，无原生依赖）\n')
        f.write('// 生成方式：python tools/gen_convert_map.py（zhconv 逐字转换数据库全部文本字符）\n')
        f.write('library;\n\n')
        f.write('/// 繁体 → 简体（单字）\n')
        f.write('const Map<String, String> kToSimplifiedByChar = {\n')
        for k in sorted(t2s):
            f.write(f"  '{k}': '{t2s[k]}',\n")
        f.write('};\n\n')
        f.write('/// 简体 → 繁体（单字，一简对多繁取数据库首现）\n')
        f.write('const Map<String, String> kToTraditionalByChar = {\n')
        for k in sorted(s2t):
            f.write(f"  '{k}': '{s2t[k]}',\n")
        f.write('};\n')

    print(f'Dart map written: t2s={len(t2s)} s2t={len(s2t)}')


if __name__ == '__main__':
    main()