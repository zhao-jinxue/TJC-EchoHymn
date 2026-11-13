import 'dart:async';

import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import '../models/hymn.dart';
import '../app_feature.dart';
import 'app_paths.dart';
import 'audio_handler.dart';
import 'log_service.dart';
import '../platform/window_controls.dart';

/// 桌面系统能力（系统音量通道；Android 空实现）

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
  /// 当前变体的**默认音频版本**（`ANDROID_PLAN §1.4` ④）
  ///
  /// - 全量版 / 钢琴版 → `鋼琴版`
  /// - **人声版 → `人聲版`**（此前硬编码 `鋼琴版`，会导致人声版包优先播鋼琴音频，属真实缺陷）
  /// - 读谱版（lite）无播放能力，取 `鋼琴版` 占位即可
  static String _variantDefaultVersion() => switch (kAudioVariant) {
        AudioVariant.vocal => '人聲版',
        _ => '鋼琴版',
      };

  String _currentAudioVersion = _variantDefaultVersion(); // 记忆版本（用户偏好，切歌选版本用）
  String _actualAudioVersion = _variantDefaultVersion(); // 实际播放版本（UI 高亮用，含降级场景）

  /// 媒体会话（Android 通知栏/锁屏）；桌面为 null（D-2）
  EchoHymnAudioHandler? _mediaHandler;

  /// 最近一次播放位置（媒体会话进度用）
  Duration _lastPosition = Duration.zero;

  /// 上次向媒体会话推送的毫秒时间戳（**节流 1s**，避免高频跨平台调用）
  int _lastPushMs = 0;
  bool _disposed = false;
  String? lastError; // 最近一次播放错误（Toast 展示用）

  // 音量 / 静音（默认 100%）
  double _volume = 1.0;
  bool _muted = false;

  /// 音量状态通知（**UI 与快捷键共用的唯一数据源**）：
  /// 播放条音量控件（图标/滑条/百分比）与全局快捷键（Ctrl+↑↓ / Ctrl+M）
  /// 都通过 AudioService 读写，任何一方改变都经此通知刷新对方，避免各调各的。
  final ValueNotifier<double> volumeNotifier = ValueNotifier<double>(1.0);
  final ValueNotifier<bool> mutedNotifier = ValueNotifier<bool>(false);

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
        .info(LogTag.lib, '音频播放库加载完成（audioplayers 6.x / 系统原生解码器）');
    _init();
  }

  /// 配置 Android 音频上下文（`ANDROID_PLAN §6` **D-1 音频焦点**）
  ///
  /// - `audioFocus: gain` → 来电 / 其他 App 播放时**系统要求本播放器让出焦点**，
  ///   `audioplayers` 的 Android 实现会自动暂停，恢复后由 App 的播放状态机续播；
  /// - `usageType: media` + `contentType: music` → 被系统识别为媒体音频
  ///   （音量键调"媒体音量"、通知栏分组正确、蓝牙路由按媒体音频选择）；
  /// - `stayAwake: true` → 息屏时不因屏幕锁定被静音（`AudioManager` 层面）。
  ///
  /// 桌面（Windows）无此概念，直接跳过。
  Future<void> _applyAndroidAudioContext() async {
    if (!Platform.isAndroid) return;
    try {
      await _player.setAudioContext(
        AudioContext(
          android: const AudioContextAndroid(
            isSpeakerphoneOn: false,
            audioMode: AndroidAudioMode.normal,
            stayAwake: true,
            contentType: AndroidContentType.music,
            usageType: AndroidUsageType.media,
            audioFocus: AndroidAudioFocus.gain,
          ),
        ),
      );
      LogService.instance.info(
        LogTag.play,
        '音频上下文已配置（Android）',
        detail: 'audioFocus=gain / usage=media / contentType=music / stayAwake=true',
      );
    } catch (e, st) {
      LogService.instance.exception('配置音频上下文失败', e, st);
    }
  }

  /// 关联媒体会话并立即推送一次当前状态（Android；桌面为 null 时无操作）
  void attachMediaHandler(EchoHymnAudioHandler handler) {
    _mediaHandler = handler;
    handler.attach(this);
    _pushMediaSession();
    LogService.instance.info(LogTag.play, '媒体会话已就绪（通知栏/锁屏可控）');
  }

  /// 把「当前曲目 + 播放状态 + 进度」推给系统（通知栏/锁屏/蓝牙）
  void _pushMediaSession() {
    final h = _mediaHandler;
    if (h == null) return;
    final hymn = _currentHymn;
    if (hymn != null) {
      h.pushItem(
        id: hymn.hymnNumber,
        title: hymn.title,
        artist: _actualAudioVersion,
        duration: null,
      );
    }
    h.pushState(playing: isPlaying, position: _lastPosition);
  }

  Future<void> _init() async {
    // D-1 音频焦点（ANDROID_PLAN §6）：先配置音频上下文，再挂事件监听
    await _applyAndroidAudioContext();
    // 时长 / 进度
    _player.onDurationChanged.listen((d) {
      if (!_durationCtrl.isClosed) _durationCtrl.add(d);
    });
    _player.onPositionChanged.listen((p) {
      if (!_positionCtrl.isClosed) _positionCtrl.add(p);
      _lastPosition = p;
      // 通知栏/锁屏进度：**最多每秒推一次**（避免高频跨平台调用）
      if (_mediaHandler != null) {
        final now = DateTime.now().millisecondsSinceEpoch;
        if (now - _lastPushMs >= 1000) {
          _lastPushMs = now;
          _pushMediaSession();
        }
      }
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

  /// 该首在 [version] 下**是否真有可播文件**（`ANDROID_PLAN §1.4` ⑤）
  ///
  /// 不能只看 `audioVersions.containsKey`：DB 里可能残留"有记录但文件未下载/未打包"的版本
  /// （实测第 `249` 首在钢琴版包里 DB 仍记着 `鋼琴版` 键，但文件不存在）——
  /// 那种情况下必须走**替代**，否则用户点播放只会得到「无音频文件」。
  bool _hasAudioFile(Hymn hymn, String version) {
    final rel = hymn.audioVersions[version];
    if (rel == null || rel.isEmpty) return false;
    final abs = AppPaths.resolveAsset(rel);
    if (abs.isEmpty) return false;
    try {
      return File(abs).existsSync();
    } catch (_) {
      return false;
    }
  }

  /// 替代候选顺序（`ANDROID_PLAN §1.4` ⑤）
  ///
  /// 单音频版缺本版音频时，优先挑**最接近本版音**的版本：
  /// - 人声版：`人聲版` > `四部合唱版` > `四部合唱-N部版` > 其它合唱 > 其它（鋼琴版垫底）
  /// - 钢琴版：`鋼琴版` > 含「人聲」的版本 > 其它
  ///
  /// **不能直接用 DB 的 `audio_version_list` 顺序**：人声版的该列表是
  /// `[鋼琴版, 四部合唱版, ...]`，取首个有文件的会落到鋼琴版 ——
  /// 而计划明确「人声版 `3`/`389` → 四部合唱版」（2026-11-11 实测发现的规则缺陷）。
  static List<String> substitutionOrder(Hymn hymn) {
    final all = <String>[
      if (hymn.audioVersionList.isNotEmpty) ...hymn.audioVersionList,
      ...hymn.audioVersions.keys,
    ];
    final unique = <String>[];
    for (final v in all) {
      if (!unique.contains(v)) unique.add(v);
    }
    int rank(String v) {
      if (kAudioVariant == AudioVariant.vocal) {
        if (v == '人聲版') return 0;
        if (v == '四部合唱版') return 1;
        if (v.startsWith('四部合唱')) return 2;
        if (v.contains('合唱')) return 3;
        if (v.contains('鋼琴')) return 9;
        return 5;
      }
      if (kAudioVariant == AudioVariant.piano) {
        if (v == '鋼琴版') return 0;
        if (v.contains('人聲')) return 1;
        return 5;
      }
      return 0;
    }

    unique.sort((a, b) => rank(a).compareTo(rank(b)));
    return unique;
  }

  /// 当前播放是否用了**替代音频**（`ANDROID_PLAN §1.4` ⑤）
  ///
  /// 单音频版全曲目可播靠「缺口互补替代」：钢琴版 1 首（`249` → 人聲版）、
  /// 人声版 11 首（`3`/`389` → 四部合唱；9 首 → 鋼琴版）。
  /// 判据：变体期望版本 ≠ 实际播放版本。
  bool get isSubstitutedVersion {
    if (!kSingleAudioVariant) return false;
    final expected =
        kAudioVariant == AudioVariant.piano ? '鋼琴版' : '人聲版';
    return _currentHymn != null && _actualAudioVersion != expected;
  }

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

  /// 播放列表下标钳制（v1.8.0 入参防御）：
  /// 仅接受落在 `[0, _playlist.length)` 的合法下标，越界/未设置时返回 `null`，
  /// 由调用方保持原 `_currentIndex` 不变——避免越界值污染当前索引
  /// （`playAt` 已守卫，但 `playHymn`/`loadHymn` 的 `index` 此前未校验）。
  int? _validIndex(int? index) {
    if (index == null) return null;
    if (index < 0 || index >= _playlist.length) return null;
    return index;
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
    final loadedIndex = _validIndex(index);
    if (loadedIndex != null) _currentIndex = loadedIndex;
    if (version != null) {
      _currentAudioVersion = version;
      _actualAudioVersion = version;
    } else {
      // 解析「实际会播放的版本」：记忆版本**真有文件** → 用它；否则找该首任一有文件的版本。
      // 这一步决定单音频版的**替代标记**是否准确（`249` 在钢琴版包里会落到人聲版）。
      final preferred = _currentAudioVersion;
      if (_hasAudioFile(hymn, preferred)) {
        _actualAudioVersion = preferred;
      }
      else {
        final candidates = AudioService.substitutionOrder(hymn);
        var found = '';
        for (final v in candidates) {
          if (v != preferred && _hasAudioFile(hymn, v)) {
            found = v;
            break;
          }
        }
        _actualAudioVersion = found.isNotEmpty ? found : preferred;
      }
    }
    onCurrentChanged?.call();
    await _player.stop(); // 停止旧源，确保进度归零
    _emitStatus(PlayerStatus.idle);
    LogService.instance.info(
      LogTag.play,
      '加载诗歌（不播放）：第 ${hymn.hymnNumber} 首《${hymn.title}》',
      detail: '音频版本: $_actualAudioVersion'
          '${isSubstitutedVersion ? '（替代：期望 ${_variantDefaultVersion()}）' : ''}'
          ' / 列表位置: $index',
    );
  }

  /// 播放指定诗歌；[version] 指定音频版本（缺省用当前版本或默认）
  Future<void> playHymn(Hymn hymn, {int? index, String? version}) async {
    _currentHymn = hymn;
    final playedIndex = _validIndex(index);
    if (playedIndex != null) _currentIndex = playedIndex;
    onCurrentChanged?.call();

    // 选择音频版本：
    // - 请求/记忆版本可用 → 使用并记忆（用户显式切换或记忆版本可用）
    // - 当前歌无该版本 → 临时用第一个可用版本（不覆盖记忆版本）
    //   （C14：记忆「人声版」播放中遇到无人声版歌自动降级钢琴，
    //    再遇到有人声版歌时仍能用记忆版本人声版播放）
    // 实际播放版本始终记录在 _actualAudioVersion，供 UI 高亮（含降级场景）。
    var audioVersion = version ?? _currentAudioVersion;
    if (_hasAudioFile(hymn, audioVersion)) {
      _currentAudioVersion = audioVersion;
      _actualAudioVersion = audioVersion;
    }
    else {
      // 缺口互补替代（§1.4 ⑤）：按候选顺序找**首个真有文件**的版本
      // （不能信 DB 的键：可能有记录但文件未打包，例如钢琴版包里的 `249`）
      final candidates = AudioService.substitutionOrder(hymn);
      var found = '';
      for (final v in candidates) {
        if (_hasAudioFile(hymn, v)) {
          found = v;
          break;
        }
      }
      if (found.isNotEmpty) {
        audioVersion = found;
        _actualAudioVersion = found;
        if (kSingleAudioVariant) {
          LogService.instance.info(
            LogTag.play,
            '替代音频：第 ${hymn.hymnNumber} 首《${hymn.title}》',
            detail: '期望 ${_variantDefaultVersion()} → 实际 $found',
          );
        }
      }
      else if (hymn.audioVersionList.isNotEmpty) {
        audioVersion = hymn.audioVersionList.first;
        _actualAudioVersion = audioVersion;
      }
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
    // 未加载音轨时拖动进度条（刚启动 / 未选曲）会走这里 —— 直接忽略。
    // audioplayers 在无 source 时 seek 会抛异常（C 阶段实机实测：日志出现异步异常栈，
    // 「谱面/进度条」类自动化点击很容易碰到，属真实缺陷而非测试噪声）。
    if (_currentHymn == null) return;
    try {
      await _player.seek(position);
    } catch (e, st) {
      LogService.instance.exception('跳转播放位置失败', e, st);
      return;
    }
    LogService.instance.info(
      LogTag.play,
      '跳转播放位置',
      detail: '→ ${(position.inMilliseconds / 1000).toStringAsFixed(1)} 秒',
    );
  }

  /// 音量 / 静音状态（快捷键控制用）
  ///
  /// **音量模型（2026-09-01 修复双重衰减）**：`_volume` 即**系统音量**，是唯一响度旋钮——
  /// 播放器增益恒 1.0（静音时 0），不再叠加 `_player.setVolume(_volume)`。
  /// 修复前系统音量与应用增益各乘一次（实际输出 = v²，如 50% 变 25%，
  /// 听感比系统默认播放器轻约 12dB）；修复后与应用外播放同一音量语义。
  double get volume => _volume;
  bool get muted => _muted;

  /// 系统音量通道是否可用（Windows=true；loadSystemVolume 成功探测后置真）
  bool _systemVolumeAvailable = false;

  /// 播放器增益：
  /// - 有系统音量通道：增益恒 1.0（静音 0），响度只由系统音量决定，防 v² 双重衰减；
  /// - 无通道平台（Android/鸿蒙预留）：退化为应用增益模式，滑条直接调 player。
  double get _gain =>
      _muted ? 0 : (_systemVolumeAvailable ? 1.0 : _volume);

  /// 绝对设置音量（0.0~1.0）；设置非零音量时自动取消静音
  Future<void> setVolume(double volume) async {
    final v = volume.clamp(0.0, 1.0);
    // 调非零音量 = 用户明确要出声 → 自动取消静音（拖动滑条 / 快捷键调高均生效）
    if (v > 0 && _muted) {
      _muted = false;
      mutedNotifier.value = false;
    }
    _volume = v;
    volumeNotifier.value = v; // 通知播放条音量控件刷新（滑条/百分比/图标）
    // 播放器增益恒 1.0：响度只由系统音量决定（避免 v² 双重衰减）
    await _player.setVolume(_gain);
    LogService.instance
        .info(LogTag.play, '音量设置为 ${(_volume * 100).round()}%');
    _syncToSystem(); // 音量 → 写回系统音量（系统音量为唯一响度旋钮）
  }

  /// 相对调节音量（快捷键 Ctrl+↑/↓ 使用）
  Future<void> changeVolume(double delta) => setVolume(_volume + delta);

  /// 静音 / 取消静音切换（快捷键 Ctrl+M / 播放条音量图标使用）
  Future<void> toggleMute() async {
    _muted = !_muted;
    mutedNotifier.value = _muted; // 通知播放条音量控件刷新（图标/百分比）
    // 静音只切增益（0/1.0），音量数值不动（响度旋钮仍是系统音量）
    await _player.setVolume(_gain);
    LogService.instance.info(LogTag.play,
        _muted ? '静音开启' : '静音取消（音量 ${(_volume * 100).round()}%）');
    _syncToSystem(); // 静音状态 → 写回系统（双向同步）
  }

  /// 初始化音量为**系统默认输出设备音量**（Windows Core Audio）。
  /// 由 HomeScreen 启动时调用；非 Windows 平台无该通道时保持默认 100%。
  Future<void> loadSystemVolume() async {
    try {
      final snapshot = await WindowControls.instance.getSystemVolume();
      if (snapshot == null) return;
      final v = snapshot.volume;
      final m = snapshot.muted;
      _volume = v.clamp(0.0, 1.0);
      volumeNotifier.value = _volume; // 通知播放条音量控件刷新
      _muted = m;
      mutedNotifier.value = _muted;
      // 系统音量已是当前响度，增益无需衰减（修复前此处 setVolume(v) 与系统音量叠乘）
      _systemVolumeAvailable = true; // 自此刻起滑条=系统音量镜像，增益恒 1.0
      await _player.setVolume(_gain);
      LogService.instance.info(LogTag.play,
          '初始化为系统音量 ${(_volume * 100).round()}%'
          '${_muted ? '（系统静音）' : ''}');
      // 有系统音量通道 → 启动轮询：系统音量面板变化实时同步到应用
      _startSystemVolumePoll();
    } catch (_) {
      // 非 Windows 平台无该通道，保持默认 100%
    }
  }

  /// 系统音量轮询（每 1s）：系统面板/媒体键改音量后，应用实时跟随。
  Timer? _sysVolPollTimer;

  void _startSystemVolumePoll() {
    _sysVolPollTimer?.cancel();
    _sysVolPollTimer =
        Timer.periodic(const Duration(seconds: 1), (_) => _pollSystemVolume());
  }

  Future<void> _pollSystemVolume() async {
    try {
      final snapshot = await WindowControls.instance.getSystemVolume();
      if (snapshot == null) return;
      final v = snapshot.volume;
      final m = snapshot.muted;
      // 仅当系统值与应用显著不同（±2%）或静音状态不同才同步，
      // 避免与应用自身写回系统产生的回读冲突。
      if ((v - _volume).abs() > 0.02 || m != _muted) {
        _volume = v.clamp(0.0, 1.0);
        volumeNotifier.value = _volume;
        _muted = m;
        mutedNotifier.value = _muted;
        // 系统音量变化只回显滑条 + 同步静音，增益不再叠加（防 v² 衰减）
        await _player.setVolume(_gain);
        LogService.instance.info(LogTag.play,
            '跟随系统音量 ${(_volume * 100).round()}%'
            '${_muted ? '（静音）' : ''}');
      }
    } catch (_) {
      // 非 Windows 平台无该通道，忽略
    }
  }

  /// 应用音量/静音变化 → 写回系统（双向同步；非 Windows 平台忽略失败）
  void _syncToSystem() {
    unawaited(WindowControls.instance
        .setSystemVolume(volume: _volume, muted: _muted)
        .catchError((_) {}));
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
    // 同步到媒体会话（通知栏播放键状态）
    _pushMediaSession();
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    if (instance == this) instance = null;
    _sysVolPollTimer?.cancel();
    volumeNotifier.dispose();
    mutedNotifier.dispose();
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
