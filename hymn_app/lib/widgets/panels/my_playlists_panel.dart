import 'package:flutter/material.dart';

import '../../../models/hymn.dart';
import '../../../models/playlist.dart';
import '../../../services/app_state_service.dart';
import '../../../services/chinese_convert_service.dart';
import '../../app.dart';
import '../playlist_dialog.dart';
import 'left_panel_base.dart';

/// 个人歌单面板：歌单列表（新建/修改/删除）+ 点开歌单展示其诗歌列表
class MyPlaylistsPanel extends LeftPanel {
  const MyPlaylistsPanel({
    super.key,
    required super.audio,
    required super.repo,
    required super.onPlayback,
    super.anchor,
  });

  @override
  State<MyPlaylistsPanel> createState() => _MyPlaylistsPanelState();
}

class _MyPlaylistsPanelState extends LeftPanelState<MyPlaylistsPanel> {
  final ScrollController _listScroll = ScrollController();
  final ScrollController _contentScroll = ScrollController();

  /// 当前选中的歌单与其诗歌列表
  Playlist? _selectedPlaylist;
  List<Hymn> _selectedHymns = const [];
  bool _showContent = false;

  List<Playlist> get _playlists => repo.getPlaylists();
  String display(String s) => ChineseConvertService.instance.toSimplified(s);

  @override
  void dispose() {
    _listScroll.dispose();
    _contentScroll.dispose();
    super.dispose();
  }

  /// 按锚点恢复：选中歌单并展开其诗歌列表，滚动到当前诗歌
  @override
  void restoreSaved(AppState anchor) {
    if (anchor.playlistName.isEmpty) return;
    final pl = _playlists.where((p) => p.name == anchor.playlistName).toList();
    if (pl.isEmpty) return;
    final sel = pl.first;
    final hymns = _buildPlaylistHymns(sel);
    if (hymns.isEmpty) return;
    final idx =
        (anchor.playlistIndex >= 0 && anchor.playlistIndex < hymns.length)
            ? anchor.playlistIndex
            : 0;
    setState(() {
      _selectedPlaylist = sel;
      _selectedHymns = hymns;
      _showContent = true;
    });
    // 延后一帧等列表重建后再滚动
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      scrollToCurrent(_contentScroll, idx);
    });
  }

  List<Hymn> _buildPlaylistHymns(Playlist pl) {
    final list = <Hymn>[];
    for (final item in pl.hymns) {
      final h = repo.hymnByNumber(item.value.toString());
      if (h != null) list.add(h);
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    if (_showContent && _selectedPlaylist != null) {
      return _buildContent();
    }
    return _buildList();
  }

  /// 歌单列表视图（顶部新建按钮）
  Widget _buildList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 顶部：新建按钮（固定位置，类似搜索框）
        Padding(
          padding: const EdgeInsets.all(8),
          child: SizedBox(
            width: double.infinity,
            child: _newPlaylistButton(),
          ),
        ),
        const Divider(height: 1, color: AppColors.divider),
        Expanded(
          child: _playlists.isEmpty
              ? const _EmptyHint(text: '暂无个人歌单')
              : ListView.builder(
                  controller: _listScroll,
                  itemCount: _playlists.length,
                  itemBuilder: (context, i) {
                    final pl = _playlists[i];
                    final selected = _selectedPlaylist?.name == pl.name;
                    return Material(
                      color: selected ? AppColors.selectedBg : AppColors.cardBg,
                      child: InkWell(
                        onTap: () {
                          setState(() {
                            _selectedPlaylist = pl;
                            _selectedHymns = _buildPlaylistHymns(pl);
                            _showContent = true;
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            border: Border(
                              left: BorderSide(
                                width: 3,
                                color: selected
                                    ? AppColors.primary
                                    : Colors.transparent,
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.queue_music,
                                  size: 18, color: AppColors.textSecondary),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  pl.name,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: selected
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                    color: selected
                                        ? AppColors.primary
                                        : AppColors.textPrimary,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Text(
                                '${pl.count}首',
                                style: const TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textTertiary),
                              ),
                              // 修改按钮：打开复用弹窗（含删除歌单）
                              IconButton(
                                icon: const Icon(Icons.edit_outlined,
                                    size: 16, color: AppColors.textTertiary),
                                tooltip: '修改歌单',
                                onPressed: () => _openEditDialog(pl),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  /// 顶部新建按钮
  Widget _newPlaylistButton() {
    return Material(
      color: AppColors.primary,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: _openCreateDialog,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add, size: 16, color: Colors.white),
              SizedBox(width: 2),
              Text('新建', style: TextStyle(fontSize: 12, color: Colors.white)),
            ],
          ),
        ),
      ),
    );
  }

  /// 歌单诗歌列表视图
  Widget _buildContent() {
    final pl = _selectedPlaylist!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, size: 18),
                tooltip: '返回歌单列表',
                onPressed: () => setState(() => _showContent = false),
              ),
              Expanded(
                child: Text(
                  display(pl.name),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '${_selectedHymns.length}首',
                style: const TextStyle(
                    fontSize: 11, color: AppColors.textTertiary),
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: AppColors.divider),
        Expanded(
          child: _selectedHymns.isEmpty
              ? const _EmptyHint(text: '暂无诗歌')
              : ListView.builder(
                  controller: _contentScroll,
                  itemCount: _selectedHymns.length,
                  itemBuilder: (context, index) =>
                      hymnTile(_selectedHymns[index], index, _selectedHymns),
                ),
        ),
      ],
    );
  }

  Future<void> _openCreateDialog() async {
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => CreatePlaylistDialog(repo: repo),
    );
    if (result == 'create' && mounted) {
      setState(() {
        _selectedPlaylist = null;
        _selectedHymns = const [];
        _showContent = false;
      });
    }
  }

  Future<void> _openEditDialog(Playlist pl) async {
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => CreatePlaylistDialog(repo: repo, existing: pl),
    );
    if (!mounted) return;
    if (result == 'save') {
      setState(() {
        // 若正在展示该歌单内容，刷新选中歌单
        if (_selectedPlaylist?.id == pl.id) {
          final updated = _playlists.where((p) => p.id == pl.id).toList();
          _selectedPlaylist = updated.isNotEmpty ? updated.first : null;
          if (_selectedPlaylist != null) {
            _selectedHymns = _buildPlaylistHymns(_selectedPlaylist!);
          }
        }
      });
    } else if (result == 'delete') {
      setState(() {
        if (_selectedPlaylist?.id == pl.id) {
          _selectedPlaylist = null;
          _selectedHymns = const [];
          _showContent = false;
        }
      });
    }
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
