import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';

import '../models/hymn.dart';
import '../models/hymn_category.dart';
import '../models/playlist.dart';
import 'app_paths.dart';
import 'log_service.dart';

/// SQLite 数据仓库：tjc_hymn / hymn_category / playlist_hymn（个人歌单单表）
class SqliteRepository {
  final Database _db;

  SqliteRepository._(this._db);

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
    final rows = _db.select(
        'SELECT * FROM tjc_hymn ORDER BY CAST(hymn_number AS INTEGER), hymn_number');
    return rows.map((r) => Hymn.fromDbRow(_rowToMap(r))).toList();
  }

  /// 按编号或标题搜索（不含作者/作曲，按需求限定范围）
  List<Hymn> searchHymns(String keyword) {
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
    final rows = _db.select(
      'SELECT * FROM tjc_hymn ORDER BY CAST(hymn_number AS INTEGER) LIMIT ? OFFSET ?',
      [limit, offset],
    );
    return rows.map((r) => Hymn.fromDbRow(_rowToMap(r))).toList();
  }

  Hymn? hymnByNumber(String number) {
    final rows = _db.select(
      'SELECT * FROM tjc_hymn WHERE hymn_number = ? LIMIT 1',
      [number],
    );
    if (rows.isEmpty) return null;
    return Hymn.fromDbRow(_rowToMap(rows.first));
  }

  Hymn? hymnById(int id) {
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

  /// 创建歌单，返回新 id
  int createPlaylist(String name) {
    final now = DateTime.now().toIso8601String();
    _db.execute(
      'INSERT INTO playlist_hymn (name, hymns, created_at, updated_at) VALUES (?, ?, ?, ?)',
      [name, '[]', now, now],
    );
    final id = _db.lastInsertRowId;
    LogService.instance.info(
      LogTag.playlist,
      '创建个人歌单',
      detail: '歌单ID: $id\n歌单名称: $name\n创建时间: $now',
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

  void dispose() {
    _db.dispose();
  }
}
