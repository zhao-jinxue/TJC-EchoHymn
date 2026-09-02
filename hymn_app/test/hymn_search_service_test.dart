import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:echo_hymn/models/hymn.dart';
import 'package:echo_hymn/services/hymn_search_service.dart';
import 'package:echo_hymn/widgets/hymn_search_dialog.dart';

/// v1.5.1 歌名+歌词统一模糊搜索守卫测试。
///
/// 覆盖：命中判定（歌名/歌词）、繁简双向匹配、多节命中取第一命中节、
/// 仅歌名命中显示第一节、排序（歌名在前歌词在后）、关键字加粗切分。
Hymn _hymn({
  required int id,
  required String number,
  required String title,
  List<String> verses = const [],
}) {
  return Hymn(
    id: id,
    hymnNumber: number,
    title: title,
    lyricist: '',
    composer: '',
    sourceInfo: '',
    verseCount: verses.length,
    verses: verses,
    staffImgPath: '',
    numberedImgPath: '',
    staffPngPath: '',
    numberedPngPath: '',
    audioVersions: const {},
    audioVersionList: const [],
    downloadStatus: '',
    integrityStatus: '',
  );
}

/// 文本库（标题/歌词为繁体，与应用库内数据形态一致）
List<Hymn> _corpus() => [
      _hymn(id: 1, number: '1', title: '頌主恩名', verses: [
        '第一节：奇异恩典，何等甘甜',
        '第二节：我命已蒙恩',
      ]),
      _hymn(id: 2, number: '2', title: '奇異恩典', verses: [
        '奇異恩典，何等甘甜',
        '我命已蒙恩',
      ]),
      _hymn(id: 3, number: '3', title: '十架的愛', verses: [
        '第一节：各各他山上',
        '副歌：十字架，是我的光荣',
        '再一节：十字架的愛，叫我心得滿足',
      ]),
      _hymn(id: 4, number: '4', title: '美的詩歌', verses: ['唯我神恩典'], ),
    ];

void main() {
  group('歌名命中', () {
    test('简体关键字命中繁体标题（转简双向匹配）', () {
      final hits = HymnSearchService.search(_corpus(), '颂主');
      expect(hits.length, 1);
      expect(hits.first.hymn.id, 1);
      expect(hits.first.titleMatched, isTrue);
    });

    test('繁体关键字命中繁体标题', () {
      final hits = HymnSearchService.search(_corpus(), '恩典');
      // 《奇異恩典》标题命中（歌名组），其余为歌词命中
      final byTitleOnly = hits.where((h) => h.titleMatched);
      expect(byTitleOnly.map((h) => h.hymn.id), contains(2));
    });

    test('仅歌名命中时歌词列默认显示第一节', () {
      final hits = HymnSearchService.search(_corpus(), '頌主');
      expect(hits.length, 1);
      expect(hits.first.verseMatched, isFalse);
      expect(hits.first.displayVerse, contains('第一节'));
    });
  });

  group('歌词命中', () {
    test('关键字只在歌词中也能命中，显示第一个命中节', () {
      final hits = HymnSearchService.search(_corpus(), '各各他');
      expect(hits.length, 1);
      expect(hits.first.hymn.id, 3);
      expect(hits.first.titleMatched, isFalse);
      expect(hits.first.verseMatched, isTrue);
      expect(hits.first.displayVerse, contains('各各他'));
    });

    test('多节命中时取第一个命中节（不合并、不取后节）', () {
      final hits = HymnSearchService.search(_corpus(), '十字架');
      expect(hits.length, 1);
      // 第 3 首的 verse_2（"副歌：十字架..."）先于 verse_3 命中
      expect(hits.first.displayVerse, startsWith('副歌'));
      expect(hits.first.displayVerse, isNot(contains('再一节')));
    });

    test('关键字命中显示为简体（库繁体已转简）', () {
      final hits = HymnSearchService.search(_corpus(), '满足');
      expect(hits.length, 1);
      expect(hits.first.displayVerse, contains('满足'));
      expect(hits.first.displayVerse, isNot(contains('滿足')));
    });
  });

  group('排序与组合', () {
    test('歌名命中在前、歌词命中在后，组内按编号', () {
      // "恩典"：id2 标题命中；id1/id4 歌词命中（id1 第一节含"恩典"）
      final hits = HymnSearchService.search(_corpus(), '恩典');
      expect(hits.map((h) => h.hymn.id).toList(), [2, 1, 4]);
      expect(hits.first.titleMatched, isTrue);
      expect(hits.skip(1).every((h) => !h.titleMatched), isTrue);
    });

    test('双重命中产生一条（红蓝同由）', () {
      final hits = HymnSearchService.search(_corpus(), '奇異恩典');
      // id2 标题+歌词双命中在前；id1 歌词首节含"恩典"同样命中
      expect(hits.length, 2);
      expect(hits.first.hymn.id, 2);
      expect(hits.first.titleMatched, isTrue);
      expect(hits.first.verseMatched, isTrue);
      expect(hits.last.hymn.id, 1);
      expect(hits.last.titleMatched, isFalse);
    });

    test('无命中返回空列表；空关键字不搜', () {
      expect(HymnSearchService.search(_corpus(), 'moon'), isEmpty);
      expect(HymnSearchService.search(_corpus(), '  '), isEmpty);
    });
  });

  group('关键字加粗切分', () {
    test('所有出现处都切为着色段，普通段保持基准样式', () {
      const base = TextStyle(fontSize: 13);
      const kwColor = Colors.red;
      final spans = buildKeywordSpans('十字架的爱，荣耀的十字架', '十字架', kwColor, base);
      // 拼接后与原文一致
      final joined =
          spans.map((s) => (s as TextSpan).text ?? '').join();
      expect(joined, '十字架的爱，荣耀的十字架');
      // 两处关键字都是着色加粗段
      final kwSpans = spans.where((s) => (s as TextSpan).style?.color == kwColor);
      expect(kwSpans.length, 2);
      expect(kwSpans.every((s) => (s as TextSpan).text == '十字架'), isTrue);
      expect(
          kwSpans.every((s) =>
              (s as TextSpan).style?.fontWeight == FontWeight.bold),
          isTrue);
    });

    test('关键字不在文本中时原样单段返回（繁体形变兜底）', () {
      const base = TextStyle(fontSize: 13);
      final spans = buildKeywordSpans('完全不同的文本', 'XYZ', Colors.red, base);
      expect(spans.length, 1);
      expect((spans.first as TextSpan).text, '完全不同的文本');
    });

    test('繁体关键字在简体显示文本上按简体形式加粗', () {
      const base = TextStyle(fontSize: 13);
      // 显示文本是简体"十字架的爱"，关键字输入繁体同样形式；换一个："荣耀"
      final spans = buildKeywordSpans('荣耀的十字架', '榮耀', Colors.blue, base);
      final kwSpans =
          spans.where((s) => (s as TextSpan).style?.color == Colors.blue);
      expect(kwSpans.length, 1);
      expect((kwSpans.first as TextSpan).text, '荣耀');
    });
  });
}
