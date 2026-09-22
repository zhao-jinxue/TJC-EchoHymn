import 'dart:convert';

/// 歌单/分类成员条目：`{标题: 编号}`（与数据库 `hymn_category.hymns` /
/// `playlist_hymn.hymns` 的 JSON 格式一致）。
///
/// **编号一律用字符串表示**，以兼容站方的甲乙变体编号（如 `51_a` / `124_b`）；
/// 读取时同时兼容历史遗留的整数（旧库 hymns 值为 `1`、`25` 这样的 int），
/// 统一由 [hymnRefNumber] 归一化成字符串。
typedef HymnRef = MapEntry<String, String>;

const List<HymnRef> kEmptyHymnRefs = <HymnRef>[];

/// 把 JSON 里的编号值归一化成字符串：`1` → `'1'`，`'51_a'` → `'51_a'`
String hymnRefNumber(Object? value) {
  if (value is num) return value.toInt().toString();
  return (value ?? '').toString();
}

/// 解析 `[{标题: 编号}]`；结构不符的条目跳过，整体失败时返回已解析部分
List<HymnRef> parseHymnRefs(String raw) {
  final refs = <HymnRef>[];
  if (raw.isEmpty) return refs;
  try {
    final decoded = jsonDecode(raw);
    if (decoded is List) {
      for (final item in decoded) {
        if (item is Map<String, dynamic>) {
          item.forEach((k, v) => refs.add(MapEntry(k, hymnRefNumber(v))));
        }
      }
    }
  } catch (_) {
    // 数据损坏时返回已解析部分，调用方按空/部分列表处理
  }
  return refs;
}

/// 序列化为 `[{标题: 编号}]`（编号以字符串写入）
String hymnRefsToJson(List<HymnRef> refs) {
  return jsonEncode(
      refs.map((e) => {e.key: e.value}).toList(growable: false));
}
