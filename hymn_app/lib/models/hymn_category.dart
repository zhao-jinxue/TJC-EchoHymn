import 'hymn_ref.dart';

/// 诗歌分类（对应数据库 hymn_category 表）
class HymnCategory {
  final int id;
  final String category; // 一级分类
  final String subcategory; // 二级分类

  /// 诗歌清单 `[{标题: 编号}]`；编号为字符串，兼容 `51_a` 这类甲乙变体编号
  final List<HymnRef> hymns;

  const HymnCategory({
    required this.id,
    required this.category,
    required this.subcategory,
    required this.hymns,
  });

  /// 从 SQLite 行构建
  factory HymnCategory.fromDbRow(Map<String, Object?> row) {
    String str(String key) => (row[key] as String?) ?? '';

    return HymnCategory(
      id: (row['id'] as int?) ?? 0,
      category: str('category'),
      subcategory: str('subcategory'),
      hymns: parseHymnRefs(str('hymns')),
    );
  }
}
