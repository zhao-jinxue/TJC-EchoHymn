import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';

import '../models/hymn.dart';

/// 播放器状态
enum PlayerStatus { idle, loading, playing, paused, error }

/// 音频播放服务：封装 just_audio
class AudioService {
  final AudioPlayer _player = AudioPlayer();
  final StreamController<PlayerStatus> _statusCtrl =
      StreamController<PlayerStatus>.broadcast();
  final StreamController<Duration> _positionCtrl =
      StreamController<Duration>.broadcast();
  final StreamController<Duration> _durationCtrl =
      StreamController<Duration>.broadcast();

  Hymn? _currentHymn;
  bool _disposed = false;

  /// 播放列表（全部诗歌，用于上一首/下一首）
  List<Hymn> _playlist = const [];
  int _currentIndex = -1;

  AudioService() {
    _init();
  }

  Future<void> _init() async {
    // 音频会话（移动端后台/锁屏控制友好）
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
    } catch (_) {}

    _player.playbackEventStream
        .where((event) => event.processingState != ProcessingState.idle)
        .listen((event) {
      switch (event.processingState) {
        case ProcessingState.ready:
        case ProcessingState.completed:
          _emitStatus(
              _player.playing ? PlayerStatus.playing : PlayerStatus.paused);
          break;
        case ProcessingState.buffering:
        case ProcessingState.loading:
          _emitStatus(PlayerStatus.loading);
          break;
        case ProcessingState.idle:
          break;
      }
    });

    _player.positionStream.listen((pos) {
      if (!_positionCtrl.isClosed) _positionCtrl.add(pos);
    });

    _player.durationStream.listen((dur) {
      if (!_durationCtrl.isClosed) _durationCtrl.add(dur ?? Duration.zero);
    });

    _player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) {
        playNext();
      }
    });
  }

  // ---- 对外接口 ----

  Stream<PlayerStatus> get statusStream => _statusCtrl.stream;
  Stream<Duration> get positionStream => _positionCtrl.stream;
  Stream<Duration> get durationStream => _durationCtrl.stream;

  Hymn? get currentHymn => _currentHymn;
  int get currentIndex => _currentIndex;
  bool get isPlaying => _player.playing;

  void setPlaylist(List<Hymn> hymns, {int? startIndex}) {
    _playlist = hymns;
    if (startIndex != null && startIndex >= 0 && startIndex < hymns.length) {
      _currentIndex = startIndex;
    }
  }

  Future<void> playHymn(Hymn hymn, {int? index}) async {
    _currentHymn = hymn;
    if (index != null) _currentIndex = index;
    _emitStatus(PlayerStatus.loading);
    try {
      await _player.setUrl(hymn.audio);
      await _player.play();
      _emitStatus(PlayerStatus.playing);
    } catch (e) {
      _emitStatus(PlayerStatus.error);
      rethrow;
    }
  }

  Future<void> playAt(int index) async {
    if (index < 0 || index >= _playlist.length) return;
    await playHymn(_playlist[index], index: index);
  }

  Future<void> togglePlayPause() async {
    if (_currentHymn == null) {
      if (_playlist.isNotEmpty) {
        await playAt(0);
      }
      return;
    }
    if (_player.playing) {
      await _player.pause();
    } else {
      await _player.play();
    }
  }

  Future<void> playNext() async {
    if (_playlist.isEmpty) return;
    final next = _currentIndex < 0 ? 0 : (_currentIndex + 1) % _playlist.length;
    await playAt(next);
  }

  Future<void> playPrev() async {
    if (_playlist.isEmpty) return;
    final prev = _currentIndex < 0
        ? 0
        : (_currentIndex - 1 + _playlist.length) % _playlist.length;
    await playAt(prev);
  }

  Future<void> seek(Duration position) async {
    await _player.seek(position);
  }

  Future<void> setVolume(double volume) async {
    await _player.setVolume(volume.clamp(0.0, 1.0));
  }

  Future<void> stop() async {
    await _player.stop();
    _emitStatus(PlayerStatus.idle);
  }

  void _emitStatus(PlayerStatus status) {
    if (!_statusCtrl.isClosed) _statusCtrl.add(status);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _player.dispose();
    await _statusCtrl.close();
    await _positionCtrl.close();
    await _durationCtrl.close();
  }
}

/// 格式化时间 mm:ss
String formatTime(Duration d) {
  final m = d.inMinutes;
  final s = d.inSeconds % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}
