# -*- coding: utf-8 -*-
r"""EchoHymn 加密载荷打包：staging 目录 -> AES-256 加密 7z（含加密头）

用法: python make_payload.py <staging目录> <输出.7z>
密码与 echohymn.iss 中 DecodeKey() 的混淆字节保持同步。
"""
import os
import sys

import py7zr

PASSWORD = "EchoHymn2026"  # 8 位；与 iss DecodeKey 的 $1F,$39,$32,$35,$12,$23,$37,$34 对应


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__)
        return 2
    staging = os.path.abspath(sys.argv[1])
    out = os.path.abspath(sys.argv[2])
    if not os.path.isdir(staging):
        print("staging 不存在:", staging)
        return 2
    if os.path.exists(out):
        os.remove(out)

    n, total = 0, 0
    for root, _, files in os.walk(staging):
        for f in files:
            n += 1
            total += os.path.getsize(os.path.join(root, f))
    print(f"载荷文件数: {n}  合计: {total / 2**30:.2f} GB")

    # 媒体素材基本不可压缩：低档位 preset 提速，体积几乎不变。
    # 注意：必须逐文件写入且不写目录条目/"." 根条目——Inno is7zxa 解包
    # FullPaths=True 时遇 "." 根条目会报 0x80070005（实测），平铺文件列表最稳。
    with py7zr.SevenZipFile(out, mode="w", password=PASSWORD, header_encryption=True,
                            filters=[{"id": py7zr.FILTER_LZMA2, "preset": 1}]) as z:
        for rel in sorted(os.path.relpath(os.path.join(r, f), staging).replace("\\", "/")
                          for r, _, fs in os.walk(staging) for f in fs):
            z.write(os.path.join(staging, rel.replace("/", os.sep)), arcname=rel)
    print(f"PAYLOAD_OK {out}  {os.path.getsize(out) / 2**30:.2f} GB")
    return 0


if __name__ == "__main__":
    sys.exit(main())
