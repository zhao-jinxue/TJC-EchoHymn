import 'package:flutter/material.dart';

import '../models/hymn.dart';
import '../services/audio_service.dart';
import '../services/hymn_repository.dart';
import '../widgets/lyrics_view.dart';
import '../widgets/player_bar.dart';
import '../widgets/hymn_list_panel.dart';

/// 主界面：左侧诗歌列表 + 右侧播放器/歌词
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<HymnRepository> _repoFuture;
  HymnRepository? _repo;
  AudioService? _audio;
  String _searchKeyword = '';
  bool _initError = false;

  bool _isNarrow = false;

  @override
  void initState() {
    super.initState();
    _repoFuture = HymnRepository.create();
    _repoFuture.then((repo) {
      if (!mounted) return;
      setState(() {
        _repo = repo;
        _audio = AudioService();
      });
    }).catchError((Object e) {
      if (!mounted) return;
      setState(() => _initError = true);
    });
  }

  @override
  void dispose() {
    _repo?.dispose();
    _audio?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 720;
        if (_isNarrow != narrow) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _isNarrow = narrow);
          });
        }
        return Scaffold(
          appBar: AppBar(
            title: const Text('🎵 EchoHymn'),
            actions: [_buildEngineBadge()],
          ),
          body: _buildBody(narrow),
        );
      },
    );
  }

  Widget _buildEngineBadge() {
    if (_repo == null) return const SizedBox.shrink();
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(right: 12),
        child: Chip(
          avatar: Icon(
            _repo!.usingCppEngine ? Icons.memory : Icons.data_object,
            size: 16,
          ),
          label: Text(
            _repo!.usingCppEngine ? 'C++ 引擎' : 'Dart 解析',
            style: const TextStyle(fontSize: 11),
          ),
          visualDensity: VisualDensity.compact,
        ),
      ),
    );
  }

  Widget _buildBody(bool narrow) {
    if (_initError) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: Colors.red),
              SizedBox(height: 12),
              Text('数据加载失败，请确认 assets/data/hymns.json 存在'),
            ],
          ),
        ),
      );
    }

    if (_repo == null || _audio == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (narrow) {
      return _buildNarrowLayout();
    }
    return _buildWideLayout();
  }

  Widget _buildWideLayout() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 300,
          child: _buildHymnList(),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _buildLyrics()),
              PlayerBar(audio: _audio!),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNarrowLayout() {
    // 移动端：使用抽屉展示列表；主区域显示播放器 + 歌词
    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: _buildLyrics()),
            PlayerBar(audio: _audio!),
          ],
        ),
        Align(
          alignment: Alignment.topLeft,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: FloatingActionButton.small(
                heroTag: 'nav',
                tooltip: '诗歌列表',
                onPressed: _openDrawer,
                child: const Icon(Icons.menu),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _openDrawer() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => FractionallySizedBox(
        heightFactor: 0.85,
        child: Material(
          color: Theme.of(ctx).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          child: _buildHymnList(),
        ),
      ),
    );
  }

  Widget _buildHymnList() {
    return HymnListPanel(
      hymns: _repo!.search(_searchKeyword),
      searchKeyword: _searchKeyword,
      onSearchChanged: (kw) => setState(() => _searchKeyword = kw),
      currentHymn: _audio!.currentHymn,
      onSelect: (h, index) {
        _audio!.setPlaylist(_repo!.search(_searchKeyword), startIndex: index);
        _audio!.playHymn(h, index: index);
        Navigator.of(context).pop(); // 关闭移动端抽屉
      },
    );
  }

  Widget _buildLyrics() {
    return LyricsView(audio: _audio!);
  }
}