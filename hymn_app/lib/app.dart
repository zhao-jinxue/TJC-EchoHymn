import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/home_screen.dart';
import 'services/audio_service.dart';
import 'services/log_service.dart';
import 'theme/app_fonts.dart';
import 'theme/app_palette.dart';
import 'widgets/user_manual_dialog.dart';

/// 全局 Navigator key（供全局快捷键等非路由内代码弹窗使用）
final GlobalKey<NavigatorState> kNavigatorKey = GlobalKey<NavigatorState>();

/// 主题色门面（按 UI 确认单规范）：
/// 全部从「当前调色板」取值 —— 换肤 = 切换 [ThemeController] 的调色板，
/// 界面各处引用本类的色槽自动跟随，无需改动业务代码。
class AppColors {
  static AppPalette get _p => ThemeController.instance.current;

  static Color get primary => _p.primary;
  static Color get primaryHover => _p.primaryHover;
  static Color get accent => _p.accent;
  static Color get pageBg => _p.pageBg;
  static Color get cardBg => _p.cardBg;
  static Color get titleBarBg => _p.titleBarBg;
  static Color get topBarBg => _p.topBarBg;
  static Color get sidebarBg => _p.sidebarBg;
  static Color get rightPanelBg => _p.rightPanelBg;
  static Color get versionBarBg => _p.versionBarBg;
  static Color get playBarBg => _p.playBarBg;
  static Color get statusBarBg => _p.statusBarBg;
  static Color get controlBg => _p.controlBg;
  static Color get controlBorder => _p.controlBorder;
  static Color get textPrimary => _p.textPrimary;
  static Color get textSecondary => _p.textSecondary;
  static Color get textTertiary => _p.textTertiary;
  static Color get divider => _p.divider;
  static Color get border => _p.border;
  static Color get success => _p.success;
  static Color get warning => _p.warning;
  static Color get danger => _p.danger;
  static Color get selectedBg => _p.selectedBg;

  /// 歌词显示区背景（与侧栏形成轻微色差，便于感知区域大小）
  static Color get lyricsBg => _p.lyricsBg;

  /// 滚动条滑块颜色
  static Color get scrollbarThumb => _p.scrollbarThumb;

  /// 标题栏窗口按钮悬停背景
  static Color get windowBtnHover => _p.windowBtnHover;
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
    // 监听字号等级（全局等比缩放）：切换时 MaterialApp 重建 + Transform 更新。
    // 字号与配色两层 VLB 嵌套，互不干扰（换肤只改色、字号只改缩放）。
    return ValueListenableBuilder<FontSizeLevel>(
      valueListenable: FontScaleController.instance.notifier,
      builder: (context, level, _) {
        // 监听调色板切换（换肤）：切换时整棵 MaterialApp 重建，所有 AppColors 引用自动跟随
        return ValueListenableBuilder<AppPalette>(
          valueListenable: ThemeController.instance.notifier,
          builder: (context, palette, _) {
            // 按配色明暗选择基础主题：暗夜墨用 dark（Dialog/输入框等 Material
            // 组件自动深底浅字），其余用 light；再叠加自绘调色板语义色。
            final base = palette.brightness == Brightness.dark
                ? ThemeData.dark(useMaterial3: true)
                : ThemeData.light(useMaterial3: true);
            final theme = base.copyWith(
              colorScheme: ColorScheme.fromSeed(
                seedColor: palette.primary,
                brightness: palette.brightness,
              ),
              scaffoldBackgroundColor: palette.pageBg,
              appBarTheme: AppBarTheme(
                backgroundColor: palette.cardBg,
                foregroundColor: palette.textPrimary,
                elevation: 0.5,
                titleTextStyle: TextStyle(
                  color: palette.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              dividerColor: palette.divider,
              // 内置字体 EchoSans（Noto Sans SC 子集，真 400/500/700 字面）：
              // apply 写入整个 textTheme，Material 组件与未显式指定 family 的
              // 手工 TextStyle（DefaultTextStyle 继承）全覆盖——w500 命中实体
              // Medium，根治中间字重合成/系统字体逐字混排不均，且不依赖目标机器
              textTheme: base.textTheme.apply(
                fontFamily: 'EchoSans',
                bodyColor: palette.textPrimary,
                displayColor: palette.textPrimary,
              ),
              cardTheme: CardThemeData(
                color: palette.cardBg,
                elevation: 0,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.all(Radius.circular(8)),
                ),
              ),
              // 全局滚动条：宽度 10px，滑块色随配色
              scrollbarTheme: ScrollbarThemeData(
                thickness: const WidgetStatePropertyAll(10),
                thumbColor: WidgetStatePropertyAll(palette.scrollbarThumb),
              ),
            );

            LogService.instance.info(
              LogTag.ui,
              'MaterialApp 构建完成（主题: ${palette.name}）',
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
                // 全局等比缩放（字号等级 v1.5.0）：
                // builder 包住整棵 Navigator（含弹窗/菜单/Toast），按字号系数缩放——
                // 所有控件尺寸/位置/字号/图标等比例放大，最小客户区 850×890 不变。
                // 画布缩小 1/s 再渲染放大 s，视觉尺寸恒等于窗口尺寸；
                // 结构沿用 v1.2.x 已验证的等比缩放模式（Align→Transform→SizedBox，
                // 命中测试在逆变换后做尺寸检查，全区域可点击）。
                builder: (context, child) {
                  final s = AppFonts.scale;
                  if (child == null) return const SizedBox.shrink();
                  return LayoutBuilder(
                    builder: (context, constraints) {
                      final w = constraints.maxWidth;
                      final h = constraints.maxHeight;
                      return Align(
                        alignment: Alignment.center,
                        child: Transform.scale(
                          scale: s,
                          alignment: Alignment.center,
                          child: SizedBox(
                            width: w / s,
                            height: h / s,
                            child: child,
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            );
          },
        );
      },
    );
  }
}
