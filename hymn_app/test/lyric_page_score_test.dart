import 'package:flutter_test/flutter_test.dart';

import 'package:echo_hymn/models/hymn.dart';
import 'package:echo_hymn/models/hymn_score.dart';

/// 构造一首最小诗歌（只填分页相关字段）
Hymn _hymn({
  List<String> verses = const [],
  String chorus = '',
  Map<String, double> durations = const {},
}) {
  return Hymn(
    id: 1,
    hymnNumber: '12',
    title: '耶穌尊名',
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
    chorus: chorus,
    audioDurations: durations,
    downloadStatus: '',
    integrityStatus: '',
  );
}

void main() {
  group('歌词分页（一页 = 一节正歌 + 副歌）', () {
    test('有副歌：每页都自动追加副歌，页数 = 正歌节数', () {
      final h = _hymn(
        verses: const ['第一节行1\n第一节行2', '第二节行1'],
        chorus: '副歌行1\n副歌行2',
      );
      final pages = h.lyricPages;
      expect(pages.length, 2);
      expect(pages[0].stanzaIndex, 0);
      expect(pages[0].verseLines, ['第一节行1', '第一节行2']);
      expect(pages[0].chorusLines, ['副歌行1', '副歌行2']);
      expect(pages[1].hasChorus, isTrue);
      // 正歌 2 行 + 副歌 2 行 + 1 个分隔行
      expect(pages[0].lineCount, 5);
    });

    test('无副歌：页数 = 正歌节数且每页无副歌', () {
      final h = _hymn(verses: const ['甲', '乙', '丙']);
      final pages = h.lyricPages;
      expect(pages.length, 3);
      expect(pages.every((p) => !p.hasChorus), isTrue);
      expect(pages.map((p) => p.lineCount), [1, 1, 1]);
    });

    test('空白正歌被剔除；只有副歌时退化为单页', () {
      expect(_hymn(verses: const ['', '  ', '真节']).lyricPages.length, 1);
      final onlyChorus = _hymn(verses: const [], chorus: '只有副歌');
      expect(onlyChorus.lyricPages.length, 1);
      expect(onlyChorus.lyricPages.single.verse, '');
      expect(onlyChorus.lyricPages.single.chorus, '只有副歌');
    });

    test('既无正歌又无副歌 → 空列表（UI 显示「暂无歌词」）', () {
      expect(_hymn().lyricPages, isEmpty);
    });

    test('audio_durations 解析：版本名 → 秒', () {
      final h = _hymn(durations: const {'鋼琴版': 150.208, '人聲版': 205.198});
      expect(h.durationOf('鋼琴版'), 150.208);
      expect(h.durationOf('人聲版'), 205.198);
      expect(h.durationOf('不存在'), isNull);
    });
  });

  group('不换行的字号上限', () {
    test('宽度上限保证最长行落在可用宽内（CJK 字宽 ≈ 字号）', () {
      const availW = 800.0;
      const displayWidth = 28; // 14 个汉字
      final font = lyricMaxFontByWidth(availW, displayWidth);
      expect(font * displayWidth / 2.0, lessThanOrEqualTo(availW));
    });

    test('空行回退 40，不产生除零', () {
      expect(lyricMaxFontByWidth(800, 0), 40.0);
      expect(lyricMaxFontByHeight(600, 0), 40.0);
    });

    test('高度上限 = 可用高 ÷ (行数 × 2.0)', () {
      expect(lyricMaxFontByHeight(600, 6), 50.0);
    });

    test('LyricPage.maxDisplayWidth 取最长行（全角=2 半角=1）', () {
      const p = LyricPage(0, '短行\n这是一个很长的句子用于测试', '副');
      expect(p.maxDisplayWidth, 13 * 2); // 最长行 13 个汉字
    });
  });

  group('简谱记号还原（code_seq → 元素序列）', () {
    test('第 1 首第 1 谱行：种子映射即可逐字还原库内 notes', () {
      const codeSeq = '4e52 4e52 4e56 4e56 4e59 5d1f 4e59 5d1f '
          '4e5c 5d1f 4e5c 4e5c 4e59 5d1f 4e56 5d1f';
      final elems = decodeScoreElements(codeSeq, const {});
      expect(elems.join(), '11335-5-6-665-3-');
      expect(elems.length, 16);
    });

    test('库内映射优先于种子；未知码位归一化为 ?', () {
      final elems = decodeScoreElements('4e52 4efb', const {'4e52': '1'});
      expect(elems, ['1', '?']);
    });

    test('PPT 合成字形归一化：t → 5-，a → 1^---', () {
      expect(normalizeScoreSym('t'), '5-');
      expect(normalizeScoreSym('a'), '1^---');
      expect(normalizeScoreSym('5'), '5');
    });
  });

  group('一谱多词：各节按第 1 节列位模板落字', () {
    const chars = [
      ScoreChar(1, '耶', 0),
      ScoreChar(2, '稣', 2),
      ScoreChar(3, '尊', 3),
    ];

    test('第 1 节直接用几何对位真值', () {
      expect(stanzaCells(chars, '耶穌尊名', 1), {0: '耶', 2: '稣', 3: '尊'});
    });

    test('第 k 节按字序落到同一套列位', () {
      expect(stanzaCells(chars, '至高至', 2), {0: '至', 2: '高', 3: '至'});
    });

    test('字数不足时只落已有字（不越界）', () {
      expect(stanzaCells(chars, '甲', 3), {0: '甲'});
    });
  });

  group('自动翻页换算', () {
    test('用户口径：4 分钟 4 节 → 每分钟切一节', () {
      int pageAt(int sec) => autoPageIndexFor(
            position: Duration(seconds: sec),
            totalSeconds: 240,
            pageCount: 4,
          );
      expect(pageAt(0), 0);
      expect(pageAt(59), 0);
      expect(pageAt(60), 1); // 第 2 分钟起 = 第二节
      expect(pageAt(119), 1);
      expect(pageAt(120), 2);
      expect(pageAt(180), 3);
      expect(pageAt(239), 3);
    });

    test('进度超出总时长钳在最后一页（不越界）', () {
      expect(
        autoPageIndexFor(
            position: const Duration(seconds: 300),
            totalSeconds: 240,
            pageCount: 4),
        3,
      );
    });

    test('单节 / 无时长 → 恒第 0 页（不翻页）', () {
      expect(
        autoPageIndexFor(
            position: const Duration(seconds: 90),
            totalSeconds: 240,
            pageCount: 1),
        0,
      );
      expect(
        autoPageIndexFor(
            position: const Duration(seconds: 90),
            totalSeconds: 0,
            pageCount: 4),
        0,
      );
    });

    test('343 首钢琴版 207.552 秒 3 节：等分点 69.18 / 138.37', () {
      int pageAt(double sec) => autoPageIndexFor(
            position: Duration(milliseconds: (sec * 1000).round()),
            totalSeconds: 207.552,
            pageCount: 3,
          );
      expect(pageAt(69.0), 0);
      expect(pageAt(69.3), 1);
      expect(pageAt(138.5), 2);
    });
  });

  group('曲谱分页', () {
    ScoreLineRow line(int no, {required Map<int, String> lyrics, bool chorus = false}) {
      return ScoreLineRow(
        lineNo: no,
        phraseNo: no,
        elements: const ['1', '2', '3'],
        chars: const [ScoreChar(1, '甲', 0), ScoreChar(2, '乙', 2)],
        lyrics: lyrics,
        isChorus: chorus,
      );
    }

    test('页数 = 正歌节数；副歌行（仅第 1 节）不增加页数', () {
      final pages = buildScorePages(lines: [
        line(1, lyrics: const {1: '甲', 2: '乙', 3: '丙'}),
        line(2, lyrics: const {1: '副歌行'}, chorus: true),
      ]);
      expect(pages.map((p) => p.stanzaNo), [1, 2, 3]);
      // 第 2 节该行只有 1 个字 → 落到第 1 个列位（模板首列），其余列空
      expect(pages[1].lines.first.cellsFor(2)[0], '乙');
      expect(pages[1].lines.first.cellsFor(2)[2], null);
      // 副歌行每页都用第 1 节文本
      expect(pages[2].lines.last.cellsFor(3)[0], '甲');
    });

    test('maxElements 取页内最宽谱行（字号不换行约束的基准）', () {
      final pages = buildScorePages(lines: [
        line(1, lyrics: const {1: '甲'}),
        const ScoreLineRow(
          lineNo: 2,
          phraseNo: 2,
          elements: ['1', '2', '3', '4', '5'],
          chars: [],
          lyrics: {1: '甲乙'},
          isChorus: false,
        ),
      ]);
      expect(pages.single.maxElements, 5);
    });
  });
}
