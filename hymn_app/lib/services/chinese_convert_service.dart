import '../data/chinese_convert_map.dart';
import 'chinese_convert_stub.dart'
    if (dart.library.io) 'chinese_convert_native.dart' as impl;
import 'log_service.dart';

/// 简繁转换服务
///
/// - 桌面/移动端（dart.library.io）：纯 Dart 查表转换
/// - Web（dart.library.js）：降级为原文（Web 无法加载本地 OpenCC 词典）
class ChineseConvertService {
  ChineseConvertService._() {
    // 库加载日志：简繁映射表
    LogService.instance.info(
      LogTag.lib,
      '简繁转换映射表加载完成（纯 Dart 查表）',
      detail: '繁→简 ${kToSimplifiedByChar.length} 字 / 简→繁 '
          '${kToTraditionalByChar.length} 字',
    );
  }

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
