import 'package:flutter/material.dart';

import '../app.dart';
import '../models/hymn.dart';
import '../models/hymn_ppt.dart';
import '../services/chinese_convert_service.dart';
import '../theme/app_fonts.dart';

/// 「PPT 官方编码 + 内嵌字体」曲谱歌词页（任务 6）
///
/// 与官方 PPT 完全同构的渲染方式：
/// - **简谱行**：编码串（如 `1  1    3  3 \ 5/5/\6/6  6\5/3/\`）用内嵌 `JianPu`
///   字体直接排版——数字/高低音点/时值下划线/小节线/延音线/反复记号皆为
///   字体 glyph，零宽修饰符（advance=0）自动叠画在前一字符上；
/// - **歌词行**：PPT 原串用内嵌 `EchoKai`（標楷體）直接排版，空格即对齐单位；
/// - **字号比恒为 1:2**（[kPptLyricFontRatio]，全库 6249 行拟合中位数 R=2.000），
///   因此两行只需把各自字体按真实 advance 排版、左对齐即可复现 PPT 的逐字对位；
/// - 字号由「页内最宽简谱行 × S ≤ 可用宽」+「最宽歌词行 × 2S ≤ 可用宽」+
///   总高约束三条件取最小值反推（不换行为硬约束）。
class PptScorePageView extends StatelessWidget {
  const PptScorePageView({
    super.key,
    required this.hymn,
    required this.slide,
    required this.constraints,
  });

  final Hymn hymn;
  final PptSlide slide;
  final BoxConstraints constraints;

  static const double padX = 20;
  static const double padTop = 20;
  static const double padBottom = 64;

  /// 行高（以简谱字号 S 为单位）：谱行 1.5、词行 2.8（=2S×1.4）、行距 0.35
  static const double kScoreRowH = 1.5;
  static const double kLyricRowH = 2.8;
  static const double kRowGap = 0.35;
  static const double kTitleH = 2.4;

  @override
  Widget build(BuildContext context) {
    final availW = constraints.maxWidth - padX * 2;
    final availH = constraints.maxHeight - padTop - padBottom;

    final maxScoreEm = slide.maxScoreEm == 0 ? 1.0 : slide.maxScoreEm;
    final maxLyricEm = slide.maxLyricEm == 0 ? 1.0 : slide.maxLyricEm;

    var fsUnits = kTitleH;
    for (final l in slide.lines) {
      if (l.isScoreLine && (l.lyric ?? '').isNotEmpty) {
        fsUnits += kScoreRowH + kLyricRowH + kRowGap;
      } else if (l.isScoreLine) {
        fsUnits += kScoreRowH + kRowGap;
      } else {
        fsUnits += kLyricRowH + kRowGap;
      }
    }

    final byScoreW = availW / maxScoreEm;
    final byLyricW = availW / (kPptLyricFontRatio * maxLyricEm);
    final byH = availH / fsUnits * AppFonts.lyricsScale;
    var size = byScoreW;
    if (byLyricW < size) size = byLyricW;
    if (byH < size) size = byH;
    size = size.clamp(8.0, 40.0);
    final totalH = fsUnits * size;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(padX, padTop, padX, padBottom),
      child: SizedBox(
        width: availW,
        height: totalH,
        child: CustomPaint(
          painter: _PptPainter(
            hymn: hymn,
            slide: slide,
            size: size,
            color: AppColors.textPrimary,
            subColor: AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _PptPainter extends CustomPainter {
  _PptPainter({
    required this.hymn,
    required this.slide,
    required this.size,
    required this.color,
    required this.subColor,
  });

  final Hymn hymn;
  final PptSlide slide;

  /// 简谱字号 S（歌词字号 = 2S）
  final double size;
  final Color color;
  final Color subColor;

  static const String _scoreFont = 'JianPu';
  static const String _lyricFont = 'EchoKai';

  TextPainter _tp(String text, double fs, String? family, Color c) {
    return TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: fs,
          height: 1.25,
          color: c,
          fontFamily: family,
          fontFamilyFallback: const ['EchoSans'],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
  }

  @override
  void paint(Canvas canvas, Size sz) {
    final conv = ChineseConvertService.instance;
    final title = _tp(
      '${conv.toSimplified(hymn.title)}　第 ${hymn.hymnNumber} 首　第 ${slide.slideNo} 页',
      (size * 1.05).clamp(13.0, 30.0),
      null,
      color,
    );
    title.paint(canvas, Offset((sz.width - title.width) / 2, 0));

    var y = PptScorePageView.kTitleH * size;
    final header = slide.header?.trim();
    if (slide.slideNo == 1 && header != null && header.isNotEmpty) {
      final hp = _tp(conv.toSimplified(header), size * 0.75, null, subColor);
      hp.paint(canvas, Offset((sz.width - hp.width) / 2, y - size * 1.2));
    }

    for (final line in slide.lines) {
      if (line.isScoreLine) {
        // 简谱行：字体自然 advance（数字 1em、空格 0.5em、零宽修饰 0）；
        // 编码为 ASCII，绝不可做简繁转换
        _tp(line.scoreEnc, size, _scoreFont, color).paint(canvas, Offset(0, y));
        y += PptScorePageView.kScoreRowH * size;
      }
      final lyric = line.lyric;
      if (lyric != null && lyric.trim().isNotEmpty) {
        // 歌词行：字号 2S，字体自然 advance（汉字 1em、半角 0.5em）
        _tp(conv.toSimplified(lyric), size * kPptLyricFontRatio, _lyricFont, color)
            .paint(canvas, Offset(0, y));
        y += PptScorePageView.kLyricRowH * size;
      }
      y += PptScorePageView.kRowGap * size;
    }
  }

  @override
  bool shouldRepaint(_PptPainter old) =>
      old.slide != slide || old.size != size || old.color != color;
}
