import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:echo_hymn/models/hymn.dart';
import 'package:echo_hymn/models/jianpu_grid.dart';
import 'package:echo_hymn/widgets/jianpu_grid_view.dart';

/// 实库（`data/tjc_hymn.db`）——测试工作目录为 `hymn_app/`，故向上找 data/
File? _dbFile() {
  for (final p in ['../data/tjc_hymn.db', 'data/tjc_hymn.db']) {
    final f = File(p);
    if (f.existsSync()) return f;
  }
  return null;
}

/// 从库中构建一首的网格（与 `SqliteRepository.loadJianpuScore` 同口径）
JianpuScore loadScore(Database db, String hymn) {
  final rows = <JianpuRow>[];
  final cells = <int, Map<int, JianpuCell>>{};
  for (final r in db.select(
      'SELECT line_no, col, kind, sym, degree, accidental, dot_len, octave,'
      ' dots, beams, fermata, rowspan, text FROM jianpu_cell'
      ' WHERE hymn_number = ? ORDER BY line_no, col',
      [hymn])) {
    final ln = r['line_no'] as int;
    cells.putIfAbsent(ln, () => {})[r['col'] as int] = JianpuCell(
      col: r['col'] as int,
      kind: cellKindOf(r['kind'] as String),
      sym: r['sym'] as String,
      degree: r['degree'] as int?,
      accidental: r['accidental'] as String?,
      dotLen: r['dot_len'] as int?,
      octave: r['octave'] as int?,
      dots: r['dots'] as int?,
      beams: r['beams'] as int?,
      fermata: r['fermata'] as int?,
      rowspan: r['rowspan'] as int?,
      text: r['text'] as String?,
    );
  }
  var stanzas = 0;
  for (final r in db.select(
      'SELECT stanza_count FROM jianpu_score WHERE hymn_number = ?', [hymn])) {
    stanzas = r['stanza_count'] as int;
  }
  for (final r in db.select(
      'SELECT line_no, block_no, kind, stanza_no, col_count FROM jianpu_row'
      ' WHERE hymn_number = ? ORDER BY line_no',
      [hymn])) {
    rows.add(JianpuRow(
      lineNo: r['line_no'] as int,
      blockNo: r['block_no'] as int,
      kind: rowKindOf(r['kind'] as String),
      colCount: r['col_count'] as int,
      stanzaNo: r['stanza_no'] as int?,
      cells: cells[r['line_no'] as int] ?? const {},
    ));
  }
  return JianpuScore.build(
      hymnNumber: hymn, source: 'test', rows: rows, stanzaCount: stanzas);
}

void main() {
  group('简谱网格模型', () {
    test('行/单元格类型映射', () {
      expect(rowKindOf('note'), JianpuRowKind.note);
      expect(rowKindOf('mark_up'), JianpuRowKind.markUp);
      expect(rowKindOf('mark_down'), JianpuRowKind.markDown);
      expect(rowKindOf('lyric'), JianpuRowKind.lyric);
      expect(rowKindOf('unknown-thing'), JianpuRowKind.blank);
      expect(cellKindOf('barline'), JianpuCellKind.barline);
      expect(cellKindOf('mark'), JianpuCellKind.mark);
      expect(cellKindOf('???'), JianpuCellKind.unknown);
    });

    test('单元格显示文本（音符含变音/附点；记号与小节线不显示）', () {
      const note = JianpuCell(
          col: 0, kind: JianpuCellKind.note, sym: '1', degree: 1, dotLen: 0);
      expect(note.displayText, '1');
      const dotted = JianpuCell(
          col: 0,
          kind: JianpuCellKind.note,
          sym: '3.',
          degree: 3,
          accidental: '#',
          dotLen: 1);
      expect(dotted.displayText, '#3.');
      const rest = JianpuCell(col: 0, kind: JianpuCellKind.rest, sym: '0');
      expect(rest.displayText, '0');
      const dash = JianpuCell(col: 0, kind: JianpuCellKind.dash, sym: '-');
      expect(dash.displayText, '-');
      const mark =
          JianpuCell(col: 0, kind: JianpuCellKind.mark, sym: 'MEN', text: 'E');
      expect(mark.displayText, '');
      const bar = JianpuCell(
          col: 0, kind: JianpuCellKind.barline, sym: 'L6', rowspan: 6);
      expect(bar.displayText, '');
      const syllable =
          JianpuCell(col: 0, kind: JianpuCellKind.text, sym: '普', text: '普');
      expect(syllable.displayText, '普');
    });

    test('分块：K 换表 → 独立块，块宽取块内最大列数；小节线跨行展开', () {
      final rows = [
        const JianpuRow(
            lineNo: 0,
            blockNo: 0,
            kind: JianpuRowKind.markUp,
            colCount: 5,
            cells: {
              1: JianpuCell(
                  col: 1, kind: JianpuCellKind.barline, sym: 'L3', rowspan: 3),
            }),
        const JianpuRow(
            lineNo: 1,
            blockNo: 0,
            kind: JianpuRowKind.note,
            colCount: 5,
            cells: {
              0: JianpuCell(
                  col: 0, kind: JianpuCellKind.note, sym: '1', degree: 1),
            }),
        const JianpuRow(
            lineNo: 2,
            blockNo: 1,
            kind: JianpuRowKind.note,
            colCount: 9,
            cells: {
              7: JianpuCell(
                  col: 7, kind: JianpuCellKind.note, sym: '2', degree: 2),
            }),
      ];
      final score = JianpuScore.build(
          hymnNumber: 'x', source: 't', rows: rows, stanzaCount: 1);
      expect(score.blocks.length, 2);
      expect(score.maxCols, 9);
      expect(score.blocks[0].colCount, 5);
      expect(score.blocks[1].colCount, 9);
      final barCols = score.blocks[0].barColsByLine();
      expect(barCols[0], {1});
      expect(barCols[1], {1});
      expect(barCols[2], {1});
      expect(barCols.containsKey(3), isFalse); // rowspan=3 覆盖 0/1/2 行
    });

    test('空网格判定', () {
      expect(JianpuScore.empty.isEmpty, isTrue);
      expect(
          JianpuScore.build(
                  hymnNumber: 'x', source: 't', rows: const [], stanzaCount: 0)
              .isEmpty,
          isTrue);
    });
  });

  final dbFile = _dbFile();

  group('实库数据：第 9 首「向主欢呼」网格（列 = 拍点）', () {
    late Database db;
    late JianpuScore score;
    setUpAll(() {
      db = sqlite3.open(dbFile!.path);
      score = loadScore(db, '9');
    });
    tearDownAll(() => db.dispose());

    test('结构：30 行 / 25 列 / 2 块，首行为上方记号行', () {
      expect(score.rowCount, 30);
      expect(score.maxCols, 25);
      expect(score.blocks.length, 2);
      expect(score.blocks[0].rows.first.kind, JianpuRowKind.markUp);
      expect(score.stanzaCount, 3);
    });

    test('小节线：第 2/7/12/17 列，跨 6 行（竖线视觉连续）', () {
      final bars = score.blocks[0].bars;
      // 同一块内两个乐句组各有 4 条小节线（第 0 行与第 9 行各起一组，各跨 6 行）
      expect(bars.length, 8);
      expect(bars.map((b) => b.col).toSet(), {2, 7, 12, 17});
      expect(bars.every((b) => b.span == 6), isTrue);
      expect(bars.map((b) => b.startLine).toSet(), {0, 9});
      final byLine = score.blocks[0].barColsByLine();
      expect(byLine[0], {2, 7, 12, 17});
      expect(byLine[5], {2, 7, 12, 17});
      expect(byLine[9], {2, 7, 12, 17});
      expect(byLine[14], {2, 7, 12, 17});
      expect(byLine.containsKey(15), isFalse); // 第 15 行属下一块
    });

    test('延长记号（fermata）：第 0 行第 10/20 列', () {
      final row0 = score.blocks[0].rows[0];
      final marks =
          row0.cells.values.where((c) => (c.fermata ?? 0) > 0).toList();
      expect(marks.map((c) => c.col).toList()..sort(), [10, 20]);
      expect(marks.first.kind, JianpuCellKind.mark);
    });

    test('音符行：16 个音符 + 低八度点派生正确', () {
      final note = score.blocks[0].rows[1];
      expect(note.kind, JianpuRowKind.note);
      final degrees = note.cols.map((c) => note.cells[c]!.degree).toList();
      expect(degrees.join(), '1176512333321432');
      // 第 4/5/6 列的 7/6/5 下一记号行为 MDN → 低八度
      expect(note.cells[4]!.octave, -1);
      expect(note.cells[5]!.octave, -1);
      expect(note.cells[6]!.octave, -1);
      expect(note.cells[1]!.octave, isNull); // 弱起 1 无八度点
    });

    test('**同步不变式**：歌词音节列 == 音符列（列 = 拍点）', () {
      final note = score.blocks[0].rows[1];
      final noteCols = note.cols
          .where((c) => note.cells[c]!.kind == JianpuCellKind.note)
          .toList();
      final lyric = score.blocks[0].rows.firstWhere((r) => r.stanzaNo == 1);
      final sylCols = lyric.cols
          .where((c) => lyric.cells[c]!.kind == JianpuCellKind.text)
          .toList();
      expect(lyric.cells[0]!.kind, JianpuCellKind.stanza);
      expect(lyric.cells[0]!.displayText, '(1)');
      // 末尾标点（！）可超出最后一个音符 → 取前 N 个音节逐列对应
      expect(sylCols.take(noteCols.length).toList(), noteCols);
      expect(lyric.cells[sylCols.first]!.displayText, '普');
      expect(sylCols.length >= noteCols.length, isTrue);
    });
  }, skip: dbFile == null ? '缺 data/tjc_hymn.db' : null);

  group('谱面数据源已切换（旧 PDF 管线表已删除）', () {
    test('hymn_score* / hymn_codepoint_map 不存在；jianpu_* 存在', () {
      final db = sqlite3.open(dbFile!.path);
      final names = db
          .select("SELECT name FROM sqlite_master WHERE type='table'")
          .map((r) => r['name'] as String)
          .toSet();
      db.dispose();
      for (final t in [
        'hymn_score',
        'hymn_score_line',
        'hymn_score_lyric',
        'hymn_score_char',
        'hymn_codepoint_map',
      ]) {
        expect(names.contains(t), isFalse, reason: '$t 应已删除');
      }
      for (final t in ['jianpu_score', 'jianpu_row', 'jianpu_cell']) {
        expect(names.contains(t), isTrue, reason: '$t 应存在');
      }
    });

    test('谱面与库内诗歌编号的对应关系（仅第 349 首为"库外"）', () {
      final db = sqlite3.open(dbFile!.path);
      final orphans = db
          .select('SELECT hymn_number FROM jianpu_score WHERE hymn_number NOT IN '
              '(SELECT hymn_number FROM tjc_hymn)')
          .map((r) => r['hymn_number'] as String)
          .toList();
      final cnt = db.select('SELECT COUNT(*) AS n FROM jianpu_score')
          .first['n'] as int;
      final noScore = db.select(
          'SELECT hymn_number FROM tjc_hymn WHERE hymn_number NOT IN '
          '(SELECT hymn_number FROM jianpu_score)');
      db.dispose();
      // APK 有 474 份 CSV；本库 473 首（第 349 首按用户要求整首移出）
      expect(cnt, 474);
      expect(orphans, ['349']);
      expect(noScore.length, 0);
    });
  }, skip: dbFile == null ? '缺 data/tjc_hymn.db' : null);

  group('渲染：JianpuGridView（列 = 拍点 → 同列必然同一 x）', () {
    testWidgets('第 9 首：弱起音符与首个歌词音节落在同一列（x 相同）',
        (tester) async {
      final db = sqlite3.open(dbFile!.path);
      final score = loadScore(db, '9');
      db.dispose();

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: JianpuGridView(
            score: score,
            constraints: const BoxConstraints(maxWidth: 900, maxHeight: 1800),
          ),
        ),
      ));

      // 渲染成功 + 内容齐全
      expect(find.text('普'), findsOneWidget);
      expect(find.text('(1)'), findsOneWidget);
      expect(find.byType(Text).evaluate().length, greaterThan(200));

      // 「同列 → 同一 x」：弱起音符（第 1 列，最左的音符，印刷字形码位 0x4e52）
      // 与歌词「普」（第 1 列）
      final ones = find.text(String.fromCharCode(0x4e52));
      expect(ones.evaluate().isNotEmpty, isTrue);
      var leftmost = double.infinity;
      for (var i = 0; i < ones.evaluate().length; i++) {
        final dx = tester.getCenter(ones.at(i)).dx;
        if (dx < leftmost) leftmost = dx;
      }
      final pu = tester.getCenter(find.text('普')).dx;
      expect((leftmost - pu).abs() < 0.6, isTrue,
          reason: '弱起音符 x=$leftmost 与歌词「普」x=$pu 应同列');

      // 小节线由自绘容器绘制：块内 8 条（2 组 × 4 列）
      expect(score.blocks.first.bars.length, 8);
    });

    testWidgets('按节显示：只保留该节歌词行（谱行不随节变化）', (tester) async {
      final db = sqlite3.open(dbFile!.path);
      final score = loadScore(db, '9');
      db.dispose();
      expect(score.stanzaCount, 3);

      Future<void> pump(int? stanza) async {
        await tester.pumpWidget(MaterialApp(
          theme: ThemeData(useMaterial3: true, fontFamily: 'EchoSans'),
          home: Scaffold(
            body: JianpuGridView(
              score: score,
              constraints:
                  const BoxConstraints(maxWidth: 900, maxHeight: 1800),
              stanza: stanza,
            ),
          ),
        ));
      }

      // 整页：三节歌词行都在（每块各 1 行/节）；节号标签只在第 1 块给出（同印刷本）
      for (final s in [1, 2, 3]) {
        final n = score.blocks
            .expand((b) => b.rows)
            .where((r) => r.kind == JianpuRowKind.lyric && r.stanzaNo == s)
            .length;
        expect(n, score.blocks.length, reason: '每块各有第 $s 节歌词行');
      }
      int labels(int s) => score.blocks
          .expand((b) => b.rows)
          .where((r) =>
              r.kind == JianpuRowKind.lyric &&
              r.stanzaNo == s &&
              r.cells[0]?.kind == JianpuCellKind.stanza)
          .length;

      await pump(null);
      for (final s in [1, 2, 3]) {
        expect(find.text('($s)'), findsNWidgets(labels(s)));
      }
      final allText = find.byType(Text).evaluate().length;

      // 第 2 节：只剩第 2 节歌词行（其余节的音节与标签都不在树上）
      await pump(2);
      expect(find.text('(2)'), findsNWidgets(labels(2)));
      expect(find.text('(1)'), findsNothing);
      expect(find.text('(3)'), findsNothing);
      // 谱行不随节变化（音符字形仍在），但总文本量变少
      expect(find.text(String.fromCharCode(0x4e52)).evaluate().isNotEmpty, isTrue);
      expect(find.byType(Text).evaluate().length, lessThan(allText));
    });
  });

  group('自动翻页与字号上限（歌词模式按节翻页）', () {
    test('4 分钟 4 节 → 每分钟切一节', () {
      const total = 240.0;
      expect(
          autoPageIndexFor(
              position: Duration.zero, totalSeconds: total, pageCount: 4),
          0);
      expect(
          autoPageIndexFor(
              position: const Duration(seconds: 61),
              totalSeconds: total,
              pageCount: 4),
          1);
      expect(
          autoPageIndexFor(
              position: const Duration(seconds: 181),
              totalSeconds: total,
              pageCount: 4),
          3);
    });

    test('进度超出总时长 → 钳在最后一页', () {
      expect(
          autoPageIndexFor(
              position: const Duration(seconds: 999),
              totalSeconds: 100,
              pageCount: 3),
          2);
    });

    test('单节 / 无时长 → 恒第 0 页（不翻页）', () {
      expect(
          autoPageIndexFor(
              position: const Duration(seconds: 50),
              totalSeconds: 0,
              pageCount: 3),
          0);
      expect(
          autoPageIndexFor(
              position: const Duration(seconds: 50),
              totalSeconds: 100,
              pageCount: 1),
          0);
    });

    test('字号上限：高度按行数换算 / 宽度保证不换行', () {
      expect(lyricMaxFontByHeight(400, 4), 50);
      expect(lyricMaxFontByHeight(400, 0), 40);
      expect(lyricMaxFontByWidth(800, 40), closeTo(38.8, 0.01));
      expect(lyricMaxFontByWidth(800, 0), 40);
    });
  });
}
