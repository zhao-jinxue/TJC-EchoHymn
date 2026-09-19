import 'package:flutter/material.dart';

import '../app.dart';
import '../models/hymn.dart';
import '../models/hymn_score.dart';
import '../services/chinese_convert_service.dart';
import '../theme/app_fonts.dart';

/// 「简谱曲谱 + 歌词」同步渲染页（数据源：`hymn_score_*` 表的逐字对位）
///
/// 版式 = 每行两排：**上排记号、下排歌词**，二者共用同一套等宽列，
/// 第 i 列即第 i 个谱元素 —— 一眼看清「哪个字落在哪个音上」。
///
/// **不换行硬约束**（需求：曲谱与歌词绝不因自动换行而错位）：
/// 字号上限由「页内最宽谱行的元素数」反推 ——
/// `cellW = 可用宽 / 最宽元素数`，`fontSize ≤ cellW`，
/// 因此一整行必然落在一行内；高度不足时再按行数收缩字号。
class ScoreLyricPageView extends StatelessWidget {
  const ScoreLyricPageView({
    super.key,
    required this.hymn,
    required this.page,
    required this.constraints,
  });

  final Hymn hymn;
  final ScorePage page;
  final BoxConstraints constraints;

  /// 上下留白 + 底部翻页条预留（翻页条自带背景，仍需足够净空避免压字）
  static const double padX = 20;
  static const double padTop = 20;
  static const double padBottom = 64;

  @override
  Widget build(BuildContext context) {
    final availW = constraints.maxWidth - padX * 2;
    final availH = constraints.maxHeight - padTop - padBottom;
    final nLines = page.lines.isEmpty ? 1 : page.lines.length;

    // 列宽 = 可用宽 / 最宽谱行元素数（保证单行不换行的充要条件）
    final maxElems = page.maxElements == 0 ? 1 : page.maxElements;
    final cellW = availW / maxElems;
    // 高度约束：每行 = 记号排(1.06) + 行内距(0.12) + 歌词排(1.15) + 行间距(0.55~0.9)
    // ≈ 3.2 个字高，另留 3.5 行给标题区与余量（估算偏保守，宁可字号略小也不溢出）
    final byH = availH / (nLines * 3.2 + 3.5);
    final ls = AppFonts.lyricsScale;
    // 字号等级只放大高度方向；列宽 cellW 是「不换行」的硬上限，绝不可破
    var size = byH * ls;
    if (size > cellW) size = cellW;
    size = size.clamp(9.0, 46.0);
    final symSize = size * 0.92;
    final lyricSize = size;
    final titleSize = (size * 1.15).clamp(13.0, 30.0);
    final labelSize = (size * 0.55).clamp(10.0, 15.0);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(padX, padTop, padX, padBottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Text(
              '${ChineseConvertService.instance.toSimplified(hymn.title)}'
              '　第 ${hymn.hymnNumber} 首　第 ${page.stanzaNo} 节',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: titleSize,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          SizedBox(height: size * 0.6),
          for (var i = 0; i < page.lines.length; i++)
            _buildLine(
              page.lines[i],
              cellW: cellW,
              symSize: symSize,
              lyricSize: lyricSize,
              labelSize: labelSize,
              gapAfter: i + 1 < page.lines.length &&
                      page.lines[i + 1].phraseNo != page.lines[i].phraseNo
                  ? size * 0.9
                  : size * 0.55,
            ),
        ],
      ),
    );
  }

  /// 一条谱行：上排记号、下排歌词，同一套等宽列
  Widget _buildLine(
    ScoreLineRow line, {
    required double cellW,
    required double symSize,
    required double lyricSize,
    required double labelSize,
    required double gapAfter,
  }) {
    final cells = line.cellsFor(page.stanzaNo);
    final n = line.elements.length;
    return Padding(
      padding: EdgeInsets.only(bottom: gapAfter),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < n; i++)
                      SizedBox(
                        width: cellW,
                        child: Center(
                          child: Text(
                            _symDisplay(line.elements[i]),
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.visible,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: symSize,
                              height: 1.15,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                SizedBox(height: lyricSize * 0.12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < n; i++)
                      SizedBox(
                        width: cellW,
                        child: Center(
                          child: Text(
                            ChineseConvertService.instance
                                .toSimplified(cells[i] ?? ''),
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.visible,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: lyricSize,
                              height: 1.15,
                              color: line.isChorus
                                  ? AppColors.primary
                                  : AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 记号显示：高音点 `^` 用组合字符「点在上」渲染，延长线 `-` 前留空更醒目
  static String _symDisplay(String sym) {
    if (!sym.contains('^')) return sym;
    final core = sym.replaceAll('^', '');
    return '$core\u0307';
  }
}
