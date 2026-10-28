import 'dart:math' as math;

import 'dart:io';

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

  /// **记谱字号系数（相对槽宽 = 拍点间距）** —— 2026-10-13 定稿 **0.50**。
  ///
  /// **论证（字形墨迹度量 + 快照像素实测）**：
  /// - 印刷记谱字体数字字形墨迹高 ≈ **0.345 em**（`lib/data/jianpu_metrics.dart`：
  ///   1~7 码位为 0.335~0.367 em）；楷体汉字墨迹高 ≈ **0.766 em**；
  /// - 修订前：记谱字号 = 1.0 × 槽宽、歌词字号 = 0.54 × 槽宽
  ///   → 音符墨迹 **0.345** 槽宽 vs 歌词墨迹 **0.414** 槽宽 = **83 %**
  ///   （快照实测 15 px vs 18 px）→ 视觉上「和歌词一样大」，歌词显小；
  /// - 用户先要求「记谱 ≈ 歌词的一半」→ 取 0.60（比值 51 %）；**同日再要求「记谱再小」→ 0.50**
  ///   （音符墨迹 0.172 槽宽 = 歌词墨迹的 **42 %**）；
  /// - **对齐不受影响**：变的是「每列内字形多大」，列宽（拍点间距）与歌词字号都没动，
  ///   同列 = 同拍点的对齐关系完全保持；歌词字宽 ≈ 1 em 歌词字号必须 ≤ 1 列宽，
  ///   所以歌词不能再放大、只能把记谱字形缩小 —— 这就是本系数存在的理由。
  /// - 继续调整口径：`0.45 → 38 %`、`0.40 → 34 %`（只改这一个常量）。
  static const double noteFontEm = 0.50;

  /// 音符上方记号行（相对**记谱字号**）
  static const double markUpEm = 0.50;

  /// 音符行（相对**记谱字号**）
  static const double noteRowEm = 1.34;

  /// 音符下方记号行（相对**记谱字号**）
  static const double markDownEm = 0.58;

  /// 空行
  static const double blankEm = 0.30;

  /// 歌词字号 = 0.54 × S（印刷实测 0.50 × S，略放大以适配屏幕）—— 本次不改
  static const double lyricFontEm = 0.54;
  static const double lyricRowEm = lyricFontEm * 1.7;

  /// 块间距（CSV 的 `K` = 换表处）
  static const double blockGapEm = 0.55;

  /// 槽宽下限/上限（像素）
  static const double minSlot = 9.0;
  static const double maxSlot = 72.0;

  /// **不足一屏时放大填满**（2026-10-25 用户先选 B，随后二次反馈关闭）：
  /// - 放大到 2.2 倍后**列间距过大**，且一行歌词无法在竖屏宽度内完整显示
  ///   （需横向滑动）→ 用户要求「一行歌词全部竖屏显示」，故**回退回不放大**
  /// - 常量与横向滚动结构保留：将来若要「曲谱专属字号」，从 `maxGrowScale` 开启即可
  static const double maxGrowScale = 1.0;
  static const double maxSlotGrow = maxSlot;

  /// 是否启用「不足一屏放大填满」——**仅移动端**（2026-10-25）：
  /// 桌面窗口大、行数固定，放大填满会让字过大；桌面保持原有版式不变。
  static bool get _growToFill => Platform.isAndroid || Platform.isIOS;

  // ---------- 移动端版式放开（2026-10-25 用户要求）----------
  //
  // 用户要求「左右留白 5%、字间更紧凑、字更大」。这三个目标**不能只调槽宽**：
  // 槽宽同时是「列距」「块宽」和「字号基数」，调小会让字变小、块变窄、留白更多。
  // 因此拆成两个独立旋钮，**只在手机/平板生效**（桌面 golden 基准保持不变）：
  // - [maxSlotFor]：放开槽宽上限 → 块宽 = 可用宽（左右只剩 [padX] ≈ 4.4% ≈ 5%）；
  // - [noteFontEmFor] / [lyricFontEmFor]：提高字号系数 → 字变大、列内空隙变小（视觉更紧凑）。

  /// 是否移动端
  static bool get _isMobile => Platform.isAndroid || Platform.isIOS;

  /// 槽宽上限：桌面 72（原值）；移动端放开到 320 → 块宽铺满可用宽
  static double get maxSlotFor => _isMobile ? 320.0 : maxSlot;

  /// 记谱字号系数：桌面 0.50（原值）；移动端 **0.95**
  ///
  /// 2026-10-27 用户反馈「文字很小、几乎无法看清」→ 系数从 0.68 提到 0.95：
  /// 槽宽 = 可用宽 ÷ 列数（一行音符越密槽宽越小），系数是**唯一**能在不改列数的
  /// 前提下放大字号的旋钮。0.95 已接近「字形墨迹填满一个拍点列」的物理上限
  /// （再大音符会横向压到相邻列）。
  static double get noteFontEmFor => _isMobile ? 0.95 : noteFontEm;

  /// 歌词字号系数：桌面 0.54（原值）；移动端 **0.88**
  ///
  /// 汉字字宽 ≈ 1 em 字号 → 必须 < 1 列宽才不与相邻音节重叠，故上限 ≈ 0.95；
  /// 取 0.88 留出标点/破折号的空间（2026-10-27 用户要求「大、看得清」）。
  static double get lyricFontEmFor => _isMobile ? 0.88 : lyricFontEm;

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
            .clamp(minSlot, maxSlotFor),
    ];
    // 高度约束：
    // - **桌面**：总像素高超过可用高时整体等比收缩（保持块间字号比例），避免滚动；
    // - **移动端（2026-10-25 用户要求「左右留白只留 5%、字更大」）**：**不收缩**，
    //   让槽宽保持「按列数铺满可用宽」→ 块宽 = 屏宽 − padX×2 ≈ 91%，字号随之最大；
    //   内容超出时交给外层纵向滚动（用户看整节可上下滑，比缩小字更实用）。
    final visible = <List<JianpuRow>>[
      for (final block in score.blocks) _visibleRows(block),
    ];
    // 每块的「相邻歌词最小列距」（2026-10-27：用于动态放大歌词字号）
    final lyricGaps = <int>[
      for (final block in score.blocks)
        JianpuGridView.minLyricColGap(block),
    ];
    // **单节全页 + 字号最大**的平衡点（2026-10-27 用户要求）：
    // bps = 每段小节数（0 = 桌面不折行）；fittedSlot = 该平衡点下的槽宽
    final (bps, fittedSlot) = fitFullPage(
      score,
      availW,
      availH,
      lyricGaps,
      _rowEm,
      visibleRows: visible,
    );
    var totalH = 0.0;
    for (var bi = 0; bi < visible.length; bi++) {
      if (bi > 0 && visible[bi].isNotEmpty) totalH += slots[bi] * blockGapEm;
      for (final row in visible[bi]) {
        totalH += slots[bi] * _rowEm(row.kind, lyricGaps[bi]);
      }
    }
    if (totalH > availH && totalH > 0 && !_isMobile) {
      final k = availH / totalH;
      for (var i = 0; i < slots.length; i++) {
        slots[i] = (slots[i] * k).clamp(minSlot, maxSlotFor);
      }
    } else if (totalH > 0 && totalH < availH && _growToFill) {
      // 内容不足一屏：**放大填满**（`maxGrowScale` 现为 1.0 = 关闭，2026-10-25
      // 用户要求"一行完整显示"后回退；此处保留结构以便将来重开）
      final k = (availH / totalH).clamp(1.0, maxGrowScale);
      for (var i = 0; i < slots.length; i++) {
        slots[i] = (slots[i] * k).clamp(minSlot, maxSlotFor);
      }
    }

    final children = <Widget>[];
    for (var bi = 0; bi < score.blocks.length; bi++) {
      final block = score.blocks[bi];
      // **按整小节折行**（2026-10-27，仅移动端）：每段不超过 `per` 列且在小节线处断开；
      // 桌面 `per = colCount` → 只有 1 段 = 原版式（golden 基准不变）。
      // 平衡点选定：`bps` 段小节数（0 = 桌面不折行），槽宽统一按 `fittedSlot`
      final segs =
          bps > 0 ? segmentsByBars(block, bps) : [(0, block.colCount)];
      final barCols = block.barColsByLine();
      for (var si = 0; si < segs.length; si++) {
        final (cs, ce) = segs[si];
        final cols = ce - cs;
        // **每段独立铺满**（2026-10-28 用户反馈"左侧空白很多"）：
        // 统一槽宽时短段（1~2 小节）只有 5~11 列 → 宽度远小于屏宽 → 居中后左右大片留白。
        // 改为按该段自身列数铺满 → 无留白；代价是短段字号更大（内容稀疏处字大，可接受）。
        final segSlot = cols > 0
            ? (availW / cols).clamp(1.0, maxSlotFor)
            : (fittedSlot > 0 ? fittedSlot : slots[bi]);
        final m = _Metrics(
          slot: segSlot,
          gridW: segSlot * cols,
          lyricColGap: lyricGaps[bi],
        );
        if (si == 0 && bi > 0 && visible[bi].isNotEmpty) {
          children.add(SizedBox(height: slots[bi] * blockGapEm));
        }
        for (final row in visible[bi]) {
          children.add(_buildRow(
            row,
            barCols[row.lineNo] ?? const <int>{},
            m,
            colStart: cs,
            colEnd: ce,
          ));
        }
      }
    }

    final viewH = (constraints.maxHeight - padTop - padBottom)
        .clamp(0.0, double.infinity);

    return Container(
      color: AppColors.lyricsBg,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(padX, padTop, padX, padBottom),
        // 允许内容溢出单元格（汉字 + 标点占 2 字宽），横向不裁剪、不挤列；
        // 各块宽度不同（按块宽渲染）→ Column 宽度取最宽块，块间左对齐
        child: SingleChildScrollView(
          // **横向滚动**（2026-10-25 用户要求 B）：内容不足一屏时被放大填满，
          // 放大后块宽可能超出可用宽 → 由此层承接，可左右滑动看全，绝不裁切
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            // **垂直居中**（与歌词页「整块居中」同口径，2026-09-23 用户确认）：
            // 内容不足一屏时整块垂直居中；超出一屏时 ConstrainedBox 被内容撑高
            // → 正常从顶滚动、不裁顶。minWidth 让「未放大到超宽」时横向仍居中
            constraints: BoxConstraints(minHeight: viewH, minWidth: availW),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: children,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// **移动端折行的目标槽宽**（dp）：一行列数受限，超出即换行。
  /// 2026-10-27：歌词密集（每列一个字）时字号上限 = 槽宽，一行 20 列只有 16.6dp
  /// ≈ 14.6sp（用户："几乎无法看清"）→ 折行让每列变宽、字变大。
  /// 30dp 起步（歌词 ~26sp）→ 用户要求"再大一些" → 试 38dp 后发现**整小节折行**下
  /// 每段只剩 5 列（1 小节）、段宽仅占屏 63%（又出现留白）→ **定 33dp**：
  /// 一行约 10 列 ≈ 2 小节，配 `segSlot = availW / 块内最大段列数` 正好铺满。
  static const double _targetSlot = 33.0;

  /// 每行最多列数：**桌面不拆**（返回该块列数，保持原版式与 golden 基准）；
  /// 移动端按 [_targetSlot] 计算上限，最少 3 列（极窄屏保护）。
  ///
  /// 公开为 static：日志/自测需要核对该值时不必复制一遍逻辑。
  static int colsPerLineFor(int colCount, double availW) {
    if (!_isMobile) return colCount;
    if (colCount <= 0) return 1;
    final maxCols = (availW / _targetSlot).floor();
    final limit = maxCols < 3 ? 3 : maxCols;
    return colCount > limit ? limit : colCount;
  }

  /// **按整小节边界折行**（2026-10-27 用户要求：不要把小节切两半）
  ///
  /// 返回 `[(startCol, endCol), ...]`，每段不超过 [maxCols] 列，且尽量在小节线处断开
  /// （小节线本身归入**下一段**开头，使每段都是完整小节）。
  /// 若一个小节本身超过 [maxCols]，则该段硬切（否则无法排布）。
  static List<(int, int)> barAlignedSegments(JianpuBlock block, int maxCols) {
    final segs = <(int, int)>[];
    if (block.colCount <= 0) return [(0, 0)];
    if (maxCols >= block.colCount) return [(0, block.colCount)];

    // 小节线列（取该块所有行的小节线并集；只有分隔线、不承载内容）
    final bars = <int>{};
    for (final cols in block.barColsByLine().values) {
      bars.addAll(cols);
    }
    final sorted = bars.toList()..sort();

    var start = 0;
    while (start < block.colCount) {
      final limit = start + maxCols;
      var end = -1;
      // 取「不超过 limit 的最后一根小节线」作为断点
      for (final b in sorted) {
        if (b > start && b <= limit) {
          if (b > end) end = b;
        }
      }
      if (end <= start) {
        // 段内没有小节线（或小节本身超长）→ 硬切
        var hard = start + maxCols;
        if (hard > block.colCount) hard = block.colCount;
        segs.add((start, hard));
        start = hard;
      } else {
        // **小节线归入本段末尾**（行尾有 `|` 收尾，符合印刷本与参考 APK 观感），
        // 下一段从 end+1 开始（该列的小节线不再重复绘制）
        final segEnd = end + 1 > block.colCount ? block.colCount : end + 1;
        segs.add((start, segEnd));
        start = segEnd;
      }
    }
    return segs;
  }

  /// **歌词基准字号**（sp）—— 2026-10-28 用户定稿：**以 18sp 为基准**
  ///
  /// 用户流程：「选 A（折行优先，允许轻微滚动）→ 找到最小字号后，以 18sp 为基准线进行显示。
  /// 每段小节如果单行无法显示，那就折行显示」。
  /// 即：**字号不低于 18sp**，一行放不下该小节就折行，行数由内容决定（可轻微滚动）。
  static const double _minLyricSp = 18.0;

  /// **按「每段 N 个小节」均衡切分**（2026-10-27 用户反馈「明明有地方显示却折成两行」）
  ///
  /// 旧的按列上限切分会让各段列数严重不均（如 12/5/3），窄段看起来"明明能一行"。
  /// 这里改为：**先把块切成小节，再每 N 个小节一段** → 各段列数接近、宽度利用均衡。
  static List<(int, int)> segmentsByBars(JianpuBlock block, int barsPerSeg) {
    final cols = block.colCount;
    if (cols <= 0) return [(0, 0)];
    final per = barsPerSeg < 1 ? 1 : barsPerSeg;
    // 小节结束列（小节线列 + 末尾 colCount）；末尾重复项去重
    final bars = <int>{};
    for (final c in block.barColsByLine().values) {
      bars.addAll(c);
    }
    final ends = bars.where((b) => b > 0 && b < cols).toList()..sort();
    ends.add(cols);

    final segs = <(int, int)>[];
    var start = 0;
    var i = 0;
    while (i < ends.length) {
      final j = i + per - 1;
      final end = ends[j >= ends.length ? ends.length - 1 : j];
      if (end > start) segs.add((start, end));
      start = end;
      i = j + 1;
    }
    return segs;
  }

  /// **按「行数最少优先」规划分块折行**（用户 2026-10-27 指定的算法）
  ///
  /// 旧实现按固定目标槽宽折行 → 短块（如「全能大主宰」8 列）明明一行放得下也被切成两行。
  /// 新算法：
  /// 1. 以 [_minLyricSp] 反推**最小槽宽** → 每行最多几列（`perAtMin`）；
  /// 2. 用 `perAtMin` 按**整小节**切分 → 得到**最少行数**；
  /// 3. 段槽宽 = `availW / 块内最大段列数` → 在该行数下**把字号最大化**。
  ///
  /// ⇒ 短块一行放下且字更大；长块折行后字号不低于 [_minLyricSp]；
  /// **能两行显示绝不三行**（不再按固定槽宽无限折行）。
  static List<(int, int)> planSegments(
    JianpuBlock block,
    double availW,
    double lyricEm,
  ) {
    final cols = block.colCount;
    if (cols <= 0) return [(0, 0)];
    if (!_isMobile) return [(0, cols)]; // 桌面：整块一行（原版式）

    final em = lyricEm <= 0 ? 0.88 : lyricEm;
    final minSlot = (_minLyricSp / em).ceilToDouble();
    var perAtMin = (availW / minSlot).floor();
    if (perAtMin < 2) perAtMin = 2;
    // 最小字号下一行就放得下 → 不折行（字号随块铺满 = 最大化）
    if (perAtMin >= cols) return [(0, cols)];
    // **按小节数均衡切分**：小节宽度 = 总列数 / 小节数，算出每段能放几个整小节
    final barCount = segmentsByBars(block, 1).length;
    final barWidth = barCount > 0 ? cols / barCount : cols.toDouble();
    var barsPerSeg = (perAtMin / barWidth).floor();
    if (barsPerSeg < 1) barsPerSeg = 1;
    return segmentsByBars(block, barsPerSeg);
  }

  /// **「全页显示」的宽容系数**（2026-10-28 用户要求「折行与全页同时存在」）
  ///
  /// 实测算术：第 1 首一节 = 80 列 × 每段 4 行(音符/上记号/下记号/歌词) ≈ 3.8 em/段。
  /// - 严格 1.0 屏（487dp）→ 只能放 4 段 = 每行 4 小节，字号被压到 **14.6sp**；
  /// - 允许 **1.35 屏**（轻微上下滚动）→ 可放 8 段（每段 2 小节），字号 **18.2sp**（+25%）。
  /// 用户明确"折行、单节全页同时存在"→ 取 1.35：优先保证**折行与字号**，
  /// 内容略超一屏时允许小幅滚动（不会是多屏）。
  static const double _fullPageSlack = 1.42;

  /// **「单节全页 + 字号最大」平衡点搜索**（2026-10-27 用户要求）
  ///
  /// 用户诉求：字号够大了，但一节内容超出一屏 → 要在「**单节全页显示**」与「折行扩字号」
  /// 之间取平衡，并以第 1 首为例确定这个字号作为新的最小字号基准。
  ///
  /// 做法：以「**每段几个小节**」`bps` 为搜索变量（1→6），
  /// - `bps` 越小 → 每段列数越少 → 槽宽越大 → 字号越大；
  /// - 逐档累加**估算总高**，取**第一个满足 `总高 ≤ 可用高`** 的档 = 字号最大的可行解。
  ///
  /// 返回 `(每段小节数, 槽宽)`；桌面返回 `(0, 0)` 表示不折行（原版式）。
  static (int, double) fitFullPage(
    JianpuScore score,
    double availW,
    double availH,
    List<int> lyricGaps,
    double Function(JianpuRowKind kind, int colGap) rowEm, {
    /// **每块实际可见的行**（`_visibleRows` 的结果）—— 必须传！
    /// 若用 `block.rows`（含所有节的歌词行）会 3 倍高估高度（2026-10-28 实测：
    /// 因此误选「每段 4 小节、字号 14.6sp」，而正确答案是「每段 2 小节、18.2sp」）。
    List<List<JianpuRow>>? visibleRows,
  }) {
    if (!_isMobile || score.blocks.isEmpty) return (0, 0.0);
    var totalCols = 0;
    for (final b in score.blocks) {
      totalCols += b.colCount;
    }
    if (totalCols <= 0) return (0, 0.0);

    // **折行后字号自动放大**（2026-10-28 用户追问的核心）：
    // bps 越小 → 每段列数越少 → 槽宽越大 → 字号越大，但总高也越大。
    // 所以从 bps=1（字号最大）起逐档试：
    //   · 高度超限 → 继续折行（bps++，段变窄→字号变小→高度下降）；
    //   · 高度满足 → **立即返回**，此时字号就是"该行数下能给出的最大值"；
    //   · 字号跌破基准 [_minLyricSp]（18sp）→ 停止（防止为了塞进一屏把字压得太小）。
    var bestBps = 0;
    var bestSlot = 0.0;
    for (var bps = 1; bps <= 6; bps++) {
      var maxSegCols = 0;
      for (final block in score.blocks) {
        for (final (s, e) in segmentsByBars(block, bps)) {
          if (e - s > maxSegCols) maxSegCols = e - s;
        }
      }
      if (maxSegCols < 2) continue;
      final slot = availW / maxSegCols;
      // 字号下限保护（按基准 em 0.88 估算；低于 18sp 就不再继续压缩）
      if (slot * 0.88 < _minLyricSp) break;
      var h = 0.0;
      for (var bi = 0; bi < score.blocks.length; bi++) {
        final block = score.blocks[bi];
        final segs = segmentsByBars(block, bps);
        final rows = (visibleRows != null && bi < visibleRows.length)
            ? visibleRows[bi]
            : block.rows;
        var segH = 0.0;
        for (final row in rows) {
          segH += slot * rowEm(row.kind, lyricGaps[bi]);
        }
        h += segH * segs.length;
        if (bi > 0) h += slot * 0.55; // blockGapEm
      }
      bestBps = bps;
      bestSlot = slot;
      // 高度已能接受 → 该档就是「字号最大且（近似）一屏」的解
      if (h <= availH * _fullPageSlack) return (bps, slot);
    }
    if (bestBps > 0) return (bestBps, bestSlot);
    // 兜底：最密档
    var maxSegCols = 0;
    for (final block in score.blocks) {
      for (final (s, e) in segmentsByBars(block, 6)) {
        if (e - s > maxSegCols) maxSegCols = e - s;
      }
    }
    if (maxSegCols < 2) maxSegCols = 2;
    return (6, availW / maxSegCols);
  }

  /// 相邻歌词列的**最小列距**（用于动态放大歌词字号）
  ///
  /// 2026-10-27 找到「字看不清」的真正原因：一行 22 列时槽宽只有 ~16.6dp，
  /// 若歌词字号 = 槽宽 × 0.88 → 仅 14.6sp（与正文同大，看不清）。
  /// 但**歌词并非每个音符都配字**：相邻歌词常隔 2~4 列，字宽完全可以超过 1 列。
  /// 故按该块「相邻歌词列距的最小值」放大字号：稀疏处字更大，密集处仍不重叠。
  ///
  /// 公开为 static：日志/自测需要核对该值时不必复制一遍逻辑。
  static int minLyricColGap(JianpuBlock block) {
    var gap = 1 << 30;
    for (final row in block.rows) {
      if (row.kind != JianpuRowKind.lyric) continue;
      final cols = row.cols.toList()..sort();
      for (var i = 1; i < cols.length; i++) {
        final d = cols[i] - cols[i - 1];
        if (d < gap) gap = d;
      }
    }
    return gap == (1 << 30) ? 1 : gap;
  }

  /// 歌词字号系数（相对槽宽）：列距越大字越大，上限 2.6 em（防个别稀疏块字过大）
  ///
  /// **仅移动端启用动态放大**：桌面版式（印刷本口径）保持原 `lyricFontEm` 不变，
  /// 否则桌面歌词会被放大数倍、破坏 golden 基准。
  double _lyricEm(int colGap) {
    if (!_isMobile) return lyricFontEm;
    if (colGap <= 1) return lyricFontEmFor;
    return (colGap * 0.92).clamp(lyricFontEmFor, 2.6);
  }

  /// 行高（em：音符/记号行相对**记谱字号**；歌词/空行相对槽宽）
  double _rowEm(JianpuRowKind k, int lyricColGap) => switch (k) {
        JianpuRowKind.note => noteRowEm * noteFontEmFor,
        JianpuRowKind.markUp => markUpEm * noteFontEmFor,
        JianpuRowKind.markDown => markDownEm * noteFontEmFor,
        JianpuRowKind.lyric => _lyricEm(lyricColGap) * 1.7,
        JianpuRowKind.blank => blankEm,
      };

  double _rowHeight(JianpuRowKind k, _Metrics m) =>
      m.slot * _rowEm(k, m.lyricColGap);

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

  Widget _buildRow(
    JianpuRow row,
    Set<int> barCols,
    _Metrics m, {
    int colStart = 0,
    int colEnd = 1 << 30,
  }) {
    final h = _rowHeight(row.kind, m);
    final stack = <Widget>[];

    // ③ 折行切片（2026-10-27）：只画落在 [colStart, colEnd) 的列，
    // x 坐标按切片起点归零 → 每段都是独立的一行
    bool inSlice(int col) => col >= colStart && col < colEnd;

    // ① 小节线（先画，位于内容之下；被 rowspan 覆盖的行同样绘制 → 视觉连续）
    for (final col in barCols) {
      if (!inSlice(col)) continue;
      stack.add(Positioned(
        left: (col - colStart) * m.slot + (m.slot - m.barW) / 2,
        top: 0,
        bottom: 0,
        child: Container(width: m.barW, color: m.barColor),
      ));
    }

    // ② 单元格内容
    for (final col in row.cols) {
      if (!inSlice(col)) continue;
      final cell = row.cells[col]!;
      final w = _buildCell(row, cell, m);
      if (w == null) continue;
      // **含标点的歌词格放宽到 1.6 列**（汉字原字号 + 小号标点，2026-10-27）：
      // 直接加宽该 Positioned，而不是靠溢出 → 既不缩小汉字，也不触发 RenderFlex overflow。
      final isMultiChar = cell.kind == JianpuCellKind.text &&
          cell.displayText.characters.length > 1;
      stack.add(Positioned(
        left: (col - colStart) * m.slot,
        top: 0,
        width: isMultiChar ? m.slot * 1.6 : m.slot,
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
        // **汉字与标点分开渲染**（2026-10-27 用户指出：整格缩放会把「哉」也缩小 —— 低级错误）
        //
        // 数据库 `jianpu_cell.text` 把「哉，」存在**同一格**（CSV 原样，未拆分）。
        // 正确做法：按末尾标点拆开 —— **汉字保持原字号**，标点用 0.55 倍字号紧贴其后；
        // 整体略宽于 1 列时允许溢出到右侧（该位置在源数据里通常是空列），
        // 既不缩小汉字，也不会与相邻字重叠。
        final rawText = cell.displayText;
        final punctMatch =
            RegExp(r'[，。、；：！？,.;:!?）】」』…—]+$').firstMatch(rawText);
        final bodyText = punctMatch == null
            ? rawText
            : rawText.substring(0, punctMatch.start);
        final punctText = punctMatch?.group(0) ?? '';
        final baseStyle = TextStyle(
          fontFamily: 'EchoKai',
          fontFamilyFallback: const ['KaiTi', 'EchoSans'],
          fontSize: m.lyricSize,
          height: 1.15,
          color: m.lyricColor,
        );
        if (punctText.isEmpty || bodyText.isEmpty) {
          return Align(
            alignment: Alignment.center,
            child: Text(
              rawText,
              maxLines: 1,
              softWrap: false,
              textAlign: TextAlign.center,
              style: baseStyle,
            ),
          );
        }
        return Align(
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(bodyText,
                  maxLines: 1, softWrap: false, style: baseStyle),
              Text(
                punctText,
                maxLines: 1,
                softWrap: false,
                style: baseStyle.copyWith(fontSize: m.lyricSize * 0.55),
              ),
            ],
          ),
        );
      case JianpuCellKind.stanza:
        // **逐节显示时不显示节号**（2026-10-25 用户要求：曲谱改为一页一节后，
        // 每页只有一节，印刷本的行首节号 `(k)` 只占位、挤占音符宽度）；
        // **整页形态（`stanza == null`，桌面印刷本视图）照旧显示** ——
        // 那里靠 (1)(2)(3) 区分同一块内的各节歌词，去掉会造成歧义。
        if (stanza != null) return null;
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
                fontSize: m.noteSize * 0.58,
                color: m.noteColor,
                fontWeight: FontWeight.w600,
                height: 1.0,
              ),
            ),
          TextSpan(
            text: digit,
            style: TextStyle(
              fontFamily: kJianpuFontFamily,
              fontSize: m.noteSize,
              color: m.noteColor,
              height: 1.0,
            ),
          ),
          if (dots.isNotEmpty)
            TextSpan(
              text: dots,
              style: TextStyle(
                fontFamily: kJianpuFontFamily,
                fontSize: m.noteSize,
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
  const _Metrics({
    required this.slot,
    required this.gridW,
    required this.lyricColGap,
  });

  /// 槽宽 = 拍点间距（列宽；与列对齐基准）
  final double slot;

  /// 网格总宽 = 槽宽 × 全曲最大列数
  final double gridW;

  /// 该块相邻歌词列的最小列距（≥1；用于放大歌词字号，2026-10-27）
  final int lyricColGap;

  /// **记谱字号**（音符/记号字形大小）= 槽宽 × [JianpuGridView.noteFontEmFor]
  /// （移动端 0.95 / 桌面 0.50，2026-10-27）
  double get noteSize => slot * JianpuGridView.noteFontEmFor;

  double get barW => (noteSize * 0.075).clamp(1.0, 3.5);

  /// **歌词字号** = 槽宽 × 动态系数（列距越大字越大，见 `_lyricEm`）。
  /// 上限 56：移动端稀疏块可达 2.6 em × 40dp ≈ 104，需限制在可读范围。
  /// **桌面保持原口径**（`lyricFontEm`，不随列距放大）。
  double get lyricSize {
    if (!JianpuGridView._isMobile) {
      return (slot * JianpuGridView.lyricFontEm).clamp(8.0, 46.0);
    }
    final em = lyricColGap <= 1
        ? JianpuGridView.lyricFontEmFor
        : (lyricColGap * 0.92).clamp(JianpuGridView.lyricFontEmFor, 2.6);
    return (slot * em).clamp(8.0, 56.0);
  }

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


