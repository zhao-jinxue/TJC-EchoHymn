import 'package:audio_service/audio_service.dart';

import 'audio_service.dart' as app;
import 'log_service.dart';

/// 全局媒体会话实例（仅 Android 非空；`main()` 里初始化）
EchoHymnAudioHandler? kMediaHandler;

/// 媒体会话 / 通知栏 / 锁屏控制（`ANDROID_PLAN §6` **D-2**）
///
/// 架构选择（**App 主导，最小侵入**）：播放逻辑仍在 [app.AudioService]，
/// 本类只是系统侧的「门面」——
/// - **系统 → App**：通知栏/锁屏/蓝牙的播放·暂停·上一首·下一首·seek 转发给 `AudioService`
/// - **App → 系统**：`AudioService` 在切歌/状态/进度变化时调用 [pushItem] / [pushState]
///
/// 这样 UI 层与播放内核**零改动**，也不需要在两个地方维护播放状态。
class EchoHymnAudioHandler extends BaseAudioHandler {
  EchoHymnAudioHandler();

  app.AudioService? _audio;

  /// 关联播放服务（`HomeScreen._init` 创建 AudioService 后调用）
  void attach(app.AudioService audio) {
    _audio = audio;
    LogService.instance.info(LogTag.play, '媒体会话已关联播放服务');
  }

  // ============ 系统 → App ============

  @override
  Future<void> play() async {
    final a = _audio;
    if (a == null) return;
    LogService.instance.info(LogTag.action, '通知栏/媒体键：播放');
    if (!a.isPlaying) await a.togglePlayPause();
  }

  @override
  Future<void> pause() async {
    final a = _audio;
    if (a == null) return;
    LogService.instance.info(LogTag.action, '通知栏/媒体键：暂停');
    if (a.isPlaying) await a.togglePlayPause();
  }

  @override
  Future<void> skipToNext() async {
    LogService.instance.info(LogTag.action, '通知栏/媒体键：下一首');
    await _audio?.playNext();
  }

  @override
  Future<void> skipToPrevious() async {
    LogService.instance.info(LogTag.action, '通知栏/媒体键：上一首');
    await _audio?.playPrev();
  }

  @override
  Future<void> seek(Duration position) async {
    LogService.instance.info(LogTag.action, '通知栏：跳转播放位置',
        detail: '→ ${(position.inMilliseconds / 1000).toStringAsFixed(1)} 秒');
    await _audio?.seek(position);
  }

  @override
  Future<void> stop() async {
    LogService.instance.info(LogTag.action, '通知栏：停止（结束前台服务）');
    await _audio?.stop();
    await super.stop();
  }

  // ============ App → 系统 ============

  /// 推送当前曲目（通知栏标题 / 锁屏 / 蓝牙显示）
  void pushItem({
    required String id,
    required String title,
    required String artist,
    Duration? duration,
  }) {
    mediaItem.add(MediaItem(
      id: id,
      title: title,
      artist: artist,
      duration: duration,
    ));
  }

  /// 推送播放状态与进度（通知栏播放键 / 进度条）
  void pushState({required bool playing, required Duration position}) {
    playbackState.add(PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        playing ? MediaControl.pause : MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: const {MediaAction.seek},
      androidCompactActionIndices: const [0, 1, 2],
      processingState: AudioProcessingState.ready,
      playing: playing,
      updatePosition: position,
    ));
  }
}
