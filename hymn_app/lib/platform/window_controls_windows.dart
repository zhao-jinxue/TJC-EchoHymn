import 'package:flutter/services.dart';

import '../services/log_service.dart';
import 'window_controls.dart';

/// Windows 实现：走原生 `echo_hymn/window` 通道
/// （由 `windows/runner/flutter_window.cpp` 注册）。
///
/// 所有调用**内部吞掉异常**（窗口能力失败不应中断业务）。
class WindowsWindowControls implements WindowControls {
  static const MethodChannel _channel = MethodChannel('echo_hymn/window');

  void Function(bool zoomed)? _onMaximized;

  @override
  bool get isSupported => true;

  @override
  void listenMaximizedChanged(void Function(bool zoomed) onChanged) {
    _onMaximized = onChanged;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onWindowMaximizedChanged') {
        final zoomed = call.arguments is bool && call.arguments as bool;
        _onMaximized?.call(zoomed);
      }
    });
  }

  @override
  void disposeListener() {
    _onMaximized = null;
    _channel.setMethodCallHandler(null);
  }

  Future<void> _invoke(String method, [Map<String, dynamic>? args]) async {
    try {
      await _channel.invokeMethod<void>(method, args);
    } catch (e) {
      LogService.instance
          .warning(LogTag.error, '窗口通道调用失败：$method', detail: '$e');
    }
  }

  @override
  Future<void> setClientSize({
    required int width,
    required int height,
    int leftPanelWidth = 0,
    int rightPanelWidth = 0,
  }) =>
      _invoke('setClientSize', {
        'width': width,
        'height': height,
        'leftPanelWidth': leftPanelWidth,
        'rightPanelWidth': rightPanelWidth,
      });

  @override
  Future<void> setWindowAppearance({
    required bool isDark,
    required int borderColor,
  }) =>
      _invoke('setWindowAppearance', {
        'isDark': isDark,
        'borderColor': borderColor,
      });

  @override
  Future<void> minimize() => _invoke('minimize');

  @override
  Future<void> maximizeToggle() => _invoke('maximizeToggle');

  @override
  Future<void> close() => _invoke('close');

  @override
  Future<void> hideToTray() => _invoke('hideToTray');

  @override
  Future<void> startWindowDrag() => _invoke('startWindowDrag');

  @override
  Future<SystemVolumeSnapshot?> getSystemVolume() async {
    try {
      final r =
          await _channel.invokeMethod<Map<dynamic, dynamic>>('getSystemVolume');
      if (r == null) return null;
      final v = (r['volume'] as num?)?.toDouble();
      if (v == null) return null;
      return SystemVolumeSnapshot(
        volume: v.clamp(0.0, 1.0),
        muted: r['muted'] as bool? ?? false,
      );
    } catch (_) {
      // 通道不可用：交由上层走应用增益模式
      return null;
    }
  }

  @override
  Future<void> setSystemVolume({
    required double volume,
    required bool muted,
  }) =>
      _invoke('setSystemVolume', {'volume': volume, 'muted': muted});
}
