import 'package:flutter/material.dart';

import '../app.dart';
import '../models/hymn.dart';
import '../services/chinese_convert_service.dart';
import '../services/hymn_search_service.dart';

/// 弹出「歌名+歌词统一搜索结果」弹窗。
///
/// 返回值：双击选中的诗歌（调用方负责左栏定位 + 播放）；关闭未选 = null。
Future<Hymn?> showHymnSearchDialog(
  BuildContext context, {
  required List<HymnSearchHit> hits,
  required String keyword,
}) {
  return showDialog<Hymn>(
    context: context,
    builder: (_) => _HymnSearchDialog(hits: hits, keyword: keyword),
  );
}

/// 统一搜索结果弹窗：右上角仅 ✕ + 三列结果表格（编号 / 诗歌名称 / 歌词）。
///
/// - 歌名命中：名称列关键字**加粗红色**（danger），歌词列默认显示第一节
/// - 歌词命中：歌词列显示第一个命中节，关键字**加粗主题色**（primary）
/// - 双重命中：同一行红蓝并存，互不干扰
/// - 单击行 = 选中高亮；双击行 = 关闭弹窗并返回该诗歌
class _HymnSearchDialog extends StatefulWidget {
  final List<HymnSearchHit> hits;
  final String keyword;

  const _HymnSearchDialog({required this.hits, required this.keyword});

  @override
  State<_HymnSearchDialog> createState() => _HymnSearchDialogState();
}

class _HymnSearchDialogState extends State<_HymnSearchDialog> {
  /// 当前选中行下标（单击选中，-1 = 未选中）
  int _selected = -1;

  static const double _numberColWidth = 56;
  static const double _titleColWidth = 170;

  int get _titleCount => widget.hits.where((h) => h.titleMatched).length;
  int get _verseCount => widget.hits.where((h) => h.verseMatched).length;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      backgroundColor: AppColors.cardBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SizedBox(
        width: 640,
        height: 560,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(),
            Divider(height: 1, color: AppColors.divider),
            _buildTableHeader(),
            Divider(height: 1, color: AppColors.divider),
            Expanded(child: _buildRows()),
          ],
        ),
      ),
    );
  }

  // ================= 顶栏：标题 + 计数 + ✕ =================

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '搜索「${widget.keyword}」：'
              '歌名匹配 $_titleCount 首 · 歌词匹配 $_verseCount 首',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            padding: EdgeInsets.zero,
            icon:
                Icon(Icons.close, size: 18, color: AppColors.textSecondary),
            tooltip: '关闭',
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  // ================= 表头 =================

  Widget _buildTableHeader() {
    final style = TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: AppColors.textSecondary);
    return Container(
      color: AppColors.versionBarBg,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          SizedBox(width: _numberColWidth, child: Text('编号', style: style)),
          SizedBox(width: _titleColWidth, child: Text('诗歌名称', style: style)),
          Expanded(child: Text('歌词', style: style)),
        ],
      ),
    );
  }

  // ================= 结果行 =================

  Widget _buildRows() {
    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: widget.hits.length,
      itemBuilder: (context, index) => _buildRow(widget.hits[index], index),
    );
  }

  Widget _buildRow(HymnSearchHit hit, int index) {
    final selected = _selected == index;
    return Material(
      color: selected ? AppColors.selectedBg : Colors.transparent,
      child: InkWell(
        hoverColor: Colors.black.withValues(alpha: 0.04),
        onTap: () => setState(() => _selected = index),
        onDoubleTap: () => Navigator.pop(context, hit.hymn),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: AppColors.divider, width: 0.5),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: _numberColWidth,
                child: Text(
                  hit.hymn.hymnNumber,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
              ),
              SizedBox(width: _titleColWidth, child: _buildTitleCell(hit)),
              Expanded(child: _buildVerseCell(hit)),
            ],
          ),
        ),
      ),
    );
  }

  /// 名称单元格：歌名命中 → 关键字红色加粗；未命中 → 正常色
  Widget _buildTitleCell(HymnSearchHit hit) {
    final title = ChineseConvertService.instance.toSimplified(hit.hymn.title);
    final base = TextStyle(fontSize: 13, color: AppColors.textPrimary);
    if (!hit.titleMatched) {
      return Text(title,
          style: base, maxLines: 2, overflow: TextOverflow.ellipsis);
    }
    return Text.rich(
      TextSpan(
        children: buildKeywordSpans(
            title, widget.keyword, AppColors.danger, base),
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }

  /// 歌词单元格：歌词命中 → 第一个命中节 + 关键字主题色加粗；
  /// 仅歌名命中 → 默认显示第一节（正常色）
  Widget _buildVerseCell(HymnSearchHit hit) {
    final verse = hit.displayVerse;
    final base = TextStyle(fontSize: 12.5, color: AppColors.textSecondary);
    if (verse.isEmpty) return Text('—', style: base);
    if (!hit.verseMatched) {
      return Text(verse,
          style: base, maxLines: 3, overflow: TextOverflow.ellipsis);
    }
    return Text.rich(
      TextSpan(
        children: buildKeywordSpans(
            verse, widget.keyword, AppColors.primary, base),
      ),
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// 将 [text] 中所有 [keyword]（按简体规范化后）出现处切成
/// 「普通段 + 加粗着色段」的 TextSpan 列表；关键字未出现在文本中时
/// 原样返回单段（繁简体形不一致时的兜底）。
List<InlineSpan> buildKeywordSpans(
  String text,
  String keyword,
  Color keywordColor,
  TextStyle base,
) {
  final kw = HymnSearchService.normalizedKeyword(keyword);
  if (kw.isEmpty || !text.contains(kw)) {
    return [TextSpan(text: text, style: base)];
  }
  final kwStyle = base.copyWith(
    color: keywordColor,
    fontWeight: FontWeight.bold,
  );
  final spans = <InlineSpan>[];
  var pos = 0;
  while (pos < text.length) {
    final i = text.indexOf(kw, pos);
    if (i < 0) {
      spans.add(TextSpan(text: text.substring(pos), style: base));
      break;
    }
    if (i > pos) {
      spans.add(TextSpan(text: text.substring(pos, i), style: base));
    }
    spans.add(TextSpan(text: kw, style: kwStyle));
    pos = i + kw.length;
  }
  return spans;
}
