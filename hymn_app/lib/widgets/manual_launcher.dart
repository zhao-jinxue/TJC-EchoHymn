import 'package:flutter/material.dart';

import '../services/log_service.dart';
import 'user_manual_dialog.dart';

/// 打开用户手册：**手机走全屏页**（`ANDROID_PLAN §3.1.8`），桌面仍走 560×560 弹窗。
///
/// 两种承载共用 `UserManualDialog` 同一份内容 —— `fullscreen` 只切换外壳与底部按钮组，
/// 内容与「启动时显示本手册」开关逻辑零分叉。
Future<void> showManualPage(BuildContext context) async {
  final isPhone = MediaQuery.sizeOf(context).shortestSide < 600;
  if (!isPhone) {
    return UserManualDialog.show(context);
  }
  LogService.instance.info(LogTag.action, '打开用户手册（全屏）');
  await Navigator.of(context).push<void>(MaterialPageRoute(
    builder: (_) => const UserManualDialog(fullscreen: true),
  ));
}
