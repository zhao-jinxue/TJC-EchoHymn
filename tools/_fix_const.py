#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""临时脚本：移除 Dart 源码中「const 表达式内引用了 AppColors/ThemeController/themeById」的 const 关键字。
AppColors 已从 static const 改为动态 getter，此类 const 表达式不再合法。
用法: python tools/_fix_const.py
"""
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else pathlib.Path(r"e:\EchoHymn\hymn_app\lib")
pat = re.compile(r"(?<!\w)const\s+(?=[\[({A-Za-z_])")
close_map = {"(": ")", "[": "]", "{": "}"}
BANNED = ("AppColors.", "ThemeController.", "themeById(", "kThemes[")


def process(content: str) -> tuple[str, int]:
    out: list[str] = []
    pos = 0
    removed = 0
    while True:
        m = pat.search(content, pos)
        if not m:
            out.append(content[pos:])
            break
        start = m.end()
        i = start
        while i < len(content) and (content[i].isalnum() or content[i] in "_<>,."):
            i += 1
        if i < len(content) and content[i] in close_map:
            depth = 0
            j = i
            while j < len(content):
                c = content[j]
                if c in "([{":
                    depth += 1
                elif c in ")]}":
                    depth -= 1
                    if depth == 0:
                        break
                j += 1
            expr = content[i : j + 1]
            if any(b in expr for b in BANNED):
                out.append(content[pos : m.start()])
                pos = m.end()  # 跳过 'const ' 关键字
                removed += 1
                continue
        out.append(content[pos : m.end()])
        pos = m.end()
    return "".join(out), removed


total = 0
for path in sorted(root.rglob("*.dart")):
    text = path.read_text(encoding="utf-8")
    new, removed = process(text)
    if removed:
        path.write_text(new, encoding="utf-8")
        total += removed
        print(f"{removed:3d}  {path}")
print(f"TOTAL removed: {total}")
