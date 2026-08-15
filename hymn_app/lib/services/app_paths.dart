import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// 应用数据与资源路径解析
///
/// Windows 桌面：定位项目 `data/` 目录（含 tjc_hymn.db 与 Hymn_Downloads）
/// Android/iOS：使用应用文档目录（打包时内置同构数据）
class AppPaths {
  /// 数据根目录（含 tjc_hymn.db 与 Hymn_Downloads/）
  static String? _dataRoot;

  /// 数据库文件路径
  static String? databasePath;

  /// 初始化：定位数据根目录
  static Future<void> init() async {
    if (_dataRoot != null) return;

    // 1) 桌面：在工作目录及父目录中查找 data/tjc_hymn.db
    if (!isMobile) {
      final found = _locateDesktopDataRoot();
      if (found != null) {
        _dataRoot = found;
        databasePath = '$_dataRoot/tjc_hymn.db';
        return;
      }
    }

    // 2) 移动端 / 回退：应用支持目录
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

  /// 数据根目录
  static String? get dataRoot => _dataRoot;

  /// 资源根目录（Hymn_Downloads 的父目录即数据根目录）
  static String get assetRoot => _dataRoot ?? '';

  /// 将数据库中的相对路径（如 Hymn_Downloads/...）解析为绝对路径
  static String resolveAsset(String relative) {
    if (relative.isEmpty) return '';
    // 已是绝对路径
    if (relative.contains(':\\') ||
        relative.startsWith('/') ||
        relative.startsWith('file:')) {
      return relative;
    }
    // 去掉可能的 data/ 前缀
    final cleaned = relative.replaceFirst(RegExp(r'^\.?/'), '');
    return '$assetRoot/$cleaned';
  }

  /// 从当前目录向上查找 data/ 目录（最多 12 层），
  /// 兼容 exe 位于 build/windows/x64/runner/Release 的深层路径
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
