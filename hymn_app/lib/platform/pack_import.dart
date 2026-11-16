import 'dart:async';

import 'package:flutter/services.dart';

/// 数据包导入进度（processed / accepted / rejected）
class PackImportProgress {
  const PackImportProgress({
    required this.processed,
    required this.accepted,
    required this.rejected,
  });

  final int processed;
  final int accepted;
  final int rejected;
}

/// 数据包导入结果
class PackImportResult {
  const PackImportResult({
    required this.accepted,
    required this.rejected,
    required this.failed,
    this.error,
  });

  /// 已导入（覆盖写）的文件数
  final int accepted;

  /// 规则外被丢弃（**不落盘**）的文件数
  final int rejected;

  final int failed;
  final String? error;

  bool get ok => error == null && failed == 0;
}

/// 数据包（zip）导入通道（2026-11-13 主体 APK 方案）
///
/// 用户在「设置 → 数据导入」选择 `扫描图 / 人声 / 钢琴` 压缩包；
/// Android 侧流式解压，**只接受符合现有 `Hymn_Downloads/<目录>/<编号>_<类型>.<ext>`
/// 规则且属于本类别的文件**（规则外一律丢弃、不落盘），同名文件直接覆盖。
class PackImport {
  PackImport._();

  static const MethodChannel _channel = MethodChannel('echohymn/pack');

  static final StreamController<PackImportProgress> _progressCtrl =
      StreamController<PackImportProgress>.broadcast();
  static final StreamController<PackImportResult> _doneCtrl =
      StreamController<PackImportResult>.broadcast();

  static bool _bound = false;

  static void _bind() {
    if (_bound) return;
    _bound = true;
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'packProgress':
          final args = call.arguments as Map<dynamic, dynamic>? ?? const {};
          _progressCtrl.add(PackImportProgress(
            processed: (args['processed'] as int?) ?? 0,
            accepted: (args['accepted'] as int?) ?? 0,
            rejected: (args['rejected'] as int?) ?? 0,
          ));
          break;
        case 'packDone':
          final args = call.arguments as Map<dynamic, dynamic>? ?? const {};
          _doneCtrl.add(PackImportResult(
            accepted: (args['accepted'] as int?) ?? 0,
            rejected: (args['rejected'] as int?) ?? 0,
            failed: (args['failed'] as int?) ?? 0,
            error: args['error'] as String?,
          ));
          break;
      }
      return null;
    });
  }

  static Stream<PackImportProgress> get progressStream {
    _bind();
    return _progressCtrl.stream;
  }

  static Stream<PackImportResult> get doneStream {
    _bind();
    return _doneCtrl.stream;
  }

  /// 选择压缩包（`kind` = `scores` / `vocal` / `piano`），返回 URI（取消为 null）
  static Future<String?> pickZip(String kind) async {
    _bind();
    return _channel.invokeMethod<String>('pickZip', {'kind': kind});
  }

  /// 开始导入（异步）：进度走 [progressStream]，结束走 [doneStream]
  static Future<bool> startImport({
    required String uri,
    required String kind,
    required String targetRoot,
  }) async {
    _bind();
    await _channel.invokeMethod<void>('importZip', {
      'uri': uri,
      'kind': kind,
      'targetRoot': targetRoot,
    });
    return true;
  }
}
