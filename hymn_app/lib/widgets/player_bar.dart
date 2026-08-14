import 'dart:async';

import 'package:flutter/material.dart';

import '../services/audio_service.dart';

/// 底部播放器栏：控制按钮 + 进度条 + 音量
class PlayerBar extends StatefulWidget {
  final AudioService audio;

  const PlayerBar({super.key, required this.audio});

  @override
  State<PlayerBar> createState() => _PlayerBarState();
}

class _PlayerBarState extends State<PlayerBar> {
  PlayerStatus _status = PlayerStatus.idle;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double _volume = 0.8;
  double? _dragValue;
  StreamSubscription<PlayerStatus>? _statusSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;

  @override
  void initState() {
    super.initState();
    _statusSub = widget.audio.statusStream.listen((s) {
      if (mounted) setState(() => _status = s);
    });
    _positionSub = widget.audio.positionStream.listen((p) {
      if (mounted && _dragValue == null) setState(() => _position = p);
    });
    _durationSub = widget.audio.durationStream.listen((d) {
      if (mounted) setState(() => _duration = d);
    });
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hymn = widget.audio.currentHymn;

    return Material(
      elevation: 8,
      color: theme.colorScheme.surfaceContainer,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: hymn == null ? _buildEmpty(theme) : _buildActive(theme),
        ),
      ),
    );
  }

  Widget _buildEmpty(ThemeData theme) {
    return SizedBox(
      height: 48,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.music_note, color: theme.colorScheme.outline),
          const SizedBox(width: 8),
          Text(
            '从左侧选择一首诗歌开始聆听',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActive(ThemeData theme) {
    final hymn = widget.audio.currentHymn!;
    final playing = _status == PlayerStatus.playing;
    final loading = _status == PlayerStatus.loading;
    final position =
        _dragValue != null ? Duration(seconds: _dragValue!.round()) : _position;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    hymn.title,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '第 ${hymn.number} 首 · ${hymn.category}',
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: '上一首',
              icon: const Icon(Icons.skip_previous),
              onPressed: () => widget.audio.playPrev(),
            ),
            IconButton.filled(
              tooltip: loading ? '加载中' : (playing ? '暂停' : '播放'),
              icon: loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(playing ? Icons.pause : Icons.play_arrow),
              onPressed: () => widget.audio.togglePlayPause(),
            ),
            IconButton(
              tooltip: '下一首',
              icon: const Icon(Icons.skip_next),
              onPressed: () => widget.audio.playNext(),
            ),
          ],
        ),
        Row(
          children: [
            Text(
              formatTime(position),
              style: theme.textTheme.labelSmall,
            ),
            Expanded(
              child: Slider(
                min: 0,
                max: _duration.inSeconds > 0
                    ? _duration.inSeconds.toDouble()
                    : 1,
                value: position.inSeconds
                    .clamp(0, _duration.inSeconds > 0 ? _duration.inSeconds : 1)
                    .toDouble(),
                onChangeStart: (v) => setState(() => _dragValue = v),
                onChanged: (v) => setState(() => _dragValue = v),
                onChangeEnd: (v) {
                  widget.audio.seek(Duration(seconds: v.round()));
                  setState(() => _dragValue = null);
                },
              ),
            ),
            Text(
              formatTime(_duration),
              style: theme.textTheme.labelSmall,
            ),
          ],
        ),
        Row(
          children: [
            const Icon(Icons.volume_down, size: 18),
            Expanded(
              child: Slider(
                min: 0,
                max: 1,
                value: _volume,
                onChanged: (v) {
                  setState(() => _volume = v);
                  widget.audio.setVolume(v);
                },
              ),
            ),
            const Icon(Icons.volume_up, size: 18),
          ],
        ),
      ],
    );
  }
}
