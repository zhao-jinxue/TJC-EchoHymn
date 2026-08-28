import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'log_service.dart';

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
        LogService.instance
            .info(LogTag.lib, '数据根目录定位（桌面向上查找）', detail: databasePath);
        return;
      }
    }

    try {
      final dir = await getApplicationSupportDirectory();
      _dataRoot = dir.path;
      databasePath = '$_dataRoot/tjc_hymn.db';
      LogService.instance
          .info(LogTag.lib, '数据根目录定位（应用支持目录）', detail: databasePath);
    } catch (e) {
      _dataRoot = Directory.current.path;
      databasePath = '$_dataRoot/data/tjc_hymn.db';
      LogService.instance.warning(
        LogTag.lib,
        '数据根目录定位失败，回退当前工作目录',
        detail: '$databasePath\n原因: $e',
      );
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
  ///
  /// **判据**：只接受「含 `tjc_hymn.db` 的 data/ 目录」——Flutter Windows 构建产物
  /// 的 `data/` 是引擎资产目录（flutter_assets/icudtl.dat，无数据库），不能当作数据根。
  ///
  /// **发布包禁向上**：当前目录名以 `echohymn_win_` 开头（发布包目录）时，数据只允许
  /// 位于 exe 同级 `data/`，不再向上查找——否则发布包内删除数据库后会向上穿透到
  /// 仓库根误命中开发旧库（UI 测试 K12/K13）。
  static String? _locateDesktopDataRoot() {
    var dir = Directory.current;
    final dirName = dir.path.split(Platform.pathSeparator).last;
    final isBundleDir = dirName.startsWith('echohymn_win_');
    for (var i = 0; i < 12; i++) {
      final candidate = '${dir.path}${Platform.pathSeparator}data';
      if (File('$candidate${Platform.pathSeparator}tjc_hymn.db').existsSync()) {
        return candidate;
      }
      if (isBundleDir) return null; // 发布包内禁止向上查找
      final parent = dir.parent;
      if (parent.path == dir.path) break;
      dir = parent;
    }
    return null;
  }
}
