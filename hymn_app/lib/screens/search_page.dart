import 'package:flutter/material.dart';

import '../app.dart';
import '../models/hymn.dart';
import '../services/hymn_search_service.dart';
import '../services/log_service.dart';

/// 全屏搜索页（`ANDROID_PLAN §3.1.6` / 确认单 3.1.6）
///
/// 结构：
/// - 顶栏 **56**：← / 搜索框（自动聚焦）/ ✕
/// - 表头 **40**：编号 | 诗歌名称 | 歌词（12sp 三级色）
/// - 行高 **72** 双行：歌名命中 = 红 + 粗；歌词命中 = 主题色 + 粗（只显示第一个命中节）
/// - 页脚 **40**：共 N 条结果
///
/// 交互：输入回车即搜（**纯数字走编号定位**、中文走统一模糊搜索）；
/// 单击 → `Navigator.pop(hymn)` 交给调用方播放；✕ / 系统返回 → 关闭。
class SearchPage extends StatefulWidget {
  const SearchPage({super.key, required this.hymns});

  final List<Hymn> hymns;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();
  List<HymnSearchHit> _hits = const [];
  String _keyword = '';

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _runSearch(String value) {
    final kw = value.trim();
    if (kw.isEmpty) {
      setState(() {
        _keyword = '';
        _hits = const [];
      });
      return;
    }

    // 纯数字 → 编号定位（§3.1.6：编号走定位，语义对齐 Windows §5.4）
    final asNumber = int.tryParse(kw);
    if (asNumber != null) {
      final exact = <HymnSearchHit>[];
      for (final h in widget.hymns) {
        if (h.hymnNumber == kw) {
          exact.add(HymnSearchHit(
            hymn: h,
            titleMatched: true,
            verseMatched: false,
            displayVerse: h.verses.isNotEmpty ? h.verses.first : '',
          ));
          break;
        }
      }
      setState(() {
        _keyword = kw;
        _hits = exact;
      });
      LogService.instance.info(LogTag.action, '搜索（编号定位）',
          detail: '编号「$kw」→ ${_hits.length} 条');
      return;
    }

    final hits = HymnSearchService.search(widget.hymns, kw);
    setState(() {
      _keyword = kw;
      _hits = hits;
    });
    LogService.instance
        .info(LogTag.action, '搜索', detail: '关键字「$kw」→ ${hits.length} 条');
  }

  /// 关键字高亮（歌名/歌词共用）：命中段着色加粗，其余用默认次级色
  List<InlineSpan> _highlight(String text, Color hitColor,
      {TextStyle? base}) {
    final kw = HymnSearchService.normalizedKeyword(_keyword);
    final baseStyle = base ??
        TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.35);
    if (kw.isEmpty || text.isEmpty) {
      return [TextSpan(text: text, style: baseStyle)];
    }
    final spans = <InlineSpan>[];
    var i = 0;
    while (i < text.length) {
      final idx = text.indexOf(kw, i);
      if (idx < 0) {
        spans.add(TextSpan(text: text.substring(i), style: baseStyle));
        break;
      }
      if (idx > i) {
        spans.add(TextSpan(text: text.substring(i, idx), style: baseStyle));
      }
      spans.add(TextSpan(
        text: text.substring(idx, idx + kw.length),
        style: baseStyle.copyWith(color: hitColor, fontWeight: FontWeight.bold),
      ));
      i = idx + kw.length;
    }
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lyricsBg,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            Divider(height: 1, color: AppColors.divider),
            _buildHeader(),
            Divider(height: 1, color: AppColors.divider),
            Expanded(child: _buildResults()),
            Divider(height: 1, color: AppColors.divider),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  // ---------- 顶栏 56：← / 搜索框 / ✕ ----------
  Widget _buildTopBar() {
    return SizedBox(
      height: 56,
      child: Row(
        children: [
          IconButton(
            iconSize: 24,
            tooltip: '返回',
            icon: Icon(Icons.arrow_back, color: AppColors.textPrimary),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          Expanded(
            child: Container(
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.controlBg,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.controlBorder),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Icon(Icons.search, size: 20, color: AppColors.textTertiary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      focusNode: _focus,
                      autofocus: true,
                      textInputAction: TextInputAction.search,
                      onSubmitted: _runSearch,
                      onChanged: (v) {
                        if (v.trim().isEmpty) _runSearch('');
                      },
                      style:
                          TextStyle(fontSize: 15, color: AppColors.textPrimary),
                      decoration: InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        hintText: '输入编号 / 歌名 / 歌词',
                        hintStyle: TextStyle(
                          fontSize: 15,
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ),
                  ),
                  if (_keyword.isNotEmpty)
                    GestureDetector(
                      onTap: () {
                        _controller.clear();
                        _runSearch('');
                        _focus.requestFocus();
                      },
                      child: Icon(Icons.close,
                          size: 18, color: AppColors.textTertiary),
                    ),
                ],
              ),
            ),
          ),
          IconButton(
            iconSize: 22,
            tooltip: '关闭',
            icon: Icon(Icons.close, color: AppColors.textPrimary),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
    );
  }

  // ---------- 表头 40：编号 | 诗歌名称 | 歌词 ----------
  Widget _buildHeader() {
    final style = TextStyle(fontSize: 12, color: AppColors.textTertiary);
    return SizedBox(
      height: 40,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            SizedBox(width: 40, child: Text('编号', style: style)),
            const SizedBox(width: 8),
            Expanded(flex: 4, child: Text('诗歌名称', style: style)),
            const SizedBox(width: 12),
            Expanded(flex: 6, child: Text('歌词', style: style)),
          ],
        ),
      ),
    );
  }

  // ---------- 结果（行高 72，双行）----------
  Widget _buildResults() {
    if (_hits.isEmpty) {
      return Center(
        child: Text(
          _keyword.isEmpty ? '输入编号 / 歌名 / 歌词' : '未找到匹配的诗歌',
          style: TextStyle(fontSize: 14, color: AppColors.textTertiary),
        ),
      );
    }
    return ListView.separated(
      itemCount: _hits.length,
      separatorBuilder: (_, __) => Divider(height: 1, color: AppColors.divider),
      itemBuilder: (context, i) => _buildRow(_hits[i]),
    );
  }

  Widget _buildRow(HymnSearchHit hit) {
    final h = hit.hymn;
    final title = HymnSearchService.normalizedKeyword(h.title);
    final titleStyle = TextStyle(
      fontSize: 14,
      color: AppColors.textPrimary,
      fontWeight: FontWeight.w600,
      height: 1.35,
    );
    return InkWell(
      onTap: () {
        LogService.instance.info(
          LogTag.action,
          '搜索页选中：第 ${h.hymnNumber} 首《${h.title}》',
        );
        Navigator.of(context).pop(h);
      },
      child: SizedBox(
        height: 72,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              SizedBox(
                width: 40,
                child: Text(
                  h.hymnNumber,
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textTertiary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 4,
                child: RichText(
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  // 歌名命中 = 红 + 粗（确认单 3.1.6）
                  text: TextSpan(
                    children: _highlight(
                      title,
                      const Color(0xFFD32F2F),
                      base: titleStyle,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 6,
                child: RichText(
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  // 歌词命中 = 主题色 + 粗
                  text: TextSpan(
                    children: _highlight(
                      hit.displayVerse,
                      AppColors.primary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------- 页脚 40 ----------
  Widget _buildFooter() {
    return SizedBox(
      height: 40,
      child: Center(
        child: Text(
          _keyword.isEmpty ? '' : '共 ${_hits.length} 条结果',
          style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
        ),
      ),
    );
  }
}

