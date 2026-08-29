import 'dart:async';

import 'package:audioplayers/audioplayers.dart';

import '../models/hymn.dart';
import 'app_paths.dart';
import 'log_service.dart';

/// 播放器状态
enum PlayerStatus { idle, loading, playing, paused, error }

/// 音频播放服务：封装 audioplayers
///
/// 用 `DeviceFileSource(path)` 直传本地文件路径（不经 URI 编码），
/// 根治中文/繁体路径经 `Uri.file` 编码导致的「Loading interrupted」问题。
/// 走 Windows Media Foundation 系统解码器（m4a/mp3 原生支持），零外部下载。
class AudioService {
  /// 全局唯一实例引用（供全局快捷键等场景使用；由 HomeScreen 创建后赋值，
  /// dispose 时清空）。与 LogService.instance 同一风格。
  static AudioService? instance;

  final AudioPlayer _player = AudioPlayer();
  final StreamController<PlayerStatus> _statusCtrl =
      StreamController<PlayerStatus>.broadcast();
  final StreamController<Duration> _positionCtrl =
      StreamController<Duration>.broadcast();
  final StreamController<Duration> _durationCtrl =
      StreamController<Duration>.broadcast();

  Hymn? _currentHymn;
  String _currentAudioVersion = '鋼琴版'; // 记忆版本（用户偏好，切歌选版本用）
  String _actualAudioVersion = '鋼琴版'; // 实际播放版本（UI 高亮用，含降级场景）
  bool _disposed = false;
  String? lastError; // 最近一次播放错误（Toast 展示用）

  // 音量 / 静音（快捷键控制，默认 100%）
  double _volume = 1.0;
  bool _muted = false;

  /// 上一次「上一首/下一首」切换时间（K17 快速连点防抖）
  DateTime _lastSwitchAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// 当前歌曲变化回调（播放新歌/加载恢复歌时触发，供上层保存状态）
  void Function()? onCurrentChanged;

  /// 播放列表（当前上下文：诗歌列表 / 默认歌单 / 个人歌单）
  List<Hymn> _playlist = const [];
  int _currentIndex = -1;

  AudioService() {
    instance = this;
    LogService.instance
        .info(LogTag.lib, '音频播放库加载完成（audioplayers / Windows Media Foundation）');
    _init();
  }

  Future<void> _init() async {
    // 时长 / 进度
    _player.onDurationChanged.listen((d) {
      if (!_durationCtrl.isClosed) _durationCtrl.add(d);
    });
    _player.onPositionChanged.listen((p) {
      if (!_positionCtrl.isClosed) _positionCtrl.add(p);
    });

    // 状态
    _player.onPlayerStateChanged.listen((state) {
      switch (state) {
        case PlayerState.playing:
          _emitStatus(PlayerStatus.playing);
          break;
        case PlayerState.paused:
        case PlayerState.stopped:
        case PlayerState.completed:
          _emitStatus(PlayerStatus.paused);
          break;
        case PlayerState.disposed:
          break;
      }
    });

    // 播放完成 → 自动下一首（唯一通道，避免与状态流双触发）
    _player.onPlayerComplete.listen((_) {
      playNext();
    });
  }

  // ---- 对外接口 ----

  Stream<PlayerStatus> get statusStream => _statusCtrl.stream;
  Stream<Duration> get positionStream => _positionCtrl.stream;
  Stream<Duration> get durationStream => _durationCtrl.stream;

  Hymn? get currentHymn => _currentHymn;

  /// 当前**实际播放**的音频版本（UI 版本栏高亮用；降级场景显示实际版本，C14）
  String get currentAudioVersion => _actualAudioVersion;

  /// 用户**记忆**的音频版本（切歌选版本用；降级不覆盖记忆）
  String get preferredAudioVersion => _currentAudioVersion;

  int get currentIndex => _currentIndex;
  bool get isPlaying => _player.state == PlayerState.playing;

  /// 当前播放列表（用于 UI 显示）
  List<Hymn> get playlist => _playlist;

  /// 当前可用的音频版本（按数据库 audio_version_list）
  List<String> availableVersions(Hymn hymn) {
    if (hymn.audioVersionList.isNotEmpty) return hymn.audioVersionList;
    if (hymn.audioVersions.isNotEmpty) return hymn.audioVersions.keys.toList();
    return const [];
  }

  void setPlaylist(List<Hymn> hymns, {int? startIndex}) {
    _playlist = hymns;
    if (startIndex != null && startIndex >= 0 && startIndex < hymns.length) {
      _currentIndex = startIndex;
    }
  }

  /// 仅加载诗歌（设置当前歌曲与上下文，**不播放**，进度条从 0 开始）。
  /// 用于应用重启后恢复上次状态但静默待播。
  /// [version] 指定音频版本（同时记忆为当前版本，供版本栏高亮）。
  Future<void> loadHymn(Hymn hymn, {int? index, String? version}) async {
    _currentHymn = hymn;
    if (index != null) _currentIndex = index;
    if (version != null) {
      _currentAudioVersion = version;
      _actualAudioVersion = version;
    }
    onCurrentChanged?.call();
    await _player.stop(); // 停止旧源，确保进度归零
    _emitStatus(PlayerStatus.idle);
    LogService.instance.info(
      LogTag.play,
      '加载诗歌（不播放）：第 ${hymn.hymnNumber} 首《${hymn.title}》',
      detail: '音频版本: $version / 列表位置: $index',
    );
  }

  /// 播放指定诗歌；[version] 指定音频版本（缺省用当前版本或默认）
  Future<void> playHymn(Hymn hymn, {int? index, String? version}) async {
    _currentHymn = hymn;
    if (index != null) _currentIndex = index;
    onCurrentChanged?.call();

    // 选择音频版本：
    // - 请求/记忆版本可用 → 使用并记忆（用户显式切换或记忆版本可用）
    // - 当前歌无该版本 → 临时用第一个可用版本（不覆盖记忆版本）
    //   （C14：记忆「人声版」播放中遇到无人声版歌自动降级钢琴，
    //    再遇到有人声版歌时仍能用记忆版本人声版播放）
    // 实际播放版本始终记录在 _actualAudioVersion，供 UI 高亮（含降级场景）。
    var audioVersion = version ?? _currentAudioVersion;
    if (hymn.audioVersions.containsKey(audioVersion)) {
      _currentAudioVersion = audioVersion;
      _actualAudioVersion = audioVersion;
    } else if (hymn.audioVersionList.isNotEmpty) {
      audioVersion = hymn.audioVersionList.first;
      _actualAudioVersion = audioVersion;
    }

    final rel = hymn.audioVersions[audioVersion];
    if (rel == null || rel.isEmpty) {
      lastError = '无音频文件';
      _emitStatus(PlayerStatus.error);
      LogService.instance.error(
        LogTag.play,
        '播放失败：第 ${hymn.hymnNumber} 首《${hymn.title}》无音频文件',
        detail: '当前音频版本: $audioVersion / 可用版本: ${hymn.audioVersionList}',
      );
      return;
    }
    final abs = AppPaths.resolveAsset(rel);
    if (abs.isEmpty) {
      lastError = '音频路径为空';
      _emitStatus(PlayerStatus.error);
      LogService.instance.error(
        LogTag.play,
        '播放失败：第 ${hymn.hymnNumber} 首《${hymn.title}》音频路径为空',
        detail: '音频版本: $audioVersion / 相对路径: $rel',
      );
      return;
    }

    LogService.instance.info(
      LogTag.play,
      '播放诗歌：第 ${hymn.hymnNumber} 首《${hymn.title}》',
      detail: '音频版本: $audioVersion\n文件路径: $abs',
    );
    _emitStatus(PlayerStatus.loading);
    try {
      await _player.stop(); // 先停止旧源，避免资源占用
      if (abs.startsWith('http://') || abs.startsWith('https://')) {
        await _player.play(UrlSource(abs));
      } else {
        await _player.play(DeviceFileSource(abs));
      }
      lastError = null;
      _emitStatus(PlayerStatus.playing);
      LogService.instance.info(
        LogTag.play,
        '播放成功：第 ${hymn.hymnNumber} 首《${hymn.title}》',
        detail: '音频版本: $audioVersion',
      );
    } catch (e) {
      lastError = e.toString();
      _emitStatus(PlayerStatus.error);
      LogService.instance.error(
        LogTag.play,
        '播放异常：第 ${hymn.hymnNumber} 首《${hymn.title}》',
        detail: '音频版本: $audioVersion\n文件路径: $abs\n异常: $e',
      );
    }
  }

  /// 切换当前诗歌的音频版本（不改变歌曲）
  Future<void> switchAudioVersion(String version) async {
    final h = _currentHymn;
    if (h == null) return;
    await playHymn(h, index: _currentIndex, version: version);
  }

  Future<void> playAt(int index) async {
    // K17：快速连续点击「上一首/下一首」防抖（250ms），避免并发播放操作错乱
    final now = DateTime.now();
    if (now.difference(_lastSwitchAt) < const Duration(milliseconds: 250)) {
      return;
    }
    _lastSwitchAt = now;
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
    final h = _currentHymn!;
    if (_player.state == PlayerState.playing) {
      await _player.pause();
      LogService.instance
          .info(LogTag.play, '暂停播放：第 ${h.hymnNumber} 首《${h.title}》');
    } else {
      // stop/completed 状态 resume 无效 → 需重新加载当前源
      if (_player.state == PlayerState.stopped ||
          _player.state == PlayerState.completed) {
        LogService.instance
            .info(LogTag.play, '重新播放：第 ${h.hymnNumber} 首《${h.title}》');
        await playHymn(h, index: _currentIndex);
      } else {
        await _player.resume();
        LogService.instance
            .info(LogTag.play, '继续播放：第 ${h.hymnNumber} 首《${h.title}》');
      }
    }
  }

  /// 当前列表内循环切换：下一首
  Future<void> playNext() async {
    if (_playlist.isEmpty) return;
    final next = _currentIndex < 0 ? 0 : (_currentIndex + 1) % _playlist.length;
    LogService.instance
        .info(LogTag.play, '切换下一首 → 列表位置 $next/${_playlist.length - 1}');
    await playAt(next);
  }

  /// 当前列表内循环切换：上一首
  Future<void> playPrev() async {
    if (_playlist.isEmpty) return;
    final prev = _currentIndex < 0
        ? 0
        : (_currentIndex - 1 + _playlist.length) % _playlist.length;
    LogService.instance
        .info(LogTag.play, '切换上一首 → 列表位置 $prev/${_playlist.length - 1}');
    await playAt(prev);
  }

  Future<void> seek(Duration position) async {
    await _player.seek(position);
  }

  /// 音量 / 静音状态（快捷键控制用）
  double get volume => _volume;
  bool get muted => _muted;

  /// 绝对设置音量（0.0~1.0）；静音时保持记忆音量
  Future<void> setVolume(double volume) async {
    _volume = volume.clamp(0.0, 1.0);
    await _player.setVolume(_muted ? 0 : _volume);
    LogService.instance
        .info(LogTag.play, '音量设置为 ${(_volume * 100).round()}%');
  }

  /// 相对调节音量（快捷键 Ctrl+↑/↓ 使用）
  Future<void> changeVolume(double delta) => setVolume(_volume + delta);

  /// 静音 / 取消静音切换（快捷键 Ctrl+M 使用）
  Future<void> toggleMute() async {
    _muted = !_muted;
    await _player.setVolume(_muted ? 0 : _volume);
    LogService.instance.info(LogTag.play,
        _muted ? '静音开启' : '静音取消（音量 ${(_volume * 100).round()}%）');
  }

  Future<void> stop() async {
    await _player.stop();
    _emitStatus(PlayerStatus.idle);
    final h = _currentHymn;
    if (h != null) {
      LogService.instance
          .info(LogTag.play, '停止播放：第 ${h.hymnNumber} 首《${h.title}》');
    }
  }

  void _emitStatus(PlayerStatus status) {
    if (!_statusCtrl.isClosed) _statusCtrl.add(status);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    if (instance == this) instance = null;
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
