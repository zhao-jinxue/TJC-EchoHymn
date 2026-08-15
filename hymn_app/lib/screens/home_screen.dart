import 'package:flutter/material.dart';

import '../app.dart';
import '../models/hymn.dart';
import '../models/hymn_category.dart';
import '../models/playlist.dart';
import '../services/audio_service.dart';
import '../services/chinese_convert_service.dart';
import '../services/sqlite_repository.dart';
import '../widgets/hymn_display.dart';
import '../widgets/playlist_dialog.dart';

/// 左侧栏视图模式
enum LeftTab { hymnList, defaultPlaylists, myPlaylists }

/// 主界面：顶栏 + 左栏 + 主内容区 + 右栏 + 底部状态栏
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  SqliteRepository? _repo;
  AudioService? _audio;
  bool _initError = false;

  // ---- 布局状态 ----
  bool _showLeft = true;
  bool _showRight = true;

  // ---- 左侧栏状态 ----
  LeftTab _leftTab = LeftTab.hymnList;
  String _searchKeyword = '';

  // 默认歌单目录展开状态
  final Set<String> _expandedCategories = {};

  // 当前选中的歌单（默认歌单 subcategory 或 个人歌单）
  String? _selectedSubcategory;
  String? _selectedPlaylistName;

  // 数据缓存
  List<Hymn> _allHymns = const [];
  List<HymnCategory> _categories = const [];
  List<Playlist> _playlists = const [];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final repo = await SqliteRepository.open();
      final audio = AudioService();
      if (!mounted) return;
      setState(() {
        _repo = repo;
        _audio = audio;
        _allHymns = repo.getAllHymns();
        _categories = repo.getAllCategories();
        _playlists = repo.getPlaylists();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _initError = true);
    }
  }

  @override
  void dispose() {
    _repo?.dispose();
    _audio?.dispose();
    super.dispose();
  }

  // ================= 构建 =================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          _buildTopBar(),
          Expanded(child: _buildBody()),
          _buildStatusBar(),
        ],
      ),
    );
  }

  // ---------- 顶栏 ----------
  Widget _buildTopBar() {
    return Container(
      height: 40,
      color: AppColors.cardBg,
      child: Row(
        children: [
          SizedBox(
            width: 60,
            height: 30,
            child: _toggleButton(
              icon: Icons.chevron_left,
              tooltip: '展开/收起左侧栏目',
              active: _showLeft,
              onTap: () => setState(() => _showLeft = !_showLeft),
            ),
          ),
          const Expanded(
            child: Center(
              child: Text(
                'EchoHymn · 聆听赞美诗',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ),
          SizedBox(
            width: 60,
            height: 30,
            child: _toggleButton(
              icon: Icons.chevron_right,
              tooltip: '展开/收起右侧栏目',
              active: _showRight,
              onTap: () => setState(() => _showRight = !_showRight),
            ),
          ),
        ],
      ),
    );
  }

  Widget _toggleButton({
    required IconData icon,
    required String tooltip,
    required bool active,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Material(
        color: active ? AppColors.primary : AppColors.cardBg,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onTap,
          child: Center(
            child: Icon(
              icon,
              size: 18,
              color: active ? Colors.white : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  // ---------- 主体 ----------
  Widget _buildBody() {
    if (_initError) {
      return const Center(child: Text('数据加载失败，请检查 data/tjc_hymn.db'));
    }
    if (_repo == null || _audio == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final children = <Widget>[
      if (_showLeft) _buildLeftPanel(),
      const VerticalDivider(width: 1, color: AppColors.divider),
      Expanded(child: HymnDisplay(audio: _audio!)),
      if (_showRight) ...[
        const VerticalDivider(width: 1, color: AppColors.divider),
        _buildRightPanel(),
      ],
    ];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  // ---------- 左侧栏 ----------
  Widget _buildLeftPanel() {
    return SizedBox(
      width: 400,
      child: Container(
        color: AppColors.sidebarBg,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildLeftTabBar(),
            const Divider(height: 1, color: AppColors.divider),
            Expanded(child: _buildLeftTabContent()),
          ],
        ),
      ),
    );
  }

  Widget _buildLeftTabBar() {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          _tabButton('诗歌列表', LeftTab.hymnList, Icons.list),
          const SizedBox(width: 4),
          _tabButton('默认歌单', LeftTab.defaultPlaylists, Icons.library_music),
          const SizedBox(width: 4),
          _tabButton('个人歌单', LeftTab.myPlaylists, Icons.favorite),
          const Spacer(),
          if (_leftTab == LeftTab.myPlaylists) _newPlaylistButton(),
        ],
      ),
    );
  }

  Widget _tabButton(String label, LeftTab tab, IconData icon) {
    final selected = _leftTab == tab;
    return Expanded(
      child: Material(
        color: selected ? AppColors.selectedBg : AppColors.sidebarBg,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () => setState(() => _leftTab = tab),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon,
                    size: 16,
                    color:
                        selected ? AppColors.primary : AppColors.textSecondary),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                    color:
                        selected ? AppColors.primary : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _newPlaylistButton() {
    return Material(
      color: AppColors.primary,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: _openCreatePlaylistDialog,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
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

  // ---------- 左侧内容 ----------
  Widget _buildLeftTabContent() {
    switch (_leftTab) {
      case LeftTab.hymnList:
        return _buildHymnListTab();
      case LeftTab.defaultPlaylists:
        return _buildDefaultPlaylistsTab();
      case LeftTab.myPlaylists:
        return _buildMyPlaylistsTab();
    }
  }

  // 诗歌列表：搜索 + 列表
  Widget _buildHymnListTab() {
    final hymns = _searchKeyword.isEmpty
        ? _allHymns
        : (_repo?.searchHymns(_searchKeyword) ?? const []);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: TextField(
            decoration: InputDecoration(
              hintText: '搜索编号/标题/作者/作曲',
              prefixIcon: const Icon(Icons.search, size: 18),
              suffixIcon: _searchKeyword.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear, size: 16),
                      onPressed: () => setState(() => _searchKeyword = ''),
                    ),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
            ),
            onChanged: (v) {
              setState(() => _searchKeyword = v);
            },
          ),
        ),
        Expanded(
          child: hymns.isEmpty
              ? const _EmptyHint(text: '未找到相关诗歌')
              : ListView.builder(
                  itemCount: hymns.length,
                  itemBuilder: (context, index) =>
                      _hymnListItem(hymns[index], index, hymns),
                ),
        ),
      ],
    );
  }

  // 默认歌单：一级分类 → 二级 → 诗歌
  Widget _buildDefaultPlaylistsTab() {
    // 分组
    final grouped = <String, List<HymnCategory>>{};
    for (final c in _categories) {
      grouped.putIfAbsent(c.category, () => []).add(c);
    }

    if (grouped.isEmpty) {
      return const _EmptyHint(text: '暂无分类');
    }

    final cats = grouped.keys.toList();
    String display(String s) => ChineseConvertService.instance.toSimplified(s);

    return ListView.builder(
      itemCount: cats.length,
      itemBuilder: (context, i) {
        final cat = cats[i];
        final subs = grouped[cat]!;
        final expanded = _expandedCategories.contains(cat);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 一级分类
            Material(
              color: AppColors.cardBg,
              child: InkWell(
                onTap: () => setState(() {
                  if (expanded) {
                    _expandedCategories.remove(cat);
                  } else {
                    _expandedCategories.add(cat);
                  }
                }),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    children: [
                      Icon(
                        expanded ? Icons.expand_more : Icons.chevron_right,
                        size: 18,
                        color: AppColors.textSecondary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        display(cat),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (expanded) ...subs.map((sub) => _subcategoryItem(sub, display)),
          ],
        );
      },
    );
  }

  Widget _subcategoryItem(HymnCategory sub, String Function(String) display) {
    final selected = _selectedSubcategory == sub.subcategory;
    return Material(
      color: selected ? AppColors.selectedBg : AppColors.sidebarBg,
      child: InkWell(
        onTap: () {
          setState(() => _selectedSubcategory = sub.subcategory);
        },
        child: Container(
          padding:
              const EdgeInsets.only(left: 28, top: 6, bottom: 6, right: 12),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                width: 3,
                color: selected ? AppColors.primary : Colors.transparent,
              ),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  display(sub.subcategory),
                  style: TextStyle(
                    fontSize: 13,
                    color:
                        selected ? AppColors.primary : AppColors.textSecondary,
                  ),
                ),
              ),
              Text(
                '${sub.hymns.length}首',
                style: const TextStyle(
                    fontSize: 11, color: AppColors.textTertiary),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 个人歌单
  Widget _buildMyPlaylistsTab() {
    if (_playlists.isEmpty) {
      return const _EmptyHint(text: '暂无个人歌单');
    }
    return ListView.builder(
      itemCount: _playlists.length,
      itemBuilder: (context, i) {
        final pl = _playlists[i];
        final selected = _selectedPlaylistName == pl.name;
        return Material(
          color: selected ? AppColors.selectedBg : AppColors.cardBg,
          child: InkWell(
            onTap: () {
              setState(() => _selectedPlaylistName = pl.name);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(
                    width: 3,
                    color: selected ? AppColors.primary : Colors.transparent,
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
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.normal,
                        color: selected
                            ? AppColors.primary
                            : AppColors.textPrimary,
                      ),
                    ),
                  ),
                  Text(
                    '${pl.count}首',
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textTertiary),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline,
                        size: 16, color: AppColors.textTertiary),
                    tooltip: '删除歌单',
                    onPressed: () => _deletePlaylist(pl),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ---------- 列表项 ----------
  Widget _hymnListItem(Hymn hymn, int index, List<Hymn> contextList) {
    final current = _audio?.currentHymn;
    final isCurrent = current?.id == hymn.id;
    return Material(
      color: isCurrent ? AppColors.selectedBg : AppColors.cardBg,
      child: InkWell(
        onTap: () => _playHymnFromList(hymn, index, contextList),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                width: 3,
                color: isCurrent ? AppColors.primary : Colors.transparent,
              ),
            ),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 56,
                child: Text(
                  hymn.hymnNumber,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color:
                        isCurrent ? AppColors.primary : AppColors.textPrimary,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  ChineseConvertService.instance.toSimplified(hymn.title),
                  style: const TextStyle(
                      fontSize: 13, color: AppColors.textPrimary),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _playHymnFromList(Hymn hymn, int index, List<Hymn> contextList) {
    _audio!.setPlaylist(contextList, startIndex: index);
    _audio!.playHymn(hymn, index: index);
    setState(() {}); // 刷新正在播放高亮
  }

  // ---------- 右侧栏（源考） ----------
  Widget _buildRightPanel() {
    final hymn = _audio?.currentHymn;
    return SizedBox(
      width: 400,
      child: Container(
        color: AppColors.sidebarBg,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.all(10),
              child: Text(
                '诗歌源考',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            const Divider(height: 1, color: AppColors.divider),
            Expanded(
              child: hymn == null
                  ? const _EmptyHint(text: '请选择一首诗歌')
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        ChineseConvertService.instance.toSimplified(
                            hymn.sourceInfo.isEmpty
                                ? '暂无源考资料'
                                : hymn.sourceInfo),
                        style: const TextStyle(
                          fontSize: 13,
                          height: 1.6,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------- 底部状态栏 ----------
  Widget _buildStatusBar() {
    final hymn = _audio?.currentHymn;
    return Container(
      height: 40,
      color: AppColors.cardBg,
      child: Row(
        children: [
          const SizedBox(width: 16),
          if (hymn != null)
            Expanded(
              child: Text(
                hymn.statusMeta,
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary),
                overflow: TextOverflow.ellipsis,
              ),
            )
          else
            const Expanded(
              child: Text(
                '就绪',
                style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
              ),
            ),
          const SizedBox(width: 16),
        ],
      ),
    );
  }

  // ---------- 弹窗 ----------
  Future<void> _openCreatePlaylistDialog() async {
    final created = await showDialog<bool>(
      context: context,
      builder: (ctx) => CreatePlaylistDialog(repo: _repo!),
    );
    if (created == true && mounted) {
      setState(() {
        _playlists = _repo!.getPlaylists();
        _leftTab = LeftTab.myPlaylists;
      });
      _showToast('歌单创建成功');
    }
  }

  void _deletePlaylist(Playlist pl) {
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除歌单'),
        content: Text('确定删除歌单「${pl.name}」吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    ).then((ok) {
      if (ok == true && mounted) {
        setState(() {
          _repo!.deletePlaylist(pl.id);
          _playlists = _repo!.getPlaylists();
          if (_selectedPlaylistName == pl.name) _selectedPlaylistName = null;
        });
        _showToast('已删除');
      }
    });
  }

  void _showToast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

/// 空状态提示
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
