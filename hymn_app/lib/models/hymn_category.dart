import 'dart:convert';

/// 诗歌分类（对应数据库 hymn_category 表）
class HymnCategory {
  final int id;
  final String category; // 一级分类
  final String subcategory; // 二级分类
  final List<MapEntry<String, int>> hymns; // [{标题: 编号}...]

  const HymnCategory({
    required this.id,
    required this.category,
    required this.subcategory,
    required this.hymns,
  });

  /// 从 SQLite 行构建
  factory HymnCategory.fromDbRow(Map<String, Object?> row) {
    String str(String key) => (row[key] as String?) ?? '';

    final hymns = <MapEntry<String, int>>[];
    try {
      final decoded = jsonDecode(str('hymns'));
      if (decoded is List) {
        for (final item in decoded) {
          if (item is Map<String, dynamic>) {
            item.forEach((k, v) => hymns.add(MapEntry(k, (v as num).toInt())));
          }
        }
      }
    } catch (_) {}

    return HymnCategory(
      id: (row['id'] as int?) ?? 0,
      category: str('category'),
      subcategory: str('subcategory'),
      hymns: hymns,
    );
  }
}
