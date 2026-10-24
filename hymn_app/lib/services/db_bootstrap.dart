import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;

import 'app_paths.dart';
import 'log_service.dart';

/// 内置数据库资产的首启安装（Android / 鸿蒙等移动平台）
///
/// **背景（B-1）**：移动端没有「安装目录 + data/」这一形态，`AppPaths` 的 mobile
/// 分支把数据根定在 `getApplicationSupportDirectory()`，但那里一开始是空的
/// ——SQLite 打开时会新建一个 12 KB 的空库（无表），首屏只能显示「数据加载失败」。
/// 因此需要把打包进 APK 的 `assets/data/tjc_hymn.db`（474 首）在首启时拷到
/// 应用私有目录。
///
/// **判据**：私有目录旁另存 `db_version.txt`（内容为 [assetVersion]）。版本戳不一致
/// 或数据库文件缺失 → 整库重拷（先写 `.tmp` 再 rename，避免半写文件被 SQLite 打开）。
/// **改库必 bump**：`data/tjc_hymn.db` 更新后重新打包时，必须把 [assetVersion] +1，
/// 否则老用户不会收到新数据。
class DbBootstrap {
  DbBootstrap._();

  /// assets 内的数据库路径（须与 `pubspec.yaml` 的 assets 声明一致）
  static const String assetPath = 'assets/data/tjc_hymn.db';

  /// 资产库版本戳（更新数据库 → 重新打包前 +1）
  static const int assetVersion = 1;

  static const String _versionFileName = 'db_version.txt';

  /// 确保移动端私有目录里有可用的数据库；桌面端直接返回（用安装目录的 data/）。
  static Future<void> ensureDatabase() async {
    if (!AppPaths.isMobile) return;

    await AppPaths.init();
    final dbPath = AppPaths.databasePath;
    final root = AppPaths.dataRoot;
    if (dbPath == null || dbPath.isEmpty || root == null) {
      LogService.instance.warning(
        LogTag.lib,
        '首启数据库安装跳过：数据根目录未定位',
        detail: 'dbPath=$dbPath root=$root',
      );
      return;
    }

    final sep = Platform.pathSeparator;
    final versionFile = File('$root$sep$_versionFileName');
    final dbFile = File(dbPath);

    // 版本戳一致 + 文件存在 → 已是当前版本，跳过（省掉 25 MB 级拷贝）
    var versionMatches = false;
    try {
      versionMatches = versionFile.existsSync() &&
          versionFile.readAsStringSync().trim() == '$assetVersion';
    } catch (_) {
      versionMatches = false;
    }
    if (dbFile.existsSync() && versionMatches) {
      LogService.instance.info(
        LogTag.lib,
        '内置数据库已是最新（跳过拷贝）',
        detail: '版本 $assetVersion / $dbPath',
      );
      return;
    }

    try {
      final data = await rootBundle.load(assetPath);
      final bytes =
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);

      final tmp = File('$dbPath.tmp');
      await tmp.writeAsBytes(bytes, flush: true);
      if (tmp.existsSync() && tmp.lengthSync() != bytes.length) {
        throw StateError('临时文件长度不符：${tmp.lengthSync()} != ${bytes.length}');
      }
      if (dbFile.existsSync()) dbFile.deleteSync();
      tmp.renameSync(dbPath);
      versionFile.writeAsStringSync('$assetVersion', flush: true);

      LogService.instance.info(
        LogTag.lib,
        '首启安装内置数据库完成',
        detail: '${bytes.length} 字节 → $dbPath（版本 $assetVersion）',
      );
    } catch (e, st) {
      LogService.instance.exception('首启安装内置数据库失败', e, st);
    }
  }
}
