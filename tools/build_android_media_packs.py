#!/usr/bin/env python3
"""Android installer 数据包生成（2026-11-13 用户定稿）

把 `data/Hymn_Downloads` 按**三类 × 两半**打成 6 个 zip（每个 < 2 GB，便于传输）：

  scores-0-237.zip   / scores-238-474.zip    简谱 + 五线谱 PNG
  vocal-0-237.zip    / vocal-238-474.zip     人聲版 + 3/389 四部合唱 + 9 首鋼琴替代
  piano-0-237.zip    / piano-238-474.zip     鋼琴版 + 249 人聲替代

zip 内路径 = DB 的 `Hymn_Downloads/<目录>/<文件名>`（与 App 导入白名单完全一致）。
音频为已压缩格式，使用 `ZIP_STORED`（不重复压缩、速度最快）。

用法：
    python tools/build_android_media_packs.py --out installer/output/android
"""

import argparse
import hashlib
import json
import os
import sqlite3
import sys
import zipfile

# 人声版 9 首「云端无原版 → 用鋼琴版替代」的编号（ANDROID_PLAN §1.4 ⑤）
VOCAL_PIANO_FALLBACK = {
    '103', '107', '178', '255', '268', '274_b', '308', '386', '387',
}
# 人声版 2 首「四部合唱版替代」
VOCAL_CHOIR_FALLBACK = {'3', '389'}
# 钢琴版 1 首「人聲版替代」
PIANO_VOCAL_FALLBACK = {'249'}


def load_rows(db_path):
    con = sqlite3.connect(db_path)
    con.row_factory = sqlite3.Row
    rows = con.execute(
        'SELECT id, hymn_number, title, audio_versions, '
        'numbered_png_path, staff_png_path FROM tjc_hymn ORDER BY id'
    ).fetchall()
    con.close()
    return rows


def parse_versions(text):
    if not text:
        return {}
    try:
        value = json.loads(text)
    except (TypeError, ValueError):
        return {}
    return {str(k): str(v) for k, v in value.items() if v} if isinstance(value, dict) else {}


def pick_files(row, kind):
    """返回该首在该类别下要打包的相对路径列表（只取真实存在的文件）。"""
    paths = []
    versions = parse_versions(row['audio_versions'])
    if kind == 'scores':
        for col in ('numbered_png_path', 'staff_png_path'):
            p = row[col]
            if p:
                paths.append(p)
        return paths

    num = row['hymn_number']
    for version, rel in versions.items():
        if kind == 'piano':
            if '鋼琴' in version:
                paths.append(rel)
        else:  # vocal
            if '人聲' in version:
                paths.append(rel)
    if kind == 'piano' and num in PIANO_VOCAL_FALLBACK:
        for version, rel in versions.items():
            if '人聲' in version:
                paths.append(rel)
    if kind == 'vocal':
        if num in VOCAL_CHOIR_FALLBACK:
            for version, rel in versions.items():
                if '合唱' in version:
                    paths.append(rel)
        if num in VOCAL_PIANO_FALLBACK:
            for version, rel in versions.items():
                if '鋼琴' in version:
                    paths.append(rel)
    return paths


def sha256_file(path, chunk=1 << 20):
    digest = hashlib.sha256()
    with open(path, 'rb') as fh:
        while True:
            block = fh.read(chunk)
            if not block:
                break
            digest.update(block)
    return digest.hexdigest()


def build_pack(rows, kind, half, start, end, src_root, out_dir):
    name = '%s-%d-%d' % (kind, start, end)
    zip_path = os.path.join(out_dir, name + '.zip')
    manifest_path = os.path.join(out_dir, name + '.json')
    collected = []
    total = 0
    with zipfile.ZipFile(zip_path, 'w', zipfile.ZIP_STORED, allowZip64=True) as zf:
        for row in rows[half[0]:half[1]]:
            for rel in pick_files(row, kind):
                abs_path = os.path.join(src_root, rel.replace('/', os.sep))
                if not os.path.isfile(abs_path):
                    continue
                arcname = rel.replace('\\', '/')
                zf.write(abs_path, arcname)
                collected.append(arcname)
                total += os.path.getsize(abs_path)
    manifest = {
        'name': name,
        'kind': kind,
        'range': [start, end],
        'files': len(collected),
        'bytes': total,
        'sha256': sha256_file(zip_path),
    }
    with open(manifest_path, 'w', encoding='utf-8') as fh:
        json.dump(manifest, fh, ensure_ascii=False, indent=2)
    print('[OK] %-22s files=%-5d %7.1f MB  sha256=%s'
          % (name, len(collected), total / 1024 / 1024, manifest['sha256'][:16]))
    return zip_path, manifest


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--db', default=os.path.join('data', 'tjc_hymn.db'))
    parser.add_argument('--src-root', default='data')
    parser.add_argument('--out', default=os.path.join('installer', 'output', 'android'))
    parser.add_argument('--mid', type=int, default=237,
                        help='前半首数（默认 237 → 0-237 / 238-474）')
    args = parser.parse_args()

    if not os.path.isfile(args.db):
        print('[FAIL] 数据库不存在：%s' % args.db)
        return 1
    os.makedirs(args.out, exist_ok=True)

    rows = load_rows(args.db)
    total = len(rows)
    mid = min(args.mid, total)
    print('曲目 %d 首 → 前半 1..%d / 后半 %d..%d' % (total, mid, mid + 1, total))

    packs = []
    for kind in ('scores', 'vocal', 'piano'):
        packs.append(build_pack(rows, kind, (0, mid), 1, mid, args.src_root, args.out))
        packs.append(build_pack(rows, kind, (mid, total), mid + 1, total,
                                args.src_root, args.out))

    sums = []
    for path, manifest in packs:
        sums.append('%s  %s' % (manifest['sha256'], os.path.basename(path)))
    with open(os.path.join(args.out, 'SHA256SUMS.txt'), 'w',
              encoding='utf-8-sig') as fh:
        fh.write('\n'.join(sums) + '\n')
    print('[OK] SHA256SUMS.txt 已生成（%d 个包）' % len(packs))
    return 0


if __name__ == '__main__':
    sys.exit(main())
