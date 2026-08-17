import 'package:flutter/material.dart';

import '../../../models/hymn.dart';
import '../../../services/app_state_service.dart';
import '../../../services/chinese_convert_service.dart';
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
  int _listPage = 0;

  /// 标题搜索匹配结果（非 null 时列表区显示匹配列表供点击选择）
  List<Hymn>? _titleResults;

  @override
  void dispose() {
    _scroll.dispose();
    _searchCtrl.dispose();
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
    final kw = v.trim();
    if (kw.isEmpty) {
      // 清空输入：保持当前定位结果
      setState(() => _titleResults = null);
      return;
    }
    if (int.tryParse(kw) != null) {
      // 编号 → 即时定位最匹配项（编号精确 / 前缀）
      final target = _findByNumber(kw);
      if (target != null) _locateTo(target);
    } else {
      // 标题 → 显示匹配列表供点击选择
      setState(() => _titleResults = _titleMatches(kw));
    }
  }

  void _onSearchSubmitted(String v) {
    final kw = v.trim();
    if (kw.isEmpty) return;
    final target = _findByNumber(kw) ?? _findByTitle(kw);
    if (target == null) return;
    final all = repo.getAllHymns();
    final idx = all.indexWhere((h) => h.id == target.id);
    _locateTo(target);
    // 回车 = 定位 + 播放
    playHymn(target, idx, all);
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
    // 优先按播放索引定位；越界/缺失时按诗歌编号兜底
    var idx = anchor.playlistIndex;
    if (idx < 0 || idx >= all.length) {
      if (anchor.hymnNumber.isEmpty) return;
      idx = all.indexWhere((h) => h.hymnNumber == anchor.hymnNumber);
      if (idx < 0) return;
    }
    final page = idx ~/ _pageSize;
    if (page != _listPage) {
      _listPage = page;
      setState(() {});
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final local = idx - _listPage * _pageSize;
      scrollToCurrent(_scroll, local);
    });
  }

  // ================= 构建 =================

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSearchBar(),
        const Divider(height: 1, color: AppColors.divider),
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
                    // 保持当前页与高亮，不重置
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
                      style: const TextStyle(
                          fontSize: 13, color: AppColors.textPrimary),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Icon(Icons.north_east,
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
            onPressed: _listPage > 0 ? () => setState(() => _listPage--) : null,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              '第 ${_listPage + 1}/$totalPages 页',
              style:
                  const TextStyle(fontSize: 12, color: AppColors.textSecondary),
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
