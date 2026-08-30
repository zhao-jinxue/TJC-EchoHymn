import 'package:flutter/material.dart';

import '../../../models/hymn.dart';
import '../../../services/app_state_service.dart';
import '../../../services/chinese_convert_service.dart';
import '../../../services/log_service.dart';
import '../../app.dart';
import 'left_panel_base.dart';

/// 诗歌列表面板：按编号分页展示全部诗歌 + 搜索定位 + 分页
///
/// 搜索框语义 = **定位跳转**（而非过滤列表），列表始终保持完整 474 首分页：
/// - 输入编号 → 即时翻页 + 滚动 + 高亮定位（**不自动播放**；回车才播放）
/// - 输入标题 → 显示匹配列表供点击选择；点击 = 定位并播放；回车 = 定位并播放第一首
/// - 清除（×）→ 保持当前定位结果（不清除页/高亮）
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

  /// 标题搜索匹配结果（非 null 时列表区显示匹配列表供点击选择）
  List<Hymn>? _titleResults;

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
      color: isCurrent ? AppColors.selectedBg : AppColors.cardBg,
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
  void _locateAndScroll(Hymn hymn) {
    final all = repo.getAllHymns();
    final idx = all.indexWhere((h) => h.id == hymn.id);
    if (idx < 0) return;
    final page = idx ~/ _pageSize;
    if (page != _listPage) {
      setState(() => _listPage = page);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        scrollCurrentIntoView(_scroll, idx - page * _pageSize,
            headerHeight: 56);
      });
    } else {
      scrollCurrentIntoView(_scroll, idx - _listPage * _pageSize,
          headerHeight: 56);
    }
  }

  /// 定位 + 加载高亮（**不播放**）：回到完整列表视图、翻页滚动高亮该行，
  /// 并把播放上下文设为「完整列表 + 定位处」，之后播放/下一首/上一首从该处开始。
  void _locateTo(Hymn hymn) {
    final all = repo.getAllHymns();
    final idx = all.indexWhere((h) => h.id == hymn.id);
    if (idx < 0) return;
    setState(() => _titleResults = null);
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
      setState(() {
        _titleResults = null;
        _activeSearchKw = null;
      });
    } else if (_activeSearchKw != null && kw != _activeSearchKw) {
      // 已搜索后修改输入：重置已搜索状态，需重新回车
      _activeSearchKw = null;
    }
  }

  void _onSearchSubmitted(String v) {
    final kw = v.trim();
    if (kw.isEmpty) return;
    // 第一次回车：结束输入并开始搜索（只搜索/定位，不播放）
    if (_activeSearchKw == null) {
      _activeSearchKw = kw;
      _performSearch(kw);
      return;
    }
    // 第二次回车：播放搜索结果（标题列表第一首，或编号定位的歌曲）
    final target = (_titleResults != null && _titleResults!.isNotEmpty)
        ? _titleResults!.first
        : _findByNumber(kw) ?? _findByTitle(kw);
    if (target == null) {
      _showSearchToast('未找到相关诗歌：$kw');
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
  }

  /// 执行搜索（第一次回车）：编号 → 定位高亮；标题 → 显示匹配列表；无匹配 → Toast
  void _performSearch(String kw) {
    final target = _findByNumber(kw) ?? _findByTitle(kw);
    if (target == null) {
      LogService.instance.info(LogTag.action, '搜索无匹配: $kw');
      setState(() => _titleResults = const []);
      _showSearchToast('未找到相关诗歌：$kw');
    } else if (int.tryParse(kw) != null) {
      // 编号：定位高亮（不播放，第二次回车才播放）
      LogService.instance.info(
        LogTag.action,
        '搜索编号: $kw',
        detail: '定位到第 ${target.hymnNumber} 首《${target.title}》',
      );
      _locateTo(target);
    } else {
      // 标题：显示匹配列表供点击/二次回车播放
      final matches = _titleMatches(kw);
      LogService.instance.info(
        LogTag.action,
        '搜索标题: $kw',
        detail: '匹配 ${matches.length} 首',
      );
      setState(() => _titleResults = matches);
    }
    // K11b/K11c：第一次回车后保持搜索框焦点，使第二次回车仍能触发 onSubmitted 播放
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocus.requestFocus();
    });
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
    if (_titleResults != null) setState(() => _titleResults = null);
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
          child:
              _titleResults != null ? _buildTitleResults() : _buildPageList(),
        ),
        if (_titleResults == null) _buildPagination(),
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
          hintText: '搜索编号/标题',
          prefixIcon: const Icon(Icons.search, size: 18),
          suffixIcon: _searchCtrl.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.clear, size: 16),
                  tooltip: '清除搜索（保持当前定位）',
                  onPressed: () {
                    _searchCtrl.clear();
                    setState(() => _titleResults = null);
                    // C08：清空后保持定位——滚回当前歌曲所在位置，不回最上方
                    final cur = currentHymn;
                    if (cur != null) _locateAndScroll(cur);
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

  /// 标题匹配列表：点击某首 = 定位到完整列表中该首并播放
  /// （翻页 + 滚动 + 高亮 + 播放，播放点为完整列表中的该首）
  Widget _buildTitleResults() {
    final results = _titleResults!;
    if (results.isEmpty) return const _EmptyHint(text: '未找到匹配的诗歌');
    return ListView.builder(
      controller: _scroll,
      itemCount: results.length,
      itemBuilder: (context, index) {
        final hymn = results[index];
        final isCurrent = currentHymn?.id == hymn.id;
        return Material(
          color: isCurrent ? AppColors.selectedBg : AppColors.cardBg,
          child: InkWell(
            onTap: () {
              final all = repo.getAllHymns();
              final idx = all.indexWhere((h) => h.id == hymn.id);
              if (idx < 0) return;
              // 回到完整列表视图 + 翻页滚动定位
              setState(() => _titleResults = null);
              _locateAndScroll(hymn);
              // 定位处播放（设置完整列表为播放上下文 + 播放 + 保存状态）
              playHymn(hymn, idx, all);
            },
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
                        color: isCurrent
                            ? AppColors.primary
                            : AppColors.textPrimary,
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
                  Icon(Icons.north_east,
                      size: 14, color: AppColors.textTertiary),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPagination() {
    final all = repo.getAllHymns();
    final totalPages = (all.length / _pageSize).ceil().clamp(1, 1 << 31);
    return Container(
      color: AppColors.cardBg,
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
