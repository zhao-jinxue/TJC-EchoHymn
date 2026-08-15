/// 个人歌单模型（对应数据库 playlist 表 + playlist_hymn 关联）
///
/// 结构（按用户确认）：
/// - playlist(id, name, created_at)
/// - playlist_hymn(playlist_id, hymn_list[{hymn_id: name}], sort_order)
class Playlist {
  final int id;
  final String name;
  final String createdAt;
  final List<PlaylistHymnItem> hymnItems; // 已按 sort_order 排序

  const Playlist({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.hymnItems,
  });

  int get count => hymnItems.length;

  /// 从 SQLite 行（playlist 表）构建
  factory Playlist.fromDbRow(Map<String, Object?> row,
      {List<PlaylistHymnItem> hymnItems = const []}) {
    return Playlist(
      id: (row['id'] as int?) ?? 0,
      name: (row['name'] as String?) ?? '',
      createdAt: (row['created_at'] as String?) ?? '',
      hymnItems: hymnItems,
    );
  }
}

/// 歌单内的一首诗歌条目
class PlaylistHymnItem {
  final int hymnId;
  final String name; // 冗余存储标题，便于列表展示
  final int sortOrder;

  const PlaylistHymnItem({
    required this.hymnId,
    required this.name,
    required this.sortOrder,
  });

  /// 从 SQLite 行（playlist_hymn 表）构建
  factory PlaylistHymnItem.fromDbRow(Map<String, Object?> row) {
    return PlaylistHymnItem(
      hymnId: (row['hymn_id'] as int?) ?? 0,
      name: (row['name'] as String?) ?? '',
      sortOrder: (row['sort_order'] as int?) ?? 0,
    );
  }
}
