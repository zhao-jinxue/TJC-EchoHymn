import 'dart:async';

import 'package:flutter/material.dart';

import '../app.dart';
import '../models/hymn.dart';
import '../models/hymn_category.dart';
import '../models/playlist.dart';
import '../services/app_state_service.dart';
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

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  SqliteRepository? _repo;
  AudioService? _audio;
  bool _initError = false;
  final AppStateService _stateService = AppStateService();

  // ---- 布局状态 ----
  bool _showLeft = true;
  bool _showRight = true;

  // ---- 左侧栏状态 ----
  LeftTab _leftTab = LeftTab.hymnList;
  String _searchKeyword = '';
  final Set<String> _expandedCategories = {};

  // 当前选中的歌单
  String? _selectedSubcategory;
  String? _selectedPlaylistName;

  // 数据缓存
  List<Hymn> _allHymns = const [];
  List<HymnCategory> _categories = const [];
  List<Playlist> _playlists = const [];

  // 当前持久化值
  String _currentAudioVersion = '鋼琴版';
  String _currentDisplayMode = 'lyrics';

  // ---- 列表联动（上一首/下一首时滚动到当前项） ----
  StreamSubscription<PlayerStatus>? _audioStatusSub;
  final ScrollController _hymnListScroll = ScrollController();
  final ScrollController _defaultListScroll = ScrollController();
  final ScrollController _myListScroll = ScrollController();

  // 默认歌单二级目录的诗歌列表（选中时展示）
  List<Hymn> _defaultPlaylistHymns = const [];
  bool _showDefaultPlaylistContent = false;

  // 个人歌单的诗歌列表（选中歌单时展示）
  List<Hymn> _myPlaylistHymns = const [];
  bool _showMyPlaylistContent = false;
  static const int _pageSize = 35;
  static const double _itemHeight = 34; // 列表项近似高度（滚动定位用）
  int _listPage = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _saveState(); // 关闭时保存
    _audioStatusSub?.cancel();
    _hymnListScroll.dispose();
    _defaultListScroll.dispose();
    _myListScroll.dispose();
    _repo?.dispose();
    _audio?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _saveState();
    }
  }

  Future<void> _init() async {
    try {
      final repo = await SqliteRepository.open();
      final audio = AudioService();
      final state = await _stateService.load().catchError((_) => const AppState(
            leftTab: '',
            subcategory: '',
            playlistName: '',
            hymnNumber: '',
            audioVersion: '',
            displayMode: '',
          ));

      if (!mounted) return;
      // 监听播放状态：错误 Toast（由 HymnDisplay 处理）+ 列表滚动高亮
      _audioStatusSub = audio.statusStream.listen((s) {
        if (!mounted) return;
        setState(() {});
        if (s == PlayerStatus.playing || s == PlayerStatus.loading) {
          _syncListScroll();
        }
      });
      setState(() {
        _repo = repo;
        _audio = audio;
        _allHymns = repo.getAllHymns();
        _categories = repo.getAllCategories();
        _playlists = repo.getPlaylists();

        // 恢复左栏视图
        if (state.leftTab == 'defaultPlaylists') {
          _leftTab = LeftTab.defaultPlaylists;
        } else if (state.leftTab == 'myPlaylists') {
          _leftTab = LeftTab.myPlaylists;
        }
        _selectedSubcategory =
            state.subcategory.isEmpty ? null : state.subcategory;
        _selectedPlaylistName =
            state.playlistName.isEmpty ? null : state.playlistName;
        _currentAudioVersion =
            state.audioVersion.isEmpty ? '鋼琴版' : state.audioVersion;
        _currentDisplayMode =
            state.displayMode.isEmpty ? 'lyrics' : state.displayMode;
      });

      // 恢复/默认加载诗歌
      Hymn? hymn;
      if (_selectedSubcategory != null) {
        final sub = _categories
            .where((c) => c.subcategory == _selectedSubcategory)
            .toList();
        if (sub.isNotEmpty) {
          final list = _buildCategoryHymns(sub.first);
          _defaultPlaylistHymns = list;
          _showDefaultPlaylistContent = list.isNotEmpty;
          if (list.isNotEmpty) {
            hymn = state.hymnNumber.isNotEmpty
                ? _findInList(list, state.hymnNumber)
                : list.first;
          }
        }
      } else if (_selectedPlaylistName != null) {
        final pl =
            _playlists.where((p) => p.name == _selectedPlaylistName).toList();
        if (pl.isNotEmpty) {
          final list = _buildPlaylistHymns(pl.first);
          _myPlaylistHymns = list;
          _showMyPlaylistContent = list.isNotEmpty;
          if (list.isNotEmpty) {
            hymn = state.hymnNumber.isNotEmpty
                ? _findInList(list, state.hymnNumber)
                : list.first;
          }
        }
      }

      if (hymn == null && _allHymns.isNotEmpty) {
        hymn = state.hymnNumber.isNotEmpty
            ? _findInList(_allHymns, state.hymnNumber)
            : _allHymns.first; // 首次默认第一首
      }

      if (hymn != null) {
        _playFromInit(hymn);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _initError = true);
    }
  }

  Hymn? _findInList(List<Hymn> list, String number) {
    for (final h in list) {
      if (h.hymnNumber == number) return h;
    }
    return null;
  }

  void _playFromInit(Hymn hymn) {
    final audio = _audio!;
    // 播放列表用当前上下文（二级目录 / 个人歌单 / 全部诗歌）
    List<Hymn> ctx = _allHymns;
    if (_selectedSubcategory != null && _defaultPlaylistHymns.isNotEmpty) {
      ctx = _defaultPlaylistHymns;
    } else if (_selectedPlaylistName != null && _myPlaylistHymns.isNotEmpty) {
      ctx = _myPlaylistHymns;
    }
    final idx = ctx.indexOf(hymn);
    audio.setPlaylist(ctx, startIndex: idx >= 0 ? idx : 0);
    audio.playHymn(hymn,
        index: idx >= 0 ? idx : 0, version: _currentAudioVersion);
    setState(() {});
    _saveState();
  }

  /// 保存状态到本地
  Future<void> _saveState() async {
    final hymn = _audio?.currentHymn;
    await _stateService.saveAll(
      leftTab: _leftTab.name,
      subcategory: _selectedSubcategory ?? '',
      playlistName: _selectedPlaylistName ?? '',
      hymnNumber: hymn?.hymnNumber ?? '',
      audioVersion: _currentAudioVersion,
      displayMode: _currentDisplayMode,
    );
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
          // 左侧按钮：未展开=蓝+展开箭头；已展开=灰+收起箭头
          SizedBox(
            width: 60,
            height: 30,
            child: _toggleButton(
              icon: _showLeft ? Icons.chevron_right : Icons.chevron_left,
              tooltip: _showLeft ? '收起左侧栏目' : '展开左侧栏目',
              active: !_showLeft,
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
          // 右侧按钮：未展开=蓝+展开箭头；已展开=灰+收起箭头
          SizedBox(
            width: 60,
            height: 30,
            child: _toggleButton(
              icon: _showRight ? Icons.chevron_left : Icons.chevron_right,
              tooltip: _showRight ? '收起右侧栏目' : '展开右侧栏目',
              active: !_showRight,
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
      child: Tooltip(
        message: tooltip,
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
      Expanded(
        child: HymnDisplay(
          audio: _audio!,
          initialMode: _currentDisplayMode,
          onModeChanged: (mode) {
            _currentDisplayMode = mode;
            _saveState();
          },
          onAudioVersionChanged: (v) {
            _currentAudioVersion = v;
            _saveState();
          },
        ),
      ),
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
      width: 280,
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
          onTap: () {
            setState(() {
              _leftTab = tab;
              _showDefaultPlaylistContent = false;
              _showMyPlaylistContent = false;
            });
            _saveState();
          },
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

  // ---------- 左侧内容 ----------
  Widget _buildLeftTabContent() {
    switch (_leftTab) {
      case LeftTab.hymnList:
        return _buildHymnListTab();
      case LeftTab.defaultPlaylists:
        return _showDefaultPlaylistContent
            ? _buildDefaultPlaylistContent()
            : _buildDefaultPlaylistsTab();
      case LeftTab.myPlaylists:
        return _showMyPlaylistContent
            ? _buildMyPlaylistContent()
            : _buildMyPlaylistsTab();
    }
  }

  // 诗歌列表（分页：每页 50 首）
  Widget _buildHymnListTab() {
    final all = _searchKeyword.isEmpty
        ? _allHymns
        : (_repo?.searchHymns(_searchKeyword) ?? const []);
    final totalPages = (all.length / _pageSize).ceil().clamp(1, 1 << 31);
    if (_listPage >= totalPages) _listPage = totalPages - 1;
    if (_listPage < 0) _listPage = 0;
    final start = _listPage * _pageSize;
    final end = (start + _pageSize).clamp(0, all.length);
    final hymns = all.sublist(start, end);
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
                      onPressed: () {
                        setState(() {
                          _searchKeyword = '';
                          _listPage = 0;
                        });
                      },
                    ),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
            ),
            onChanged: (v) {
              setState(() {
                _searchKeyword = v;
                _listPage = 0;
              });
            },
          ),
        ),
        Expanded(
          child: hymns.isEmpty
              ? const _EmptyHint(text: '未找到相关诗歌')
              : ListView.builder(
                  controller: _hymnListScroll,
                  itemCount: hymns.length,
                  itemBuilder: (context, index) =>
                      _hymnListItem(hymns[index], start + index, all),
                ),
        ),
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

  // 默认歌单：一级分类 → 二级目录 → 点二级展示诗歌
  Widget _buildDefaultPlaylistsTab() {
    final grouped = <String, List<HymnCategory>>{};
    for (final c in _categories) {
      grouped.putIfAbsent(c.category, () => []).add(c);
    }
    if (grouped.isEmpty) return const _EmptyHint(text: '暂无分类');

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
          setState(() {
            _selectedSubcategory = sub.subcategory;
            _defaultPlaylistHymns = _buildCategoryHymns(sub);
            _showDefaultPlaylistContent = true;
          });
          _saveState();
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

  /// 默认歌单二级目录的诗歌列表视图
  Widget _buildDefaultPlaylistContent() {
    final display = ChineseConvertService.instance.toSimplified;
    String name = '';
    if (_selectedSubcategory != null) {
      final title = _categories
          .where((c) => c.subcategory == _selectedSubcategory)
          .toList();
      if (title.isNotEmpty) name = display(title.first.subcategory);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, size: 18),
                tooltip: '返回分类目录',
                onPressed: () =>
                    setState(() => _showDefaultPlaylistContent = false),
              ),
              Expanded(
                child: Text(
                  name,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '${_defaultPlaylistHymns.length}首',
                style: const TextStyle(
                    fontSize: 11, color: AppColors.textTertiary),
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: AppColors.divider),
        Expanded(
          child: _defaultPlaylistHymns.isEmpty
              ? const _EmptyHint(text: '暂无诗歌')
              : ListView.builder(
                  controller: _defaultListScroll,
                  itemCount: _defaultPlaylistHymns.length,
                  itemBuilder: (context, index) => _hymnListItem(
                      _defaultPlaylistHymns[index],
                      index,
                      _defaultPlaylistHymns),
                ),
        ),
      ],
    );
  }

  List<Hymn> _buildCategoryHymns(HymnCategory sub) {
    final list = <Hymn>[];
    for (final entry in sub.hymns) {
      final h = _repo?.hymnByNumber(entry.value.toString());
      if (h != null) list.add(h);
    }
    return list;
  }

  // 个人歌单
  Widget _buildMyPlaylistsTab() {
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
                  itemCount: _playlists.length,
                  itemBuilder: (context, i) {
                    final pl = _playlists[i];
                    final selected = _selectedPlaylistName == pl.name;
                    return Material(
                      color: selected ? AppColors.selectedBg : AppColors.cardBg,
                      child: InkWell(
                        onTap: () {
                          setState(() {
                            _selectedPlaylistName = pl.name;
                            _myPlaylistHymns = _buildPlaylistHymns(pl);
                            _showMyPlaylistContent = true;
                          });
                          _saveState();
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
                                onPressed: () => _openEditPlaylistDialog(pl),
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

  List<Hymn> _buildPlaylistHymns(Playlist pl) {
    final list = <Hymn>[];
    for (final item in pl.hymns) {
      // item = {标题: 编号}（与 hymn_category.hymns 一致，编号即数据库 hymn_number）
      final h = _repo?.hymnByNumber(item.value.toString());
      if (h != null) list.add(h);
    }
    return list;
  }

  /// 个人歌单的诗歌列表视图（点击歌单后展示，可播放）
  Widget _buildMyPlaylistContent() {
    final display = ChineseConvertService.instance.toSimplified;
    String name = '';
    if (_selectedPlaylistName != null) {
      final pl =
          _playlists.where((p) => p.name == _selectedPlaylistName).toList();
      if (pl.isNotEmpty) name = display(pl.first.name);
    }
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
                onPressed: () => setState(() => _showMyPlaylistContent = false),
              ),
              Expanded(
                child: Text(
                  name,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '${_myPlaylistHymns.length}首',
                style: const TextStyle(
                    fontSize: 11, color: AppColors.textTertiary),
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: AppColors.divider),
        Expanded(
          child: _myPlaylistHymns.isEmpty
              ? const _EmptyHint(text: '暂无诗歌')
              : ListView.builder(
                  controller: _myListScroll,
                  itemCount: _myPlaylistHymns.length,
                  itemBuilder: (context, index) => _hymnListItem(
                      _myPlaylistHymns[index], index, _myPlaylistHymns),
                ),
        ),
      ],
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
    _audio!.playHymn(hymn, index: index, version: _currentAudioVersion);
    setState(() {});
    _saveState();
  }

  /// 上一首/下一首（或任意播放切换）时，将左侧列表滚动到当前项并保证翻页
  void _syncListScroll() {
    final audio = _audio;
    if (audio == null || !mounted) return;
    final idx = audio.currentIndex;
    if (idx < 0) return;
    final list = audio.playlist;
    if (list.isEmpty) return;

    ScrollController? controller;
    var localIndex = idx;

    if (_leftTab == LeftTab.hymnList) {
      final all = _searchKeyword.isEmpty
          ? _allHymns
          : (_repo?.searchHymns(_searchKeyword) ?? const []);
      if (identical(list, all)) {
        final page = idx ~/ _pageSize;
        if (page != _listPage) {
          _listPage = page;
          setState(() {});
        }
        localIndex = idx - _listPage * _pageSize;
        controller = _hymnListScroll;
      }
    } else if (_leftTab == LeftTab.defaultPlaylists &&
        _showDefaultPlaylistContent &&
        identical(list, _defaultPlaylistHymns)) {
      controller = _defaultListScroll;
    } else if (_leftTab == LeftTab.myPlaylists &&
        _showMyPlaylistContent &&
        identical(list, _myPlaylistHymns)) {
      controller = _myListScroll;
    }

    if (controller == null) return;
    final target = localIndex * _itemHeight;
    final ctrl = controller;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !ctrl.hasClients) return;
      final max = ctrl.position.maxScrollExtent;
      ctrl
          .animateTo(
            target.clamp(0.0, max).toDouble(),
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          )
          .catchError((_) {});
    });
  }

  // ---------- 右侧栏（源考） ----------
  Widget _buildRightPanel() {
    final hymn = _audio?.currentHymn;
    return SizedBox(
      width: 340,
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
  /// 新建歌单弹窗
  Future<void> _openCreatePlaylistDialog() async {
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => CreatePlaylistDialog(repo: _repo!),
    );
    if (!mounted) return;
    if (result == 'create') {
      setState(() {
        _playlists = _repo!.getPlaylists();
        _leftTab = LeftTab.myPlaylists;
        _showMyPlaylistContent = false;
      });
      _saveState();
      _showToast('歌单创建成功');
    }
  }

  /// 修改歌单弹窗（复用创建弹窗，编辑模式追加「删除歌单」按钮）
  Future<void> _openEditPlaylistDialog(Playlist pl) async {
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => CreatePlaylistDialog(repo: _repo!, existing: pl),
    );
    if (!mounted) return;
    if (result == 'save') {
      setState(() {
        _playlists = _repo!.getPlaylists();
        final updated = _playlists.where((p) => p.id == pl.id).toList();
        if (updated.isNotEmpty) {
          final newPl = updated.first;
          // 歌单可能被重命名，同步选中的歌单名与内容
          if (_selectedPlaylistName == pl.name) {
            _selectedPlaylistName = newPl.name;
            _myPlaylistHymns = _buildPlaylistHymns(newPl);
          }
        }
      });
      _saveState();
      _showToast('歌单已保存');
    } else if (result == 'delete') {
      setState(() {
        _repo!.deletePlaylist(pl.id);
        _playlists = _repo!.getPlaylists();
        if (_selectedPlaylistName == pl.name) {
          _selectedPlaylistName = null;
          _myPlaylistHymns = const [];
          _showMyPlaylistContent = false;
        }
      });
      _saveState();
      _showToast('歌单已删除');
    }
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
