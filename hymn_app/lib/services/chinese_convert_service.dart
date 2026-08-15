import 'chinese_convert_stub.dart'
    if (dart.library.io) 'chinese_convert_native.dart' as impl;

/// 繁→简转换服务
///
/// - 桌面/移动端（dart.library.io）：OpenCC FFI 高质量转换
/// - Web（dart.library.js）：降级为原文（Web 无法加载本地 OpenCC 词典）
class ChineseConvertService {
  ChineseConvertService._();

  /// 单例
  static final ChineseConvertService instance = ChineseConvertService._();

  /// 繁体 → 简体
  String toSimplified(String text) => impl.toSimplifiedImpl(text);
}
