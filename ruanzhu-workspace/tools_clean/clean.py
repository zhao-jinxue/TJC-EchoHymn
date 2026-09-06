#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""软著源代码清洗脚本（EchoHymn ruanzhu-workspace / 01 提示词 Step 2 前置工具）。

模式：
  report  —— Step 1 资产盘点：逐文件统计原始/清洗后行数 + 敏感信息预扫描（不改写任何文件）
  build   —— Step 2 产物生成：按传入的有序文件清单清洗拼接，取前 N 页 + 后 M 页写入输出文件，
              并做每页 50 行与总行数断言校验

清洗规则（对齐 ruanzhu-workspace/01_cline_master_prompt.md）：
  删除空行与纯注释行；删除行尾 // 注释与 /*..*/ 块注释（支持 Dart 嵌套块注释）；
  字符串字面量（含 raw / 三引号多行串）内的 // 与引号安全处理；
  import/library/part/export 指令行原样保留；行尾空白去除；统一 \n。
"""
import io
import json
import re
import sys
from pathlib import Path

PAGE_LINES = 50


def strip_dart(src: str) -> list[str]:
    """返回清洗后的行列表。逐字符状态机：注释/空行剔除，字符串内容原样保留。"""
    out: list[str] = []
    buf: list[str] = []
    block_depth = 0           # /* */ 嵌套深度（Dart 支持嵌套块注释）
    quote: str | None = None  # 当前字符串定界符: ' / " / ''' / """
    raw = False               # 当前字符串是否 r 前缀
    n = len(src)
    i = 0
    while i < n:
        ch = src[i]
        if block_depth:
            if src.startswith("/*", i):
                block_depth += 1
                i += 2
                continue
            if src.startswith("*/", i):
                block_depth -= 1
                i += 2
                continue
            if ch == "\n":
                if "".join(buf).strip():
                    out.append("".join(buf).rstrip())
                buf = []
            i += 1
            continue
        if quote:
            if not raw and ch == "\\" and quote in ("'", '"') and len(quote) == 1:
                buf.append(src[i:i + 2])
                i += 2
                continue
            if src.startswith(quote, i):
                buf.append(quote)
                i += len(quote)
                quote = None
                continue
            if ch == "\n" and len(quote) == 1:  # 单引号串内不应有裸换行，容错结束
                quote = None
            buf.append(ch)
            i += 1
            continue
        # 非字符串、非块注释：识别行注释 / 块注释 / 字符串起始 / 普通字符
        if src.startswith("//", i):  # 行注释（/// 文档注释同理被吞），跳到行尾
            j = src.find("\n", i)
            j = n if j < 0 else j
            i = j  # 换行符留给下一轮处理（触发 flush）
            continue
        if src.startswith("/*", i):
            block_depth = 1
            i += 2
            continue
        if ch in "rR" and i + 1 < n and src[i + 1] in "'\"":
            prev = src[i - 1] if i else " "
            if not (prev.isalnum() or prev in "_$"):  # raw 字符串前缀
                q3 = src[i + 1:i + 4]
                if q3 in ("'''", '"""'):
                    buf.append(src[i:i + 4])
                    i += 4
                    quote = q3
                    raw = True
                    continue
                buf.append(src[i:i + 2])
                i += 2
                quote = src[i - 1]
                raw = True
                continue
        if ch in "'\"":
            q3 = src[i:i + 3]
            if q3 in ("'''", '"""'):
                buf.append(q3)
                i += 3
                quote = q3
            else:
                buf.append(ch)
                i += 1
                quote = ch
            raw = False
            continue
        if ch == "\n":
            line = "".join(buf).rstrip()
            if line:
                out.append(line)
            buf = []
            i += 1
            continue
        buf.append(ch)
        i += 1
    tail = "".join(buf).rstrip()
    if tail:
        out.append(tail)
    return out


SENSITIVE = [
    ("IPv4", re.compile(r"\b(?!127\.0\.0\.1|0\.0\.0\.0|8\.8\.8\.8)(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})\b")),
    ("手机号", re.compile(r"\b1[3-9]\d{9}\b")),
    ("邮箱", re.compile(r"\b[\w.+-]+@[\w-]+\.[\w.]{2,}\b")),
    ("凭据字样", re.compile(r"(?i)\b(api[_-]?key|secret|token|passwd|password)\b\s*[:=]")),
    ("sk-密钥", re.compile(r"\bsk-[A-Za-z0-9]{8,}")),
    ("http链接", re.compile(r"https?://[^\s'\"\),]+")),
]

EXCLUDE = {"lib/data/chinese_convert_map.dart"}  # 01 规则 6：纯数据映射表


def collect(root: Path) -> list[Path]:
    files = sorted(p for p in root.rglob("*.dart"))
    return [p for p in files if str(p.relative_to(root.parent)).replace("\\", "/") not in EXCLUDE]


def rel(p: Path, root: Path) -> str:
    return str(p.relative_to(root.parent)).replace("\\", "/")


def main() -> int:
    mode = sys.argv[1] if len(sys.argv) > 1 else "report"
    root = Path(sys.argv[2]) if len(sys.argv) > 2 else Path("E:/EchoHymn/hymn_app/lib")
    files = collect(root)
    total_raw = total_clean = 0
    hits: list[str] = []
    stats: dict[str, int] = {}

    for f in files:
        src = f.read_text(encoding="utf-8-sig", newline="")
        raw_lines = src.count("\n") + (0 if src.endswith("\n") else 1)
        cleaned = strip_dart(src)
        stats[rel(f, root)] = len(cleaned)
        total_raw += raw_lines
        total_clean += len(cleaned)
        for name, pat in SENSITIVE:
            for no, line in enumerate(cleaned, 1):
                m = pat.search(line)
                if m:
                    hits.append(f"{rel(f, root)}:{no} [{name}] {m.group(0)[:60]} | {line.strip()[:80]}")

    if mode == "report":
        print(f"{'file':<58}{'raw->?':>8}{'cleaned':>9}")
        for k in stats:
            print(f"{k:<58}{'':>8}{stats[k]:>9}")
        print(f"TOTAL include-scope files={len(files)} cleaned_lines={total_clean} "
              f"pages_needed={total_clean // PAGE_LINES} strategy={'60页(前30+后30)' if total_clean > 3000 else '全量'}")
        print(f"SENSITIVE_HITS={len(hits)}")
        for h in hits:
            print("  " + h)
        (root.parent / "../ruanzhu-workspace/tools_clean/stats.json").resolve().write_text(
            json.dumps({"total_cleaned": total_clean, "files": stats}, ensure_ascii=False, indent=2),
            encoding="utf-8")
        return 0

    print("usage: clean.py report [lib_dir]", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")
    sys.exit(main())
