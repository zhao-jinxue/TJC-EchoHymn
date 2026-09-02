import '../models/hymn.dart';
import 'chinese_convert_service.dart';

/// 歌名+歌词统一模糊搜索的单条命中（每首诗歌一条）
class HymnSearchHit {
  final Hymn hymn;

  /// 歌名（标题）是否命中
  final bool titleMatched;

  /// 歌词是否命中
  final bool verseMatched;

  /// 歌词列显示内容（简体）：歌词命中 = 第一个命中节；仅歌名命中 = 默认第一节
  final String displayVerse;

  const HymnSearchHit({
    required this.hymn,
    required this.titleMatched,
    required this.verseMatched,
    required this.displayVerse,
  });
}

/// 歌名+歌词统一模糊搜索服务。
///
/// 库内标题/歌词为繁体，显示层统一转简体（简繁逐字 1:1 映射，等长）。
/// 命中判定沿用标题搜索的**繁简双向匹配**逻辑：
/// - 用户输入简体 → 库文本转简后 contains（简体关键字）
/// - 用户输入繁体 → 关键字转繁后 contains 于库原文
class HymnSearchService {
  HymnSearchService._();

  /// 关键字的简体形式（单元格显示为简体，加粗定位统一使用简体关键字）
  static String normalizedKeyword(String keyword) =>
      ChineseConvertService.instance.toSimplified(keyword.trim());

  /// 单条文本（库原文，繁体）是否命中关键字
  static bool _matches(String rawText, String kwS, String kwT) {
    if (kwS.isNotEmpty &&
        ChineseConvertService.instance.toSimplified(rawText).contains(kwS)) {
      return true;
    }
    return kwT.isNotEmpty && kwT != kwS && rawText.contains(kwT);
  }

  /// 全量搜索歌名+歌词，返回命中列表。
  ///
  /// 排序：**歌名命中在前、歌词命中在后**，组内保持 [all] 的编号升序。
  /// 每首歌只产出一条：歌词命中多节时取**第一个命中节**作为显示内容。
  static List<HymnSearchHit> search(List<Hymn> all, String keyword) {
    final kw = keyword.trim();
    if (kw.isEmpty) return const [];
    final kwS = ChineseConvertService.instance.toSimplified(kw);
    final kwT = ChineseConvertService.instance.toTraditional(kw);
    final titleHits = <HymnSearchHit>[];
    final verseHits = <HymnSearchHit>[];
    for (final h in all) {
      final titleMatched = _matches(h.title, kwS, kwT);
      // 歌词：找第一个命中节
      var matchedVerse = -1;
      for (var i = 0; i < h.verses.length; i++) {
        if (_matches(h.verses[i], kwS, kwT)) {
          matchedVerse = i;
          break;
        }
      }
      final verseMatched = matchedVerse >= 0;
      if (!titleMatched && !verseMatched) continue;
      // 歌词列显示内容：命中节优先，否则默认第一节
      final rawVerse = verseMatched
          ? h.verses[matchedVerse]
          : (h.verses.isNotEmpty ? h.verses.first : '');
      final hit = HymnSearchHit(
        hymn: h,
        titleMatched: titleMatched,
        verseMatched: verseMatched,
        displayVerse:
            rawVerse.trim().isEmpty ? '' : _toSimplifiedMultiline(rawVerse),
      );
      (titleMatched ? titleHits : verseHits).add(hit);
    }
    return [...titleHits, ...verseHits];
  }

  /// 多行歌词逐行转简（转换映射为按字符处理，整段直接转即可）
  static String _toSimplifiedMultiline(String text) =>
      ChineseConvertService.instance.toSimplified(text);
}
