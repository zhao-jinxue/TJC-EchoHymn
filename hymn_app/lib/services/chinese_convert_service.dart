import 'chinese_convert_stub.dart'
    if (dart.library.io) 'chinese_convert_native.dart' as impl;

/// 简繁转换服务
///
/// - 桌面/移动端（dart.library.io）：OpenCC FFI 高质量转换
/// - Web（dart.library.js）：降级为原文（Web 无法加载本地 OpenCC 词典）
class ChineseConvertService {
  ChineseConvertService._();

  /// 单例
  static final ChineseConvertService instance = ChineseConvertService._();

  /// 初始化 OpenCC 字典目录（绝对路径，含 t2s.json/s2t.json 与 .ocd2）。
  /// 需在首次转换前调用；Web 端为空操作。
  void initOpencc(String dictDir) => impl.initOpenccImpl(dictDir);

  /// 繁体 → 简体
  String toSimplified(String text) => impl.toSimplifiedImpl(text);

  /// 简体 → 繁体（供搜索匹配繁体库标题时使用）
  String toTraditional(String text) => impl.toTraditionalImpl(text);
}
