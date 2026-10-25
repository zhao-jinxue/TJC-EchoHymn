import 'dart:io';

import 'package:flutter/material.dart';

import '../services/log_service.dart';

/// 字号等级（写入 state.json 的 fontSizeLevel 字段）
///
/// **桌面系数**（2026-08-31 用户调整）：1.0 / 1.3 / 1.6 / 1.9 —— **保持不变**。
/// **移动端系数**（2026-10-25 用户要求）：三档、档间差异温和 —— 1.0 / 1.12 / 1.26
///（第 4 档 `xlarge` 手机不再显示，仅桌面用 1.40 作最大档）。
enum FontSizeLevel {
  normal('normal', '默认', 1.0, 1.0),
  medium('medium', '中号', 1.3, 1.12),
  large('large', '大号', 1.6, 1.26),
  xlarge('xlarge', '最大', 1.9, 1.40);

  const FontSizeLevel(this.id, this.label, this.scale, this.mobileScale);

  /// 持久化标识
  final String id;

  /// 中文显示名（字号切换菜单展示）
  final String label;

  /// **桌面**全局等比缩放系数
  final double scale;

  /// **移动端**全局等比缩放系数（档间差异更温和，2026-10-25）
  final double mobileScale;

  /// 当前平台实际生效的系数
  double get activeScale =>
      (Platform.isAndroid || Platform.isIOS) ? mobileScale : scale;
}

/// 全局字号控制器：持有当前字号等级，切换时通知整棵 UI 树重建（全局等比缩放）。
///
/// 与换肤的 [ThemeController] 同构：界面各处读 [AppFonts] 取当前系数，
/// MaterialApp / HomeScreen 用 ValueListenableBuilder 监听重建。
class FontScaleController {
  FontScaleController._();

  static final FontScaleController instance = FontScaleController._();

  /// 当前字号等级（ValueNotifier：MaterialApp / HomeScreen 监听重建）
  final ValueNotifier<FontSizeLevel> notifier =
      ValueNotifier(FontSizeLevel.normal);

  FontSizeLevel get current => notifier.value;

  double get scale => current.activeScale;

  void switchTo(FontSizeLevel level) {
    if (level == current) return;
    LogService.instance
        .info(LogTag.action, '切换字号等级: ${level.label}（×${level.scale}）');
    notifier.value = level;
  }
}

/// 全局字号缩放门面。
///
/// 实现原理：MaterialApp 的 builder 用 `Transform.scale` 把整棵 Navigator
/// （含弹窗/菜单/Toast，覆盖全部 UI 区域）按 [scale] **等比缩放**——
/// 所有控件尺寸/位置/字号/图标天然等比例放大，无需逐个改动字号与尺寸常量，
/// 完美满足「字号变更 = 整树等比例放大各控件」的需求。
///
/// 歌词区例外：保持「铺满自适应字号」算法（以缩放后画布为基准计算），
/// 内部再乘 [lyricsScale] 让歌词随等级进一步放大——否则铺满算法会
/// 抵消缩放效果（画布变小 → 计算值变小 → ×缩放后不变）。
class AppFonts {
  static double get scale => FontScaleController.instance.scale;

  /// 歌词区系数（与全局一致；单独定义便于将来独立调校歌词缩放力度）
  static double get lyricsScale => scale;
}

/// 按 id 查找字号等级，找不到回退默认（state.json 容错）
FontSizeLevel fontSizeLevelById(String? id) {
  return FontSizeLevel.values.firstWhere(
    (l) => l.id == id,
    orElse: () => FontSizeLevel.normal,
  );
}
