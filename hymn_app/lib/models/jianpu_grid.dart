/// 简谱网格模型（数据源：`jianpu_score` / `jianpu_row` / `jianpu_cell` 三表）
///
/// 数据来源与结构（2026-09-22 定稿）：
/// - 三表由 `tools/import_apk_csv.py` 从第三方 APK 的 `assets/NNN.csv` 谱面网格导入；
/// - **核心不变式 = 「同一列 = 同一拍点」**：音符、记号（减时线 / 低·高音点 /
///   延长记号）、小节线（跨行）、歌词音节全部落在同一列的单元格里 ——
///   对齐来自**数据**，渲染层不做任何时间→像素换算（这正是 APK 的同步机制）。
///
/// 行类型（CSV 行角色，同一乐句块内的固定次序）：
/// `markUp`（音符上方：高八度点 / 延长记号 / 小节线）
/// `note`（音符行）  `markDown`（音符下方：减时线 / 低八度点）
/// `lyric`（歌词行，每行一节）  `blank`（空行）
///
/// 自检：`tools/jianpu_csv_selftest.py`（DB↔CSV 逐格 / 列对齐不变式 / 实机快照交叉验证）。
library;

/// 行类型
enum JianpuRowKind {
  /// 音符行（数字谱）
  note,

  /// 音符**上方**记号行（高八度点 `UD`、延长记号 `E`、小节线 `L2~L7`）
  markUp,

  /// 音符**下方**记号行（减时线 `B`、低八度点 `D`，及组合 `BD`/`BBD`/…）
  markDown,

  /// 歌词行（一行 = 一节）
  lyric,

  /// 空行
  blank,
}

/// 单元格类型
enum JianpuCellKind {
  /// 音符（1~7）
  note,

  /// 休止符（`0`）
  rest,

  /// 增时线（`-`）
  dash,

  /// 记号插图（`M…N`：`B` 减时线 / `D` 低八度点 / `UD` 高八度点 / `E` 延长记号…）
  mark,

  /// 小节线（`,L2`~`,L7`，`rowspan` 跨行）
  barline,

  /// 歌词音节（含随音节的标点）
  text,

  /// 节号标记（`(1)`）
  stanza,

  /// 变音记号（单独的 `#` / `b`）
  accidental,

  /// 附点单元格（单独的 `.` / `..`）
  dotLen,

  /// 无法识别（源数据里的 `?` 等）
  unknown,
}

JianpuRowKind rowKindOf(String s) => switch (s) {
      'note' => JianpuRowKind.note,
      'mark_up' => JianpuRowKind.markUp,
      'mark_down' => JianpuRowKind.markDown,
      'lyric' => JianpuRowKind.lyric,
      _ => JianpuRowKind.blank,
    };

JianpuCellKind cellKindOf(String s) => switch (s) {
      'note' => JianpuCellKind.note,
      'rest' => JianpuCellKind.rest,
      'dash' => JianpuCellKind.dash,
      'mark' => JianpuCellKind.mark,
      'barline' => JianpuCellKind.barline,
      'text' => JianpuCellKind.text,
      'stanza' => JianpuCellKind.stanza,
      'accidental' => JianpuCellKind.accidental,
      'dot_len' => JianpuCellKind.dotLen,
      _ => JianpuCellKind.unknown,
    };

/// 一个网格单元格（列 = 拍点）
class JianpuCell {
  const JianpuCell({
    required this.col,
    required this.kind,
    required this.sym,
    this.degree,
    this.accidental,
    this.dotLen,
    this.octave,
    this.dots,
    this.beams,
    this.fermata,
    this.rowspan,
    this.text,
  });

  /// 列号（0 基；同列 = 同拍点）
  final int col;
  final JianpuCellKind kind;

  /// 原始 token（便于自检与回退显示）
  final String sym;

  /// 音级 1~7（[JianpuCellKind.note]；休止符为 0）
  final int? degree;

  /// 变音记号 `#` / `b`
  final String? accidental;

  /// 附点个数（0~2）
  final int? dotLen;

  /// 八度偏移（正 = 高八度点个数；负 = 低八度点个数）——由同列的上/下记号行派生
  final int? octave;

  /// 记号点数（`D` 个数）
  final int? dots;

  /// 减时线数（`B` 个数；1 = 八分，2 = 十六分）
  final int? beams;

  /// 延长记号（fermata，`E` 字形）
  final int? fermata;

  /// 小节线跨行数（`rowspan`）
  final int? rowspan;

  /// 文本内容（歌词音节 / 节号 / 记号字形名）
  final String? text;

  /// 单元格可显示的文本（音符/休止/增时线/歌词/节号；记号与小节线返回空串）
  String get displayText {
    switch (kind) {
      case JianpuCellKind.note:
        return '${accidental ?? ''}${degree ?? ''}${'.' * (dotLen ?? 0)}';
      case JianpuCellKind.rest:
        return '0';
      case JianpuCellKind.dash:
        return '-';
      case JianpuCellKind.text:
      case JianpuCellKind.stanza:
        return text ?? sym;
      case JianpuCellKind.accidental:
        return accidental ?? sym;
      case JianpuCellKind.dotLen:
        return '.' * (dotLen ?? 1);
      case JianpuCellKind.mark:
      case JianpuCellKind.barline:
      case JianpuCellKind.unknown:
        return '';
    }
  }
}

/// 一行网格数据
class JianpuRow {
  const JianpuRow({
    required this.lineNo,
    required this.blockNo,
    required this.kind,
    required this.colCount,
    required this.cells,
    this.stanzaNo,
  });

  /// CSV 行号（0 基，保持原始顺序）
  final int lineNo;

  /// 块号（CSV 里 `K` = 换表；块内列宽一致）
  final int blockNo;

  final JianpuRowKind kind;

  /// 该行单元格数（= 列数）
  final int colCount;

  /// 节号（歌词行 1 基）
  final int? stanzaNo;

  /// 列号 → 单元格（空单元格不落库，取不到即为空）
  final Map<int, JianpuCell> cells;

  bool get isMusical =>
      kind == JianpuRowKind.note ||
      kind == JianpuRowKind.markUp ||
      kind == JianpuRowKind.markDown;

  /// 该行是否带印刷节号 `(k)`（源 CSV 歌词行首列的 `(k)` 单元格）。
  ///
  /// 印刷本**只在每首第 1 个乐句块**逐节写节号 → 「带节号的**行数**」即全曲节数
  /// （见 [JianpuScore.build] 的节数推导）。
  bool get hasStanzaLabel =>
      cells.values.any((c) => c.kind == JianpuCellKind.stanza);

  /// 该行参与显示的列号（升序）
  List<int> get cols => cells.keys.toList()..sort();

  /// 该行是否有可显示内容（供空态判定与自检）
  bool get hasContent => cells.values.any((c) =>
      c.displayText.isNotEmpty ||
      c.kind == JianpuCellKind.mark ||
      c.kind == JianpuCellKind.barline);
}

/// 小节线跨行区间（列 + 起始行 + 跨行数）
class JianpuBarSpan {
  const JianpuBarSpan(this.col, this.startLine, this.span);
  final int col;
  final int startLine;
  final int span;
}

/// 一个乐句块（CSV 里一次 `<table>`；APK 用 `K` 标记换表）
class JianpuBlock {
  const JianpuBlock({
    required this.blockNo,
    required this.rows,
    required this.colCount,
    required this.bars,
  });

  final int blockNo;
  final List<JianpuRow> rows;

  /// 块列宽（块内各行单元格数的最大值）
  final int colCount;

  /// 块内全部小节线
  final List<JianpuBarSpan> bars;

  /// 块内歌词行数（= 该块承载的「行数」：分节块 = 节数(+ 重复句)；副歌块 < 节数）
  int get lyricCount {
    var n = 0;
    for (final r in rows) {
      if (r.kind == JianpuRowKind.lyric) n++;
    }
    return n;
  }

  /// 该块歌词是否**各节共用**（副歌 / 各节完全相同的句子）——每节都要唱。
  ///
  /// 判据（2026-10-12 全库 474 首核对的数据事实）：印刷本对副歌/叠句**只写一遍**，
  /// 所以这类块的歌词行数**少于全曲节数**（第 283 首副歌两块各 1 行、节数 3；
  /// 第 103 首副歌两块各 2 行、节数 3）。逐节显示时若只认节号，
  /// 第 2 节起这些块就会整块无词 —— 这是「有副歌的曲子没词」的根因。
  bool sharesLyricsAcrossStanzas(int stanzaCount) =>
      stanzaCount > 1 && lyricCount > 0 && lyricCount < stanzaCount;

  /// 行号 → 该行需要绘制小节线的列集合（含被 `rowspan` 覆盖的行）
  Map<int, Set<int>> barColsByLine() {
    final out = <int, Set<int>>{};
    for (final b in bars) {
      for (var i = 0; i < b.span; i++) {
        out.putIfAbsent(b.startLine + i, () => <int>{}).add(b.col);
      }
    }
    return out;
  }
}

/// 一首诗的完整简谱网格
class JianpuScore {
  const JianpuScore({
    required this.hymnNumber,
    required this.source,
    required this.blocks,
    required this.stanzaCount,
  });

  final String hymnNumber;

  /// 数据来源标记（如 `apk_csv:009`）
  final String source;

  final List<JianpuBlock> blocks;

  /// 节数（全曲；「一页一节」的页数与行归节都以它为准）
  ///
  /// 由 [build] 从行数据推导（见 [_deriveStanzaCount]），数据库
  /// `jianpu_score.stanza_count` 只作兜底 —— 后者按「行内位置」统计，
  /// 会被重复句行虚增（第 18 首 3 节却记成 6）。
  final int stanzaCount;

  static const JianpuScore empty =
      JianpuScore(hymnNumber: '', source: '', blocks: [], stanzaCount: 0);

  bool get isEmpty => blocks.isEmpty || blocks.every((b) => b.rows.isEmpty);

  /// 由仓库查询结果构建（行按 line_no 升序、单元格按列稀疏）
  ///
  /// [firstVoiceOnly] = true 时按「四部合唱谱只取第一声部」过滤：
  /// 源数据每个乐句块 = 一个系统 = 女高/女低/歌词/男高/男低 五行组（S,A,词,T,B），
  /// 过滤后每块只保留**第一个声部组**（记号上+音符+记号下）+ 全部歌词行 ——
  /// 即用户红框口径：各节歌词共唱第一行旋律（2026-09-23 定稿）。
  ///
  /// [stanzaCount]（数据库 `jianpu_score.stanza_count`）只作**兜底**：
  /// 正常数据下节数由 [_deriveStanzaCount] 从行数据推导（2026-10-12）。
  factory JianpuScore.build({
    required String hymnNumber,
    required String source,
    required List<JianpuRow> rows,
    required int stanzaCount,
    bool firstVoiceOnly = false,
  }) {
    final byBlock = <int, List<JianpuRow>>{};
    for (final r in rows) {
      byBlock.putIfAbsent(r.blockNo, () => []).add(r);
    }
    final blocks = <JianpuBlock>[];
    for (final no in byBlock.keys.toList()..sort()) {
      var rs = byBlock[no]!..sort((a, b) => a.lineNo.compareTo(b.lineNo));
      if (firstVoiceOnly) rs = _firstVoiceRows(rs);
      var width = 0;
      final bars = <JianpuBarSpan>[];
      for (var i = 0; i < rs.length; i++) {
        final r = rs[i];
        if (r.colCount > width) width = r.colCount;
        for (final c in r.cells.values) {
          if (c.kind == JianpuCellKind.barline) {
            // 小节线跨行 = 自本行起**连续的乐谱行**数：过滤声部后自动缩短为
            // 一个声部组的高度（全声部形态下与源数据 rowspan 等价）
            var span = 1;
            for (var k = i + 1; k < rs.length && rs[k].isMusical; k++) {
              span++;
            }
            bars.add(JianpuBarSpan(c.col, r.lineNo, span));
          }
        }
      }
      blocks.add(
          JianpuBlock(blockNo: no, rows: rs, colCount: width, bars: bars));
    }
    return JianpuScore(
      hymnNumber: hymnNumber,
      source: source,
      blocks: blocks,
      // 节数以**行数据**为准（数据库 stanza_count 会被重复句虚增，只作兜底）
      stanzaCount: _deriveStanzaCount(rows, stanzaCount),
    );
  }

  /// 推导全曲节数（「一页一节」的页数与行归节都以此为准）。
  ///
  /// 数据事实（2026-10-12 全库 474 首逐首核对）：
  /// 1. 印刷本每个乐句块**逐节写一行歌词**，且只在第 1 个块里写节号 `(k)`；
  /// 2. 故「带 `(k)` 节号的行数（**只看行数、不看节号取值**）」= 全曲节数 ——
  ///    个别诗歌（第 111 首）把首块每行都印成 `(1)`，行数依然正确，
  ///    而数据库按行内位置统计的 `stanza_count` 则被虚增（第 18 首 3 节记成 6、
  ///    第 130 首 4 节记成 5 …，全库 25 首）；
  /// 3. 极少数诗歌（第 460 首）**完全没有节号** → 回退「块内最大歌词行数」
  ///    （与数据库口径一致，行为不变）。
  static int _deriveStanzaCount(List<JianpuRow> rows, int fallback) {
    final labelled = <int, int>{};
    final lyric = <int, int>{};
    for (final r in rows) {
      if (r.kind != JianpuRowKind.lyric) continue;
      lyric.update(r.blockNo, (v) => v + 1, ifAbsent: () => 1);
      if (r.hasStanzaLabel) {
        labelled.update(r.blockNo, (v) => v + 1, ifAbsent: () => 1);
      }
    }
    var maxLabelled = 0;
    for (final n in labelled.values) {
      if (n > maxLabelled) maxLabelled = n;
    }
    if (maxLabelled > 1) return maxLabelled;
    var maxLyric = 0;
    for (final n in lyric.values) {
      if (n > maxLyric) maxLyric = n;
    }
    return maxLyric > 0 ? maxLyric : fallback;
  }

  /// 四部合唱谱（S,A,词,T,B）只保留**第一声部**：每块第一个
  /// 「记号上 + 音符 + 记号下」组 + 全部歌词/空行；其余声部行丢弃。
  static List<JianpuRow> _firstVoiceRows(List<JianpuRow> rows) {
    final out = <JianpuRow>[];
    var seenNote = false;
    var done = false;
    for (final r in rows) {
      if (!r.isMusical) {
        out.add(r); // 歌词/空行始终保留
        continue;
      }
      if (done) continue; // 第一声部组之后的声部行丢弃
      switch (r.kind) {
        case JianpuRowKind.markUp:
          if (seenNote) {
            done = true; // 音符后再现记号上 = 下一声部开始
          } else {
            out.add(r);
          }
        case JianpuRowKind.note:
          out.add(r);
          seenNote = true;
        case JianpuRowKind.markDown:
          out.add(r);
          if (seenNote) done = true; // 记号下收尾 = 第一声部组结束
        case JianpuRowKind.lyric:
        case JianpuRowKind.blank:
          out.add(r);
      }
    }
    return out;
  }

  /// 全曲最大列数（渲染时统一列宽的基准）
  int get maxCols =>
      blocks.fold(0, (m, b) => b.colCount > m ? b.colCount : m);

  /// 行数（全部块）
  int get rowCount => blocks.fold(0, (s, b) => s + b.rows.length);
}

