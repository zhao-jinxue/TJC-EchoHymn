import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;

import 'app_paths.dart';
import 'log_service.dart';

/// 内置音频样本的首启安装（移动端）
///
/// **背景（B-2）**：移动端播放走 `audioplayers` 的 `DeviceFileSource(绝对路径)`，
/// 而 DB 里存的是相对路径（`Hymn_Downloads/<中文目录>/<中文文件名>`，`/` 分隔）。
/// 样本音频打包进 APK 后必须**还原成同样的目录结构**，`AppPaths.resolveAsset`
/// 才能拼出可用路径（中文目录名 / 文件名全程保留 —— 这就是路径复测点）。
///
/// **素材方案**（ANDROID_PLAN §7.5）：样本内置（12 首）+ 外部导入（后续 SAF）。
/// 变体裁剪由 `tools/sync_audio_samples.ps1` 在构建前完成：lite 变体的
/// `index.json` 为空数组 → 包内不含任何音频文件。
///
/// **只补齐、不清理**：不删除用户已导入的文件；大小一致则跳过，避免每次启动重拷。
class MediaBootstrap {
  MediaBootstrap._();

  /// 样本索引 assets 路径（由 sync_audio_samples.ps1 生成）
  static const String assetIndexPath = 'assets/media/index.json';

  /// 样本素材版本戳（样本清单变化时 +1）
  static const int mediaVersion = 1;

  static const String _versionFileName = 'media_version.txt';

  /// 确保移动端私有目录里有内置样本音频；桌面端直接返回。
  static Future<void> ensureSamples() async {
    if (!AppPaths.isMobile) return;

    await AppPaths.init();
    final root = AppPaths.dataRoot;
    if (root == null || root.isEmpty) return;

    final sep = Platform.pathSeparator;
    final versionFile = File('$root$sep$_versionFileName');

    List<dynamic> entries;
    try {
      final raw = await rootBundle.loadString(assetIndexPath);
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        LogService.instance
            .warning(LogTag.lib, '样本索引格式异常（非数组），跳过安装');
        return;
      }
      entries = decoded;
    } catch (e) {
      // 理论上每个变体都有 index.json；缺失按「无内置样本」处理，不阻断启动
      LogService.instance.info(LogTag.lib, '无内置样本索引，跳过素材安装', detail: '$e');
      return;
    }

    if (entries.isEmpty) {
      LogService.instance.info(LogTag.lib, '当前变体不含内置音频样本（lite）');
      return;
    }

    var versionMatches = false;
    try {
      versionMatches = versionFile.existsSync() &&
          versionFile.readAsStringSync().trim() == '$mediaVersion';
    } catch (_) {
      versionMatches = false;
    }

    var installed = 0;
    var skipped = 0;
    var failed = 0;

    for (final e in entries) {
      if (e is! Map) continue;
      final asset = e['asset'] as String?;
      final target = e['target'] as String?;
      final bytes = e['bytes'];
      if (asset == null || target == null) continue;

      // DB 内相对路径（`/` 分隔）→ 平台绝对路径
      final targetPath = '$root$sep${target.replaceAll('/', sep)}';
      final file = File(targetPath);
      final expectLen = bytes is int ? bytes : null;

      if (file.existsSync() &&
          (expectLen == null || file.lengthSync() == expectLen)) {
        skipped++;
        continue;
      }

      try {
        final data = await rootBundle.load('assets/media/$asset');
        final raw =
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
        await file.parent.create(recursive: true);
        final tmp = File('$targetPath.tmp');
        await tmp.writeAsBytes(raw, flush: true);
        if (file.existsSync()) file.deleteSync();
        tmp.renameSync(targetPath);
        installed++;
      } catch (err, st) {
        failed++;
        LogService.instance.exception('样本素材安装失败：$target', err, st);
      }
    }

    if (failed == 0) {
      try {
        versionFile.writeAsStringSync('$mediaVersion', flush: true);
      } catch (_) {
        // 版本戳写失败只影响下次重复校验，不影响可用性
      }
    }

    LogService.instance.info(
      LogTag.lib,
      '内置样本素材安装完成',
      detail: '新增 $installed / 跳过 $skipped / 失败 $failed'
          '（共 ${entries.length} 条，版本 $mediaVersion，版本戳匹配=$versionMatches）',
    );
  }
}
