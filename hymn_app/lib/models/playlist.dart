import 'hymn_ref.dart';

/// 个人歌单模型（对应数据库 playlist_hymn 单表）
///
/// 表结构（v1.0.3 重构，参考 hymn_category 的 hymns JSON 字段）：
/// - `id`：歌单 id（INTEGER PRIMARY KEY AUTOINCREMENT）
/// - `name`：歌单名称
/// - `hymns`：诗歌列表（JSON 字符串，格式 `[{标题: 编号}]`，与 hymn_category.hymns 一致）
/// - `created_at`：创建时间
/// - `updated_at`：更新时间
class Playlist {
  final int id;
  final String name;
  final String createdAt;
  final String updatedAt;

  /// 诗歌清单 `[{标题: 编号}]`；编号为字符串，兼容 `51_a` 这类甲乙变体编号
  final List<HymnRef> hymns;

  const Playlist({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    required this.hymns,
  });

  int get count => hymns.length;

  /// 从 SQLite 行（playlist_hymn 表）构建
  factory Playlist.fromDbRow(Map<String, Object?> row) {
    String str(String key) => (row[key] as String?) ?? '';

    return Playlist(
      id: (row['id'] as int?) ?? 0,
      name: str('name'),
      createdAt: str('created_at'),
      updatedAt: str('updated_at'),
      hymns: parseHymnRefs(str('hymns')),
    );
  }

  /// 将 hymns 序列化为 JSON 字符串（[{标题: 编号}]）
  static String hymnsToJson(List<HymnRef> hymns) => hymnRefsToJson(hymns);
}
