import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app.dart';
import '../models/jianpu_grid.dart';
import '../models/jianpu_layout.dart';

/// 简谱网格视图（「列 = 拍点」同步渲染，EchoHymn 风格）
///
/// 数据源：[JianpuScore]（`jianpu_score/row/cell` 三表，由 APK 的 `assets/NNN.csv`
/// 谱面网格导入）。渲染原则（**不照搬 APK 的黑底动态 HTML 表格**）：
/// 1. **列宽统一** = 可用宽 / 全曲最大列数 → 同列必然对齐；
///    对齐来自数据（列 = 拍点），视图不做任何时间→像素换算；
/// 2. 配色全部走当前皮肤语义色（[AppColors]），随换肤 / 字号等级联动（白底深字）；
/// 3. 音符数字用内置印刷记谱字体 `EchoJianpu`（与旧「曲谱」视图同源），
///    记号（减时线 / 低·高音点 / 延长记号）与小节线按数据语义自绘 ——
///    数据侧它们本就在独立行/列，自绘即忠实呈现；
/// 4. 小节线按 `rowspan` 跨行绘制（被覆盖的行也画），视觉连续。
class JianpuGridView extends StatelessWidget {
  const JianpuGridView({
    super.key,
    required this.score,
    required this.constraints,
    this.stanza,
  });

  final JianpuScore score;
  final BoxConstraints constraints;

  /// 只显示该节（1 基）；`null` = 显示全部节（印刷/APK 的整页形态）。
  ///
  /// **概念前提**：数据里「节」只是**歌词行**的属性 ——
  /// 一个乐句块（block）的谱行被该块的所有节共用
  /// （全库 474 首实测无「一块一节」：见 `tools/jianpu_csv_selftest.py` 的统计口径）。
  /// 因此按节过滤只会让歌词从 N 行减到 1 行，**谱面行不随节变化**。
  final int? stanza;

  // ---------- 版式常量（em：相对槽宽 S = 记谱字号；印刷实测 槽距 ≈ 1.0 × S） ----------
  static const double padX = 18;
  static const double padTop = 16;

  /// 底部留白：为「上一节/下一节」翻页条预留净空（与歌词页同口径）
  static const double padBottom = 52;

  /// 音符上方记号行（高八度点 / 延长记号 / 小节线）
  static const double markUpEm = 0.50;

  /// 音符行
  static const double noteRowEm = 1.34;

  /// 音符下方记号行（减时线 / 低八度点）
  static const double markDownEm = 0.58;

  /// 空行
  static const double blankEm = 0.30;

  /// 歌词字号 = 0.54 × S（印刷实测 0.50 × S，略放大以适配屏幕）
  static const double lyricFontEm = 0.54;
  static const double lyricRowEm = lyricFontEm * 1.7;

  /// 块间距（CSV 的 `K` = 换表处）
  static const double blockGapEm = 0.55;

  /// 槽宽下限/上限（像素）
  static const double minSlot = 9.0;
  static const double maxSlot = 72.0;

  @override
  Widget build(BuildContext context) {
    final availW = (constraints.maxWidth - padX * 2).clamp(60.0, 100000.0);
    final availH =
        (constraints.maxHeight - padTop - padBottom).clamp(60.0, 100000.0);

    // **按块宽渲染**：每个乐句块（CSV 的一次 <table>）用**自己的列数**铺满可用宽
    // （列数少的块字号更大，与 APK 每表独立排布同构）；块内行宽差异属源数据自身
    // 问题（163/197/297），按块内最大行宽（[JianpuBlock.colCount]）处理，
    // 行宽不足的行右侧自然留空、不与其它行错位（同列仍同 x）。
    final slots = <double>[
      for (final block in score.blocks)
        (availW / (block.colCount > 0 ? block.colCount : 1))
            .clamp(minSlot, maxSlot),
    ];
    // 高度约束：总像素高超过可用高时整体等比收缩（保持块间字号比例），否则纵向滚动
    var totalH = 0.0;
    for (var bi = 0; bi < score.blocks.length; bi++) {
      final block = score.blocks[bi];
      if (bi > 0 && _hasVisible(block)) totalH += slots[bi] * blockGapEm;
      for (final row in block.rows) {
        if (_visible(row)) totalH += slots[bi] * _rowEm(row.kind);
      }
    }
    if (totalH > availH && totalH > 0) {
      final k = availH / totalH;
      for (var i = 0; i < slots.length; i++) {
        slots[i] = (slots[i] * k).clamp(minSlot, maxSlot);
      }
    }

    final children = <Widget>[];
    for (var bi = 0; bi < score.blocks.length; bi++) {
      final block = score.blocks[bi];
      final m = _Metrics(slot: slots[bi], gridW: slots[bi] * block.colCount);
      if (bi > 0 && _hasVisible(block)) {
        children.add(SizedBox(height: slots[bi] * blockGapEm));
      }
      final barCols = block.barColsByLine();
      for (final row in block.rows) {
        if (!_visible(row)) continue;
        children.add(_buildRow(row, barCols[row.lineNo] ?? const <int>{}, m));
      }
    }

    return Container(
      color: AppColors.lyricsBg,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(padX, padTop, padX, padBottom),
        // 允许内容溢出单元格（汉字 + 标点占 2 字宽），横向不裁剪、不挤列；
        // 各块宽度不同（按块宽渲染）→ Column 宽度取最宽块，块间左对齐
        child: Center(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        ),
      ),
    );
  }

  /// 行高（em：相对槽宽 = 记谱字号）
  double _rowEm(JianpuRowKind k) => switch (k) {
        JianpuRowKind.note => noteRowEm,
        JianpuRowKind.markUp => markUpEm,
        JianpuRowKind.markDown => markDownEm,
        JianpuRowKind.lyric => lyricRowEm,
        JianpuRowKind.blank => blankEm,
      };

  double _rowHeight(JianpuRowKind k, _Metrics m) => m.slot * _rowEm(k);

  /// 该行是否参与显示 —— 按节过滤**只作用于歌词行**
  /// （谱行/记号行被该块全部节共用，故任何一节都要显示；节号缺失时照样显示，避免丢词）
  bool _visible(JianpuRow row) =>
      stanza == null ||
      row.kind != JianpuRowKind.lyric ||
      row.stanzaNo == null ||
      row.stanzaNo == stanza;

  bool _hasVisible(JianpuBlock block) => block.rows.any(_visible);

  Widget _buildRow(JianpuRow row, Set<int> barCols, _Metrics m) {
    final h = _rowHeight(row.kind, m);
    final stack = <Widget>[];

    // ① 小节线（先画，位于内容之下；被 rowspan 覆盖的行同样绘制 → 视觉连续）
    for (final col in barCols) {
      stack.add(Positioned(
        left: col * m.slot + (m.slot - m.barW) / 2,
        top: 0,
        bottom: 0,
        child: Container(width: m.barW, color: m.barColor),
      ));
    }

    // ② 单元格内容
    for (final col in row.cols) {
      final cell = row.cells[col]!;
      final w = _buildCell(row, cell, m);
      if (w == null) continue;
      stack.add(Positioned(
        left: col * m.slot,
        top: 0,
        width: m.slot,
        height: h,
        child: w,
      ));
    }

    return SizedBox(
      height: h,
      child: SizedBox(
        width: m.gridW,
        child: Stack(clipBehavior: Clip.none, children: stack),
      ),
    );
  }

  /// 单元格内容（按行类型决定竖直贴合方向：记号紧贴音符一侧）
  Widget? _buildCell(JianpuRow row, JianpuCell cell, _Metrics m) {
    switch (cell.kind) {
      case JianpuCellKind.barline:
      case JianpuCellKind.unknown:
        return null; // 小节线由 ① 绘制；未知记号不显示
      case JianpuCellKind.mark:
        return _buildMark(row.kind, cell, m);
      case JianpuCellKind.note:
        return Align(alignment: Alignment.center, child: _noteText(cell, m));
      case JianpuCellKind.rest:
      case JianpuCellKind.dash:
      case JianpuCellKind.dotLen:
        return Align(
          alignment: _sideAlign(row.kind),
          child: Text(
            _symbolGlyph(cell),
            style: TextStyle(
              fontFamily: kJianpuFontFamily,
              fontSize: m.slot * 0.92,
              color: m.noteColor,
            ),
          ),
        );
      case JianpuCellKind.accidental:
        return Align(
          alignment: Alignment.center,
          child: Text(
            cell.displayText,
            style: TextStyle(
              fontSize: m.slot * 0.62,
              color: m.noteColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        );
      case JianpuCellKind.text:
        return Align(
          alignment: Alignment.center,
          child: Text(
            cell.displayText,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.visible,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'EchoKai',
              fontFamilyFallback: const ['KaiTi', 'EchoSans'],
              fontSize: m.lyricSize,
              height: 1.15,
              color: m.lyricColor,
            ),
          ),
        );
      case JianpuCellKind.stanza:
        return Align(
          alignment: Alignment.center,
          child: Text(
            cell.displayText,
            maxLines: 1,
            softWrap: false,
            style: TextStyle(
              fontSize: m.lyricSize * 0.78,
              color: m.stanzaColor,
            ),
          ),
        );
    }
  }

  /// 记号行内容贴合方向：上方记号行贴下、下方记号行贴上（紧邻音符）
  Alignment _sideAlign(JianpuRowKind kind) => switch (kind) {
        JianpuRowKind.markUp => Alignment.bottomCenter,
        JianpuRowKind.markDown => Alignment.topCenter,
        _ => Alignment.center,
      };

  /// 音符文本：变音记号（UI 字体）+ 音级（印刷记谱字体）+ 附点（印刷记谱字体）
  ///
  /// ⚠️ 印刷记谱字体的数字字形挂在 **CJK 码位**上（`0x4e52` = `1` … `0x4e5d` = `7`，
  /// 见 [kJianpuDigitCodepoints]），**不能**直接用 `Text('1')` ——
  /// 字体里没有 U+0031 的字形，会静默退化成别的字体（甚至空白）。
  Widget _noteText(JianpuCell cell, _Metrics m) {
    final digit = _digitGlyph(cell.degree);
    final dots = _dotGlyph(cell.dotLen ?? 0);
    final acc = cell.accidental ?? '';
    if (acc.isEmpty && dots.isEmpty) {
      return Text(
        digit,
        style: TextStyle(
          fontFamily: kJianpuFontFamily,
          fontSize: m.slot,
          height: 1.0,
          color: m.noteColor,
        ),
      );
    }
    return RichText(
      text: TextSpan(
        children: [
          if (acc.isNotEmpty)
            TextSpan(
              text: acc,
              style: TextStyle(
                fontSize: m.slot * 0.58,
                color: m.noteColor,
                fontWeight: FontWeight.w600,
                height: 1.0,
              ),
            ),
          TextSpan(
            text: digit,
            style: TextStyle(
              fontFamily: kJianpuFontFamily,
              fontSize: m.slot,
              color: m.noteColor,
              height: 1.0,
            ),
          ),
          if (dots.isNotEmpty)
            TextSpan(
              text: dots,
              style: TextStyle(
                fontFamily: kJianpuFontFamily,
                fontSize: m.slot,
                color: m.noteColor,
                height: 1.0,
              ),
            ),
        ],
      ),
    );
  }

  /// 音级 → 印刷字形（1~7 → `0x4e52`…；休止 `0` → `0x5d4c`；越界回退数字文本）
  String _digitGlyph(int? degree) {
    final cp = kJianpuDigitCodepoints[degree];
    if (cp != null) return String.fromCharCode(cp);
    if (degree == 0) return String.fromCharCode(0x5d4c); // 印刷体 0
    return '${degree ?? ''}';
  }

  /// 附点 → 印刷字形（`0x5d3d` = 附点）
  String _dotGlyph(int count) =>
      count <= 0 ? '' : String.fromCharCode(0x5d3d) * count;

  /// 休止 / 增时线 / 附点格 → 印刷字形（同样按码位取，不能直传 `0`/`-`）
  String _symbolGlyph(JianpuCell cell) => switch (cell.kind) {
        JianpuCellKind.rest => String.fromCharCode(0x5d4c), // 印刷体 0
        JianpuCellKind.dash => String.fromCharCode(0x5d1f), // 增时线
        JianpuCellKind.dotLen => _dotGlyph(cell.dotLen ?? 1),
        _ => cell.displayText,
      };

  /// 记号（减时线 `B` / 低·高音点 `D` / 延长记号 `E`）
  ///
  /// 排布规则与印刷一致：**离音符越近的记号画在越靠音符的一侧**——
  /// 上方行 = 点在内、延长记号在外；下方行 = 减时线在内、低八度点在外。
  Widget _buildMark(JianpuRowKind kind, JianpuCell cell, _Metrics m) {
    final dots = cell.dots ?? 0;
    final beams = cell.beams ?? 0;
    final hasFermata = (cell.fermata ?? 0) > 0;
    final pieces = <Widget>[];
    if (kind == JianpuRowKind.markUp) {
      if (hasFermata) {
        pieces.add(SizedBox(
          width: m.slot * 0.66,
          height: m.slot * 0.30,
          child: CustomPaint(painter: _FermataPainter(m.markColor)),
        ));
      }
      if (dots > 0) pieces.add(_dots(dots, m));
    } else {
      if (beams > 0) pieces.add(_beams(beams, m));
      if (dots > 0) pieces.add(_dots(dots, m));
    }
    if (pieces.isEmpty) return const SizedBox.shrink();
    return Align(
      alignment: _sideAlign(kind),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: kind == JianpuRowKind.markUp
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: pieces,
      ),
    );
  }

  /// 八度点（1 点 = 低/高八度；2 点 = 倍低/倍高八度）
  Widget _dots(int count, _Metrics m) {
    final d = (m.slot * 0.15).clamp(1.6, 8.0);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < count; i++) ...[
          if (i > 0) SizedBox(height: d * 0.55),
          Container(
            width: d,
            height: d,
            decoration: BoxDecoration(color: m.markColor, shape: BoxShape.circle),
          ),
        ],
      ],
    );
  }

  /// 减时线（1 条 = 八分音符；2 条 = 十六分音符）
  Widget _beams(int count, _Metrics m) {
    final t = (m.slot * 0.048).clamp(1.0, 3.0);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < count; i++) ...[
          if (i > 0) SizedBox(height: t * 1.2),
          Container(width: m.slot * 0.68, height: t, color: m.markColor),
        ],
      ],
    );
  }
}

/// 渲染度量（由槽宽 [slot] 派生，随窗口/字号等级联动）
class _Metrics {
  const _Metrics({required this.slot, required this.gridW});

  /// 槽宽 = 记谱字号（印刷实测 槽距 ≈ 1.0 em）
  final double slot;

  /// 网格总宽 = 槽宽 × 全曲最大列数
  final double gridW;

  double get barW => (slot * 0.075).clamp(1.0, 3.5);

  double get lyricSize => (slot * JianpuGridView.lyricFontEm).clamp(8.0, 40.0);

  Color get noteColor => AppColors.textPrimary;
  Color get lyricColor => AppColors.textPrimary;
  Color get markColor => AppColors.textPrimary;
  Color get stanzaColor => AppColors.textTertiary;

  /// 小节线：主题主色半透明（比纯黑更贴合 EchoHymn 的配色体系）
  Color get barColor => AppColors.primary.withValues(alpha: 0.45);
}

/// 延长记号（fermata）：上方弧 + 弧下圆点（与印刷/APK 的 `E` 字形一致）
class _FermataPainter extends CustomPainter {
  const _FermataPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = (size.height * 0.13).clamp(0.8, 3.0)
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromLTWH(0, size.height * 0.42, size.width, size.height * 0.86),
      math.pi, // 上半弧（180° → 360°）
      math.pi,
      false,
      stroke,
    );
    canvas.drawCircle(
      Offset(size.width / 2, size.height * 0.80),
      (size.height * 0.13).clamp(0.6, 2.6),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _FermataPainter oldDelegate) =>
      oldDelegate.color != color;
}


