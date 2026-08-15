import 'package:sqlite3/sqlite3.dart';

import '../models/hymn.dart';
import '../models/hymn_category.dart';
import '../models/playlist.dart';
import 'app_paths.dart';

/// SQLite 数据仓库：tjc_hymn / hymn_category / playlist / playlist_hymn
class SqliteRepository {
  final Database _db;

  SqliteRepository._(this._db);

  /// 打开数据库并确保个人歌单表存在
  static Future<SqliteRepository> open() async {
    await AppPaths.init();
    final path = AppPaths.databasePath ?? '';
    final db = sqlite3.open(path);
    final repo = SqliteRepository._(db);
    repo._ensurePlaylistTables();
    return repo;
  }

  /// 创建个人歌单相关表（若不存在）
  void _ensurePlaylistTables() {
    _db.execute('''
      CREATE TABLE IF NOT EXISTS playlist (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
    _db.execute('''
      CREATE TABLE IF NOT EXISTS playlist_hymn (
        playlist_id INTEGER NOT NULL,
        hymn_id INTEGER NOT NULL,
        name TEXT,
        sort_order INTEGER NOT NULL,
        PRIMARY KEY (playlist_id, hymn_id)
      )
    ''');
  }

  // ---------- 诗歌 ----------

  /// 按编号排序的全部诗歌
  List<Hymn> getAllHymns() {
    final rows = _db.select(
        'SELECT * FROM tjc_hymn ORDER BY CAST(hymn_number AS INTEGER), hymn_number');
    return rows.map((r) => Hymn.fromDbRow(_rowToMap(r))).toList();
  }

  /// 按编号或标题搜索
  List<Hymn> searchHymns(String keyword) {
    final kw = keyword.trim();
    if (kw.isEmpty) return getAllHymns();
    final like = '%$kw%';
    // 数字 → 优先匹配编号；其余匹配标题/作词/作曲
    final isNum = int.tryParse(kw) != null;
    if (isNum) {
      final rows = _db.select(
        'SELECT * FROM tjc_hymn WHERE hymn_number = ? OR hymn_number LIKE ? ORDER BY CAST(hymn_number AS INTEGER)',
        [kw, '$kw%'],
      );
      return rows.map((r) => Hymn.fromDbRow(_rowToMap(r))).toList();
    }
    final rows = _db.select(
      '''SELECT * FROM tjc_hymn
         WHERE title LIKE ? OR lyricist LIKE ? OR composer LIKE ?
         ORDER BY CAST(hymn_number AS INTEGER)''',
      [like, like, like],
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

  // ---------- 个人歌单 ----------

  /// 全部个人歌单（含成员）
  List<Playlist> getPlaylists() {
    final rows = _db.select('SELECT * FROM playlist ORDER BY id');
    return rows.map((r) {
      final pl = Playlist.fromDbRow(_rowToMap(r));
      return Playlist(
        id: pl.id,
        name: pl.name,
        createdAt: pl.createdAt,
        hymnItems: _getPlaylistItems(pl.id),
      );
    }).toList();
  }

  List<PlaylistHymnItem> _getPlaylistItems(int playlistId) {
    final rows = _db.select(
      'SELECT * FROM playlist_hymn WHERE playlist_id = ? ORDER BY sort_order',
      [playlistId],
    );
    return rows.map((r) => PlaylistHymnItem.fromDbRow(_rowToMap(r))).toList();
  }

  /// 创建歌单，返回新 id
  int createPlaylist(String name) {
    final now = DateTime.now().toIso8601String();
    _db.execute(
      'INSERT INTO playlist (name, created_at) VALUES (?, ?)',
      [name, now],
    );
    return _db.lastInsertRowId;
  }

  /// 向歌单添加诗歌（不允许重复）→ 返回是否添加成功
  bool addHymnToPlaylist(int playlistId, int hymnId, String name) {
    final exists = _db.select(
      'SELECT 1 FROM playlist_hymn WHERE playlist_id = ? AND hymn_id = ?',
      [playlistId, hymnId],
    );
    if (exists.isNotEmpty) return false; // 不允许重复

    final count = _db.select(
      'SELECT COUNT(*) AS c FROM playlist_hymn WHERE playlist_id = ?',
      [playlistId],
    ).first['c'] as int;

    _db.execute(
      'INSERT INTO playlist_hymn (playlist_id, hymn_id, name, sort_order) VALUES (?, ?, ?, ?)',
      [playlistId, hymnId, name, count],
    );
    return true;
  }

  /// 从歌单移除诗歌
  void removeHymnFromPlaylist(int playlistId, int hymnId) {
    _db.execute(
      'DELETE FROM playlist_hymn WHERE playlist_id = ? AND hymn_id = ?',
      [playlistId, hymnId],
    );
    // 重新排序
    final items = _getPlaylistItems(playlistId);
    for (var i = 0; i < items.length; i++) {
      _db.execute(
        'UPDATE playlist_hymn SET sort_order = ? WHERE playlist_id = ? AND hymn_id = ?',
        [i, playlistId, items[i].hymnId],
      );
    }
  }

  /// 删除歌单（含成员）
  void deletePlaylist(int playlistId) {
    _db.execute(
        'DELETE FROM playlist_hymn WHERE playlist_id = ?', [playlistId]);
    _db.execute('DELETE FROM playlist WHERE id = ?', [playlistId]);
  }

  /// 重命名歌单
  void renamePlaylist(int playlistId, String newName) {
    _db.execute(
        'UPDATE playlist SET name = ? WHERE id = ?', [newName, playlistId]);
  }

  /// 歌单内是否已含该歌
  bool playlistContains(int playlistId, int hymnId) {
    final rows = _db.select(
      'SELECT 1 FROM playlist_hymn WHERE playlist_id = ? AND hymn_id = ?',
      [playlistId, hymnId],
    );
    return rows.isNotEmpty;
  }

  // ---------- 工具 ----------

  /// sqlite3 的 Row 即实现 Map<String, Object?>，此处仅在需要时转为普通 Map
  Map<String, Object?> _rowToMap(Row row) => Map<String, Object?>.from(row);

  void dispose() {
    _db.dispose();
  }
}
