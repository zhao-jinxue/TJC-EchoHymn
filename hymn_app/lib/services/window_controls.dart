import 'dart:io' show Platform;

import 'window_controls_stub.dart';
import 'window_controls_windows.dart';

/// 系统音量快照（桌面 Core Audio 通道返回值）
class SystemVolumeSnapshot {
  final double volume;
  final bool muted;

  const SystemVolumeSnapshot({required this.volume, required this.muted});
}

/// 桌面窗口能力抽象（Windows 实现 / 其它平台空实现）
///
/// 背景（Android 阶段 A2）：原实现把 `MethodChannel('echo_hymn/window')`
/// 直接写在 `home_screen.dart` 与 `audio_service.dart` 里，Android 上无原生
/// 实现 → 调用即抛 `MissingPluginException`。本抽象把平台差异收敛到一处：
/// - Windows：走 MethodChannel（`windows/runner/flutter_window.cpp` 注册）
/// - Android / 其它：`NoopWindowControls`（空实现，`isSupported == false`）
///
/// 约定：**调用方不需要 try/catch 兜底**（Noop 不抛异常；Windows 实现内部吞掉异常）。
abstract class WindowControls {
  /// 全局唯一实现（按平台一次性选择）
  static final WindowControls instance = _create();

  static WindowControls _create() =>
      Platform.isWindows ? WindowsWindowControls() : const NoopWindowControls();

  /// 是否具备桌面窗口能力（Android 恒 false）
  bool get isSupported;

  /// 注册 native 推送：最大化/还原状态变化
  void listenMaximizedChanged(void Function(bool zoomed) onChanged);

  /// 注销推送（页面销毁时调用，防止闭包滞留）
  void disposeListener();

  /// 窗口客户区尺寸（展开/收起侧栏时调用；Android 空实现）
  Future<void> setClientSize({
    required int width,
    required int height,
    int leftPanelWidth = 0,
    int rightPanelWidth = 0,
  });

  /// 窗口外观（深色标题栏 + 边框色；Android 空实现）
  Future<void> setWindowAppearance({
    required bool isDark,
    required int borderColor,
  });

  Future<void> minimize();
  Future<void> maximizeToggle();
  Future<void> close();
  Future<void> hideToTray();
  Future<void> startWindowDrag();

  /// 读取系统音量；返回 `null` 表示平台无此能力（调用方走应用增益模式）
  Future<SystemVolumeSnapshot?> getSystemVolume();

  /// 写回系统音量（Android 空实现）
  Future<void> setSystemVolume({
    required double volume,
    required bool muted,
  });
}
