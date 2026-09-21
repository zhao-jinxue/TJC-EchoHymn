import 'package:flutter/material.dart';

import '../app.dart';
import '../models/hymn.dart';
import '../models/hymn_score.dart';
import '../services/chinese_convert_service.dart';
import '../theme/app_fonts.dart';

/// 「简谱曲谱 + 歌词」同步渲染页（数据源：`hymn_score_*` 表的逐字对位）
///
/// 版式 = 每行两排：**上排记号、下排歌词**，二者共用同一套等宽列，
/// 第 i 列即第 i 个谱元素 —— 一眼看清「哪个字落在哪个音上」。
///
/// **不换行硬约束**（需求：曲谱与歌词绝不因自动换行而错位）：
/// 字号上限由「页内最宽谱行的元素数」反推 ——
/// `cellW = 可用宽 / 最宽元素数`，`fontSize ≤ cellW`，
/// 因此一整行必然落在一行内；高度不足时再按行数收缩字号。
class ScoreLyricPageView extends StatelessWidget {
  const ScoreLyricPageView({
    super.key,
    required this.hymn,
    required this.page,
    required this.constraints,
  });

  final Hymn hymn;
  final ScorePage page;
  final BoxConstraints constraints;

  /// 上下留白 + 底部翻页条预留（翻页条自带背景，仍需足够净空避免压字）
  static const double padX = 20;
  static const double padTop = 20;
  static const double padBottom = 64;

  @override
  Widget build(BuildContext context) {
    final availW = constraints.maxWidth - padX * 2;
    final availH = constraints.maxHeight - padTop - padBottom;
    final nLines = page.lines.isEmpty ? 1 : page.lines.length;

    // 列宽 = 可用宽 / 最宽谱行元素数（保证单行不换行的充要条件）
    final maxElems = page.maxElements == 0 ? 1 : page.maxElements;
    final cellW = availW / maxElems;
    // 整页统一列网格宽：各行左对齐到同一列基准（行内元素数不同也不错位）
    final gridW = maxElems * cellW;
    // 高度约束：每行 = 记号排(1.06) + 行内距(0.12) + 歌词排(1.15) + 行间距(0.55~0.9)
    // ≈ 3.2 个字高，另留 3.5 行给标题区与余量（估算偏保守，宁可字号略小也不溢出）
    final byH = availH / (nLines * 3.2 + 3.5);
    final ls = AppFonts.lyricsScale;
    // 字号等级只放大高度方向；列宽 cellW 是「不换行」的硬上限，绝不可破
    var size = byH * ls;
    if (size > cellW) size = cellW;
    size = size.clamp(9.0, 46.0);
    final symSize = size * 0.92;
    final lyricSize = size;
    final titleSize = (size * 1.15).clamp(13.0, 30.0);
    final labelSize = (size * 0.55).clamp(10.0, 15.0);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(padX, padTop, padX, padBottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Text(
              '${ChineseConvertService.instance.toSimplified(hymn.title)}'
              '　第 ${hymn.hymnNumber} 首　第 ${page.stanzaNo} 节',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: titleSize,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          SizedBox(height: size * 0.6),
          for (var i = 0; i < page.lines.length; i++)
            _buildLine(
              page.lines[i],
              cellW: cellW,
              gridW: gridW,
              symSize: symSize,
              lyricSize: lyricSize,
              labelSize: labelSize,
              gapAfter: i + 1 < page.lines.length &&
                      page.lines[i + 1].phraseNo != page.lines[i].phraseNo
                  ? size * 0.9
                  : size * 0.55,
            ),
        ],
      ),
    );
  }

  /// 一条谱行：上排记号、下排歌词，同一套等宽列（整页统一列基准，左对齐）
  Widget _buildLine(
    ScoreLineRow line, {
    required double cellW,
    required double gridW,
    required double symSize,
    required double lyricSize,
    required double labelSize,
    required double gapAfter,
  }) {
    final cells = line.cellsFor(page.stanzaNo);
    final n = line.elements.length;
    return Padding(
      padding: EdgeInsets.only(bottom: gapAfter),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Center(
              child: Column(
                children: [
                  SizedBox(
                    width: gridW,
                    child: Row(
                      children: [
                        for (var i = 0; i < n; i++)
                          _SymCell(
                            sym: line.elements[i],
                            width: cellW,
                            height: symSize * 1.42,
                            size: symSize,
                            color: AppColors.textPrimary,
                          ),
                      ],
                    ),
                  ),
                  SizedBox(height: lyricSize * 0.06),
                  SizedBox(
                    width: gridW,
                    child: Row(
                      children: [
                        for (var i = 0; i < n; i++)
                          _LyricCell(
                            text: ChineseConvertService.instance
                                .toSimplified(cells[i] ?? ''),
                            width: cellW,
                            size: lyricSize,
                            color: line.isChorus
                                ? AppColors.primary
                                : AppColors.textSecondary,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 歌词单元：**音节居中于本列**，标点作小字号侧标紧随其右（可溢出列宽）
///
/// 2026-09-21（用户反馈修正）：此前标点并入前字后「整串居中」，
/// 导致音节偏离音符列中心（例：「上﹑」整体居中 → 「上」左移半格）。
/// 现在标点不参与居中、不占列位，只贴在音节右侧。
class _LyricCell extends StatelessWidget {
  const _LyricCell({
    required this.text,
    required this.width,
    required this.size,
    required this.color,
  });

  final String text;
  final double width;
  final double size;
  final Color color;

  /// 非「汉字/字母/数字/空格」均视为标点（随前字显示）
  static bool _isMark(int r) =>
      !(r >= 0x4e00 && r <= 0x9fff) && // CJK 基本区
      !(r >= 0x3400 && r <= 0x4dbf) && // CJK 扩展 A
      !(r >= 0xf900 && r <= 0xfaff) && // 兼容汉字
      !(r >= 0x20000 && r <= 0x2fa1f) && // 扩展 B+
      !(r >= 0x30 && r <= 0x39) &&
      !(r >= 0x41 && r <= 0x5a) &&
      !(r >= 0x61 && r <= 0x7a) &&
      r != 0x20;

  /// ASCII / 异体标点 → 印刷体全角标点（与印刷本一致）
  static const _norm = {
    0x2c: '，',
    0x2e: '。',
    0x3b: '；',
    0x3a: '：',
    0x21: '！',
    0x3f: '？',
    0xfe51: '、',
    0xfe10: '、',
    0xfe11: '、',
  };

  @override
  Widget build(BuildContext context) {
    final runes = text.runes.toList();
    var i = 0;
    while (i < runes.length && !_isMark(runes[i])) {
      i++;
    }
    final base = String.fromCharCodes(runes.take(i));
    final buf = StringBuffer();
    for (var k = i; k < runes.length; k++) {
      buf.write(_norm[runes[k]] ?? String.fromCharCode(runes[k]));
    }
    final marks = buf.toString();
    final baseStyle = TextStyle(
      fontSize: size,
      height: 1.15,
      fontFamily: 'EchoKai',
      fontFamilyFallback: const ['KaiTi', 'EchoSans'],
      color: color,
    );
    final height = size * 1.2;
    if (marks.isEmpty || base.isEmpty) {
      return SizedBox(
        width: width,
        height: height,
        child: Center(
          child: Text(
            base.isEmpty ? marks : base,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.visible,
            textAlign: TextAlign.center,
            style: baseStyle,
          ),
        ),
      );
    }
    final bw = _measure(base, baseStyle);
    final markSize = size * (marks.length > 1 ? 0.52 : 0.62);
    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: Center(
              child: Text(
                base,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.visible,
                textAlign: TextAlign.center,
                style: baseStyle,
              ),
            ),
          ),
          Positioned(
            left: width / 2 + bw / 2 - size * 0.05,
            top: 0,
            bottom: 0,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                marks,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.visible,
                style: baseStyle.copyWith(fontSize: markSize),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static double _measure(String s, TextStyle st) {
    final tp = TextPainter(
        text: TextSpan(text: s, style: st), textDirection: TextDirection.ltr)
      ..layout();
    return tp.width;
  }
}

/// 记号装饰解析：`1^` 高音点、`2,` 低音点、`5.` 附点、`3_`/`4=` 时值线、`6-|` 小节线
class _GlyphDeco {
  const _GlyphDeco(this.core,
      {this.high = false,
      this.low = false,
      this.dot = false,
      this.ulines = 0,
      this.bar = false});
  final String core;
  final bool high, low, dot, bar;
  final int ulines;

  static _GlyphDeco parse(String sym) {
    var s = sym;
    final bar = s.endsWith('|');
    if (bar) s = s.substring(0, s.length - 1);
    var ulines = 0;
    while (s.endsWith('=')) {
      ulines += 2;
      s = s.substring(0, s.length - 1);
    }
    while (s.endsWith('_')) {
      ulines += 1;
      s = s.substring(0, s.length - 1);
    }
    if (ulines > 3) ulines = 3;
    final dot = s.endsWith('.');
    if (dot) s = s.substring(0, s.length - 1);
    final low = s.endsWith(',');
    if (low) s = s.substring(0, s.length - 1);
    final high = s.contains('^');
    s = s.replaceAll('^', '');
    return _GlyphDeco(s,
        high: high, low: low, dot: dot, ulines: ulines, bar: bar);
  }
}

/// 单个记号单元：数字主体 + 自绘装饰（点居中于数字、时值线在下、小节线在右缘）
class _SymCell extends StatelessWidget {
  const _SymCell({
    required this.sym,
    required this.width,
    required this.height,
    required this.size,
    required this.color,
  });

  final String sym;
  final double width, height, size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(
        painter: _SymPainter(_GlyphDeco.parse(sym), size, color),
        child: const SizedBox.shrink(),
      ),
    );
  }
}

class _SymPainter extends CustomPainter {
  _SymPainter(this.d, this.size, this.color);

  final _GlyphDeco d;
  final double size;
  final Color color;

  @override
  void paint(Canvas canvas, Size sz) {
    final tp = TextPainter(
      text: TextSpan(
        text: d.core,
        style: TextStyle(fontSize: size, height: 1.15, color: color),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final tx = (sz.width - tp.width) / 2;
    final ty = (sz.height - tp.height) / 2 + size * 0.10;
    tp.paint(canvas, Offset(tx, ty));

    // 全部装饰以「数字基线」为锚：数字视觉高 ≈ 0.72em（cap 高），中线 = 基线 - 0.36em
    final baseline = ty + tp.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    final digitTop = baseline - size * 0.72;
    final digitMidY = baseline - size * 0.36;
    final cx = tx + tp.width / 2;
    final paint = Paint()..color = color;
    final linePaint = Paint()
      ..color = color
      ..strokeWidth = size * 0.06;

    // 高音点：数字正上方居中
    if (d.high) {
      canvas.drawCircle(Offset(cx, digitTop - size * 0.17), size * 0.075, paint);
    }
    // 时值下划线：数字下方 1~3 条（贴基线，避免与低音点冲突）
    for (var i = 0; i < d.ulines; i++) {
      final y = baseline + size * (0.13 + i * 0.12);
      canvas.drawLine(Offset(tx, y), Offset(tx + tp.width, y), linePaint);
    }
    // 低音点：数字正下方居中（在时值线之下）
    if (d.low) {
      canvas.drawCircle(
          Offset(cx, baseline + size * (0.30 + d.ulines * 0.12)),
          size * 0.075,
          paint);
    }
    // 附点：数字右侧、**垂直居中**（与数字中线齐平，2026-09-21 按用户反馈修正）
    if (d.dot) {
      canvas.drawCircle(
          Offset(tx + tp.width + size * 0.17, digitMidY), size * 0.068, paint);
    }
    // 小节线：列右缘竖线
    if (d.bar) {
      canvas.drawLine(
          Offset(sz.width - size * 0.06, digitTop - size * 0.10),
          Offset(sz.width - size * 0.06, baseline + size * 0.26),
          Paint()
            ..color = color
            ..strokeWidth = size * 0.05);
    }
  }

  @override
  bool shouldRepaint(_SymPainter old) =>
      old.size != size ||
      old.color != color ||
      old.d.core != d.core ||
      old.d.high != d.high ||
      old.d.low != d.low ||
      old.d.dot != d.dot ||
      old.d.ulines != d.ulines ||
      old.d.bar != d.bar;
}
