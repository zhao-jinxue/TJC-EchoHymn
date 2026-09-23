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

  /// 节数（全曲）
  final int stanzaCount;

  static const JianpuScore empty =
      JianpuScore(hymnNumber: '', source: '', blocks: [], stanzaCount: 0);

  bool get isEmpty => blocks.isEmpty || blocks.every((b) => b.rows.isEmpty);

  /// 由仓库查询结果构建（行按 line_no 升序、单元格按列稀疏）
  factory JianpuScore.build({
    required String hymnNumber,
    required String source,
    required List<JianpuRow> rows,
    required int stanzaCount,
  }) {
    final byBlock = <int, List<JianpuRow>>{};
    for (final r in rows) {
      byBlock.putIfAbsent(r.blockNo, () => []).add(r);
    }
    final blocks = <JianpuBlock>[];
    for (final no in byBlock.keys.toList()..sort()) {
      final rs = byBlock[no]!..sort((a, b) => a.lineNo.compareTo(b.lineNo));
      var width = 0;
      final bars = <JianpuBarSpan>[];
      for (final r in rs) {
        if (r.colCount > width) width = r.colCount;
        for (final c in r.cells.values) {
          if (c.kind == JianpuCellKind.barline) {
            bars.add(JianpuBarSpan(c.col, r.lineNo, c.rowspan ?? 1));
          }
        }
      }
      blocks.add(JianpuBlock(
          blockNo: no, rows: rs, colCount: width, bars: bars));
    }
    return JianpuScore(
      hymnNumber: hymnNumber,
      source: source,
      blocks: blocks,
      stanzaCount: stanzaCount,
    );
  }

  /// 全曲最大列数（渲染时统一列宽的基准）
  int get maxCols =>
      blocks.fold(0, (m, b) => b.colCount > m ? b.colCount : m);

  /// 行数（全部块）
  int get rowCount => blocks.fold(0, (s, b) => s + b.rows.length);
}

