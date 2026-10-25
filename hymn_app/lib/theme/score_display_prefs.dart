import 'package:flutter/foundation.dart';

/// 深色主题下**扫描谱面**的显示方式（`ANDROID_PLAN §3.10` 定稿）
///
/// 扫描简谱 / 五线谱是**白底图**，暗色主题下不改会夜间刺眼：
/// - `dim`（**默认**）：原色 + **20% 黑遮罩** —— 保留白底可读性、只降亮度
///   （反色会丢印刷谱细节，不采用；强制浅色违背用户选择）
/// - `original`：原色（不处理）
/// - `invert`：反色（**实验性**，供用户自行对比）
///
/// 曲谱网格（`JianpuGridView`）不受影响 —— 它自绘且取 `AppColors` 语义色。
class ScoreDisplayPrefs {
  ScoreDisplayPrefs._();

  static final ScoreDisplayPrefs instance = ScoreDisplayPrefs._();

  /// 可选值（与设置页 chips 顺序一致）
  static const List<String> modes = ['dim', 'original', 'invert'];

  static const String defaultMode = 'dim';

  /// 中文标签（设置页 chips）
  static String labelOf(String mode) => switch (mode) {
        'original' => '原色',
        'invert' => '反色',
        _ => '暗化',
      };

  final ValueNotifier<String> modeNotifier = ValueNotifier<String>(defaultMode);

  String get mode => modeNotifier.value;

  /// 启动恢复（state.json 的 `scoreDarkMode`）
  void restoreFrom(String? value) {
    modeNotifier.value =
        (value != null && modes.contains(value)) ? value : defaultMode;
  }

  void set(String value) {
    if (!modes.contains(value) || value == modeNotifier.value) return;
    modeNotifier.value = value;
  }

  /// 20% 黑遮罩透明度（`image.dim` 令牌）
  static const double dimAlpha = 0.20;
}
