import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// 应用数据与资源路径解析
class AppPaths {
  static String? _dataRoot;
  static String? databasePath;

  /// 初始化：定位数据根目录
  static Future<void> init() async {
    if (_dataRoot != null) return;

    if (!isMobile) {
      final found = _locateDesktopDataRoot();
      if (found != null) {
        _dataRoot = found;
        databasePath = '$_dataRoot/tjc_hymn.db';
        return;
      }
    }

    try {
      final dir = await getApplicationSupportDirectory();
      _dataRoot = dir.path;
      databasePath = '$_dataRoot/tjc_hymn.db';
    } catch (_) {
      _dataRoot = Directory.current.path;
      databasePath = '$_dataRoot/data/tjc_hymn.db';
    }
  }

  static bool get isMobile =>
      !Platform.isWindows && !Platform.isLinux && !Platform.isMacOS;

  static String? get dataRoot => _dataRoot;

  /// 资源根目录（Hymn_Downloads 的父目录）
  static String get assetRoot => _dataRoot ?? '';

  /// 将数据库相对路径（Linux 风格 `/` 分隔）解析为平台绝对路径
  static String resolveAsset(String relative) {
    if (relative.isEmpty) return '';
    if (relative.contains(':\\')) return relative;
    if (relative.startsWith('file:')) return relative;

    String cleaned = relative.replaceFirst(RegExp(r'^\.?/'), '');
    if (Platform.isWindows) {
      cleaned = cleaned.replaceAll('/', '\\'); // Linux 分隔符 → Windows
    }
    return '$assetRoot${Platform.pathSeparator}$cleaned';
  }

  /// 从当前目录向上查找 data/ 目录（最多 12 层）
  static String? _locateDesktopDataRoot() {
    var dir = Directory.current;
    for (var i = 0; i < 12; i++) {
      final candidate = '${dir.path}${Platform.pathSeparator}data';
      if (File('$candidate${Platform.pathSeparator}tjc_hymn.db').existsSync()) {
        return candidate;
      }
      final parent = dir.parent;
      if (parent.path == dir.path) break;
      dir = parent;
    }
    return null;
  }
}
