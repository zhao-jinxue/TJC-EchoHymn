import 'package:flutter/material.dart';

import '../app.dart';
import '../models/hymn.dart';
import '../models/hymn_score.dart';
import '../models/jianpu_layout.dart';
import '../services/chinese_convert_service.dart';

/// 「简谱曲谱 + 歌词」同步渲染页（数据源：`hymn_score_*` 表的逐字对位）
///
/// 版式 = 每行两排：**上排记号、下排歌词**，二者共用同一套槽位（第 i 槽 = 第 i 个谱元素）。
///
/// **渲染方式（2026-09-21 二轮定稿）：字体原生渲染**
/// 记号不再自绘几何，而是用**印刷 PDF 内嵌的 MMP2005 字体**（`EchoJianpu`）直接绘制
/// `code_seq` 的码位——时值线、低/高音点、附点、小节线、**连音弧**全部由字形自带
/// （字形是预合成装饰，如 `4ef0` = `5̲`、`4e4d` = 低音 `5`、`5e6e` = 3.75em 宽弧）。
/// 排版比例取自印刷页实测（em，相对记谱字号 S）：槽距 = 1.0 S、歌词字号 = 0.5 S。
/// 纯装饰字形（连音弧等，码本解码为空串）**不占槽位**，覆盖绘制在音符之上。
///
/// **不换行硬约束**：槽距 = min(可用宽 / 最宽行槽数, 高度反推值)，因此一整行必然单行排完。
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

  // ---------- 版式常量（em，相对记谱字号 S；实测自印刷页，见 §5.18） ----------
  /// 槽距 = 1.0 × S（印刷：槽距 24.9pt / 记谱字号 24.6pt）
  static const double slotEm = 1.0;

  /// 歌词字号 = 0.50 × S（印刷：歌词 12.6pt / 记谱 24.6pt）
  static const double lyricEm = 0.50;

  /// 音符行带上下留白（em）
  static const double notePadTop = 0.08;
  static const double notePadBottom = 0.10;

  /// 音符基线 → 歌词行顶（em）
  static const double lyricGapEm = 0.24;

  /// 歌词行高倍数
  static const double lyricLineHeight = 1.25;

  /// 行间距（em）
  static const double rowGapEm = 0.55;

  /// 标题区折算高度（em）
  static const double titleEm = 1.9;

  @override
  Widget build(BuildContext context) {
    final availW = constraints.maxWidth - padX * 2;
    final availH = constraints.maxHeight - padTop - padBottom;

    // 每行元素（token 缺省时退化为「空字形」——只影响记号排，歌词仍按列位显示）
    final rows = [
      for (final l in page.lines)
        [
          for (var i = 0; i < l.elements.length; i++)
            JianpuElement(
                l.tokens.length == l.elements.length ? l.tokens[i] : '',
                l.elements[i]),
        ],
    ];
    final metrics = JianpuPageMetrics.of(rows.expand((r) => r));
    final nLines = rows.isEmpty ? 1 : rows.length;

    // 槽数上限 = 各行「非覆盖元素」数（连音弧不占列）
    var maxSlots = 1;
    for (final r in rows) {
      final n = r.where((e) => !e.isOverlay).length;
      if (n > maxSlots) maxSlots = n;
    }

    // 行距（em）：音符行带 + 上下留白 + 间空 + 歌词行 + 行间距
    final pitchEm = metrics.band +
        notePadTop +
        notePadBottom +
        lyricGapEm +
        lyricEm * lyricLineHeight +
        rowGapEm;

    // 字号 S：宽度上限（不换行）× 高度上限（整页放得下），取小
    var size = availW / maxSlots;
    final byH = availH / (nLines * pitchEm + titleEm);
    if (byH < size) size = byH;
    size = size.clamp(10.0, 120.0);

    final slotW = size * slotEm;
    final lyricSize = (size * lyricEm).clamp(8.0, 48.0);
    final lyricH = lyricSize * lyricLineHeight;
    final gridW = maxSlots * slotW;
    final titleSize = (size * 0.62).clamp(13.0, 30.0);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(padX, padTop, padX, padBottom),
      child: Center(
        child: SizedBox(
          width: gridW,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
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
              SizedBox(height: size * 0.5),
              for (var i = 0; i < rows.length; i++)
                _buildLine(
                  rows[i],
                  page.lines[i],
                  slotW: slotW,
                  size: size,
                  lyricSize: lyricSize,
                  lyricH: lyricH,
                  yTop: metrics.yTop,
                  yBot: metrics.yBot,
                  gapAfter: i + 1 < rows.length &&
                          page.lines[i + 1].phraseNo != page.lines[i].phraseNo
                      ? size * 0.9
                      : size * rowGapEm,
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 一条谱行：上排记号、下排歌词，同一套等宽列（整页统一列基准，左对齐）
  /// 一条谱行：上排「字体原生记号」、下排歌词，共用同一套槽位（左对齐到页列网格）
  Widget _buildLine(
    List<JianpuElement> elems,
    ScoreLineRow line, {
    required double slotW,
    required double size,
    required double lyricSize,
    required double lyricH,
    required double yTop,
    required double yBot,
    required double gapAfter,
  }) {
    final cells = line.cellsFor(page.stanzaNo);
    final noteH = (yTop - yBot + notePadTop + notePadBottom) * size;
    final color = line.isChorus ? AppColors.primary : AppColors.textPrimary;
    final lyricColor = line.isChorus ? AppColors.primary : AppColors.textSecondary;
    return Padding(
      padding: EdgeInsets.only(bottom: gapAfter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: elems.length * slotW,
            height: noteH,
            child: CustomPaint(
              painter: _ScoreLinePainter(
                elems: elems,
                slotW: slotW,
                size: size,
                yTop: yTop,
                yBot: yBot,
                color: color,
              ),
            ),
          ),
          SizedBox(height: lyricGapEm * size),
          Row(
            children: [
              for (var i = 0; i < elems.length; i++)
                SizedBox(
                  width: elems[i].isOverlay ? 0 : slotW,
                  height: lyricH,
                  child: _LyricCell(
                    text: ChineseConvertService.instance
                        .toSimplified(cells[i] ?? ''),
                    width: elems[i].isOverlay ? 0 : slotW,
                    size: lyricSize,
                    color: lyricColor,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 记号行画笔：**字体原生渲染** —— 逐元素按 token 码位绘制 `EchoJianpu` 字形
///
/// - 非覆盖元素占 1 槽（槽距 = 记谱字号），字形按**墨迹**居中对齐到槽位；
/// - 纯装饰元素（连音弧等，解码为空串）不推进槽位，按自然墨迹宽覆盖绘制；
/// - 小节线字形本身跨整个谱系高度 → 按本行行带裁剪，避免戳出音符排之外。
class _ScoreLinePainter extends CustomPainter {
  _ScoreLinePainter({
    required this.elems,
    required this.slotW,
    required this.size,
    required this.yTop,
    required this.yBot,
    required this.color,
  });

  final List<JianpuElement> elems;
  final double slotW;
  final double size;
  final double yTop;
  final double yBot;
  final Color color;

  /// 字形 TextPainter 缓存（同一行内码位高度重复，省去每帧重复 layout）
  final Map<int, TextPainter> _cache = {};

  TextPainter _glyph(int cp) => _cache.putIfAbsent(cp, () {
        final tp = TextPainter(
          text: TextSpan(
            text: String.fromCharCode(cp),
            style: TextStyle(
              fontFamily: kJianpuFontFamily,
              fontSize: size,
              color: color,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        return tp;
      });

  @override
  void paint(Canvas canvas, Size sz) {
    // 行盒顶 = 墨迹上界 + 上留白；基线以「墨迹上界」为锚（字形自身带装饰偏移）
    final top = ScoreLyricPageView.notePadTop * size;
    final baseline = top + yTop * size;
    final clipTop = baseline - (yTop + 0.04) * size;
    final clipBottom = baseline + (0.06 - yBot) * size;

    var slot = 0;
    for (final e in elems) {
      if (!e.isKnown) continue;
      final x = slot * slotW;
      if (e.isOverlay) {
        _paintElement(canvas, e, x, baseline);
      } else {
        _paintElement(canvas, e, x, baseline,
            clipTop: e.hasBarline ? clipTop : null,
            clipBottom: e.hasBarline ? clipBottom : null);
        slot++;
      }
    }
  }

  /// 画一个元素：多码位元素按「墨迹宽 + 0.10em 间距」从左到右排，整体居中于槽位
  void _paintElement(Canvas canvas, JianpuElement e, double x, double baseline,
      {double? clipTop, double? clipBottom}) {
    const gapEm = 0.10;
    final total = e.inkWidth + gapEm * (e.glyphs.length - 1);
    final start = x + (slotW - total * size) / 2;
    if (clipTop != null) {
      canvas.save();
      canvas.clipRect(Rect.fromLTRB(0, clipTop, double.infinity, clipBottom!));
    }
    var pen = start;
    for (final g in e.glyphs) {
      final tp = _glyph(g.codepoint);
      // 墨迹居中：笔位置 = 墨迹起点 − 字形左侧留白（xMin）
      final dx = pen - g.xMin * size;
      final dy = baseline - tp.computeDistanceToActualBaseline(TextBaseline.alphabetic);
      tp.paint(canvas, Offset(dx, dy));
      pen += (g.inkWidth + gapEm) * size;
    }
    if (clipTop != null) canvas.restore();
  }

  @override
  bool shouldRepaint(_ScoreLinePainter old) =>
      old.size != size || old.color != color || old.slotW != slotW ||
      !identical(old.elems, elems);
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

