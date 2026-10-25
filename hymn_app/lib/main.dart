import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:audio_service/audio_service.dart' as media;
import 'package:flutter/material.dart';

import 'app.dart';
import 'platform/notification_permission.dart';
import 'services/app_state_service.dart';
import 'services/audio_handler.dart';
import 'services/log_service.dart';
import 'theme/app_fonts.dart';
import 'theme/app_palette.dart';
import 'theme/score_display_prefs.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化日志系统（exe 同级 logs/ 目录，保留 7 份日志文件）
  await LogService.instance.init();
  LogService.instance.info(LogTag.system, '应用启动');

  // Android：初始化媒体会话（通知栏 / 锁屏 / 蓝牙控制 + 前台服务；ANDROID_PLAN §6 D-2）
  if (Platform.isAndroid) {
    try {
      // Android 13+ 必须**运行时**授予通知权限，否则媒体通知 importance=NONE 不显示
      // （走自建通道 echohymn/permission；不用 permission_handler —— 它会破坏 Windows 构建）
      final granted = await NotificationPermission.ensureGranted();
      LogService.instance.info(
        LogTag.system,
        '通知权限: ${granted ? '已授予' : '未授予（已发起请求，允许后下次启动生效）'}',
      );
    } catch (e, st) {
      LogService.instance.exception('请求通知权限失败', e, st);
    }
    try {
      kMediaHandler = await media.AudioService.init<EchoHymnAudioHandler>(
        builder: EchoHymnAudioHandler.new,
        config: const media.AudioServiceConfig(
          androidNotificationChannelId: 'com.echohymn.app.playback',
          androidNotificationChannelName: 'EchoHymn 播放',
          androidNotificationOngoing: true,
          androidStopForegroundOnPause: true,
        ),
      );
      LogService.instance
          .info(LogTag.system, '媒体会话初始化完成（通知栏/锁屏/蓝牙可控）');
    } catch (e, st) {
      LogService.instance.exception('媒体会话初始化失败（不影响播放）', e, st);
    }
  }

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
    // 恢复「深色下谱面显示」（§3.10；缺失/非法回退 dim）
    ScoreDisplayPrefs.instance.restoreFrom(state.scoreDarkMode);
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
