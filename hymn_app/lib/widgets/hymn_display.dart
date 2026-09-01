import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../app.dart';
import '../models/hymn.dart';
import '../services/audio_service.dart';
import '../services/app_paths.dart';
import '../services/chinese_convert_service.dart';
import '../services/log_service.dart';
import '../theme/app_fonts.dart';

/// 歌词显示模式
enum DisplayMode { lyrics, numbered, staff }

/// 主内容区：版本切换 + 歌词/谱面 + 播放控制
class HymnDisplay extends StatefulWidget {
  final AudioService audio;

  /// 初始歌词模式（状态恢复用）
  final String? initialMode;

  /// 选中歌词模式回调（供上层持久化）
  final ValueChanged<String>? onModeChanged;

  /// 选中音频版本回调（供上层持久化）
  final ValueChanged<String>? onAudioVersionChanged;

  const HymnDisplay({
    super.key,
    required this.audio,
    this.initialMode,
    this.onModeChanged,
    this.onAudioVersionChanged,
  });

  @override
  State<HymnDisplay> createState() => _HymnDisplayState();
}

class _HymnDisplayState extends State<HymnDisplay> {
  late DisplayMode _mode;
  StreamSubscription? _statusSub;

  @override
  void initState() {
    super.initState();
    LogService.instance.info(LogTag.ui, '主内容区 HymnDisplay 初始化');
    _mode = DisplayMode.values.firstWhere(
      (m) => m.name == widget.initialMode,
      orElse: () => DisplayMode.lyrics,
    );
    _statusSub = widget.audio.statusStream.listen((s) {
      if (!mounted) return;
      setState(() {});
      if (s == PlayerStatus.error) _showAudioError();
    });
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    super.dispose();
  }

  String get currentModeName => _mode.name;

  @override
  Widget build(BuildContext context) {
    final hymn = widget.audio.currentHymn;
    return Container(
      color: AppColors.pageBg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildVersionBar(hymn),
          Divider(height: 1, color: AppColors.divider),
          Expanded(child: _buildContent(hymn)),
          Divider(height: 1, color: AppColors.divider),
          _buildPlayerBar(hymn),
        ],
      ),
    );
  }

  // ============ 版本栏 ============
  Widget _buildVersionBar(Hymn? hymn) {
    return Container(
      height: 44,
      color: AppColors.versionBarBg,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          _versionBtn(
            label: '钢琴版',
            icon: Icons.piano,
            active:
                hymn != null && widget.audio.currentAudioVersion.contains('鋼琴'),
            onTap: hymn == null ? null : () => _switchVersion(hymn, '鋼琴版'),
          ),
          const SizedBox(width: 8),
          _buildVoiceButton(hymn),
          const Spacer(),
          _modeBtn('歌词', DisplayMode.lyrics, Icons.lyrics_outlined),
          const SizedBox(width: 4),
          _modeBtn('简谱', DisplayMode.numbered, Icons.music_note),
          const SizedBox(width: 4),
          _modeBtn('五线谱', DisplayMode.staff, Icons.graphic_eq),
        ],
      ),
    );
  }

  Widget _versionBtn({
    required String label,
    required IconData icon,
    required bool active,
    VoidCallback? onTap,
  }) {
    return Material(
      color: active ? AppColors.primary : AppColors.controlBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: BorderSide(
          color: active ? Colors.transparent : AppColors.controlBorder,
          width: 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              Icon(icon,
                  size: 16,
                  color: active ? Colors.white : AppColors.textSecondary),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: active ? Colors.white : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 人声版本 = 音频版本中除「钢琴版」外
  List<String> voiceVersions(Hymn hymn) {
    final all = widget.audio.availableVersions(hymn);
    return all.where((v) => !v.contains('鋼琴')).toList();
  }

  String _voiceLabel(String v) =>
      ChineseConvertService.instance.toSimplified(v);

  /// 人声版切换按钮（切到第一个人声版本；多版本列表在播放条）
  Widget _buildVoiceButton(Hymn? hymn) {
    final voices = hymn == null ? <String>[] : voiceVersions(hymn);
    if (hymn == null || voices.isEmpty) {
      return _versionBtn(label: '人声版', icon: Icons.mic, active: false);
    }
    final currentVoice = widget.audio.currentAudioVersion;
    final isVoiceActive = currentVoice.contains('人聲') ||
        currentVoice.contains('人声') ||
        !currentVoice.contains('鋼琴');
    return _versionBtn(
      label: '人声版',
      icon: Icons.mic,
      active: isVoiceActive,
      onTap: () => _switchVersion(hymn, voices.first),
    );
  }

  Widget _modeBtn(String label, DisplayMode mode, IconData icon) {
    final selected = _mode == mode;
    return Material(
      color: selected ? AppColors.selectedBg : AppColors.controlBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: BorderSide(
          color: selected ? Colors.transparent : AppColors.controlBorder,
          width: 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => _setMode(mode),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            children: [
              Icon(icon,
                  size: 15,
                  color:
                      selected ? AppColors.primary : AppColors.textSecondary),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: selected ? AppColors.primary : AppColors.textSecondary,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _setMode(DisplayMode mode) {
    setState(() => _mode = mode);
    widget.onModeChanged?.call(mode.name);
    LogService.instance.info(
      LogTag.action,
      '切换歌词显示模式: ${mode.name}',
    );
  }

  Future<void> _switchVersion(Hymn hymn, String version) async {
    try {
      LogService.instance.info(
        LogTag.action,
        '切换音频版本: ${ChineseConvertService.instance.toSimplified(version)}',
        detail: '诗歌: 第 ${hymn.hymnNumber} 首《${hymn.title}》',
      );
      await widget.audio.switchAudioVersion(version);
      widget.onAudioVersionChanged?.call(version);
      if (mounted) setState(() {});
    } catch (e) {
      LogService.instance.error(
        LogTag.error,
        '切换音频版本异常',
        detail: '版本: $version\n异常: $e',
      );
      _showAudioError();
    }
  }

  // ============ 内容区 ============
  Widget _buildContent(Hymn? hymn) {
    if (hymn == null) {
      return Center(
        child: Text(
          '请在左侧选择一首诗歌',
          style: TextStyle(fontSize: 14, color: AppColors.textTertiary),
        ),
      );
    }

    switch (_mode) {
      case DisplayMode.lyrics:
        return _buildLyrics(hymn);
      case DisplayMode.numbered:
        return _buildScore(hymn.numberedPngPath, isEmpty: '暂无简谱');
      case DisplayMode.staff:
        return _buildScore(hymn.staffPngPath, isEmpty: '暂无五线谱');
    }
  }

  Widget _buildLyrics(Hymn hymn) {
    final verses = hymn.verses;
    if (verses.isEmpty) {
      return Center(
        child: Text(
          '暂无歌词',
          style: TextStyle(color: AppColors.textTertiary),
        ),
      );
    }

    // 歌词显示区：暖白背景（与左右侧栏冷灰形成轻微色差，便于感知区域大小）
    return Container(
      color: AppColors.lyricsBg,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 以「铺满显示区」为目标计算字号：用内容行数估算高度，再按比例放大字号
          const pad = 48.0; // 上下留白 24+24
          // 粗估总行数：标题 + 「第 N 首」 + 每节（节标签 + 歌词行）
          final verseTexts = verses.where((v) => v.trim().isNotEmpty).toList();
          int lineCount = 2; // 标题 + 「第 N 首」
          for (final v in verseTexts) {
            final lines = v.split('\n').length;
            lineCount += lines + 1; // + 节标签
          }
          // 每行按 1.8 倍字号高度估算
          final availH = (constraints.maxHeight - pad).clamp(100.0, 4000.0);
          final availW = constraints.maxWidth - pad;
          // 行高与字号关系：行距 1.8 → 每行约 2.0 倍字号
          final maxByH = lineCount > 0 ? availH / (lineCount * 2.0) : 40.0;
          final maxByW = availW / 14.0; // 每行约 14 个汉字
          // K10c：字号完全由窗口尺寸决定（maxByH/maxByW）。
          // 不再用固定 baseBody=18 参与最小值运算——否则窗口放大后
          // 字号被 18 卡住、无法随窗口增大铺满歌词区。
          // 优化（2026-08-28）：整体字号 +4，改善最小尺寸界面的可读性。
          // v1.5.0 字号等级：铺满算法保持为「基准」，结果再乘字号系数——
          // 全局 Transform.scale 会把画布缩小 1/s 再放大 s，铺满算法若不做
          // 补偿会自我抵消（歌词不随字号变化）；乘系数后视觉字号 ≈ 基准×系数。
          // 大字号下歌词会超出显示区 → 由外层 SingleChildScrollView 滚动兜底。
          final ls = AppFonts.lyricsScale;
          final bodySize =
              ([maxByH, maxByW].reduce((a, b) => a < b ? a : b) + 4.0)
                      .clamp(12.0, 100.0) *
                  ls;
          final titleSize = (bodySize * 1.4).clamp(20.0 * ls, 34.0 * ls);
          final labelSize = (bodySize * 0.7).clamp(12.0 * ls, 16.0 * ls);

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            // K10c：内容垂直铺满——不足显示区高度时用 spaceBetween 均匀分布
            // 各节（标题贴顶、结尾贴底），避免「底部大片空白」；超出时正常滚动
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight:
                    (constraints.maxHeight - pad).clamp(0.0, double.infinity),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    ChineseConvertService.instance.toSimplified(hymn.title),
                    style: TextStyle(
                      fontSize: titleSize,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '第 ${hymn.hymnNumber} 首',
                    style: TextStyle(
                        fontSize: labelSize, color: AppColors.textTertiary),
                  ),
                  const SizedBox(height: 24),
                  for (var i = 0; i < verses.length; i++) ...[
                    if (verses[i].trim().isNotEmpty) ...[
                      Text(
                        '第${i + 1}节',
                        style: TextStyle(
                          fontSize: labelSize,
                          color: AppColors.textTertiary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        ChineseConvertService.instance.toSimplified(verses[i]),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: bodySize,
                          height: 1.8,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildScore(String path, {required String isEmpty}) {
    final abs = AppPaths.resolveAsset(path);
    if (abs.isEmpty || !(abs.contains('http') || _fileExists(abs))) {
      return Center(
        child: Text(isEmpty, style: TextStyle(color: AppColors.textTertiary)),
      );
    }
    return Center(
      child: InteractiveViewer(
        child: abs.startsWith('http')
            ? Image.network(abs,
                errorBuilder: (_, __, ___) => const Icon(Icons.broken_image))
            : Image.file(File(abs),
                errorBuilder: (_, __, ___) => const Icon(Icons.broken_image)),
      ),
    );
  }

  bool _fileExists(String path) {
    try {
      return File(path).existsSync();
    } catch (_) {
      return false;
    }
  }

  // ============ 播放条（两层） ============
  Widget _buildPlayerBar(Hymn? hymn) {
    return Container(
      color: AppColors.playBarBg,
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 上层：进度条
          _buildProgress(),
          const SizedBox(height: 6),
          // 下层：控制按钮 + 人声版本列表（>1 时显示）
          _buildControls(hymn),
        ],
      ),
    );
  }

  Widget _buildControls(Hymn? hymn) {
    final voices = hymn == null ? <String>[] : voiceVersions(hymn);
    // F27 修复（v1.5.0 大字号下音量滑条与播放按钮重叠）：
    // 画布宽度 = 窗口宽 ÷ 字号系数，大字号下画布变窄，固定宽度控件
    // （音量图标48+滑条150+百分比38≈236）会与居中的播放按钮组（约144）
    // 重叠。用 LayoutBuilder 计算左侧可用宽度（= 半宽 - 按钮组半宽 - 间距），
    // 限制音量控件不超过它；空间充足时（默认字号）不生效，零回归。
    return LayoutBuilder(
      builder: (context, constraints) {
        // 音量控件可用宽 = 半宽 - 居中按钮组半宽(144/2=72)。
        // 按钮组图标内缩，视觉上仍与音量控件有明显间隔；-72 为几何零重叠。
        final leftMax =
            (constraints.maxWidth / 2 - 72).clamp(120.0, double.infinity);
        return Stack(
          alignment: Alignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: Icon(Icons.skip_previous, color: AppColors.textPrimary),
                  tooltip: '上一首',
                  onPressed: () => widget.audio.playPrev(),
                ),
                StreamBuilder<PlayerStatus>(
                  stream: widget.audio.statusStream,
                  builder: (context, snap) {
                    final status = snap.data ?? PlayerStatus.idle;
                    final playing = status == PlayerStatus.playing;
                    return IconButton(
                      iconSize: 42,
                      icon: Icon(
                        playing
                            ? Icons.pause_circle_filled
                            : Icons.play_circle_filled,
                        color: AppColors.primary,
                      ),
                      tooltip: playing ? '暂停' : '播放',
                      onPressed: () {
                        LogService.instance.info(
                          LogTag.action,
                          playing ? '点击播放条：暂停' : '点击播放条：播放',
                        );
                        widget.audio.togglePlayPause();
                      },
                    );
                  },
                ),
                IconButton(
                  icon: Icon(Icons.skip_next, color: AppColors.textPrimary),
                  tooltip: '下一首',
                  onPressed: () => widget.audio.playNext(),
                ),
              ],
            ),
            // 人声版本列表（>1 时显示，悬停提示 10 秒，固定右侧不挤压居中按钮组）
            if (voices.length > 1)
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                child: Center(child: _buildVoiceListButton(hymn!, voices)),
              ),
            // 音量调节（通用方案）：图标=静音切换 / 滑条=调节 / 百分比=当前音量
            // 与全局快捷键（Ctrl+↑↓/Ctrl+M）共用 AudioService 同一数据源，实时联动
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: leftMax),
                  child: _buildVolumeControl(),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// 播放条左侧音量控件：静音图标 + 滑条 + 音量百分比
  ///
  /// 数据源为 `AudioService.volumeNotifier/mutedNotifier`（ValueNotifier）：
  /// 拖动滑条 / 点击静音 / 快捷键调节，都会更新同一来源并互相刷新。
  ///
  /// v1.5.0 方案 A（用户选定）：**滑轨占满可用宽度、永不小于默认 150px**——
  /// - 图标/百分比反向缩放（画布宽 = 48/系数、38/系数），**视觉恒为 48px/38px**，
  ///   不随字号挤占滑轨空间；
  /// - 滑轨宽度 = 剩余可用画布，视觉下限 150px、上限 150×系数（默认档保持 150 零回归），
  ///   大字号下更宽更好拖；
  /// - 滑块/轨道经 SliderTheme 反向缩放（/系数），**视觉恒为 20px/4px**，
  ///   避免「轨道变短、滑块变大」的比例失调。
  Widget _buildVolumeControl() {
    return ValueListenableBuilder<double>(
      valueListenable: widget.audio.volumeNotifier,
      builder: (context, volume, _) {
        return ValueListenableBuilder<bool>(
          valueListenable: widget.audio.mutedNotifier,
          builder: (context, muted, _) {
            final effective = muted ? 0.0 : volume;
            return LayoutBuilder(
              builder: (context, constraints) {
                final s = AppFonts.scale;
                final iconW = 48 / s; // 视觉恒 48
                final pctW = 38 / s; // 视觉恒 38
                // 滑轨可用画布宽 = 容器限宽 - 图标 - 百分比；
                // 视觉下限 150（画布 150/s）、上限 150 画布（默认档保持 150 视觉）
                final avail = constraints.maxWidth - iconW - pctW;
                final sliderW = avail.clamp(150 / s, 150).toDouble();
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: iconW,
                      height: 48,
                      child: Center(
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          iconSize: 24 / s, // 视觉恒 24
                          icon: Icon(
                            muted ? Icons.volume_off : Icons.volume_up,
                            color: AppColors.textPrimary,
                          ),
                          tooltip: muted ? '取消静音（Ctrl+M）' : '静音（Ctrl+M）',
                          onPressed: () => widget.audio.toggleMute(),
                        ),
                      ),
                    ),
                    SliderTheme(
                      data: SliderThemeData(
                        activeTrackColor: AppColors.primary,
                        thumbColor: AppColors.primary,
                        // 滑块/轨道反向缩放 → 视觉恒 20px/4px，不随字号变形
                        trackHeight: 4 / s,
                        thumbShape:
                            RoundSliderThumbShape(enabledThumbRadius: 10 / s),
                        overlayShape:
                            RoundSliderOverlayShape(overlayRadius: 20 / s),
                      ),
                      child: SizedBox(
                        width: sliderW,
                        child: Slider(
                          value: effective,
                          onChanged: (v) => widget.audio.setVolume(v),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: pctW,
                      child: Center(
                        child: Text(
                          '${(effective * 100).round()}%',
                          textAlign: TextAlign.left,
                          style: TextStyle(
                            fontSize: 12 / s, // 视觉恒 12
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildVoiceListButton(Hymn hymn, List<String> voices) {
    final currentVoice = widget.audio.currentAudioVersion;
    return Tooltip(
      message: '共 ${voices.length} 个人声版本，可选择切换',
      waitDuration: Duration.zero,
      showDuration: const Duration(seconds: 10),
      child: PopupMenuButton<String>(
        tooltip: '人声版本列表',
        initialValue:
            voices.contains(currentVoice) ? currentVoice : voices.first,
        onSelected: (v) => _switchVersion(hymn, v),
        icon: Icon(Icons.groups, size: 22, color: AppColors.textPrimary),
        itemBuilder: (ctx) => [
          for (final v in voices)
            PopupMenuItem(value: v, child: Text(_voiceLabel(v))),
        ],
      ),
    );
  }

  Widget _buildProgress() {
    return StreamBuilder<Duration>(
      stream: widget.audio.positionStream,
      builder: (context, posSnap) {
        final pos = posSnap.data ?? Duration.zero;
        return StreamBuilder<Duration>(
          stream: widget.audio.durationStream,
          builder: (context, durSnap) {
            final dur = durSnap.data ?? Duration.zero;
            return Row(
              children: [
                Text(formatTime(pos),
                    style: TextStyle(
                        fontSize: 12, color: AppColors.textSecondary)),
                Expanded(
                  child: Slider(
                    value: dur.inMilliseconds > 0
                        ? pos.inMilliseconds
                            .clamp(0, dur.inMilliseconds)
                            .toDouble()
                        : 0,
                    max: dur.inMilliseconds > 0
                        ? dur.inMilliseconds.toDouble()
                        : 1,
                    onChanged: (v) =>
                        widget.audio.seek(Duration(milliseconds: v.toInt())),
                  ),
                ),
                Text(formatTime(dur),
                    style: TextStyle(
                        fontSize: 12, color: AppColors.textSecondary)),
              ],
            );
          },
        );
      },
    );
  }

  void _showAudioError() {
    if (!mounted) return;
    final err = widget.audio.lastError;
    final msg = (err == null || err.isEmpty) ? '音频加载失败' : '音频加载失败：$err';
    LogService.instance.error(LogTag.error, '音频加载失败（Toast）', detail: msg);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
