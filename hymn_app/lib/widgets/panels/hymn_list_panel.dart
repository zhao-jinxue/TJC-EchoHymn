import 'package:flutter/material.dart';

import '../../../services/app_state_service.dart';
import '../../app.dart';
import 'left_panel_base.dart';

/// 诗歌列表面板：按编号分页展示全部诗歌 + 搜索 + 分页
class HymnListPanel extends LeftPanel {
  const HymnListPanel({
    super.key,
    required super.audio,
    required super.repo,
    required super.onPlayback,
    super.anchor,
  });

  @override
  State<HymnListPanel> createState() => _HymnListPanelState();
}

class _HymnListPanelState extends LeftPanelState<HymnListPanel> {
  static const int _pageSize = 35;
  final ScrollController _scroll = ScrollController();
  final TextEditingController _searchCtrl = TextEditingController();
  String _keyword = '';
  int _listPage = 0;

  @override
  void dispose() {
    _scroll.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  void restoreSaved(AppState anchor) {
    // 全部诗歌列表：按播放索引翻到对应页并滚动
    final idx = anchor.playlistIndex;
    if (idx < 0) return;
    final page = idx ~/ _pageSize;
    if (page != _listPage) {
      _listPage = page;
      setState(() {});
    }
    // 延后一帧等列表重建后再滚动
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final local = idx - _listPage * _pageSize;
      scrollToCurrent(_scroll, local);
    });
  }

  @override
  Widget build(BuildContext context) {
    final all =
        _keyword.isEmpty ? repo.getAllHymns() : repo.searchHymns(_keyword);
    final totalPages = (all.length / _pageSize).ceil().clamp(1, 1 << 31);
    if (_listPage >= totalPages) _listPage = totalPages - 1;
    if (_listPage < 0) _listPage = 0;
    final start = _listPage * _pageSize;
    final end = (start + _pageSize).clamp(0, all.length);
    final hymns = all.sublist(start, end);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 搜索框
        Padding(
          padding: const EdgeInsets.all(8),
          child: TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: '搜索编号/标题/作者/作曲',
              prefixIcon: const Icon(Icons.search, size: 18),
              suffixIcon: _keyword.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear, size: 16),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() {
                          _keyword = '';
                          _listPage = 0;
                        });
                      },
                    ),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
            ),
            onChanged: (v) {
              setState(() {
                _keyword = v;
                _listPage = 0;
              });
            },
          ),
        ),
        // 列表
        Expanded(
          child: hymns.isEmpty
              ? const _EmptyHint(text: '未找到相关诗歌')
              : ListView.builder(
                  controller: _scroll,
                  itemCount: hymns.length,
                  itemBuilder: (context, index) =>
                      hymnTile(hymns[index], start + index, all),
                ),
        ),
        // 分页
        Container(
          color: AppColors.cardBg,
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left, size: 20),
                tooltip: '上一页',
                onPressed:
                    _listPage > 0 ? () => setState(() => _listPage--) : null,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  '第 ${_listPage + 1}/$totalPages 页',
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right, size: 20),
                tooltip: '下一页',
                onPressed: _listPage < totalPages - 1
                    ? () => setState(() => _listPage++)
                    : null,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EmptyHint extends StatelessWidget {
  final String text;
  const _EmptyHint({required this.text});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.music_off, size: 48, color: AppColors.textTertiary),
          const SizedBox(height: 12),
          Text(text,
              style: const TextStyle(
                  fontSize: 14, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}
