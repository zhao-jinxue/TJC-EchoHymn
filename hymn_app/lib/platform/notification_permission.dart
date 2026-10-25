import 'dart:io';

import 'package:flutter/services.dart';

import '../services/log_service.dart';

/// 通知权限（Android 13+ 需**运行时**授予 `POST_NOTIFICATIONS`）
///
/// **为什么不用 `permission_handler`**：它的 Windows 插件依赖已废弃的
/// `<experimental/coroutine>`，MSVC 14.51 直接编译失败（实测 `error C2338: STL1011`），
/// 会**破坏桌面构建**。本项目只需要这一个权限，自建 MethodChannel 更可控、零副作用。
///
/// 通道：`echohymn/permission` → `MainActivity.configureFlutterEngine`
class NotificationPermission {
  NotificationPermission._();

  static const MethodChannel _channel = MethodChannel('echohymn/permission');

  /// 确保已授予通知权限；返回 `true` = 已授予。
  ///
  /// 未授予时会**发起系统授权对话框**（用户点"允许"后，本次返回值仍是 false，
  /// 下次启动即 true —— 通知是否显示由系统按当前授权状态决定，无需 App 阻塞等待）。
  static Future<bool> ensureGranted() async {
    if (!Platform.isAndroid) return true;
    // 首次启动时 Dart 侧可能先于原生 `configureFlutterEngine` 发起调用 →
    // `MissingPluginException`（实测 1 次）。重试 3 次、间隔 300ms 即可覆盖。
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        return await _channel.invokeMethod<bool>('requestNotifications') ?? false;
      } on MissingPluginException {
        await Future<void>.delayed(const Duration(milliseconds: 300));
      } catch (e, st) {
        LogService.instance.exception('请求通知权限失败', e, st);
        return false;
      }
    }
    LogService.instance
        .warning(LogTag.system, '通知权限通道不可用（重试 3 次仍失败）');
    return false;
  }
}
