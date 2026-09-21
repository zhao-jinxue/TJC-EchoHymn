/// 简谱曲谱「字体原生渲染」的排版模型（2026-09-21 二轮方案）
///
/// 背景（取证结论，见 `docs/Windows/UI_CONFIRMATION.md` §5.18）：
/// - 印刷 PDF 的乐谱是**位图**，其上文本层的 advance 被压平成 0.25em（不可排版）；
/// - 但**字体字形本身是预合成装饰**——`5̲`(4ef0)、`低音5`(4e4d)、`连音弧`(5e66~5e6e, 宽 1.7~3.7em)
///   各自都是单个字形。因此「库内 `code_seq` 码位序列 + 该字体」原生渲染即等于印刷记号：
///   时值线、低/高音点、附点、小节线、连音弧全部由字形自带，**不再自绘几何**。
/// - advance 不可用 → 用 [kJianpuGlyphMetrics]（字形墨迹宽 + 上下界，em）排布：
///   槽距 = 记谱字号（印刷实测 24.9pt / 24.6pt ≈ 1.0），歌词字号 = 0.5×记谱字号。
library;

import '../data/jianpu_metrics.dart';

/// 记谱字体族名（`assets/fonts/jianpu_mmp2005.ttf`：印刷 PDF 内嵌 MMP2005 跨文件合并子集）
const String kJianpuFontFamily = 'EchoJianpu';

/// 单个字形（一个码位）的度量与类别
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

  /// 小节线（细高竖线）——字形本身跨越整个谱系高度，绘制时按行带裁剪
  final bool barline;

  /// 由度量表构建；码位不在表内 → `glyphs` 为空、按「空列」处理
  static JianpuGlyph? of(int cp) {
    final m = kJianpuGlyphMetrics[cp.toRadixString(16).padLeft(4, '0')];
    if (m == null) return null;
    final tall = m[3] - m[2] >= 1.0;
    return JianpuGlyph(cp, m[0], m[1], m[2], m[3], tall && m[0] <= 0.30);
  }
}

/// 一个谱元素 = 一个 `code_seq` token（可含 '+连接的 1~4 个码位）及其字形与解码记号
class JianpuElement {
  JianpuElement(this.token, this.sym)
      : glyphs = [
          for (final cp in token.split('+'))
            if (int.tryParse(cp, radix: 16) case final v?)
              if (JianpuGlyph.of(v) case final g?) g,
        ];

  /// 原始码位串（如 `4e59+5d3d`）
  final String token;

  /// 库内码本解码结果（空串 = 纯装饰字形：连音弧/延长记号等）
  final String sym;

  final List<JianpuGlyph> glyphs;

  /// 纯装饰（不占列位、覆盖绘制在音符之上）
  bool get isOverlay => sym.isEmpty;

  /// 小节线（按行带裁剪绘制）
  bool get hasBarline => glyphs.any((g) => g.barline);

  /// 元素墨迹总宽（em；含多码位）
  double get inkWidth => glyphs.fold(0.0, (s, g) => s + g.inkWidth);

  /// 元素墨迹上/下界（em）
  double get yMax =>
      glyphs.isEmpty ? 0 : glyphs.map((g) => g.yMax).reduce((a, b) => a > b ? a : b);

  double get yMin =>
      glyphs.isEmpty ? 0 : glyphs.map((g) => g.yMin).reduce((a, b) => a < b ? a : b);

  /// 未知码位（字体/度量表缺失）→ 渲染时跳过，不产生假记号
  bool get isKnown => glyphs.isNotEmpty;
}

/// 页面级行盒度量：全页字形墨迹上下界（em，**排除小节线**——line 由行带裁剪决定）
class JianpuPageMetrics {
  const JianpuPageMetrics(this.yTop, this.yBot);
  final double yTop;
  final double yBot;

  /// 音符行带高度（em）
  double get band => yTop - yBot;

  static JianpuPageMetrics of(Iterable<JianpuElement> elems) {
    var top = 0.0;
    var bot = 0.0;
    var first = true;
    for (final e in elems) {
      if (e.hasBarline || !e.isKnown) continue;
      if (first) {
        top = e.yMax;
        bot = e.yMin;
        first = false;
      } else {
        if (e.yMax > top) top = e.yMax;
        if (e.yMin < bot) bot = e.yMin;
      }
    }
    return first ? const JianpuPageMetrics(0.61, 0.10) : JianpuPageMetrics(top, bot);
  }
}
