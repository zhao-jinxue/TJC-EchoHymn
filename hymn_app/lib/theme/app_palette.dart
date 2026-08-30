import 'package:flutter/material.dart';

/// 一套可换肤的调色板（语义色槽，非具体颜色）。
///
/// 换肤原理：界面所有颜色引用统一走 [AppColors]（lib/app.dart）——
/// 它读取「当前调色板」的各语义色槽。要新增/调整配色，
/// 只需在本文件改色值或追加一套 `AppPalette`，界面零改动。
class AppPalette {
  final String id; // 持久化标识（写入 state.json 的 appTheme 字段）
  final String name; // 中文显示名（换肤菜单展示）

  // 主色系
  final Color primary; // 主色（按钮/激活/进度条/logo）
  final Color primaryHover; // 主色悬停
  final Color accent; // 强调色（音量滑条/成功语义）

  // 背景系（分区极浅底色：白主调下用同色相极浅色区分各 UI 区域）
  final Color pageBg; // 内容区外层背景
  final Color cardBg; // 卡片/弹窗/按钮底色
  final Color titleBarBg; // 标题栏背景
  final Color topBarBg; // 顶栏背景
  final Color sidebarBg; // 左栏背景
  final Color rightPanelBg; // 右栏（源考）背景
  final Color versionBarBg; // 版本栏背景
  final Color playBarBg; // 播放条背景
  final Color statusBarBg; // 状态栏背景
  final Color lyricsBg; // 歌词显示区背景

  // 文字系
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;

  // 线框系
  final Color divider;
  final Color border;

  // 语义色
  final Color success;
  final Color warning;
  final Color danger;
  final Color selectedBg; // 列表选中背景

  // 细节
  final Color scrollbarThumb; // 滚动条滑块
  final Color windowBtnHover; // 标题栏按钮悬停背景

  const AppPalette({
    required this.id,
    required this.name,
    required this.primary,
    required this.primaryHover,
    required this.accent,
    required this.pageBg,
    required this.cardBg,
    required this.titleBarBg,
    required this.topBarBg,
    required this.sidebarBg,
    required this.rightPanelBg,
    required this.versionBarBg,
    required this.playBarBg,
    required this.statusBarBg,
    required this.lyricsBg,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.divider,
    required this.border,
    required this.success,
    required this.warning,
    required this.danger,
    required this.selectedBg,
    required this.scrollbarThumb,
    required this.windowBtnHover,
  });
}

/// ① 晨光蓝 · 经典（默认，白色主调 + 极浅蓝层次分区）
const kPaletteMorning = AppPalette(
  id: 'morningBlue',
  name: '晨光蓝 · 经典',
  primary: Color(0xFF2B6AE0),
  primaryHover: Color(0xFF1E57C8),
  accent: Color(0xFF00A870),
  pageBg: Color(0xFFFAFBFC),
  cardBg: Color(0xFFFFFFFF),
  titleBarBg: Color(0xFFFFFFFF),
  topBarBg: Color(0xFFF5F8FF),
  sidebarBg: Color(0xFFEBF1FA),
  rightPanelBg: Color(0xFFF1F4FA),
  versionBarBg: Color(0xFFE4EFFC),
  playBarBg: Color(0xFFFBFCFE),
  statusBarBg: Color(0xFFF2F5FA),
  lyricsBg: Color(0xFFF2F6FD),
  textPrimary: Color(0xFF1F2329),
  textSecondary: Color(0xFF646A73),
  textTertiary: Color(0xFF8F959E),
  divider: Color(0xFFE5E6EB),
  border: Color(0xFFD0D3D9),
  success: Color(0xFF00A870),
  warning: Color(0xFFFF9F0A),
  danger: Color(0xFFF54A45),
  selectedBg: Color(0xFFE8F0FE),
  scrollbarThumb: Color(0xFFC1C1C1),
  windowBtnHover: Color(0xFFE5E6EB),
);

/// ② 暖阳金 · 圣堂：复古圣殿风，暖奶油纸感 + 圣金黄 + 深橄榄绿点缀
const kPaletteWarmGold = AppPalette(
  id: 'warmGold',
  name: '暖阳金 · 圣堂',
  primary: Color(0xFFC68A1B),
  primaryHover: Color(0xFFA8730F),
  accent: Color(0xFF5B8C5A),
  pageBg: Color(0xFFFDFBF6),
  cardBg: Color(0xFFFFFFFF),
  titleBarBg: Color(0xFFFFFFFF),
  topBarBg: Color(0xFFFBF6EA),
  sidebarBg: Color(0xFFF6EFDD),
  rightPanelBg: Color(0xFFF8F2E5),
  versionBarBg: Color(0xFFF0E7CE),
  playBarBg: Color(0xFFFCFAF4),
  statusBarBg: Color(0xFFF8F4EA),
  lyricsBg: Color(0xFFFCF4E0),
  textPrimary: Color(0xFF3A3124),
  textSecondary: Color(0xFF6B6152),
  textTertiary: Color(0xFF97896F),
  divider: Color(0xFFE9DFC8),
  border: Color(0xFFD6C9AE),
  success: Color(0xFF5B8C5A),
  warning: Color(0xFFD97A06),
  danger: Color(0xFFC0392B),
  selectedBg: Color(0xFFF5E7C3),
  scrollbarThumb: Color(0xFFCBBF9F),
  windowBtnHover: Color(0xFFEFE6CF),
);

/// ③ 静谧绿 · 草木：鼠尾草绿 + 薄荷白，自然安宁、长时间阅读护眼
const kPaletteCalmGreen = AppPalette(
  id: 'calmGreen',
  name: '静谧绿 · 草木',
  primary: Color(0xFF2F7D5A),
  primaryHover: Color(0xFF25654A),
  accent: Color(0xFF5BA37E),
  pageBg: Color(0xFFFBFFFC),
  cardBg: Color(0xFFFFFFFF),
  titleBarBg: Color(0xFFFFFFFF),
  topBarBg: Color(0xFFF2F8F4),
  sidebarBg: Color(0xFFEBF4EE),
  rightPanelBg: Color(0xFFEFF7F2),
  versionBarBg: Color(0xFFE3F0E7),
  playBarBg: Color(0xFFF7FBF8),
  statusBarBg: Color(0xFFF1F7F3),
  lyricsBg: Color(0xFFEEF8F2),
  textPrimary: Color(0xFF22322B),
  textSecondary: Color(0xFF5C6E65),
  textTertiary: Color(0xFF8A9A92),
  divider: Color(0xFFDEE8E1),
  border: Color(0xFFC9D6CE),
  success: Color(0xFF3E8F6A),
  warning: Color(0xFFD9840A),
  danger: Color(0xFFD04A44),
  selectedBg: Color(0xFFE1F0E7),
  scrollbarThumb: Color(0xFFB9C6BE),
  windowBtnHover: Color(0xFFE2EDE6),
);

/// ④ 典雅紫 · 暮云：紫罗兰 + 青碧强调，晚祷般的静谧与尊贵
const kPaletteElegantPurple = AppPalette(
  id: 'elegantPurple',
  name: '典雅紫 · 暮云',
  primary: Color(0xFF6E56CF),
  primaryHover: Color(0xFF5B46B3),
  accent: Color(0xFF1FA8A0),
  pageBg: Color(0xFFFBFAFD),
  cardBg: Color(0xFFFFFFFF),
  titleBarBg: Color(0xFFFFFFFF),
  topBarBg: Color(0xFFF4F1FB),
  sidebarBg: Color(0xFFEDE7F7),
  rightPanelBg: Color(0xFFF1EDF8),
  versionBarBg: Color(0xFFE5DFF4),
  playBarBg: Color(0xFFFAF8FD),
  statusBarBg: Color(0xFFF2EFF9),
  lyricsBg: Color(0xFFF1EBFA),
  textPrimary: Color(0xFF2E2A3C),
  textSecondary: Color(0xFF6A6480),
  textTertiary: Color(0xFF9790AC),
  divider: Color(0xFFE4DFEE),
  border: Color(0xFFCEC6DE),
  success: Color(0xFF17A094),
  warning: Color(0xFFE08B0C),
  danger: Color(0xFFD34D55),
  selectedBg: Color(0xFFECE5FA),
  scrollbarThumb: Color(0xFFC2BACD),
  windowBtnHover: Color(0xFFE9E3F2),
);

/// ⑤ 暗夜墨 · 深色：深空灰蓝底 + 明亮青蓝强调，夜读护眼（分区用相近深色层次）
const kPaletteMidnightDark = AppPalette(
  id: 'midnightDark',
  name: '暗夜墨 · 深色',
  primary: Color(0xFF4A8DF7),
  primaryHover: Color(0xFF3B75D4),
  accent: Color(0xFF22C3A6),
  pageBg: Color(0xFF171A21),
  cardBg: Color(0xFF1F232C),
  titleBarBg: Color(0xFF1E232D),
  topBarBg: Color(0xFF242B37),
  sidebarBg: Color(0xFF191D26),
  rightPanelBg: Color(0xFF1C212B),
  versionBarBg: Color(0xFF29303D),
  playBarBg: Color(0xFF1E232C),
  statusBarBg: Color(0xFF252B36),
  lyricsBg: Color(0xFF20252F),
  textPrimary: Color(0xFFE8EAED),
  textSecondary: Color(0xFFA9B0BC),
  textTertiary: Color(0xFF7D8595),
  divider: Color(0xFF2C313C),
  border: Color(0xFF3A4150),
  success: Color(0xFF2FC38A),
  warning: Color(0xFFE8A33D),
  danger: Color(0xFFE0564F),
  selectedBg: Color(0xFF26344A),
  scrollbarThumb: Color(0xFF4A5260),
  windowBtnHover: Color(0xFF2C313C),
);

/// 全部可用配色（第一个为默认「晨光蓝」）
const List<AppPalette> kThemes = [
  kPaletteMorning,
  kPaletteWarmGold,
  kPaletteCalmGreen,
  kPaletteElegantPurple,
  kPaletteMidnightDark,
];

/// 按 id 查找配色，找不到回退默认
AppPalette themeById(String? id) {
  return kThemes.firstWhere((t) => t.id == id, orElse: () => kThemes.first);
}

/// 全局主题控制器：持有当前调色板，切换时通知整棵 UI 树重建（换肤）。
class ThemeController {
  ThemeController._();

  static final ThemeController instance = ThemeController._();

  /// 当前调色板（ValueNotifier：MaterialApp 用 ValueListenableBuilder 监听重建）
  final ValueNotifier<AppPalette> notifier = ValueNotifier(kPaletteMorning);

  AppPalette get current => notifier.value;

  void switchTo(AppPalette palette) {
    if (palette.id == current.id) return;
    notifier.value = palette;
  }
}
