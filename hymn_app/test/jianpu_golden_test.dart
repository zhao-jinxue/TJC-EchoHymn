import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:echo_hymn/models/jianpu_grid.dart';
import 'package:echo_hymn/widgets/jianpu_grid_view.dart';

/// 生成「第 9 首简谱网格」的渲染快照（PNG）供人工核对版式：
///   cd hymn_app && flutter test --update-goldens test/jianpu_golden_test.dart
/// 产出：`test/goldens/jianpu_009.png`
///
/// 说明：flutter_test 默认字体是"方块测试字体"，故这里显式加载内置字体
/// （EchoJianpu 数字 / EchoKai 歌词 / EchoSans 界面），使快照与实机观感一致。
JianpuScore _loadScore(Database db, String hymn, {bool firstVoiceOnly = false}) {
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
      hymnNumber: hymn,
      source: 'golden',
      rows: rows,
      stanzaCount: stanzas,
      firstVoiceOnly: firstVoiceOnly);
}

void main() {
  setUpAll(() async {
    const fonts = {
      'EchoJianpu': 'assets/fonts/jianpu_mmp2005.ttf',
      'EchoKai': 'assets/fonts/lyric_kai.ttf',
      'EchoSans': 'assets/fonts/NotoSansSC-Regular.ttf',
    };
    for (final e in fonts.entries) {
      final f = File(e.value);
      if (!f.existsSync()) continue;
      final data = ByteData.view(Uint8List.fromList(f.readAsBytesSync()).buffer);
      await (FontLoader(e.key)..addFont(Future.value(data))).load();
    }
  });

  testWidgets('第 9 首「向主欢呼」简谱网格渲染快照', (tester) async {
    tester.view.physicalSize = const Size(1040, 1500);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final db = sqlite3.open('../data/tjc_hymn.db');
    final score = _loadScore(db, '9');
    db.dispose();

    await tester.pumpWidget(MaterialApp(
      // 与 App 一致：全局字体 EchoSans（lib/app.dart 的 ThemeData.fontFamily）
      theme: ThemeData(useMaterial3: true, fontFamily: 'EchoSans'),
      home: Scaffold(
        backgroundColor: const Color(0xFFF2F6FD), // 晨光蓝 lyricsBg
        body: JianpuGridView(
          score: score,
          constraints: const BoxConstraints(maxWidth: 1040, maxHeight: 1500),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(JianpuGridView),
      matchesGoldenFile('goldens/jianpu_009.png'),
    );
  });

  testWidgets('第 9 首「曲谱 = 一页一节 · 单声部」渲染快照', (tester) async {
    tester.view.physicalSize = const Size(1040, 1120);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final db = sqlite3.open('../data/tjc_hymn.db');
    final score = _loadScore(db, '9', firstVoiceOnly: true);
    db.dispose();

    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(useMaterial3: true, fontFamily: 'EchoSans'),
      home: Scaffold(
        backgroundColor: const Color(0xFFF2F6FD),
        body: JianpuGridView(
          score: score,
          constraints: const BoxConstraints(maxWidth: 1040, maxHeight: 1120),
          stanza: 2,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(JianpuGridView),
      matchesGoldenFile('goldens/jianpu_009_stanza2.png'),
    );
  });

  testWidgets('第 163 首（源数据块内行宽差异）按块宽渲染快照', (tester) async {
    tester.view.physicalSize = const Size(1040, 1500);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final db = sqlite3.open('../data/tjc_hymn.db');
    final score = _loadScore(db, '163');
    db.dispose();
    // 源数据事实：该首存在**块内**行宽不一致（20 / 37）→ 块宽取块内最大行宽
    expect(
        score.blocks
            .any((b) => b.rows.map((r) => r.colCount).toSet().length > 1),
        isTrue);

    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(useMaterial3: true, fontFamily: 'EchoSans'),
      home: Scaffold(
        backgroundColor: const Color(0xFFF2F6FD),
        body: JianpuGridView(
          score: score,
          constraints: const BoxConstraints(maxWidth: 1040, maxHeight: 1500),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(JianpuGridView),
      matchesGoldenFile('goldens/jianpu_163.png'),
    );
  });

  testWidgets('第 283 首《为主收庄稼》第 3 节：副歌块必须有词（2026-10-12 修复）',
      (tester) async {
    tester.view.physicalSize = const Size(1040, 1120);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final db = sqlite3.open('../data/tjc_hymn.db');
    final score = _loadScore(db, '283', firstVoiceOnly: true);
    db.dispose();
    // 数据事实：4 个块 = 正歌 2 块（各 3 行词）+ 副歌 2 块（各 1 行词，各节共用）
    expect(score.stanzaCount, 3);
    expect(score.blocks.map((b) => b.lyricCount).toList(), [3, 3, 1, 1]);

    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(useMaterial3: true, fontFamily: 'EchoSans'),
      home: Scaffold(
        backgroundColor: const Color(0xFFF2F6FD),
        body: JianpuGridView(
          score: score,
          constraints: const BoxConstraints(maxWidth: 1040, maxHeight: 1120),
          stanza: 3,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(JianpuGridView),
      matchesGoldenFile('goldens/jianpu_283_stanza3.png'),
    );
  });

  testWidgets('第 20 首《尊主为王》第 1 节：行距 / 字号版式快照（2026-10-13）',
      (tester) async {
    // 窗口按实机常用宽（1920）取，槽宽 ≈ 65 px，与用户实机截图同口径
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final db = sqlite3.open('../data/tjc_hymn.db');
    final score = _loadScore(db, '20', firstVoiceOnly: true);
    db.dispose();
    // 数据事实：4 块 = 正歌 3 块（各 3 节歌词）+ 末块 3 节 + 第 4 节歌词在末块；
    // 每块「音符行 + 下方记号行 + 歌词行」→ 单声部每块 1 行音符、1 行词
    expect(score.stanzaCount, 3);
    expect(
        score.blocks
            .map((b) => b.rows.where((r) => r.kind == JianpuRowKind.note).length)
            .toList(),
        everyElement(1));

    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(useMaterial3: true, fontFamily: 'EchoSans'),
      home: Scaffold(
        backgroundColor: const Color(0xFFF2F6FD),
        body: JianpuGridView(
          score: score,
          constraints: const BoxConstraints(maxWidth: 1920, maxHeight: 1080),
          stanza: 1,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(JianpuGridView),
      matchesGoldenFile('goldens/jianpu_020_stanza1.png'),
    );
  });

  testWidgets('第 1 首《颂赞独一真神》第 1 节：歌词上下各只有一行简谱（2026-10-13 修复）',
      (tester) async {
    tester.view.physicalSize = const Size(1040, 1120);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final db = sqlite3.open('../data/tjc_hymn.db');
    final score = _loadScore(db, '1', firstVoiceOnly: true);
    db.dispose();
    // 数据事实：该首每块 = S,A 在歌词上方 + T,B 在下方（4 声部）
    // → 单声部形态每块只应剩 1 个音符行
    final notes = score.blocks
        .map((b) => b.rows.where((r) => r.kind == JianpuRowKind.note).length)
        .toList();
    expect(notes, everyElement(1), reason: '每块只保留第一声部（S）一行音符');

    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(useMaterial3: true, fontFamily: 'EchoSans'),
      home: Scaffold(
        backgroundColor: const Color(0xFFF2F6FD),
        body: JianpuGridView(
          score: score,
          constraints: const BoxConstraints(maxWidth: 1040, maxHeight: 1120),
          stanza: 1,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(JianpuGridView),
      matchesGoldenFile('goldens/jianpu_001_stanza1.png'),
    );
  });
}
