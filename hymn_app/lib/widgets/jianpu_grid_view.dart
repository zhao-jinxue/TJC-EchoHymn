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
  /// **概念前提**：数据里「节」是**歌词行**的属性 ——
  /// 一个乐句块（block）的谱行被该块的所有节共用
  /// （全库 474 首实测无「一块一节」：见 `tools/jianpu_csv_selftest.py` 的统计口径）。
  /// 因此按节过滤只会让歌词行数变化，**谱面行不随节变化**。
  ///
  /// **两类歌词行**（2026-10-12 修正）：
  /// - 分节块（歌词行数 ≥ 节数）：取**第 k 行**（行位置 = 节号）；位置超出节数的
  ///   行是**块内叠句**（四声部合唱歌词，不属任何一节）→ **抛弃**；
  /// - 副歌 / 各节共用的块（歌词行数 < 节数，印刷本只写一遍）：**每节都显示**。
  final int? stanza;

  // ---------- 版式常量（em：相对槽宽 S = 拍点间距；印刷实测 槽距 ≈ 1.0 × 记谱字号） ----------
  static const double padX = 18;
  static const double padTop = 16;

  /// 底部留白：为「上一节/下一节」翻页条预留净空（与歌词页同口径）
  static const double padBottom = 52;

  /// **记谱字号系数（相对槽宽 = 拍点间距）** —— 2026-10-13 定稿 **0.56**。
  ///
  /// **论证（字形墨迹度量 + 快照像素实测）**：
  /// - 印刷记谱字体数字字形墨迹高 ≈ **0.345 em**（`lib/data/jianpu_metrics.dart`：
  ///   1~7 码位为 0.335~0.367 em）；楷体汉字墨迹高 ≈ **0.766 em**（快照实测）；
  /// - 调参历史：`1.0`（= 83 %，与歌词一样大，用户反馈「歌词显小」）→
  ///   `0.60`（51 %）→ `0.50`（**41.6 %**，用户「记谱再小」，快照实测音符 11 px vs 歌词 27 px）；
  /// - 2026-10-13 第二轮：用户要求「歌词行距压一半，腾出空间放大歌词和记谱」⇒
  ///   歌词 0.54 → **0.60**、记谱按**同一光学比**同步 0.50 → **0.56**
  ///   （墨迹比仍 = **42 %**，与用户认可的那一版一致）+ 行距重构 ⇒
  ///   净空 −49 %、行距 −37 %，歌词/记谱墨迹各 **+11 %**。
  /// - **对齐不受影响**：变的是「每列内字形多大」，列宽（拍点间距）没动，
  ///   同列 = 同拍点的对齐关系完全保持。
  /// - 继续调整口径（只改这一个常量 + [lyricFontEm]）：
  ///   记谱再小 `0.50 → 37 %`；两者一起放大 `0.60 / 0.64 → 42 %`（净空仍 ≈ 一半）。
  static const double noteFontEm = 0.56;

  /// 音符**行盒**系数（相对记谱字号）—— 记谱字体的字面盒比墨迹大得多
  /// （墨迹 0.345 em，而 hhea 行盒 ascent 0.877 / descent 0.123 em）：
  /// 若按 1.0 em 行盒排版，数字墨迹上方会白留 0.28 em（≈ 0.19 × 槽宽）——
  /// 这正是「两行歌词之间太空」的主要来源。把行盒压到 0.74 em
  /// （墨迹上边 0.05 em / 下边 0.35 em）⇒ **基线位置不变**（Flutter 按 ascent 比例
  /// 摆基线：0.877 × 0.74 = 0.649 em），字形大小不变、上方空白砍掉 0.23 em。
  static const double noteBoxEm = 0.74;

  /// 音符行内的「符号字形」（休止 0 / 增时线 - / 附点 .）行盒系数：
  /// 它们用 0.92 × 记谱字号 ⇒ 行盒 = `noteBoxEm / 0.92` 才能**与数字同一基线**。
  static const double symbolBoxEm = noteBoxEm / 0.92;

  /// 音符行高（相对记谱字号）= 行盒 + 上下各 0.03 em 呼吸
  static const double noteRowEm = noteBoxEm + 0.06;

  /// 音符上方记号行（相对**记谱字号**）：装高八度点 / 延长记号 / 小节线。
  /// 上限实测（全库 474 首）：记号栈最高 = 延长记号 0.30 + 单点 0.15 = **0.45 em**
  /// （块首 markUp 行 48 处；2 点 = 0.3825、2 减时线 = 0.154）→ 取 0.46
  /// 保证**记号不溢出本行**，块间距才敢压得很小而不与上一行歌词相撞。
  static const double markUpEm = 0.46;

  /// 音符下方记号行（相对**记谱字号**）：装减时线 / 低八度点。
  /// 上限实测（全库 474 首逐格）：最常见复杂栈 = 1 减时线 + 2 点 0.3036、
  /// 2 减时线 0.1536、**2 点 + 1 减时线 0.4305（8 格）**；仅 2 格为 0.5361
  /// （第 207 首「2 点 + 2 减时线」，溢出 0.09 em ≈ 4 px，落进歌词行上方留白，可接受）
  /// ⇒ 取 **0.45**。
  static const double markDownEm = 0.45;

  /// 空行
  static const double blankEm = 0.20;

  /// 歌词字号 = 0.60 × S（印刷实测 0.50 × S，略放大以适配屏幕）
  static const double lyricFontEm = 0.60;

  /// 歌词**行盒系数**（= 歌词 TextStyle 的 `height`）：楷体 1.15 em 行盒刚好裹住
  /// 汉字墨迹（墨迹实测占行盒 0.16~1.04 em）⇒ 行高 = 行盒，上下不再多留白。
  static const double lyricLeadingEm = 1.15;
  static const double lyricRowEm = lyricFontEm * lyricLeadingEm;

  /// 块间距（CSV 的 `K` = 换表处）—— 记号行已不溢出 ⇒ 只需一点点气口
  static const double blockGapEm = 0.14;

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
    final visible = <List<JianpuRow>>[
      for (final block in score.blocks) _visibleRows(block),
    ];
    var totalH = 0.0;
    for (var bi = 0; bi < visible.length; bi++) {
      if (bi > 0 && visible[bi].isNotEmpty) totalH += slots[bi] * blockGapEm;
      for (final row in visible[bi]) {
        totalH += slots[bi] * _rowEm(row.kind);
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
      if (bi > 0 && visible[bi].isNotEmpty) {
        children.add(SizedBox(height: slots[bi] * blockGapEm));
      }
      final barCols = block.barColsByLine();
      for (final row in visible[bi]) {
        children.add(_buildRow(row, barCols[row.lineNo] ?? const <int>{}, m));
      }
    }

    return Container(
      color: AppColors.lyricsBg,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(padX, padTop, padX, padBottom),
        // 允许内容溢出单元格（汉字 + 标点占 2 字宽），横向不裁剪、不挤列；
        // 各块宽度不同（按块宽渲染）→ Column 宽度取最宽块，块间左对齐
        child: ConstrainedBox(
          // **垂直居中**（与歌词页「整块居中」同口径，2026-09-23 用户确认）：
          // 内容不足一屏时整块垂直居中；超出一屏时 ConstrainedBox 被内容撑高
          // → 正常从顶滚动、不裁顶
          constraints: BoxConstraints(
            minHeight: (constraints.maxHeight - padTop - padBottom)
                .clamp(0.0, double.infinity),
          ),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ),
      ),
    );
  }

  /// 行高（em：音符/记号行相对**记谱字号**；歌词/空行相对槽宽）
  double _rowEm(JianpuRowKind k) => switch (k) {
        JianpuRowKind.note => noteRowEm * noteFontEm,
        JianpuRowKind.markUp => markUpEm * noteFontEm,
        JianpuRowKind.markDown => markDownEm * noteFontEm,
        JianpuRowKind.lyric => lyricRowEm,
        JianpuRowKind.blank => blankEm,
      };
  double _rowHeight(JianpuRowKind k, _Metrics m) => m.slot * _rowEm(k);

  /// 该块在当前节下要显示的行（保持原行序）
  ///
  /// **按节过滤规则（`stanza == null` 时全部显示 = 印刷本整页形态）**：
  /// 1. 非歌词行（音符/记号/小节线）恒显示 —— 一段旋律被该块全部节共用；
  /// 2. 该块歌词**各节共用**（[JianpuBlock.sharesLyricsAcrossStanzas]：副歌 /
  ///    各节完全相同的句子，印刷本只写一遍）⇒ **每节都显示**；
  ///    修订前只认节号 → 第 2 节起副歌块整块无词（2026-10-12 用户实机反馈的 bug）；
  /// 3. 歌词行缺节号（旧库/异常数据）⇒ 照旧显示，避免丢词；
  /// 4. 其余按**歌词行在块内的位置**归节：第 i 行 = 第 i 节；**位置 > 节数的行
  ///    （块内叠句）直接抛弃**（用户 2026-10-12 裁定：这类叠句是四声部合唱的歌词，
  ///    不属于任何单独一节 —— 第 242 首「请救主进来…」即此类；全库 65 行）。
  ///
  /// 位置比行上记的节号可靠：源数据里第 111 首首块每行都印 `(1)`。
  List<JianpuRow> _visibleRows(JianpuBlock block) {
    final n = score.stanzaCount;
    final s = stanza;
    if (s == null || n <= 1 || block.sharesLyricsAcrossStanzas(n)) {
      return block.rows;
    }
    final out = <JianpuRow>[];
    var lyricPos = 0;
    for (final row in block.rows) {
      if (row.kind != JianpuRowKind.lyric) {
        out.add(row);
        continue;
      }
      lyricPos++;
      if (lyricPos > n) continue; // 块内叠句（四声部合唱歌词）→ 抛弃
      if (row.stanzaNo == null || lyricPos == s) out.add(row);
    }
    return out;
  }

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
              fontSize: m.noteSize * 0.92,
              // 与数字**同一基线**（否则增时线/休止会相对数字上下错位）：
              // 行盒 = noteBoxEm / 0.92 ⇒ ascent = 0.877 × 0.74 × noteSize
              height: symbolBoxEm,
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
              fontSize: m.noteSize * 0.62,
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
              height: lyricLeadingEm,
              color: m.lyricColor,
            ),
          ),
        );
      case JianpuCellKind.stanza:
        // 节号 `(k)` 只在它标示的那一节显示：源数据里第 111 首首块每行都印 `(1)`，
        // 逐节显示时若不判断，第 2/3 节会显示错的节号（整页形态照旧全部显示）
        if (stanza != null && cell.displayText != '($stanza)') return null;
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
          fontSize: m.noteSize,
          // 行盒压到 [noteBoxEm]：字形大小不变（Flutter 按 ascent 比例摆基线），
          // 只把数字墨迹上方的空白砍掉 —— 行距压缩的关键（见常量注释）
          height: noteBoxEm,
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
                fontSize: m.noteSize * 0.58,
                color: m.noteColor,
                fontWeight: FontWeight.w600,
                height: noteBoxEm,
              ),
            ),
          TextSpan(
            text: digit,
            style: TextStyle(
              fontFamily: kJianpuFontFamily,
              fontSize: m.noteSize,
              color: m.noteColor,
              height: noteBoxEm,
            ),
          ),
          if (dots.isNotEmpty)
            TextSpan(
              text: dots,
              style: TextStyle(
                fontFamily: kJianpuFontFamily,
                fontSize: m.noteSize,
                color: m.noteColor,
                height: noteBoxEm,
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
          width: m.noteSize * 0.66,
          height: m.noteSize * 0.30,
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
    final d = (m.noteSize * 0.15).clamp(1.0, 8.0);
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
    final t = (m.noteSize * 0.048).clamp(1.0, 3.0);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < count; i++) ...[
          if (i > 0) SizedBox(height: t * 1.2),
          Container(width: m.noteSize * 0.68, height: t, color: m.markColor),
        ],
      ],
    );
  }
}

/// 渲染度量（由槽宽 [slot] 派生，随窗口/字号等级联动）
class _Metrics {
  const _Metrics({required this.slot, required this.gridW});

  /// 槽宽 = 拍点间距（列宽；歌词字号与列对齐都以它为基准）
  final double slot;

  /// 网格总宽 = 槽宽 × 全曲最大列数
  final double gridW;

  /// **记谱字号**（音符/记号字形大小）= 槽宽 × [JianpuGridView.noteFontEm]
  double get noteSize => slot * JianpuGridView.noteFontEm;

  double get barW => (noteSize * 0.075).clamp(1.0, 3.5);

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


