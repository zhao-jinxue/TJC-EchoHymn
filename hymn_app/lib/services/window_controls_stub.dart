import 'window_controls.dart';

/// Android / 其它非桌面平台的空实现
///
/// 所有方法为空操作；`getSystemVolume()` 返回 null（音量走应用增益模式）。
/// 这样上层无需 `try/catch`，也不会触发 `MissingPluginException`。
class NoopWindowControls implements WindowControls {
  const NoopWindowControls();

  @override
  bool get isSupported => false;

  @override
  void listenMaximizedChanged(void Function(bool zoomed) onChanged) {}

  @override
  void disposeListener() {}

  @override
  Future<void> setClientSize({
    required int width,
    required int height,
    int leftPanelWidth = 0,
    int rightPanelWidth = 0,
  }) async {}

  @override
  Future<void> setWindowAppearance({
    required bool isDark,
    required int borderColor,
  }) async {}

  @override
  Future<void> minimize() async {}

  @override
  Future<void> maximizeToggle() async {}

  @override
  Future<void> close() async {}

  @override
  Future<void> hideToTray() async {}

  @override
  Future<void> startWindowDrag() async {}

  @override
  Future<SystemVolumeSnapshot?> getSystemVolume() async => null;

  @override
  Future<void> setSystemVolume({
    required double volume,
    required bool muted,
  }) async {}
}
