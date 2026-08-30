import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import 'app.dart';
import 'services/app_state_service.dart';
import 'services/log_service.dart';
import 'theme/app_palette.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化日志系统（exe 同级 logs/ 目录，保留 7 份日志文件）
  await LogService.instance.init();
  LogService.instance.info(LogTag.system, '应用启动');

  // 恢复上次配色（state.json 的 appTheme；缺失/非法回退默认晨光蓝）
  try {
    final state = await AppStateService().load();
    ThemeController.instance.switchTo(themeById(state.appTheme));
  } catch (e) {
    LogService.instance.error(LogTag.error, '恢复配色失败，使用默认', detail: '$e');
  }

  // 全局异常捕获（Flutter 框架层）
  FlutterError.onError = (FlutterErrorDetails details) {
    LogService.instance.exception(
      'Flutter 框架异常',
      details.exception,
      details.stack,
    );
  };
  // 平台通道/异步异常
  PlatformDispatcher.instance.onError = (error, stack) {
    LogService.instance.exception('平台/异步异常', error, stack);
    return true; // 已处理，不崩溃
  };

  runApp(const EchoHymnApp());
}
