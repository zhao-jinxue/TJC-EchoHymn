import 'dart:async';

import 'package:flutter/services.dart';

import '../services/log_service.dart';

/// 素材导入进度
class MediaImportProgress {
  const MediaImportProgress({required this.copied, required this.failed});

  final int copied;
  final int failed;
}

/// 素材导入结果
class MediaImportResult {
  const MediaImportResult({
    required this.copied,
    required this.failed,
    this.error,
  });

  final int copied;
  final int failed;
  final String? error;

  bool get success => error == null;
}

/// SAF 目录导入（`ANDROID_PLAN §7.5` 外部导入方案）
///
/// 用户在系统目录选择器里选 `Hymn_Downloads` 目录 → 原生侧**递归复制**到应用私有目录。
///
/// **为什么是"复制"而不是直接播 `content://`**：`audioplayers` 的 `DeviceFileSource`
/// 只接受**文件绝对路径**，SAF URI 无法直接播放；复制完成后 DB 里的相对路径
/// （`Hymn_Downloads/<曲目>/<文件>`）自然生效，播放链路零改动。
///
/// 通道：`echohymn/import` → `MainActivity`（`ACTION_OPEN_DOCUMENT_TREE` + DocumentFile）
class MediaImport {
  MediaImport._();

  static const MethodChannel _channel = MethodChannel('echohymn/import');

  static final StreamController<MediaImportProgress> _progressCtrl =
      StreamController<MediaImportProgress>.broadcast();
  static final StreamController<MediaImportResult> _doneCtrl =
      StreamController<MediaImportResult>.broadcast();

  static bool _handlerInstalled = false;

  /// 进度（每 20 个文件一次）
  static Stream<MediaImportProgress> get progressStream => _progressCtrl.stream;

  /// 结束（含失败统计与错误信息）
  static Stream<MediaImportResult> get doneStream => _doneCtrl.stream;

  static void _installHandler() {
    if (_handlerInstalled) return;
    _handlerInstalled = true;
    _channel.setMethodCallHandler((call) async {
      final args = call.arguments is Map ? call.arguments as Map : null;
      switch (call.method) {
        case 'importProgress':
          _progressCtrl.add(MediaImportProgress(
            copied: (args?['copied'] as num?)?.toInt() ?? 0,
            failed: (args?['failed'] as num?)?.toInt() ?? 0,
          ));
          break;
        case 'importDone':
          _doneCtrl.add(MediaImportResult(
            copied: (args?['copied'] as num?)?.toInt() ?? 0,
            failed: (args?['failed'] as num?)?.toInt() ?? 0,
            error: args?['error'] as String?,
          ));
          break;
      }
      return null;
    });
  }

  /// 打开系统目录选择器；返回 `content://` tree URI（用户取消则 null）
  static Future<String?> pickDirectory() async {
    _installHandler();
    try {
      return await _channel.invokeMethod<String>('pickDirectory');
    } catch (e, st) {
      LogService.instance.exception('选择素材目录失败', e, st);
      return null;
    }
  }

  /// 开始导入（异步）：进度走 [progressStream]，结束走 [doneStream]
  static Future<bool> startImport({
    required String treeUri,
    required String targetRoot,
  }) async {
    _installHandler();
    LogService.instance.info(
      LogTag.action,
      '素材导入开始',
      detail: '目标目录: $targetRoot',
    );
    try {
      await _channel.invokeMethod<void>('importTree', {
        'uri': treeUri,
        'targetRoot': targetRoot,
      });
      return true;
    } catch (e, st) {
      LogService.instance.exception('素材导入调用失败', e, st);
      return false;
    }
  }
}
