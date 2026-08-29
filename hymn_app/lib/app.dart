import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/home_screen.dart';
import 'services/audio_service.dart';
import 'services/log_service.dart';
import 'widgets/user_manual_dialog.dart';

/// 全局 Navigator key（供全局快捷键等非路由内代码弹窗使用）
final GlobalKey<NavigatorState> kNavigatorKey = GlobalKey<NavigatorState>();

/// 主题色常量（按 UI 确认单规范）
class AppColors {
  static const Color primary = Color(0xFF2B6AE0);
  static const Color primaryHover = Color(0xFF1E57C8);
  static const Color accent = Color(0xFF00A870);
  static const Color pageBg = Color(0xFFFAFBFC);
  static const Color cardBg = Color(0xFFFFFFFF);
  static const Color sidebarBg = Color(0xFFF5F6FA);
  static const Color textPrimary = Color(0xFF1F2329);
  static const Color textSecondary = Color(0xFF646A73);
  static const Color textTertiary = Color(0xFF8F959E);
  static const Color divider = Color(0xFFE5E6EB);
  static const Color border = Color(0xFFD0D3D9);
  static const Color success = Color(0xFF00A870);
  static const Color warning = Color(0xFFFF9F0A);
  static const Color danger = Color(0xFFF54A45);
  static const Color selectedBg = Color(0xFFE8F0FE);

  /// 歌词显示区背景（暖白，与侧栏冷灰 #F5F6FA 形成轻微色差，便于感知区域大小）
  static const Color lyricsBg = Color(0xFFFDF8EE);
}

/// EchoHymn 全局快捷键（通用方案）：
///
/// | 功能           | 快捷键                                      |
/// | -------------- | ------------------------------------------- |
/// | 播放 / 暂停     | 空格键 或 Ctrl+P（MediaPlayPause）          |
/// | 下一首         | Ctrl+→ 或 Alt+→（MediaTrackNext）           |
/// | 上一首         | Ctrl+← 或 Alt+←（MediaTrackPrevious）       |
/// | 音量增大       | Ctrl+↑（MediaVolumeUp）                     |
/// | 音量减小       | Ctrl+↓（MediaVolumeDown）                   |
/// | 静音 / 取消静音 | Ctrl+M（MediaVolumeMute）                   |
/// | 打开用户手册    | F1                                          |
///
/// 规则：播放/暂停、切歌、静音等**切换类**动作忽略长按重复；
/// 音量允许长按连续调节；输入框获得焦点时空格仍用于输入文字。
KeyEventResult _handleGlobalShortcuts(FocusNode node, KeyEvent event) {
  if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
    return KeyEventResult.ignored;
  }
  final bool isRepeat = event is KeyRepeatEvent;
  final audio = AudioService.instance;
  final logical = event.logicalKey;

  // ---- 通用媒体键（媒体键盘直接控制） ----
  if (logical == LogicalKeyboardKey.mediaPlayPause) {
    if (!isRepeat) audio?.togglePlayPause();
    return KeyEventResult.handled;
  }
  if (logical == LogicalKeyboardKey.mediaTrackNext) {
    if (!isRepeat) audio?.playNext();
    return KeyEventResult.handled;
  }
  if (logical == LogicalKeyboardKey.mediaTrackPrevious) {
    if (!isRepeat) audio?.playPrev();
    return KeyEventResult.handled;
  }
  if (logical == LogicalKeyboardKey.audioVolumeUp) {
    audio?.changeVolume(0.05);
    return KeyEventResult.handled;
  }
  if (logical == LogicalKeyboardKey.audioVolumeDown) {
    audio?.changeVolume(-0.05);
    return KeyEventResult.handled;
  }
  if (logical == LogicalKeyboardKey.audioVolumeMute) {
    if (!isRepeat) audio?.toggleMute();
    return KeyEventResult.handled;
  }

  // ---- F1：打开用户手册 ----
  if (logical == LogicalKeyboardKey.f1) {
    if (!isRepeat) {
      final navCtx = kNavigatorKey.currentContext;
      if (navCtx != null) UserManualDialog.show(navCtx);
    }
    return KeyEventResult.handled;
  }

  // ---- 修饰键组合 ----
  final keys = HardwareKeyboard.instance.logicalKeysPressed;
  final ctrl = keys.contains(LogicalKeyboardKey.controlLeft) ||
      keys.contains(LogicalKeyboardKey.controlRight);
  final alt = keys.contains(LogicalKeyboardKey.altLeft) ||
      keys.contains(LogicalKeyboardKey.altRight);
  final shift = keys.contains(LogicalKeyboardKey.shiftLeft) ||
      keys.contains(LogicalKeyboardKey.shiftRight);

  // 无修饰键：空格 = 播放/暂停（输入框聚焦时放行，用于输入空格）
  if (!ctrl && !alt && !shift) {
    if (logical == LogicalKeyboardKey.space) {
      if (isRepeat || _isTextInputFocused()) return KeyEventResult.ignored;
      audio?.togglePlayPause();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // Ctrl 组合
  if (ctrl && !alt && !shift) {
    if (logical == LogicalKeyboardKey.keyP) {
      if (!isRepeat) audio?.togglePlayPause();
      return KeyEventResult.handled;
    }
    if (logical == LogicalKeyboardKey.arrowRight) {
      if (!isRepeat) audio?.playNext();
      return KeyEventResult.handled;
    }
    if (logical == LogicalKeyboardKey.arrowLeft) {
      if (!isRepeat) audio?.playPrev();
      return KeyEventResult.handled;
    }
    if (logical == LogicalKeyboardKey.arrowUp) {
      audio?.changeVolume(0.05);
      return KeyEventResult.handled;
    }
    if (logical == LogicalKeyboardKey.arrowDown) {
      audio?.changeVolume(-0.05);
      return KeyEventResult.handled;
    }
    if (logical == LogicalKeyboardKey.keyM) {
      if (!isRepeat) audio?.toggleMute();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // Alt 组合：Alt+←/→ 兼容常见播放器切歌方案
  if (alt && !ctrl && !shift) {
    if (logical == LogicalKeyboardKey.arrowRight) {
      if (!isRepeat) audio?.playNext();
      return KeyEventResult.handled;
    }
    if (logical == LogicalKeyboardKey.arrowLeft) {
      if (!isRepeat) audio?.playPrev();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  return KeyEventResult.ignored;
}

/// 当前焦点是否在文本输入框内（判断空格是否应放行给输入）
bool _isTextInputFocused() {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return false;
  return context.findAncestorWidgetOfExactType<EditableText>() != null;
}

/// EchoHymn 应用根组件
class EchoHymnApp extends StatelessWidget {
  const EchoHymnApp({super.key});

  @override
  Widget build(BuildContext context) {
    LogService.instance.info(LogTag.ui, '生成应用根组件（EchoHymnApp / Material 主题）');
    final base = ThemeData.light(useMaterial3: true);
    final theme = base.copyWith(
      colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primary),
      scaffoldBackgroundColor: AppColors.pageBg,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.cardBg,
        foregroundColor: AppColors.textPrimary,
        elevation: 0.5,
        titleTextStyle: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
      dividerColor: AppColors.divider,
      textTheme: base.textTheme.apply(
        bodyColor: AppColors.textPrimary,
        displayColor: AppColors.textPrimary,
      ),
      cardTheme: const CardThemeData(
        color: AppColors.cardBg,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(8)),
        ),
      ),
      // 全局滚动条：宽度 13px（默认 8 → +5），滑块 #C1C1C1
      scrollbarTheme: const ScrollbarThemeData(
        thickness: WidgetStatePropertyAll(10),
        thumbColor: WidgetStatePropertyAll(Color(0xFFC1C1C1)),
      ),
    );

    LogService.instance.info(
      LogTag.ui,
      'MaterialApp 构建完成',
      detail: '标题: EchoHymn · 聆听赞美诗\n主页: HomeScreen',
    );
    // 全局快捷键：把 MaterialApp 包在 Focus 下，事件从任意焦点（含弹窗）
    // 冒泡到根节点统一处理（播放控制 + F1 手册）
    return Focus(
      autofocus: true,
      onKeyEvent: _handleGlobalShortcuts,
      child: MaterialApp(
        title: 'EchoHymn · 聆听赞美诗',
        debugShowCheckedModeBanner: false,
        navigatorKey: kNavigatorKey,
        theme: theme,
        home: const HomeScreen(),
      ),
    );
  }
}
