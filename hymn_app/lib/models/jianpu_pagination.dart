import 'dart:math' as math;

import '../services/log_service.dart';
import 'jianpu_grid.dart';

/// 曲谱分页：**一页 = 若干小节**（按小节线切分）
///
/// 规则来源：`ANDROID_PLAN.md` §3.14 / B9 / C15 —— 自适应 2~4 小节/页，可固定 2/3/4；
/// 页内仍复用 `JianpuGridView`（同列同 x / 记号自绘 / 小节线跨行），本类只负责
/// **算页面窗口（列范围）与全曲小节序号**。
///
/// 小节划分（每块独立，块 = CSV 里一次 `<table>`）：
/// - 小节线（`JianpuCellKind.barline`）的列 = 该小节的**右边界**；
/// - 末尾若在小节线之后仍有内容，则额外构成一个「无右线小节」；
/// - 块内无任何小节线 → 整块视为 1 个小节。
///
/// 页数 = **各块页数之和**（块之间不合并：块是乐句系统，跨块拼页会破坏排版）。
class JianpuPage {
  const JianpuPage({
    required this.blockNo,
    required this.indexInBlock,
    required this.startCol,
    required this.endCol,
    required this.firstBar,
    required this.lastBar,
    required this.barCount,
  });

  /// 所属乐句块号
  final int blockNo;

  /// 块内页序号（0 起）
  final int indexInBlock;

  /// 页内起始列（含）
  final int startCol;

  /// 页内结束列（含；通常是该页最后一小节的右小节线列）
  final int endCol;

  /// 全曲第 a 小节（1 起，含）
  final int firstBar;

  /// 全曲第 b 小节（1 起，含）
  final int lastBar;

  /// 本页小节数
  final int barCount;

  /// 「第 a~b 小节」文案（a == b 时只写一个）
  String get barRangeLabel =>
      firstBar == lastBar ? '第 $firstBar 小节' : '第 $firstBar~$lastBar 小节';
}

/// 分页结果
class JianpuPagination {
  const JianpuPagination({
    required this.pages,
    required this.barCount,
    required this.barsPerPage,
    required this.elapsedMs,
  });

  static const JianpuPagination empty = JianpuPagination(
    pages: [],
    barCount: 0,
    barsPerPage: 0,
    elapsedMs: 0,
  );

  final List<JianpuPage> pages;

  /// 全曲小节总数
  final int barCount;

  /// 实际采用的「每页小节数」
  final int barsPerPage;

  /// 切页计算耗时（毫秒）；验收口径 ≤16 ms（一帧）
  final double elapsedMs;

  bool get isEmpty => pages.isEmpty;

  int get pageCount => pages.length;

  /// 块内页数
  int pagesInBlock(int blockNo) =>
      pages.where((p) => p.blockNo == blockNo).length;

  /// 计算分页（纯 CPU，476 首量级下远低于 1 ms；异常数据也不抛）。
  ///
  /// [barsPerPage] 固定每页小节数（2/3/4 为计划口径；其它值按 1~8 钳制）。
  static JianpuPagination build(JianpuScore score, {int barsPerPage = 2}) {
    final sw = Stopwatch()..start();
    final k = barsPerPage.clamp(1, 8);
    final pages = <JianpuPage>[];
    var barOffset = 0; // 已累计小节数（全曲小节序号用）

    for (final block in score.blocks) {
      final spans = _barsOf(block);
      if (spans.isEmpty) continue;
      for (var i = 0; i < spans.length; i += k) {
        final chunk = spans.sublist(i, math.min(i + k, spans.length));
        pages.add(JianpuPage(
          blockNo: block.blockNo,
          indexInBlock: i ~/ k,
          startCol: chunk.first.startCol,
          endCol: chunk.last.endCol,
          firstBar: barOffset + i + 1,
          lastBar: barOffset + i + chunk.length,
          barCount: chunk.length,
        ));
      }
      barOffset += spans.length;
    }

    sw.stop();
    final ms = sw.elapsedMicroseconds / 1000.0;
    final result = JianpuPagination(
      pages: pages,
      barCount: barOffset,
      barsPerPage: k,
      elapsedMs: ms,
    );
    LogService.instance.info(
      LogTag.ui,
      '曲谱分页计算完成',
      detail: '${score.hymnNumber.isEmpty ? '（未命名）' : '第 ${score.hymnNumber} 首'}'
          '：${pages.length} 页 / $barOffset 小节 / 每页 $k 小节 / 耗时 ${ms.toStringAsFixed(3)} ms'
          '${ms > 16 ? '（超出 16ms 预算）' : ''}',
    );
    return result;
  }

  /// 自适应每页小节数：按「可用宽 ÷ 列宽」能容纳的列数折算小节数，钳制 2~4。
  ///
  /// 用**全曲平均**每小节列数（按块各自算会让页大小忽大忽小，翻页体验不稳）。
  static int autoBarsPerPage({
    required JianpuScore score,
    required double availableWidth,
    required double colWidth,
  }) {
    if (availableWidth <= 0 || colWidth <= 0) return 2;
    var cols = 0;
    var bars = 0;
    for (final b in score.blocks) {
      final spans = _barsOf(b);
      if (spans.isEmpty) continue;
      cols += spans.fold<int>(0, (s, e) => s + (e.endCol - e.startCol + 1));
      bars += spans.length;
    }
    if (bars == 0 || cols == 0) return 2;
    final colsPerBar = cols / bars;
    final availCols = availableWidth / colWidth;
    final fit = (availCols / colsPerBar).floor();
    return fit.clamp(2, 4);
  }
}

/// 块内小节（列范围；[startCol]..[endCol] 含该小节右小节线）
class _BarSpan {
  const _BarSpan(this.startCol, this.endCol);
  final int startCol;
  final int endCol;
}

/// 按小节线把一块切成小节
List<_BarSpan> _barsOf(JianpuBlock block) {
  if (block.rows.isEmpty || block.colCount <= 0) return const [];
  final lastCol = block.colCount - 1;
  final barCols = block.bars.map((b) => b.col).where((c) => c >= 0 && c <= lastCol).toSet().toList()
    ..sort();
  if (barCols.isEmpty) return [_BarSpan(0, lastCol)];

  final out = <_BarSpan>[];
  var start = 0;
  for (final c in barCols) {
    if (c < start) continue; // 同行重复/乱序数据容错
    out.add(_BarSpan(start, c));
    start = c + 1;
  }
  // 末尾没有小节线收尾 → 剩余列构成「无右线小节」
  if (start <= lastCol) out.add(_BarSpan(start, lastCol));
  return out;
}
