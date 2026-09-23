/// 简谱「印刷记谱字体」接入（`assets/fonts/jianpu_mmp2005.ttf`，family `EchoJianpu`）
///
/// 用途（2026-09-22 简谱网格视图改版后）：**只用于音符数字字形** ——
/// 该字体来自印刷 PDF 内嵌的 MMP2005（跨文件合并子集），数字本身就是印刷体；
/// 时值线 / 低·高音点 / 延长记号 / 小节线由视图自绘（数据侧这些记号在独立行/列，
/// 见 `lib/models/jianpu_grid.dart` 与 `docs/knowledge/TJC_APK_JIANPU_RENDER.md`）。
///
/// 度量表 `lib/data/jianpu_metrics.dart` 由 `tools/build_jianpu_font.py` 生成
/// （值 = [墨迹宽, xMin, yMin, yMax]，单位 em，相对 upm=2048；advance 已被压平不可用）。
library;

import '../data/jianpu_metrics.dart';

/// 记谱字体族名
const String kJianpuFontFamily = 'EchoJianpu';

/// 单个字形（一个码位）的度量
class JianpuGlyph {
  const JianpuGlyph(this.codepoint, this.inkWidth, this.xMin, this.yMin,
      this.yMax, this.barline);

  final int codepoint;

  /// 墨迹宽（em）
  final double inkWidth;

  /// 墨迹左右/上下界（em，相对基线）
  final double xMin;
  final double yMin;
  final double yMax;

  /// 细高竖线字形（印刷小节线）
  final bool barline;

  /// 由度量表构建；码位不在表内 → null（按「空字形」处理）
  static JianpuGlyph? of(int cp) {
    final m = kJianpuGlyphMetrics[cp.toRadixString(16).padLeft(4, '0')];
    if (m == null) return null;
    final tall = m[3] - m[2] >= 1.0;
    return JianpuGlyph(cp, m[0], m[1], m[2], m[3], tall && m[0] <= 0.30);
  }

  /// 按十六进制码位串（如 `4e59`）构建
  static JianpuGlyph? ofHex(String hex) {
    final cp = int.tryParse(hex, radix: 16);
    return cp == null ? null : of(cp);
  }
}

/// 印刷简谱数字码位（`1`~`7`）
const Map<int, int> kJianpuDigitCodepoints = {
  1: 0x4e52,
  2: 0x4e53,
  3: 0x4e56,
  4: 0x4e58,
  5: 0x4e59,
  6: 0x4e5c,
  7: 0x4e5d,
};

/// 印刷简谱「带低八度点」数字码位（1~7）
const Map<int, int> kJianpuLowDigitCodepoints = {
  1: 0x4e45,
  2: 0x4e47,
  3: 0x4e48,
  4: 0x4e4b,
  5: 0x4e4d,
  6: 0x4e4e,
  7: 0x4e4f,
};

/// 印刷简谱「带一条减时线」数字码位（1~7）
const Map<int, int> kJianpuBeam1DigitCodepoints = {
  1: 0x4eda,
  2: 0x4edc,
  3: 0x4edd,
  4: 0x4ede,
  5: 0x4edf,
  6: 0x4ee1,
  7: 0x4ee3,
};
