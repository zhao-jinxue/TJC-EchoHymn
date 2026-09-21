import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';

import '../models/hymn.dart';
import '../models/hymn_category.dart';
import '../models/hymn_score.dart';
import '../models/playlist.dart';
import 'app_paths.dart';
import 'log_service.dart';

/// SQLite 数据仓库：tjc_hymn / hymn_category / playlist_hymn（个人歌单单表）
class SqliteRepository {
  final Database _db;

  /// 核心表（tjc_hymn / hymn_category）是否存在。
  ///
  /// 数据库文件缺失/被删除后由 sqlite3.open 重建的空库没有这些表；
  /// 此时各查询方法返回空列表（UI 显示空态），而不是抛异常导致初始化失败
  /// （UI 测试 K12/K13：删库后应显示「暂无分类/暂无诗歌」空态）。
  final bool hasCoreTables;

  SqliteRepository._(this._db) : hasCoreTables = _probeCoreTables(_db);

  static bool _probeCoreTables(Database db) {
    try {
      final rows = db.select(
          "SELECT name FROM sqlite_master WHERE type='table' AND name IN ('tjc_hymn','hymn_category')");
      return rows.length == 2;
    } catch (_) {
      return false;
    }
  }

  /// 打开数据库并确保个人歌单表存在（含旧双表结构自动迁移）
  static Future<SqliteRepository> open() async {
    await AppPaths.init();
    final path = AppPaths.databasePath ?? '';
    final db = sqlite3.open(path);
    LogService.instance.info(LogTag.lib, '打开 SQLite 数据库', detail: path);
    final repo = SqliteRepository._(db);
    repo._ensurePlaylistTable();
    // 统计已加载数据量
    try {
      final hymnCount =
          db.select('SELECT COUNT(*) AS c FROM tjc_hymn').first['c'];
      final catCount =
          db.select('SELECT COUNT(*) AS c FROM hymn_category').first['c'];
      final plCount =
          db.select('SELECT COUNT(*) AS c FROM playlist_hymn').first['c'];
      LogService.instance.info(
        LogTag.lib,
        '数据库数据加载完成',
        detail: '诗歌 $hymnCount 首 / 分类 $catCount 条 / 个人歌单 $plCount 个',
      );
    } catch (e) {
      LogService.instance.warning(LogTag.lib, '数据库统计失败', detail: '$e');
    }
    return repo;
  }

  /// 确保个人歌单表（playlist_hymn）存在
  ///
  /// v1.0.3 起由「playlist + playlist_hymn 双表」重构为「单表 playlist_hymn」，
  /// 字段：id / name / hymns(JSON) / created_at / updated_at，
  /// 与 hymn_category.hymns 的 JSON 格式一致（[{标题: 编号}]）。
  ///
  /// 若检测到旧双表结构，自动将其数据合并迁移后删除旧表。
  void _ensurePlaylistTable() {
    const newTableSql = '''
      CREATE TABLE IF NOT EXISTS playlist_hymn (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        hymns TEXT NOT NULL DEFAULT '[]',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''';

    final hasOldPlaylist = _tableExists('playlist');
    final hasPlaylistHymn = _tableExists('playlist_hymn');

    // 检测现有 playlist_hymn 是否为新结构（含 hymns 列）
    final currentIsNew =
        hasPlaylistHymn && _tableHasColumn('playlist_hymn', 'hymns');

    if (hasOldPlaylist && hasPlaylistHymn && !currentIsNew) {
      // 旧双表结构：将旧 playlist_hymn 改名备份，再建新表
      _db.execute('DROP TABLE IF EXISTS playlist_hymn_old');
      _db.execute('ALTER TABLE playlist_hymn RENAME TO playlist_hymn_old');
      _db.execute(newTableSql);
      _migrateFromOldTwoTables();
    } else if (hasOldPlaylist && !hasPlaylistHymn) {
      // 只有旧 playlist 表（playlist_hymn 缺失）：直接建新表并迁移
      _db.execute(newTableSql);
      _migrateFromOldTwoTables();
    } else if (!hasPlaylistHymn) {
      // 全新环境
      _db.execute(newTableSql);
    } else if (hasOldPlaylist && currentIsNew) {
      // 新表已存在且旧表残留：仅清理旧表（罕见的中断场景）
      _db.execute('DROP TABLE IF EXISTS playlist');
      _db.execute('DROP TABLE IF EXISTS playlist_hymn_old');
    }
    // 其余情况（已是新表，无旧表）：无需处理
  }

  bool _tableExists(String name) {
    final rows = _db.select(
        "SELECT name FROM sqlite_master WHERE type='table' AND name = ?",
        [name]);
    return rows.isNotEmpty;
  }

  bool _tableHasColumn(String table, String column) {
    // 注意：PRAGMA 的 $table 由 Dart 字符串插值填充（表名来自内部常量，安全）
    final info = _db.select('PRAGMA table_info($table)');
    return info.any((r) => (r['name'] as String?) == column);
  }

  /// 旧双表（playlist + playlist_hymn_old）→ 新单表（playlist_hymn）迁移
  void _migrateFromOldTwoTables() {
    // 读取旧 playlist 歌单
    final oldRows = _db
        .select('SELECT * FROM playlist ORDER BY id')
        .toList(growable: false);

    for (final row in oldRows) {
      final id = (row['id'] as int?) ?? 0;
      final name = (row['name'] as String?) ?? '';
      final createdAt = (row['created_at'] as String?) ?? '';

      // 读取该歌单的成员（旧表：playlist_hymn_old，playlist_id → hymn_id/name/sort_order）
      final items = _db.select(
        'SELECT * FROM playlist_hymn_old WHERE playlist_id = ? ORDER BY sort_order',
        [id],
      ).toList(growable: false);
      final hymnList = <Map<String, Object>>[];
      for (final it in items) {
        final hymnId = (it['hymn_id'] as int?) ?? 0;
        final itemName = (it['name'] as String?) ?? '';
        if (hymnId > 0) {
          hymnList.add({itemName: hymnId});
        }
      }

      _db.execute(
        'INSERT OR REPLACE INTO playlist_hymn (id, name, hymns, created_at, updated_at) VALUES (?, ?, ?, ?, ?)',
        [id, name, jsonEncode(hymnList), createdAt, createdAt],
      );
    }

    // 删除旧表
    _db.execute('DROP TABLE IF EXISTS playlist');
    _db.execute('DROP TABLE IF EXISTS playlist_hymn_old');
  }

  // ---------- 诗歌 ----------

  /// 按编号排序的全部诗歌
  List<Hymn> getAllHymns() {
    if (!hasCoreTables) return const [];
    final rows = _db.select(
        'SELECT * FROM tjc_hymn ORDER BY CAST(hymn_number AS INTEGER), hymn_number');
    return rows.map((r) => Hymn.fromDbRow(_rowToMap(r))).toList();
  }

  /// 按编号或标题搜索（不含作者/作曲，按需求限定范围）
  List<Hymn> searchHymns(String keyword) {
    if (!hasCoreTables) return const [];
    final kw = keyword.trim();
    if (kw.isEmpty) return getAllHymns();
    final like = '%$kw%';
    // 数字 → 优先匹配编号；其余仅匹配标题
    final isNum = int.tryParse(kw) != null;
    if (isNum) {
      final rows = _db.select(
        'SELECT * FROM tjc_hymn WHERE hymn_number = ? OR hymn_number LIKE ? ORDER BY CAST(hymn_number AS INTEGER)',
        [kw, '$kw%'],
      );
      return rows.map((r) => Hymn.fromDbRow(_rowToMap(r))).toList();
    }
    final rows = _db.select(
      'SELECT * FROM tjc_hymn WHERE title LIKE ? ORDER BY CAST(hymn_number AS INTEGER)',
      [like],
    );
    return rows.map((r) => Hymn.fromDbRow(_rowToMap(r))).toList();
  }

  /// 分页加载诗歌列表
  List<Hymn> getHymnsPage(int offset, int limit) {
    if (!hasCoreTables) return const [];
    final rows = _db.select(
      'SELECT * FROM tjc_hymn ORDER BY CAST(hymn_number AS INTEGER) LIMIT ? OFFSET ?',
      [limit, offset],
    );
    return rows.map((r) => Hymn.fromDbRow(_rowToMap(r))).toList();
  }

  Hymn? hymnByNumber(String number) {
    if (!hasCoreTables) return null;
    final rows = _db.select(
      'SELECT * FROM tjc_hymn WHERE hymn_number = ? LIMIT 1',
      [number],
    );
    if (rows.isEmpty) return null;
    return Hymn.fromDbRow(_rowToMap(rows.first));
  }

  Hymn? hymnById(int id) {
    if (!hasCoreTables) return null;
    final rows = _db.select(
      'SELECT * FROM tjc_hymn WHERE id = ? LIMIT 1',
      [id],
    );
    if (rows.isEmpty) return null;
    return Hymn.fromDbRow(_rowToMap(rows.first));
  }

  // ---------- 分类 ----------

  /// 全部分类（默认歌单目录）
  List<HymnCategory> getAllCategories() {
    if (!hasCoreTables) return const [];
    final rows = _db.select('SELECT * FROM hymn_category ORDER BY id');
    return rows.map((r) => HymnCategory.fromDbRow(_rowToMap(r))).toList();
  }

  /// 构建分级目录：category → [subcategory → hymns]
  Map<String, List<HymnCategory>> buildCategoryTree() {
    final map = <String, List<HymnCategory>>{};
    for (final c in getAllCategories()) {
      map.putIfAbsent(c.category, () => []).add(c);
    }
    return map;
  }

  // ---------- 个人歌单（单表 playlist_hymn） ----------

  /// 全部个人歌单（按 id 排序）
  List<Playlist> getPlaylists() {
    final rows = _db.select('SELECT * FROM playlist_hymn ORDER BY id');
    return rows.map((r) => Playlist.fromDbRow(_rowToMap(r))).toList();
  }

  Playlist? getPlaylistById(int id) {
    final rows =
        _db.select('SELECT * FROM playlist_hymn WHERE id = ? LIMIT 1', [id]);
    if (rows.isEmpty) return null;
    return Playlist.fromDbRow(_rowToMap(rows.first));
  }

  /// 创建歌单（名称+成员**单次 INSERT 原子落库**，杜绝"先建空表再补成员"
  /// 双写中断留下半创建歌单的中间态），返回新 id
  int createPlaylist(String name, [List<MapEntry<String, int>> hymns = const []]) {
    final now = DateTime.now().toIso8601String();
    final json = Playlist.hymnsToJson(hymns);
    _db.execute(
      'INSERT INTO playlist_hymn (name, hymns, created_at, updated_at) VALUES (?, ?, ?, ?)',
      [name, json, now, now],
    );
    final id = _db.lastInsertRowId;
    LogService.instance.info(
      LogTag.playlist,
      '创建个人歌单',
      detail: '歌单ID: $id\n歌单名称: $name\n诗歌数量: ${hymns.length}\n成员明细: $json\n创建时间: $now',
    );
    return id;
  }

  /// 更新歌单（名称 + 诗歌列表 + 更新时间）
  void updatePlaylist(
    int id,
    String name,
    List<MapEntry<String, int>> hymns,
  ) {
    final now = DateTime.now().toIso8601String();
    final json = Playlist.hymnsToJson(hymns);
    _db.execute(
      'UPDATE playlist_hymn SET name = ?, hymns = ?, updated_at = ? WHERE id = ?',
      [name, json, now, id],
    );
    LogService.instance.info(
      LogTag.playlist,
      '修改个人歌单',
      detail: '歌单ID: $id\n歌单名称: $name\n诗歌数量: ${hymns.length}\n'
          '成员明细: $json\n更新时间: $now',
    );
  }

  /// 重命名歌单（保留成员）
  void renamePlaylist(int id, String newName) {
    final now = DateTime.now().toIso8601String();
    _db.execute(
      'UPDATE playlist_hymn SET name = ?, updated_at = ? WHERE id = ?',
      [newName, now, id],
    );
    LogService.instance.info(
      LogTag.playlist,
      '重命名个人歌单',
      detail: '歌单ID: $id\n新名称: $newName\n更新时间: $now',
    );
  }

  /// 删除歌单
  void deletePlaylist(int id) {
    final before = getPlaylistById(id);
    _db.execute('DELETE FROM playlist_hymn WHERE id = ?', [id]);
    LogService.instance.info(
      LogTag.playlist,
      '删除个人歌单',
      detail: before == null
          ? '歌单ID: $id（删除前未能读取到歌单信息）'
          : '歌单ID: $id\n歌单名称: ${before.name}\n'
              '诗歌数量: ${before.hymns.length}\n成员明细: ${Playlist.hymnsToJson(before.hymns)}',
    );
  }

  // ---------- 工具 ----------

  /// sqlite3 的 Row 即实现 Map<String, Object?>，此处仅在需要时转为普通 Map
  Map<String, Object?> _rowToMap(Row row) => Map<String, Object?>.from(row);

  // ---------- 简谱曲谱（hymn_score_* 表，任务 2「曲谱+歌词同步」显示用） ----------

  /// 曲谱三表是否存在（老数据库可能没有 v9 表）
  bool get hasScoreTables {
    if (_scoreTablesChecked) return _hasScoreTables;
    _scoreTablesChecked = true;
    try {
      final rows = _db.select(
          "SELECT name FROM sqlite_master WHERE type='table' AND name IN "
          "('hymn_score_line','hymn_score_lyric','hymn_score_char')");
      _hasScoreTables = rows.length == 3;
    } catch (_) {
      _hasScoreTables = false;
    }
    return _hasScoreTables;
  }

  bool _scoreTablesChecked = false;
  bool _hasScoreTables = false;

  /// 库内码位映射（`hymn_codepoint_map`，全量加载一次缓存；优先于 Dart 侧种子）
  Map<String, String> codepointMap() {
    if (_codepointMap != null) return _codepointMap!;
    final out = <String, String>{};
    try {
      for (final r in _db.select('SELECT codepoint, sym FROM hymn_codepoint_map')) {
        final cp = (r['codepoint'] as String?) ?? '';
        final sym = (r['sym'] as String?) ?? '';
        if (cp.isNotEmpty && sym.isNotEmpty) out[cp] = sym;
      }
    } catch (_) {}
    _codepointMap = out;
    return out;
  }

  Map<String, String>? _codepointMap;

  /// 装载某首歌的曲谱分页（每节一页；副歌行每页重复）
  ///
  /// [chorus] 传 `tjc_hymn.chorus` 原文，用于副歌行判定（与爬虫侧
  /// `show_score.chorus_line_nos` 同判据：只有第 1 节 **且** 与官网副歌某行吻合，
  /// 双重判据避免把「其他节词缺失」的行误判为副歌）。
  List<ScorePage> loadScorePages(String hymnNumber, {String chorus = ''}) {
    if (!hasScoreTables) return const [];
    final map = codepointMap();

    // 逐字对位（按行分组，char_no 升序 = 字序）
    final charsByLine = <int, List<ScoreChar>>{};
    for (final r in _db.select(
        'SELECT line_no, char_no, syllable, note_index FROM hymn_score_char '
        'WHERE hymn_number = ? ORDER BY line_no, char_no',
        [hymnNumber])) {
      final ln = (r['line_no'] as int?) ?? 0;
      charsByLine
          .putIfAbsent(ln, () => [])
          .add(ScoreChar((r['char_no'] as int?) ?? 0,
              (r['syllable'] as String?) ?? '', (r['note_index'] as int?) ?? -1));
    }

    // 各节歌词（行 → 节 → 文本）
    final lyricsByLine = <int, Map<int, String>>{};
    for (final r in _db.select(
        'SELECT line_no, stanza_no, text FROM hymn_score_lyric '
        'WHERE hymn_number = ? ORDER BY line_no, stanza_no',
        [hymnNumber])) {
      final ln = (r['line_no'] as int?) ?? 0;
      lyricsByLine
          .putIfAbsent(ln, () => {})[(r['stanza_no'] as int?) ?? 1] =
          (r['text'] as String?) ?? '';
    }

    final chorusLines = _chorusLineNos(lyricsByLine, chorus);

    final rows = _db.select(
        'SELECT line_no, phrase_no, notes, code_seq FROM hymn_score_line '
        'WHERE hymn_number = ? AND is_primary = 1 ORDER BY line_no',
        [hymnNumber]);
    final lines = <ScoreLineRow>[];
    for (final r in rows) {
      final ln = (r['line_no'] as int?) ?? 0;
      final codeSeq = (r['code_seq'] as String?) ?? '';
      final notes = (r['notes'] as String?) ?? '';
      var elements = decodeScoreElements(codeSeq, map);
      // 旧数据无 code_seq 时退化为逐字符（与爬虫侧 decode_elements 同兜底）
      if (elements.isEmpty) elements = notes.split('');
      final lyrics = lyricsByLine[ln];
      if (lyrics == null || lyrics.isEmpty) continue; // 无词乐句（间奏）不占页
      lines.add(ScoreLineRow(
        lineNo: ln,
        phraseNo: (r['phrase_no'] as int?) ?? 0,
        elements: elements,
        chars: charsByLine[ln] ?? const [],
        lyrics: lyrics,
        isChorus: chorusLines.contains(ln),
      ));
    }
    return buildScorePages(lines: lines);
  }

  // ---------- PPT 官方编码曲谱（hymn_ppt / hymn_ppt_line，任务 6） ----------
  //
  // 编码数据（`score_enc` 原始简谱编码串 + `lyric` 歌词原串，475 首/3032 页/12674 行）
  // 与两款字体（简谱字体/標楷體）已入库与留档，供后续「字形专项」使用；
  // 当前「曲谱」视图的对位真值仍取 PDF 管线（`hymn_score_char.note_index`），
  // 因其与印刷 PDF 逐字一致（PPT 编码的行内空格基准与 PDF 音符位置不属同源，
  // 2026-09-21 全库比对确认无法简单映射）。

  /// 副歌行号集合（判据同爬虫侧 `show_score.chorus_line_nos`）
  static Set<int> _chorusLineNos(Map<int, Map<int, String>> lyricsByLine, String chorus) {
    if (chorus.trim().isEmpty) return const {};
    final targets = <String>{
      for (final ln in chorus.split('\n')) _normText(ln),
    }..remove('');
    if (targets.isEmpty) return const {};
    final out = <int>{};
    lyricsByLine.forEach((ln, stanzas) {
      if (stanzas.length != 1 || !stanzas.containsKey(1)) return;
      final t = _normText(stanzas[1]!);
      if (t.isEmpty) return;
      for (final c in targets) {
        if (t == c || (t.length >= 6 && (t.contains(c) || c.contains(t)))) {
          out.add(ln);
          break;
        }
      }
    });
    return out;
  }

  /// 归一化：只留字母/数字（去标点与空白），供副歌逐行比对
  static String _normText(String s) =>
      s.replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '');

  void dispose() {
    _db.dispose();
  }
}
