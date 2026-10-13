#!/usr/bin/env python3
"""曲谱版式实测：从快照 PNG 量「行带墨迹」——行距 / 墨迹高 / 墨迹比例（确定性证据）

用途（2026-10-13 建立）：调「行距 / 字号」这类版式常量时，**不许凭感觉**——
先在 golden 快照上量出数值，改常量后重量，两次数值对比即改动效果。

口径（务必与实现一致）：

- 快照来源：`hymn_app/test/jianpu_golden_test.dart` 的 golden PNG
  （生成 / 更新：`cd hymn_app && flutter test --update-goldens test/jianpu_golden_test.dart`）；
- 墨迹判定：灰度 < `--thr`（默认 200）；背景 `#F2F6FD`（≈246）与抗锯齿边缘不算；
- **行带（band）** = 竖直方向连续出现墨迹的像素行合并成一段（一个「排版行组」的墨迹，
  例：小节线跨音符行 + 下方记号行 ⇒ 该两行合成一条 band）；
- 分类：把各 band 的高度做 1 维 2 均值聚类（k-means，初始化取最小/最大高度）——
  **矮带 = 记谱行组**（音符 + 记号，字矮）、**高带 = 歌词行组**（汉字墨迹高）；
- 指标：
  - `歌词行距` = 相邻两条高带**墨迹中心**的间距（像素；最贴近人眼「两行歌词之间」的感受）；
  - `歌词净空` = 相邻两条高带之间的空白带高（= 行距 − 两条带墨迹高的一半）；
  - `歌词墨迹 / 记谱墨迹` = 两类带的墨迹高度中位数（比值即「记谱相对歌词多大」）。

用法：

    python tools/jianpu_ink_measure.py hymn_app/test/goldens/jianpu_020_stanza1.png
    python tools/jianpu_ink_measure.py <png> --thr 200 --json
    python tools/jianpu_ink_measure.py <实机截图.png> --crop 140:840   # 裁掉界面栏位

退出码：0 = 测量成功；2 = 参数/文件问题；3 = band 少于 2 条（无法测行距）。
"""

from __future__ import annotations

import argparse
import json
import statistics
import sys

try:
    import numpy as np
    from PIL import Image
except ImportError as exc:  # pragma: no cover - 环境缺依赖时给明确提示
    print(f'[错误] 需要 Pillow + numpy（pip install pillow numpy）：{exc}', file=sys.stderr)
    sys.exit(2)


def load_bands(path: str, thr: int, min_px: int, crop: tuple[int, int] | None = None,
               xcrop: tuple[int, int] | None = None) -> tuple[np.ndarray, list[dict]]:
    """返回 (灰度数组, band 列表)；band = 竖直连续的墨迹行段

    [crop] = (y0, y1) 只在指定像素行区间内测量（实机整屏截图裁掉界面栏位时用）
    [xcrop] = (x0, x1) 只统计指定像素列区间（量单列墨迹、避开小节线时用）
    """
    img = Image.open(path).convert('L')
    gray = np.asarray(img, dtype=np.uint8)
    top = 0
    if crop is not None:
        top = max(0, crop[0])
        gray = gray[top:max(top + 1, crop[1]), :]
    if xcrop is not None:
        gray = gray[:, max(0, xcrop[0]):max(xcrop[0] + 1, xcrop[1])]
    counts = (gray < thr).sum(axis=1)  # 每行墨迹像素数
    bands: list[dict] = []
    start = None
    for y, c in enumerate(counts):
        if c >= min_px and start is None:
            start = y
        elif c < min_px and start is not None:
            bands.append(_band(gray, start, y - 1, thr, top))
            start = None
    if start is not None:
        bands.append(_band(gray, start, len(counts) - 1, thr, top))
    return gray, bands


def _band(gray: np.ndarray, y0: int, y1: int, thr: int, offset: int = 0) -> dict:
    sub = gray[y0 : y1 + 1] < thr
    cols = np.where(sub.any(axis=0))[0]
    return {
        'y0': int(y0) + offset,
        'y1': int(y1) + offset,
        'h': int(y1 - y0 + 1),
        'ink_px': int(sub.sum()),
        'x0': int(cols[0]) if cols.size else -1,
        'x1': int(cols[-1]) if cols.size else -1,
    }


def kmeans2(values: list[int], iters: int = 50) -> tuple[float, float]:
    """1 维 2 均值聚类（初始化 = 最小 / 最大高度）"""
    lo, hi = float(min(values)), float(max(values))
    if lo == hi:
        return lo, hi
    for _ in range(iters):
        g0 = [v for v in values if abs(v - lo) <= abs(v - hi)]
        g1 = [v for v in values if abs(v - lo) > abs(v - hi)]
        if not g0 or not g1:
            break
        nlo, nhi = statistics.fmean(g0), statistics.fmean(g1)
        if abs(nlo - lo) < 1e-9 and abs(nhi - hi) < 1e-9:
            break
        lo, hi = nlo, nhi
    return (lo, hi) if lo <= hi else (hi, lo)


def measure(path: str, thr: int = 200, min_px: int = 3,
            crop: tuple[int, int] | None = None,
            xcrop: tuple[int, int] | None = None) -> dict:
    gray, bands = load_bands(path, thr, min_px, crop, xcrop)
    out: dict = {
        'file': path,
        'image': f'{gray.shape[1]}x{gray.shape[0]}',
        'thr': thr,
        'crop': list(crop) if crop else None,
        'xcrop': list(xcrop) if xcrop else None,
        'bands': bands,
    }
    if len(bands) < 2:
        out['labels'] = ['?'] * len(bands)
        return out

    lo, hi = kmeans2([b['h'] for b in bands])
    # 分类：**页面首带必为音符/记号行**（每个乐句块都以乐谱行开头）
    # → 首带所属簇标 note，另一簇标 lyric。小节线跨行会让「记谱带」比歌词带更高，
    #    故不能按「矮 = 记谱」判（2026-10-13 实测教训）。
    h0 = bands[0]['h']
    first_is_lo = abs(h0 - lo) <= abs(h0 - hi)
    labels = [
        'note' if (abs(b['h'] - lo) <= abs(b['h'] - hi)) == first_is_lo else 'lyric'
        for b in bands
    ]
    out['labels'] = labels

    for key in ('note', 'lyric'):
        hs = [b['h'] for b, lb in zip(bands, labels) if lb == key]
        out[f'{key}_count'] = len(hs)
        out[f'{key}_ink_median'] = round(statistics.median(hs), 1) if hs else None

    pitch: list[float] = []  # 歌词行距（相邻歌词带墨迹中心距）
    clear: list[float] = []  # 歌词净空（相邻歌词带之间的空白；内含中间那个乐谱行组）
    ly = [b for b, lb in zip(bands, labels) if lb == 'lyric']
    for a, b in zip(ly, ly[1:]):
        pitch.append((b['y0'] + b['y1']) / 2 - (a['y0'] + a['y1']) / 2)
        clear.append(b['y0'] - a['y1'] - 1)
    if pitch:
        out['lyric_pitch_median'] = round(statistics.median(pitch), 1)
        out['lyric_pitch_px'] = [round(p, 1) for p in pitch]
    if clear:
        out['lyric_clear_median'] = round(statistics.median(clear), 1)
        out['lyric_clear_px'] = [round(c, 1) for c in clear]
    if out.get('lyric_ink_median') and out.get('note_ink_median'):
        out['note_over_lyric_ink'] = round(
            out['note_ink_median'] / out['lyric_ink_median'], 3
        )
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description='曲谱快照行带墨迹测量（行距 / 字号）')
    ap.add_argument('png', help='快照 PNG 路径')
    ap.add_argument('--thr', type=int, default=200, help='墨迹灰度阈值（默认 200）')
    ap.add_argument('--min-px', type=int, default=3, help='一行至少多少墨迹像素算墨迹（默认 3）')
    ap.add_argument('--crop', metavar='Y0:Y1',
                    help='只在像素行 Y0~Y1 内测量（实机整屏截图裁掉界面栏位）')
    ap.add_argument('--xcrop', metavar='X0:X1',
                    help='只在像素列 X0~X1 内测量（避开小节线量单列记号墨迹）')
    ap.add_argument('--json', action='store_true', help='输出 JSON（默认人读格式）')
    args = ap.parse_args()

    def _pair(spec: str) -> tuple[int, int]:
        a, b = spec.split(':')
        return int(a), int(b)

    crop: tuple[int, int] | None = None
    xcrop: tuple[int, int] | None = None
    try:
        if args.crop:
            crop = _pair(args.crop)
        if args.xcrop:
            xcrop = _pair(args.xcrop)
    except ValueError:
        print('[错误] --crop / --xcrop 形如 Y0:Y1 / X0:X1', file=sys.stderr)
        return 2

    try:
        res = measure(args.png, args.thr, args.min_px, crop, xcrop)
    except FileNotFoundError:
        print(f'[错误] 找不到文件：{args.png}', file=sys.stderr)
        return 2

    if args.json:
        print(json.dumps(res, ensure_ascii=False, indent=2))
    else:
        print(f"文件：{res['file']}  图像：{res['image']}  阈值：{res['thr']}")
        print(f"{'#':>3} {'y0':>5} {'y1':>5} {'高':>4} {'墨迹px':>8} {'类别':<6}")
        for i, (b, lb) in enumerate(zip(res['bands'], res['labels'])):
            print(f"{i:>3} {b['y0']:>5} {b['y1']:>5} {b['h']:>4} {b['ink_px']:>8} {lb:<6}")
        print('-' * 46)
        print(
            '记谱带墨迹中位高 {} px（{} 条） / 歌词带墨迹中位高 {} px（{} 条）'.format(
                res.get('note_ink_median'),
                res.get('note_count'),
                res.get('lyric_ink_median'),
                res.get('lyric_count'),
            )
        )
        print(f"记谱墨迹 ÷ 歌词墨迹 = {res.get('note_over_lyric_ink')}")
        print(f"歌词行距（相邻歌词带墨迹中心距）中位数 = {res.get('lyric_pitch_median')} px")
        print(f"歌词净空（两条歌词带之间的空白）中位数 = {res.get('lyric_clear_median')} px")

    return 0 if len(res['bands']) >= 2 else 3


if __name__ == '__main__':
    sys.exit(main())
