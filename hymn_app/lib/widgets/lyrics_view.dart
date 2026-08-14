import 'dart:async';

import 'package:flutter/material.dart';

import '../services/audio_service.dart';

/// 歌词视图：随播放器状态更新
class LyricsView extends StatefulWidget {
  final AudioService audio;

  const LyricsView({super.key, required this.audio});

  @override
  State<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends State<LyricsView> {
  StreamSubscription<PlayerStatus>? _statusSub;

  @override
  void initState() {
    super.initState();
    _statusSub = widget.audio.statusStream.listen((s) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hymn = widget.audio.currentHymn;

    if (hymn == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.library_music,
                size: 64, color: theme.colorScheme.outline),
            const SizedBox(height: 12),
            Text(
              '选择一首诗歌，歌词将显示在这里',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ],
        ),
      );
    }

    // 播放器可能已更换歌曲但字段尚未同步，直接取 currentHymn
    final lyrics = hymn.lyrics;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 标题区
          Text(
            hymn.title,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            hymn.meta,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
          const SizedBox(height: 24),

          // 歌词分节
          for (var i = 0; i < lyrics.length; i++) ...[
            if (i > 0) const SizedBox(height: 20),
            _StanzaView(stanza: lyrics[i]),
          ],
        ],
      ),
    );
  }
}

/// 单节歌词
class _StanzaView extends StatelessWidget {
  final List<String> stanza;

  const _StanzaView({required this.stanza});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        for (var i = 0; i < stanza.length; i++) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              stanza[i],
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(height: 1.6),
            ),
          ),
        ],
      ],
    );
  }
}
