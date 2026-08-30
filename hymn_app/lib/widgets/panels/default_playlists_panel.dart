import 'package:flutter/material.dart';

import '../../../models/hymn.dart';
import '../../../models/hymn_category.dart';
import '../../../services/app_state_service.dart';
import '../../../services/chinese_convert_service.dart';
import '../../../services/log_service.dart';
import '../../app.dart';
import 'left_panel_base.dart';

/// 默认歌单面板：一级分类 → 二级目录 → 点二级展示该目录诗歌列表
class DefaultPlaylistsPanel extends LeftPanel {
  const DefaultPlaylistsPanel({
    super.key,
    required super.audio,
    required super.repo,
    required super.onPlayback,
    super.anchor,
  });

  @override
  State<DefaultPlaylistsPanel> createState() => _DefaultPlaylistsPanelState();
}

class _DefaultPlaylistsPanelState
    extends LeftPanelState<DefaultPlaylistsPanel> {
  final Set<String> _expandedCategories = {};
  final ScrollController _treeScroll = ScrollController();
  final ScrollController _contentScroll = ScrollController();

  // 当前选中的二级目录与其诗歌列表
  HymnCategory? _selectedSub;
  List<Hymn> _selectedHymns = const [];
  bool _showContent = false;

  List<HymnCategory> get _categories => repo.getAllCategories();
  String display(String s) => ChineseConvertService.instance.toSimplified(s);

  @override
  void dispose() {
    _treeScroll.dispose();
    _contentScroll.dispose();
    super.dispose();
  }

  /// 诗歌行渲染：编号 + 标题（来源 = 当前二级目录）
  @override
  Widget buildHymnTile(Hymn hymn, int index, List<Hymn> contextList) {
    final isCurrent = currentHymn?.id == hymn.id;
    return Material(
      color: isCurrent ? AppColors.selectedBg : AppColors.sidebarBg,
      child: InkWell(
        onTap: () => playHymn(
          hymn,
          index,
          contextList,
          sourceSubcategory: _selectedSub?.subcategory,
        ),
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
                  display(hymn.title),
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

  /// 切歌联动：当前歌曲属于展开的二级目录时，滚动到可视区域（避开目录标题栏）。
  @override
  void syncWithPlayback() {
    final hymn = currentHymn;
    if (hymn == null || !_showContent || _selectedSub == null) return;
    final idx = _selectedHymns.indexWhere((h) => h.id == hymn.id);
    if (idx < 0) return;
    scrollCurrentIntoView(_contentScroll, idx, headerHeight: 47);
  }

  /// 按锚点恢复：展开对应二级目录并滚动到当前诗歌
  @override
  void restoreSaved(AppState anchor) {
    if (anchor.subcategory.isEmpty) return;
    final sub =
        _categories.where((c) => c.subcategory == anchor.subcategory).toList();
    if (sub.isEmpty) return;
    final sel = sub.first;
    // 展开一级分类
    _expandedCategories.add(sel.category);
    // 构建该目录诗歌列表并展开
    final hymns = <Hymn>[];
    for (final e in sel.hymns) {
      final h = repo.hymnByNumber(e.value.toString());
      if (h != null) hymns.add(h);
    }
    if (hymns.isEmpty) return;
    final idx =
        (anchor.playlistIndex >= 0 && anchor.playlistIndex < hymns.length)
            ? anchor.playlistIndex
            : 0;
    setState(() {
      _selectedSub = sel;
      _selectedHymns = hymns;
      _showContent = true;
    });
    // 延后一帧等列表重建后再滚动
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      scrollToCurrent(_contentScroll, idx);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_showContent && _selectedSub != null) {
      return _buildContent();
    }
    return _buildTree();
  }

  /// 分类树视图
  Widget _buildTree() {
    final grouped = <String, List<HymnCategory>>{};
    for (final c in _categories) {
      grouped.putIfAbsent(c.category, () => []).add(c);
    }
    if (grouped.isEmpty) return const _EmptyHint(text: '暂无分类');
    final cats = grouped.keys.toList();

    return ListView.builder(
      controller: _treeScroll,
      itemCount: cats.length,
      itemBuilder: (context, i) {
        final cat = cats[i];
        final subs = grouped[cat]!;
        final expanded = _expandedCategories.contains(cat);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Material(
              color: AppColors.sidebarBg,
              child: InkWell(
                onTap: () {
                  LogService.instance.info(
                    LogTag.action,
                    expanded
                        ? '收起分类: ${display(cat)}'
                        : '展开分类: ${display(cat)}',
                  );
                  setState(() {
                    if (expanded) {
                      _expandedCategories.remove(cat);
                    } else {
                      _expandedCategories.add(cat);
                    }
                  });
                },
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    children: [
                      Icon(expanded ? Icons.expand_more : Icons.chevron_right,
                          size: 18, color: AppColors.textSecondary),
                      const SizedBox(width: 4),
                      Text(
                        display(cat),
                        style: TextStyle(
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
            if (expanded) ...subs.map((sub) => _subItem(sub)),
          ],
        );
      },
    );
  }

  Widget _subItem(HymnCategory sub) {
    final selected =
        _selectedSub?.subcategory == sub.subcategory && _showContent;
    return Material(
      color: selected ? AppColors.selectedBg : AppColors.sidebarBg,
      child: InkWell(
        onTap: () {
          final hymns = <Hymn>[];
          for (final e in sub.hymns) {
            final h = repo.hymnByNumber(e.value.toString());
            if (h != null) hymns.add(h);
          }
          LogService.instance.info(
            LogTag.action,
            '打开默认歌单子目录: ${display(sub.subcategory)}',
            detail: '所属分类: ${display(sub.category)}\n诗歌数量: ${hymns.length}',
          );
          setState(() {
            _selectedSub = sub;
            _selectedHymns = hymns;
            _showContent = true;
          });
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
                style: TextStyle(
                    fontSize: 11, color: AppColors.textTertiary),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 二级目录诗歌列表视图
  Widget _buildContent() {
    final sub = _selectedSub!;
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
                onPressed: () {
                  LogService.instance.info(
                    LogTag.action,
                    '返回分类目录（关闭子目录）',
                  );
                  setState(() => _showContent = false);
                },
              ),
              Expanded(
                child: Text(
                  display(sub.subcategory),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '${_selectedHymns.length}首',
                style: TextStyle(
                    fontSize: 11, color: AppColors.textTertiary),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: AppColors.divider),
        Expanded(
          child: _selectedHymns.isEmpty
              ? const _EmptyHint(text: '暂无诗歌')
              : ListView.builder(
                  controller: _contentScroll,
                  itemCount: _selectedHymns.length,
                  itemBuilder: (context, index) => buildHymnTile(
                      _selectedHymns[index], index, _selectedHymns),
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
