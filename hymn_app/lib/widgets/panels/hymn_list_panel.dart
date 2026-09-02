import 'package:flutter/material.dart';

import '../../../models/hymn.dart';
import '../../../services/app_state_service.dart';
import '../../../services/chinese_convert_service.dart';
import '../../../services/hymn_search_service.dart';
import '../../../services/log_service.dart';
import '../../app.dart';
import '../hymn_search_dialog.dart';
import 'left_panel_base.dart';

/// 诗歌列表面板：按编号分页展示全部诗歌 + 搜索定位 + 分页
///
/// 搜索框语义 = **定位跳转**（而非过滤列表），列表始终保持完整 474 首分页：
/// - 输入编号 → 第一次回车翻页 + 滚动 + 高亮定位（**不自动播放**），
///   第二次回车播放并**自动清空搜索框**（S02，为下一次搜索做准备）
/// - 输入中文 → 歌名+歌词统一模糊搜索：命中 → 统一搜索结果弹窗（歌名关键字
///   红色加粗 / 歌词关键字主题色加粗，显示第一个命中节且从关键字所在行开窗）；
///   弹窗单击行选中、**双击行 = 关闭弹窗 + 定位 + 播放 + 清框**；
///   再次回车 = 重新弹窗（S11/S24：回车不直接播放，不双击 = 不选择）
/// - 无命中 → 左栏「未找到匹配的诗歌」+ Toast；清除（×）→ 强制滚回当前定位行
/// - 定位后点播放条播放，或点下一首/上一首 = 从定位处开始切换
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

  /// 搜索框焦点：第一次回车搜索后保持焦点，使第二次回车能继续触发（K11b/K11c）
  final FocusNode _searchFocus = FocusNode();
  int _listPage = 0;

  /// 搜索无命中空态：true = 左栏显示「未找到匹配的诗歌」
  /// （歌名/歌词命中的结果不再占用左栏，改由统一搜索弹窗呈现）
  bool _searchEmpty = false;

  /// 已完成的搜索关键字（第一次回车后设置；第二次回车播放，输入变化重置）
  String? _activeSearchKw;

  @override
  void dispose() {
    _scroll.dispose();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  /// 诗歌行渲染：编号 + 标题（来源 = 全部诗歌，无需来源标识）
  @override
  Widget buildHymnTile(Hymn hymn, int index, List<Hymn> contextList) {
    final isCurrent = currentHymn?.id == hymn.id;
    return Material(
      color: isCurrent ? AppColors.selectedBg : AppColors.sidebarBg,
      child: InkWell(
        onTap: () => playHymn(hymn, index, contextList),
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
                  style: TextStyle(
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

  // ================= 定位 =================

  /// 在完整列表中定位 [hymn] 所在页并滚动到可视区域（避开搜索框）。
  /// S04：滚动统一排到帧后——空态/换页时 ListView 重建后 `_scroll` 才重新挂载，
  /// 同步 jumpTo 会因 hasClients 为旧值而失效。
  void _locateAndScroll(Hymn hymn, {bool force = false}) {
    final all = repo.getAllHymns();
    final idx = all.indexWhere((h) => h.id == hymn.id);
    if (idx < 0) return;
    final page = idx ~/ _pageSize;
    if (page != _listPage) {
      setState(() => _listPage = page);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      scrollCurrentIntoView(_scroll, idx - page * _pageSize,
          headerHeight: 56, force: force);
    });
  }

  /// 定位 + 加载高亮（**不播放**）：回到完整列表视图、翻页滚动高亮该行，
  /// 并把播放上下文设为「完整列表 + 定位处」，之后播放/下一首/上一首从该处开始。
  void _locateTo(Hymn hymn) {
    final all = repo.getAllHymns();
    final idx = all.indexWhere((h) => h.id == hymn.id);
    if (idx < 0) return;
    setState(() => _searchEmpty = false);
    _locateAndScroll(hymn);
    audio.setPlaylist(all, startIndex: idx);
    audio.loadHymn(hymn, index: idx, version: audio.currentAudioVersion);
  }

  // ================= 搜索匹配 =================

  Hymn? _findByNumber(String kw) {
    final all = repo.getAllHymns();
    final exact = all.where((h) => h.hymnNumber == kw).toList();
    if (exact.isNotEmpty) return exact.first;
    final prefix = all.where((h) => h.hymnNumber.startsWith(kw)).toList();
    return prefix.isNotEmpty ? prefix.first : null;
  }

  List<Hymn> _titleMatches(String kw) {
    // 双向匹配：
    // ① 库标题转简后包含「简体关键字」（用户输入繁体 → 匹配）
    // ② 关键字转繁后包含于「库原始繁体标题」（用户输入简体 → 匹配）
    final kwS = ChineseConvertService.instance.toSimplified(kw);
    final kwT = ChineseConvertService.instance.toTraditional(kw);
    return repo.getAllHymns().where((h) {
      if (kwS.isNotEmpty &&
          ChineseConvertService.instance.toSimplified(h.title).contains(kwS)) {
        return true;
      }
      return kwT.isNotEmpty && kwT != kwS && h.title.contains(kwT);
    }).toList();
  }

  Hymn? _findByTitle(String kw) {
    final matches = _titleMatches(kw);
    return matches.isNotEmpty ? matches.first : null;
  }

  void _onSearchChanged(String v) {
    // 输入变化不再即时搜索（C03/K11）：只做状态重置，等回车触发搜索。
    final kw = v.trim();
    if (kw.isEmpty) {
      // 输入清空（back 删空 / × 清除）：回到分页列表，保持当前定位
      // （S04：空态→列表重建会丢滚动位置，force 滚回定位行）
      setState(() {
        _searchEmpty = false;
        _activeSearchKw = null;
      });
      final cur = currentHymn;
      if (cur != null) _locateAndScroll(cur, force: true);
    } else if (_activeSearchKw != null && kw != _activeSearchKw) {
      // 已搜索后修改输入：重置已搜索状态，需重新回车
      _activeSearchKw = null;
    }
  }

  void _onSearchSubmitted(String v) {
    final kw = v.trim();
    if (kw.isEmpty) return;
    // 中文关键字：每次回车都重新执行搜索（S11/S24——弹窗是唯一播放入口，
    // 双击选中才播放；回车从不直接播放某首，未选中 = 用户放弃本次结果）
    if (int.tryParse(kw) == null) {
      _performSearch(kw);
      return;
    }
    // 编号关键字：两次回车状态机——第一次定位，第二次播放（与之前一致）
    if (_activeSearchKw != kw) {
      _activeSearchKw = kw;
      _performSearch(kw);
      return;
    }
    final target = _findByNumber(kw) ?? _findByTitle(kw);
    if (target == null) {
      _showSearchToast('未找到相关诗歌：$kw');
      _activeSearchKw = null;
      return;
    }
    final all = repo.getAllHymns();
    final idx = all.indexWhere((h) => h.id == target.id);
    LogService.instance.info(
      LogTag.action,
      '搜索回车播放: $kw',
      detail: '定位到第 ${target.hymnNumber} 首《${target.title}》',
    );
    _locateTo(target);
    playHymn(target, idx, all);
    // S02：播放后清空搜索框，为下一次搜索做准备（防止再回车从头重播）
    _clearSearchAfterPlay();
  }

  /// 播放动作完成后清空搜索框并复位搜索状态（S02；定位/高亮保持不动）
  void _clearSearchAfterPlay() {
    _searchCtrl.clear();
    _activeSearchKw = null;
  }

  /// 执行搜索（每次回车都执行）：
  /// - 编号 → 定位高亮（不播放，第二次回车才播放；与之前一致）
  /// - 中文 → 歌名+歌词统一模糊搜索：命中 → 结果弹窗（唯一播放入口）；
  ///   无命中 → 空态 + Toast
  void _performSearch(String kw) {
    if (int.tryParse(kw) != null) {
      final target = _findByNumber(kw) ?? _findByTitle(kw);
      if (target == null) {
        LogService.instance.info(LogTag.action, '搜索编号无匹配: $kw');
        setState(() => _searchEmpty = true);
        _showSearchToast('未找到相关诗歌：$kw');
      } else {
        // 编号：定位高亮（不播放，第二次回车才播放）
        LogService.instance.info(
          LogTag.action,
          '搜索编号: $kw',
          detail: '定位到第 ${target.hymnNumber} 首《${target.title}》',
        );
        _locateTo(target);
      }
      _keepSearchFocus();
      return;
    }
    final hits = HymnSearchService.search(repo.getAllHymns(), kw);
    if (hits.isEmpty) {
      LogService.instance.info(LogTag.action, '搜索歌名+歌词无匹配: $kw');
      setState(() => _searchEmpty = true);
      _showSearchToast('未找到相关诗歌：$kw');
      _keepSearchFocus();
    } else {
      final titleCount = hits.where((h) => h.titleMatched).length;
      LogService.instance.info(
        LogTag.action,
        '搜索歌名+歌词: $kw',
        detail: '命中 ${hits.length} 首（歌名 $titleCount 首 / '
            '歌词 ${hits.length - titleCount} 首）',
      );
      // 命中走弹窗呈现；左栏若处于无命中空态则恢复分页列表
      if (_searchEmpty) setState(() => _searchEmpty = false);
      _showHits(hits, kw);
    }
  }

  /// K11b/K11c：搜索框保持焦点，使第二次回车仍能触发 onSubmitted 播放
  /// （弹窗展示期间不抢焦点——弹窗持有焦点，关闭后再回焦搜索框）
  void _keepSearchFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _searchFocus.requestFocus();
      // S09：桌面端焦点移入 TextField 默认全选文本导致光标不可见——
      // 折叠光标到文本末尾，保持可继续编辑
      _searchCtrl.selection =
          TextSelection.collapsed(offset: _searchCtrl.text.length);
    });
  }

  /// 展示统一搜索弹窗；双击选中 = 定位并播放，关闭未选 = 回焦搜索框
  Future<void> _showHits(List<HymnSearchHit> hits, String kw) async {
    final picked =
        await showHymnSearchDialog(context, hits: hits, keyword: kw);
    if (!mounted) return;
    if (picked != null) {
      _openHit(picked);
    } else {
      _keepSearchFocus();
    }
  }

  /// 打开搜索命中的诗歌：回到完整列表，翻页定位 + 播放；播后清框（S02 同理）
  void _openHit(Hymn hymn) {
    final all = repo.getAllHymns();
    final idx = all.indexWhere((h) => h.id == hymn.id);
    if (idx < 0) return;
    LogService.instance.info(
      LogTag.action,
      '搜索弹窗播放',
      detail: '定位到第 ${hymn.hymnNumber} 首《${hymn.title}》',
    );
    _locateTo(hymn);
    playHymn(hymn, idx, all);
    _clearSearchAfterPlay();
  }

  void _showSearchToast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ================= 切歌联动 / 恢复 =================

  @override
  void syncWithPlayback() {
    final hymn = currentHymn;
    if (hymn == null) return;
    if (_searchEmpty) setState(() => _searchEmpty = false);
    _locateAndScroll(hymn);
  }

  @override
  void restoreSaved(AppState anchor) {
    final all = repo.getAllHymns();
    if (all.isEmpty) return;
    int? idx;
    // ① 当前播放歌曲优先：用户最终留下的播放状态最可靠
    // （修复 G11：切 Tab 重建后面板用旧页码快照定位，导致高亮与播放歌曲错位）
    final cur = currentHymn;
    if (cur != null) {
      final i = all.indexWhere((h) => h.id == cur.id);
      if (i >= 0) idx = i;
    }
    // ② 兜底：播放索引 → 诗歌编号（J06：搜索定位播放后重启按编号恢复）
    if (idx == null) {
      idx = anchor.playlistIndex;
      if (idx < 0 || idx >= all.length) {
        if (anchor.hymnNumber.isEmpty) return;
        idx = all.indexWhere((h) => h.hymnNumber == anchor.hymnNumber);
        if (idx < 0) return;
      }
    }
    final page = idx ~/ _pageSize;
    if (page != _listPage) {
      _listPage = page;
      setState(() {});
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final local = idx! - _listPage * _pageSize;
      // G11：避开顶部搜索栏（56px），否则高亮行被搜索栏遮挡
      scrollCurrentIntoView(_scroll, local, headerHeight: 56);
    });
  }

  // ================= 构建 =================

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSearchBar(),
        Divider(height: 1, color: AppColors.divider),
        Expanded(
          child: _searchEmpty
              ? const _EmptyHint(text: '未找到匹配的诗歌')
              : _buildPageList(),
        ),
        if (!_searchEmpty) _buildPagination(),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: TextField(
        controller: _searchCtrl,
        focusNode: _searchFocus,
        decoration: InputDecoration(
          hintText: '搜索编号 / 歌名 / 歌词',
          prefixIcon: const Icon(Icons.search, size: 18),
          suffixIcon: _searchCtrl.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.clear, size: 16),
                  tooltip: '清除搜索（保持当前定位）',
                  onPressed: () {
                    _searchCtrl.clear();
                    _activeSearchKw = null;
                    setState(() => _searchEmpty = false);
                    // C08：清空后保持定位——滚回当前歌曲所在位置，不回最上方
                    // S04：force 强制对齐（列表刚重建/行高近似误判时也要回到定位行）
                    final cur = currentHymn;
                    if (cur != null) _locateAndScroll(cur, force: true);
                  },
                ),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
        ),
        onChanged: _onSearchChanged,
        onSubmitted: _onSearchSubmitted,
      ),
    );
  }

  Widget _buildPageList() {
    final all = repo.getAllHymns();
    final totalPages = (all.length / _pageSize).ceil().clamp(1, 1 << 31);
    if (_listPage >= totalPages) _listPage = totalPages - 1;
    if (_listPage < 0) _listPage = 0;
    final start = _listPage * _pageSize;
    final end = (start + _pageSize).clamp(0, all.length);
    final hymns = all.sublist(start, end);
    return ListView.builder(
      controller: _scroll,
      itemCount: hymns.length,
      itemBuilder: (context, index) =>
          buildHymnTile(hymns[index], start + index, all),
    );
  }

  Widget _buildPagination() {
    final all = repo.getAllHymns();
    final totalPages = (all.length / _pageSize).ceil().clamp(1, 1 << 31);
    return Container(
      color: AppColors.sidebarBg,
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left, size: 20),
            tooltip: '上一页',
            onPressed: _listPage > 0
                ? () {
                    LogService.instance
                        .info(LogTag.action, '诗歌列表上一页 → 第 $_listPage 页');
                    setState(() => _listPage--);
                  }
                : null,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              '第 ${_listPage + 1}/$totalPages 页',
              style:
                  TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right, size: 20),
            tooltip: '下一页',
            onPressed: _listPage < totalPages - 1
                ? () {
                    LogService.instance
                        .info(LogTag.action, '诗歌列表下一页 → 第 ${_listPage + 2} 页');
                    setState(() => _listPage++);
                  }
                : null,
          ),
        ],
      ),
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
          Icon(Icons.music_off, size: 48, color: AppColors.textTertiary),
          const SizedBox(height: 12),
          Text(text,
              style: TextStyle(
                  fontSize: 14, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}
