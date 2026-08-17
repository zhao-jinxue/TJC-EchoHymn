import '../data/chinese_convert_map.dart';

/// 纯 Dart 简繁转换适配（无原生依赖，不阻塞 UI，跨平台稳定）
///
/// 映射表由 `python tools/gen_convert_map.py` 从 data/tjc_hymn.db 全量字符
/// 生成（zhconv 校准），覆盖数据库中出现的全部繁简体。
///
/// 逐字查表：命中返回映射，未命中原样保留（绝不出错/崩溃）。
String toSimplifiedImpl(String text) {
  if (text.isEmpty) return text;
  final buf = StringBuffer();
  for (final rune in text.runes) {
    final ch = String.fromCharCode(rune);
    buf.write(kToSimplifiedByChar[ch] ?? ch);
  }
  return buf.toString();
}

/// 简体 → 繁体（供搜索匹配繁体库标题）
String toTraditionalImpl(String text) {
  if (text.isEmpty) return text;
  final buf = StringBuffer();
  for (final rune in text.runes) {
    final ch = String.fromCharCode(rune);
    buf.write(kToTraditionalByChar[ch] ?? ch);
  }
  return buf.toString();
}

/// 初始化（纯 Dart 实现无需初始化）
void initOpenccImpl(String dir) {}
