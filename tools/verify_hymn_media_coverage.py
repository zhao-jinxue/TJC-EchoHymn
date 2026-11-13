#!/usr/bin/env python3
"""替代音频 474 全可播核对（ANDROID_PLAN §1.4 ⑤ / §7.4）

口径与 App 端 `lib/services/audio_service.dart` 完全一致：

  1. DB `tjc_hymn.audio_versions` 存的是**相对素材根**的文件路径（JSON）；
  2. `_hasAudioFile()` 的判据 = `data/<相对路径>` 文件存在（本脚本同口径）；
  3. 候选顺序 = `audio_version_list` 优先，再补 `audio_versions.keys`；
  4. 单音频版（piano / vocal）期望版本缺文件时，**按候选顺序取首个有文件的版本**
     （即"缺口互补替代"：钢琴版 `249` → 人聲版；人声版 `3`/`389` → 四部合唱、9 首 → 鋼琴版）；
  5. `lite` 无播放功能 → 不校验音频，仅统计扫描图素材。

用法：

    python tools/verify_hymn_media_coverage.py --variant full
    python tools/verify_hymn_media_coverage.py --variant piano --expect-substitutions 1
    python tools/verify_hymn_media_coverage.py --variant vocal --expect-substitutions 11
    python tools/verify_hymn_media_coverage.py --variant lite
    python tools/verify_hymn_media_coverage.py --variant full --json-out build/media-coverage.json

退出码：0 = 全部可播且替代数与预期一致；1 = 存在缺口或替代数不符。
"""

import argparse
import json
import os
import sqlite3
import sys

VARIANTS = {
    'full': None,       # 任一版本有文件即可
    'piano': '鋼琴版',
    'vocal': '人聲版',
    'lite': None,       # 不校验音频
}

# 扫描图列（lite 用于统计）
IMAGE_COLUMNS = ('numbered_png_path', 'staff_png_path',
                 'numbered_img_path', 'staff_img_path')


def load_rows(db_path):
    con = sqlite3.connect(db_path)
    con.row_factory = sqlite3.Row
    rows = con.execute(
        'SELECT hymn_number, title, ' + ', '.join(IMAGE_COLUMNS) +
        ', audio_version_list, audio_versions FROM tjc_hymn ORDER BY id'
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
    if not isinstance(value, dict):
        return {}
    return {str(k): str(v) for k, v in value.items() if v}


def parse_version_list(text):
    if not text:
        return []
    try:
        value = json.loads(text)
        if isinstance(value, list):
            return [str(x) for x in value]
    except (TypeError, ValueError):
        pass
    return [part.strip() for part in str(text).split(',') if part.strip()]


def existing_versions(versions, ordered, root):
    """按候选顺序返回 (version, 绝对路径) 中文件存在的那一个。"""
    for version in ordered:
        rel = versions.get(version)
        if not rel:
            continue
        path = os.path.join(root, rel.replace('/', os.sep))
        if os.path.isfile(path):
            return version, path
    return None, None


def substitution_rank(variant, version):
    """替代优先级（与 App 端 AudioService.substitutionOrder 保持一致）。"""
    if variant == 'vocal':
        if version == '人聲版':
            return 0
        if version == '四部合唱版':
            return 1
        if version.startswith('四部合唱'):
            return 2
        if '合唱' in version:
            return 3
        if '鋼琴' in version:
            return 9
        return 5
    if variant == 'piano':
        if version == '鋼琴版':
            return 0
        if '人聲' in version:
            return 1
        return 5
    return 0


def main():
    parser = argparse.ArgumentParser(description='EchoHymn 素材可播性核对')
    parser.add_argument('--variant', default='full', choices=list(VARIANTS))
    parser.add_argument('--db', default=os.path.join('data', 'tjc_hymn.db'))
    parser.add_argument('--root', default='data',
                        help='素材根目录（DB 相对路径的基准，默认 data/）')
    parser.add_argument('--expect-substitutions', type=int, default=None,
                        help='替代曲目数期望值（piano=1 / vocal=11）')
    parser.add_argument('--show', type=int, default=30,
                        help='最多打印多少条明细（默认 30）')
    parser.add_argument('--json-out', default=None)
    args = parser.parse_args()

    if not os.path.isfile(args.db):
        print('[FAIL] 数据库不存在：%s' % args.db)
        return 1

    expected = VARIANTS[args.variant]
    rows = load_rows(args.db)
    total = len(rows)

    playable = 0
    substituted = []
    missing = []
    lite_images = 0

    for row in rows:
        versions = parse_versions(row['audio_versions'])
        vlist = parse_version_list(row['audio_version_list'])
        ordered = [v for v in vlist if v in versions]
        ordered += [v for v in versions if v not in ordered]
        ordered.sort(key=lambda v: substitution_rank(args.variant, v))

        if args.variant == 'lite':
            if any(row[col] for col in IMAGE_COLUMNS):
                lite_images += 1
            continue

        actual, _path = existing_versions(versions, ordered, args.root)

        # 口径修正（2026-11-11）：App 端先判「变体期望版本」是否真有文件
        # （audio_service.dart 的 _hasAudioFile(expected)），缺才走候选替代。
        # 若直接取候选首个，vocal 会把 463 首人聲版误判成「替代鋼琴版」。
        if expected is not None:
            exp_version, _exp_path = existing_versions(
                versions, [expected], args.root)
            if exp_version == expected:
                playable += 1
                continue

        if actual is None:
            missing.append((row['hymn_number'], row['title'], sorted(versions)))
            continue
        if expected is None or actual == expected:
            playable += 1
        else:
            substituted.append(
                (row['hymn_number'], row['title'], expected, actual))

    print('=' * 60)
    print('变体: %s   数据库: %s   素材根: %s' % (args.variant, args.db, args.root))
    print('曲目总数: %d' % total)

    if args.variant == 'lite':
        print('lite：无播放功能，跳过音频核对；含扫描图的曲目 %d / %d'
              % (lite_images, total))
        print('=' * 60)
        return 0

    print('可直接播放（本版版本）: %d' % playable)
    print('替代播放: %d' % len(substituted))
    print('无可播文件（缺口）: %d' % len(missing))

    if substituted[:args.show]:
        print('\n-- 替代明细（最多 %d 条）--' % args.show)
        for num, title, want, got in substituted[:args.show]:
            print('  第 %-4s 首《%s》：期望 %s → 实际 %s' % (num, title, want, got))
    if missing[:args.show]:
        print('\n-- 缺口明细（最多 %d 条）--' % args.show)
        for num, title, versions in missing[:args.show]:
            print('  第 %-4s 首《%s》：DB 版本 %s' % (num, title, versions))

    failed = False
    if playable + len(substituted) != total:
        failed = True
        print('\n[FAIL] 可播 + 替代 ≠ 总数（%d + %d != %d）'
              % (playable, len(substituted), total))
    else:
        print('\n[OK] %d / %d 全部可播（含替代 %d）'
              % (total, total, len(substituted)))

    if args.expect_substitutions is not None:
        if len(substituted) == args.expect_substitutions:
            print('[OK] 替代数 = %d（与手册清单一致）' % len(substituted))
        else:
            failed = True
            print('[FAIL] 替代数 %d ≠ 期望 %d'
                  % (len(substituted), args.expect_substitutions))

    if args.json_out:
        payload = {
            'variant': args.variant,
            'total': total,
            'playable': playable,
            'substituted': [
                {'hymn_number': n, 'title': t, 'expected': w, 'actual': g}
                for n, t, w, g in substituted
            ],
            'missing': [
                {'hymn_number': n, 'title': t, 'versions': v}
                for n, t, v in missing
            ],
        }
        out_dir = os.path.dirname(os.path.abspath(args.json_out))
        os.makedirs(out_dir, exist_ok=True)
        with open(args.json_out, 'w', encoding='utf-8') as fh:
            json.dump(payload, fh, ensure_ascii=False, indent=2)
        print('[OK] 结果已写入 %s' % args.json_out)

    print('=' * 60)
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
