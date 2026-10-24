import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';

import 'app.dart';
import 'services/app_state_service.dart';
import 'services/log_service.dart';
import 'theme/app_fonts.dart';
import 'theme/app_palette.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化日志系统（exe 同级 logs/ 目录，保留 7 份日志文件）
  await LogService.instance.init();
  LogService.instance.info(LogTag.system, '应用启动');

  // 恢复上次配色（state.json 的 appTheme；缺失/非法回退默认晨光蓝）
  try {
    // 移动端状态目录需先初始化（桌面端为 exe 同级）
    await AppStateService.ensurePath();
    final state = await AppStateService().load();
    final theme = themeById(state.appTheme);
    final font = fontSizeLevelById(state.fontSizeLevel);
    ThemeController.instance.switchTo(theme);
    // 恢复上次字号等级（state.json 的 fontSizeLevel；缺失/非法回退默认）
    FontScaleController.instance.switchTo(font);
    LogService.instance.info(
      LogTag.system,
      '恢复上次状态',
      detail: '配色 ${theme.id} / 字号 ${font.id}（×${font.scale}）',
    );
  } catch (e) {
    LogService.instance.error(LogTag.error, '恢复配色/字号失败，使用默认', detail: '$e');
  }

  // 移动端限制图片缓存：扫描图按显示宽解码后单张约 25 MB（2048×3028），
  // 默认 100 MB 缓存可容 4 张；降到 80 MB 让多首切换时更早淘汰，避免 OOM。
  if (Platform.isAndroid) {
    PaintingBinding.instance.imageCache.maximumSizeBytes = 80 << 20;
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
