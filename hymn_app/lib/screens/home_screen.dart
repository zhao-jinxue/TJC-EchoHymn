import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app.dart';
import '../models/hymn.dart';
import '../services/app_state_service.dart';
import '../services/audio_service.dart';
import '../services/chinese_convert_service.dart';
import '../services/log_service.dart';
import '../services/sqlite_repository.dart';
import '../widgets/hymn_display.dart';
import '../widgets/panels/default_playlists_panel.dart';
import '../widgets/panels/hymn_list_panel.dart';
import '../widgets/panels/left_panel_base.dart';
import '../widgets/panels/my_playlists_panel.dart';

/// 左侧栏视图模式
enum LeftTab { hymnList, defaultPlaylists, myPlaylists }

/// Windows 窗口尺寸控制通道（native 侧 flutter_window.cpp 注册）
const MethodChannel _windowChannel = MethodChannel('echo_hymn/window');

/// 基座画面物理像素尺寸（用户屏幕实际像素，不受 DPI 缩放影响）
const int kBaseWindowWidth = 850; // 基座宽度
const int kBaseWindowHeight = 890; // 基座高度
const int kLeftPanelWidth = 350; // 歌单列表展开宽度（物理像素）
const int kRightPanelWidth = 600; // 诗歌源考展开宽度（物理像素）

/// 主界面：顶栏 + 左栏（三面板之一）+ 主内容区 + 右栏 + 底部状态栏
///
/// 本类是「协调者」：只负责
/// - 顶栏/主体/右栏/状态栏布局
/// - 左栏三 Tab 的切换与对应面板构建（面板各自持有显示/交互/恢复逻辑）
/// - 锚点状态保存（leftTab/诗歌/版本/歌词/播放列表位置）
/// - 播放来源状态同步（面板播放时回调）
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
  // 默认收起两侧栏 = 基座画面（最简播放画面，窗口 850 宽）；
  // 需要歌单/源考时再展开（展开时窗口可手动加宽容纳）。
  bool _showLeft = false;
  bool _showRight = false;

  // ---- 左栏视图状态 ----
  LeftTab _leftTab = LeftTab.hymnList;
  int _restoredPlaylistIndex = -1;

  // ---- 数据缓存（供状态保存/恢复判断来源） ----
  List<Hymn> _allHymns = const [];

  // ---- 播放来源（供保存 leftTab） ----
  String? _playSubcategory; // 当前播放来自默认歌单的二级目录
  String? _playPlaylistName; // 当前播放来自个人歌单名

  // 当前持久化值
  String _currentAudioVersion = '鋼琴版';
  String _currentDisplayMode = 'lyrics';

  // 恢复锚点（传给左栏面板自动恢复）
  AppState? _anchor;

  @override
  void initState() {
    super.initState();
    LogService.instance.info(LogTag.ui, 'HomeScreen 初始化（initState）');
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _saveState(); // 关闭时保存
    _repo?.dispose();
    _audio?.dispose();
    LogService.instance.info(LogTag.system, 'HomeScreen 销毁（应用关闭）');
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      LogService.instance.info(LogTag.system, '应用生命周期变化: ${state.name}，保存状态');
      _saveState();
    }
  }

  Future<void> _init() async {
    try {
      LogService.instance.info(LogTag.ui, 'HomeScreen 初始化数据中...');
      final repo = await SqliteRepository.open();
      final audio = AudioService();
      final state = await _stateService.load().catchError((_) => const AppState(
            leftTab: '',
            subcategory: '',
            playlistName: '',
            hymnNumber: '',
            audioVersion: '',
            displayMode: '',
            playlistIndex: -1,
          ));

      if (!mounted) return;
      // 切歌（上一首/下一首/播放完成）时自动保存状态
      audio.onCurrentChanged = _saveState;
      setState(() {
        _repo = repo;
        _audio = audio;
        _allHymns = repo.getAllHymns();
        _currentAudioVersion =
            state.audioVersion.isEmpty ? '鋼琴版' : state.audioVersion;
        _currentDisplayMode =
            state.displayMode.isEmpty ? 'lyrics' : state.displayMode;
        _restoredPlaylistIndex = state.playlistIndex;
        _playSubcategory = state.subcategory.isEmpty ? null : state.subcategory;
        _playPlaylistName =
            state.playlistName.isEmpty ? null : state.playlistName;
        // 恢复左栏视图
        if (state.leftTab == 'defaultPlaylists') {
          _leftTab = LeftTab.defaultPlaylists;
        } else if (state.leftTab == 'myPlaylists') {
          _leftTab = LeftTab.myPlaylists;
        }
        // 恢复左右侧栏展开/收起状态
        _showLeft = state.showLeft;
        _showRight = state.showRight;
      });
      // 恢复侧栏状态后同步窗口宽度
      _syncWindowSize();

      // 首次默认/恢复一首诗歌（只加载不播放，进度条从 0 开始）
      // 播放列表按「播放来源」构建：默认歌单二级目录 / 个人歌单 / 全部诗歌
      var restoreList = _allHymns;
      if (_playSubcategory != null) {
        final list = _hymnsOfSubcategory(_playSubcategory!);
        if (list.isNotEmpty) restoreList = list;
      } else if (_playPlaylistName != null) {
        final list = _hymnsOfPlaylistName(_playPlaylistName!);
        if (list.isNotEmpty) restoreList = list;
      }
      Hymn? hymn;
      if (restoreList.isNotEmpty) {
        hymn = state.hymnNumber.isNotEmpty
            ? _findInList(restoreList, state.hymnNumber)
            : restoreList.first;
      }
      if (hymn != null) {
        // 索引：恢复的播放列表位置索引优先；否则按诗歌在列表中的位置
        var idx = _restoredPlaylistIndex;
        if (idx < 0 || idx >= restoreList.length) {
          idx = restoreList.indexOf(hymn);
        }
        if (idx < 0) idx = 0;
        audio.setPlaylist(restoreList, startIndex: idx);
        audio.loadHymn(hymn, index: idx, version: _currentAudioVersion);
      }

      // 组装恢复锚点，传给左栏面板自动恢复滚动/展开/分页
      _anchor = AppState(
        leftTab: state.leftTab,
        subcategory: state.subcategory,
        playlistName: state.playlistName,
        hymnNumber: state.hymnNumber,
        audioVersion: _currentAudioVersion,
        displayMode: _currentDisplayMode,
        playlistIndex: _restoredPlaylistIndex,
      );
      setState(() {});
      LogService.instance.info(
        LogTag.ui,
        'HomeScreen 初始化完成',
        detail: '诗歌总数: ${_allHymns.length}',
      );
      LogService.instance.info(LogTag.ui, 'HomeScreen 首帧构建完成');
    } catch (e) {
      if (!mounted) return;
      LogService.instance.error(LogTag.error, 'HomeScreen 初始化失败', detail: '$e');
      setState(() => _initError = true);
    }
  }

  Hymn? _findInList(List<Hymn> list, String number) {
    for (final h in list) {
      if (h.hymnNumber == number) return h;
    }
    return null;
  }

  List<Hymn> _hymnsOfSubcategory(String subcategory) {
    final cats = _repo?.getAllCategories() ?? const [];
    final list = <Hymn>[];
    for (final c in cats) {
      if (c.subcategory == subcategory) {
        for (final e in c.hymns) {
          final h = _repo?.hymnByNumber(e.value.toString());
          if (h != null) list.add(h);
        }
      }
    }
    return list;
  }

  List<Hymn> _hymnsOfPlaylistName(String name) {
    final pls = _repo?.getPlaylists() ?? const [];
    final list = <Hymn>[];
    for (final pl in pls) {
      if (pl.name == name) {
        for (final item in pl.hymns) {
          final h = _repo?.hymnByNumber(item.value.toString());
          if (h != null) list.add(h);
        }
      }
    }
    return list;
  }

  /// 保存状态到本地
  Future<void> _saveState() async {
    final hymn = _audio?.currentHymn;
    var leftTab = _leftTab.name;
    // 按「当前播放列表来源」优先（而非当前 UI 所在栏）
    final list = _audio?.playlist ?? const <Hymn>[];
    // 仅当播放列表 = 全部诗歌（逐 id 比对）时，索引才与全局定位一致；
    // 搜索结果/歌单子集由 hymnNumber 定位，索引不保存（-1）。
    var saveIndex = false;
    if (list.isNotEmpty) {
      if (_playSubcategory != null) {
        leftTab = LeftTab.defaultPlaylists.name;
      } else if (_playPlaylistName != null) {
        leftTab = LeftTab.myPlaylists.name;
      } else {
        leftTab = LeftTab.hymnList.name;
        saveIndex = _containsAllHymns(list);
      }
    }
    await _stateService.saveAll(
      leftTab: leftTab,
      subcategory: _playSubcategory ?? '',
      playlistName: _playPlaylistName ?? '',
      hymnNumber: hymn?.hymnNumber ?? '',
      audioVersion: _currentAudioVersion,
      displayMode: _currentDisplayMode,
      playlistIndex: saveIndex ? (_audio?.currentIndex ?? -1) : -1,
      showLeft: _showLeft,
      showRight: _showRight,
    );
  }

  /// 判断 [list] 是否为全部诗歌列表（长度 + 逐 id 比对）
  bool _containsAllHymns(List<Hymn> list) {
    if (list.length != _allHymns.length) return false;
    for (var i = 0; i < list.length; i++) {
      if (list[i].id != _allHymns[i].id) return false;
    }
    return true;
  }

  // ================= 构建 =================

  /// 侧栏展开/收起时同步窗口尺寸（物理像素）：
  /// 基座画面（850 宽）永远居中，左栏向左扩展、右栏向右扩展；
  /// 向上层传左右栏宽度，native 据此计算窗口位置。
  /// 同步窗口尺寸与画布宽度（native resize 完成后再重建一次，
  /// 保证 scale 按新窗口尺寸计算，避免【收缩/展开侧栏后画面与窗口
  /// 比例不匹配】的时序竞态）。
  Future<void> _syncWindowSize() async {
    if (kIsWeb) return; // Web 无原生窗口
    try {
      await _windowChannel.invokeMethod<void>('setClientSize', {
        'width': kBaseWindowWidth,
        'height': kBaseWindowHeight,
        'leftPanelWidth': _showLeft ? kLeftPanelWidth : 0,
        'rightPanelWidth': _showRight ? kRightPanelWidth : 0,
      });
      // native 窗口 resize 完成后强制重建：
      // LayoutBuilder 拿到最新 constraints，scale = 新窗口/新画布，等比正确。
      if (mounted) setState(() {});
    } catch (_) {
      // 非 Windows 平台无此通道，忽略
    }
  }

  @override
  Widget build(BuildContext context) {
    // K10：解除等比缩放限制（不再 Transform.scale 锁定 850:890 长宽比）。
    // 内容直接随窗口长宽铺满——放大时窗口多大内容多大，无顶部/底部空白；
    // 最小尺寸由 native WM_GETMINMAXINFO（SetMinClientSize）保证。
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
              icon: _showLeft ? Icons.chevron_right : Icons.chevron_left,
              tooltip: _showLeft ? '收起左侧栏目' : '展开左侧栏目',
              active: !_showLeft,
              onTap: () {
                LogService.instance.info(
                  LogTag.action,
                  _showLeft ? '收起左侧栏目' : '展开左侧栏目',
                );
                setState(() => _showLeft = !_showLeft);
                _syncWindowSize();
                _saveState();
              },
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
              icon: _showRight ? Icons.chevron_left : Icons.chevron_right,
              tooltip: _showRight ? '收起右侧栏目' : '展开右侧栏目',
              active: !_showRight,
              onTap: () {
                LogService.instance.info(
                  LogTag.action,
                  _showRight ? '收起右侧栏目' : '展开右侧栏目',
                );
                setState(() => _showRight = !_showRight);
                _syncWindowSize();
                _saveState();
              },
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

    final repo = _repo!;
    final audio = _audio!;
    // K10：歌词区不再固定 850 逻辑宽，改 Expanded 填满剩余空间——
    // 窗口放大时歌词区随之变宽变高（配合 HymnDisplay 的 LayoutBuilder 自适应字号）。
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_showLeft) ...[
          _buildLeftPanel(repo, audio),
          const VerticalDivider(width: 1, color: AppColors.divider),
        ],
        Expanded(
          child: HymnDisplay(
            audio: audio,
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
      ],
    );
  }

  // ---------- 左侧栏：tab + 对应面板 ----------
  Widget _buildLeftPanel(SqliteRepository repo, AudioService audio) {
    // 物理 350px ÷ devicePixelRatio = 逻辑宽度（保证各 DPI 下物理宽度恒为 350）
    final leftWidth = kLeftPanelWidth / MediaQuery.devicePixelRatioOf(context);
    return SizedBox(
      width: leftWidth,
      child: Container(
        color: AppColors.sidebarBg,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildLeftTabBar(),
            const Divider(height: 1, color: AppColors.divider),
            // 三 Tab 面板分发：各自持有显示/交互/恢复逻辑，互不影响
            Expanded(
              child: switch (_leftTab) {
                LeftTab.hymnList => HymnListPanel(
                    key: const ValueKey('hymnList'),
                    audio: audio,
                    repo: repo,
                    anchor: _anchor,
                    onPlayback: _onPlayback,
                  ),
                LeftTab.defaultPlaylists => DefaultPlaylistsPanel(
                    key: const ValueKey('defaultPlaylists'),
                    audio: audio,
                    repo: repo,
                    anchor: _anchor,
                    onPlayback: _onPlayback,
                  ),
                LeftTab.myPlaylists => MyPlaylistsPanel(
                    key: const ValueKey('myPlaylists'),
                    audio: audio,
                    repo: repo,
                    anchor: _anchor,
                    onPlayback: _onPlayback,
                  ),
              },
            ),
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
            LogService.instance.info(
              LogTag.action,
              '切换左侧栏目: $label',
            );
            setState(() => _leftTab = tab);
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

  /// 面板内点击播放回调：同步播放来源并保存状态
  void _onPlayback(PlaybackEvent e) {
    LogService.instance.info(
      LogTag.play,
      '面板点击播放：第 ${e.hymn.hymnNumber} 首《${e.hymn.title}》',
      detail: '来源子目录: ${e.sourceSubcategory ?? '无'}\n'
          '来源个人歌单: ${e.sourcePlaylistName ?? '无'}\n'
          '列表位置: ${e.index}',
    );
    _playSubcategory = e.sourceSubcategory;
    _playPlaylistName = e.sourcePlaylistName;
    if (e.sourceSubcategory != null) {
      _leftTab = LeftTab.defaultPlaylists;
    } else if (e.sourcePlaylistName != null) {
      _leftTab = LeftTab.myPlaylists;
    } else {
      _leftTab = LeftTab.hymnList;
    }
    setState(() {});
    _saveState();
  }

  // ---------- 右侧栏（源考） ----------
  Widget _buildRightPanel() {
    final hymn = _audio?.currentHymn;
    // 物理 600px ÷ devicePixelRatio = 逻辑宽度（保证各 DPI 下物理宽度恒为 600）
    final rightWidth =
        kRightPanelWidth / MediaQuery.devicePixelRatioOf(context);
    return SizedBox(
      width: rightWidth,
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
                ChineseConvertService.instance.toSimplified(hymn.statusMeta),
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
          // C02：播放进度（位置 / 总时长 · 百分比）
          StreamBuilder<Duration>(
            stream: _audio?.positionStream ?? const Stream<Duration>.empty(),
            builder: (context, posSnap) {
              final pos = posSnap.data ?? Duration.zero;
              return StreamBuilder<Duration>(
                stream: _audio?.durationStream ?? const Stream<Duration>.empty(),
                builder: (context, durSnap) {
                  final dur = durSnap.data ?? Duration.zero;
                  final pct = dur.inMilliseconds > 0
                      ? (pos.inMilliseconds * 100 / dur.inMilliseconds).floor()
                      : 0;
                  return Padding(
                    padding: const EdgeInsets.only(right: 16),
                    child: Text(
                      '${formatTime(pos)} / ${formatTime(dur)} · $pct%',
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary),
                    ),
                  );
                },
              );
            },
          ),
        ],
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
