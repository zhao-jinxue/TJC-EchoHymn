import 'package:flutter_test/flutter_test.dart';

import 'package:echo_hymn/models/jianpu_grid.dart';
import 'package:echo_hymn/models/jianpu_pagination.dart';

/// 构造一个乐句块（1 行音符 + 给定小节线列）
JianpuBlock _block({
  required int blockNo,
  required int colCount,
  required List<int> barCols,
}) {
  return JianpuBlock(
    blockNo: blockNo,
    rows: [
      JianpuRow(
        lineNo: blockNo * 10,
        blockNo: blockNo,
        kind: JianpuRowKind.note,
        colCount: colCount,
        cells: const {},
      ),
    ],
    colCount: colCount,
    bars: [
      for (final c in barCols) JianpuBarSpan(c, blockNo * 10, 1),
    ],
  );
}

JianpuScore _score(List<JianpuBlock> blocks) => JianpuScore(
      hymnNumber: 'test',
      source: 'unit',
      blocks: blocks,
      stanzaCount: 1,
    );

void main() {
  group('小节划分', () {
    test('按小节线切：4 个小节（每个小节含右小节线列）', () {
      final score = _score([
        _block(blockNo: 1, colCount: 20, barCols: [4, 9, 14, 19]),
      ]);
      final pg = JianpuPagination.build(score, barsPerPage: 4);
      expect(pg.barCount, 4);
      expect(pg.pageCount, 1);
      expect(pg.pages.single.startCol, 0);
      expect(pg.pages.single.endCol, 19);
      expect(pg.pages.single.barCount, 4);
      expect(pg.pages.single.firstBar, 1);
      expect(pg.pages.single.lastBar, 4);
    });

    test('末尾无小节课 → 额外构成一个「无右线小节」', () {
      final score = _score([
        _block(blockNo: 1, colCount: 13, barCols: [4, 9]),
      ]);
      final pg = JianpuPagination.build(score, barsPerPage: 2);
      expect(pg.barCount, 3);
      expect(pg.pageCount, 2);
      // 第 2 页 = 无右线小节（列 10~12）
      expect(pg.pages.last.startCol, 10);
      expect(pg.pages.last.endCol, 12);
      expect(pg.pages.last.firstBar, 3);
      expect(pg.pages.last.lastBar, 3);
    });

    test('块内无小节线 → 整块视为 1 个小节', () {
      final score = _score([
        _block(blockNo: 1, colCount: 7, barCols: []),
      ]);
      final pg = JianpuPagination.build(score, barsPerPage: 2);
      expect(pg.barCount, 1);
      expect(pg.pageCount, 1);
      expect(pg.pages.single.startCol, 0);
      expect(pg.pages.single.endCol, 6);
    });
  });

  group('页切分（每页小节数）', () {
    final score = _score([
      _block(blockNo: 1, colCount: 20, barCols: [4, 9, 14, 19]),
    ]);

    test('每页 2 小节 → 2 页，列范围连续不重叠', () {
      final pg = JianpuPagination.build(score, barsPerPage: 2);
      expect(pg.pageCount, 2);
      expect([for (final p in pg.pages) p.startCol], [0, 10]);
      expect([for (final p in pg.pages) p.endCol], [9, 19]);
      expect([for (final p in pg.pages) p.firstBar], [1, 3]);
      expect([for (final p in pg.pages) p.lastBar], [2, 4]);
      for (var i = 1; i < pg.pages.length; i++) {
        expect(pg.pages[i].startCol, pg.pages[i - 1].endCol + 1);
      }
    });

    test('每页 3 小节 → 2 页（3 + 1，末页不足也成页）', () {
      final pg = JianpuPagination.build(score, barsPerPage: 3);
      expect(pg.pageCount, 2);
      expect(pg.pages.first.barCount, 3);
      expect(pg.pages.last.barCount, 1);
      expect(pg.pages.last.startCol, 15);
      expect(pg.pages.last.endCol, 19);
    });

    test('每页 4 小节 → 1 页', () {
      final pg = JianpuPagination.build(score, barsPerPage: 4);
      expect(pg.pageCount, 1);
      expect(pg.barsPerPage, 4);
    });

    test('非法每页小节数按 1~8 钳制', () {
      expect(JianpuPagination.build(score, barsPerPage: 0).barsPerPage, 1);
      expect(JianpuPagination.build(score, barsPerPage: 99).barsPerPage, 8);
    });
  });

  group('多块：页数 = 各块页数之和', () {
    test('块 1 四小节 + 块 2 两小节，每页 3 小节 → 2 + 1 = 3 页', () {
      final score = _score([
        _block(blockNo: 1, colCount: 20, barCols: [4, 9, 14, 19]),
        _block(blockNo: 2, colCount: 10, barCols: [4, 9]),
      ]);
      final pg = JianpuPagination.build(score, barsPerPage: 3);
      expect(pg.barCount, 6);
      expect(pg.pageCount, 3);
      expect(pg.pagesInBlock(1), 2);
      expect(pg.pagesInBlock(2), 1);
      // 块之间不拼页：块 2 的第 1 页自成一页
      expect(pg.pages[2].blockNo, 2);
      expect(pg.pages[2].firstBar, 5);
      expect(pg.pages[2].lastBar, 6);
      // 全曲小节序号连续
      expect([for (final p in pg.pages) p.firstBar], [1, 4, 5]);
    });

    test('空谱面 → 0 页 / 0 小节', () {
      final pg = JianpuPagination.build(JianpuScore.empty);
      expect(pg.pageCount, 0);
      expect(pg.barCount, 0);
      expect(pg.isEmpty, isTrue);
    });
  });

  group('自适应每页小节数（2~4）', () {
    final score = _score([
      _block(blockNo: 1, colCount: 20, barCols: [4, 9, 14, 19]),
    ]);
    // 每小节平均 5 列；列宽 10
    test('窄屏（只能容 6 列）→ 2 小节/页', () {
      expect(
        JianpuPagination.autoBarsPerPage(
            score: score, availableWidth: 60, colWidth: 10),
        2,
      );
    });

    test('宽屏（能容 20 列）→ 4 小节/页', () {
      expect(
        JianpuPagination.autoBarsPerPage(
            score: score, availableWidth: 200, colWidth: 10),
        4,
      );
    });

    test('非法尺寸 → 回退 2', () {
      expect(
        JianpuPagination.autoBarsPerPage(
            score: score, availableWidth: 0, colWidth: 10),
        2,
      );
      expect(
        JianpuPagination.autoBarsPerPage(
            score: score, availableWidth: 100, colWidth: 0),
        2,
      );
    });
  });

  group('性能（验收：切页 ≤16ms）', () {
    test('24 块 × 8 小节 / 每页 2 小节 = 96 页，单次 ≤16ms', () {
      final blocks = [
        for (var b = 1; b <= 24; b++)
          _block(
            blockNo: b,
            colCount: 40,
            barCols: [for (var i = 1; i <= 8; i++) i * 5 - 1],
          ),
      ];
      final score = _score(blocks);
      final sw = Stopwatch()..start();
      final pg = JianpuPagination.build(score, barsPerPage: 2);
      sw.stop();
      expect(pg.barCount, 24 * 8);
      expect(pg.pageCount, 24 * 4);
      expect(sw.elapsedMicroseconds / 1000.0, lessThanOrEqualTo(16.0));
      expect(pg.elapsedMs, lessThanOrEqualTo(16.0));
    });
  });
}
