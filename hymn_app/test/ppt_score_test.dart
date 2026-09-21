import 'package:flutter_test/flutter_test.dart';

import 'package:echo_hymn/models/hymn_ppt.dart';

/// PPT 编码体系单元测试（任务 6）
///
/// 期望值来源：`tools/_em_expect.py`（同一规则独立复算）+ 字体实测 advance
/// （简谱字体：数字 1em / 空格 0.5em / 零宽修饰 0em；歌词字体：汉字 1em / 半角 0.5em）。
void main() {
  group('简谱编码 em 宽度（字体实测规则）', () {
    test('第 1 首第 1 节第 1 行 = 26.0 em', () {
      const enc = '1  1    3  3 \\ 5/5/\\6/6  6\\5/3/\\';
      expect(scoreLineEm(enc), 26.0);
    });

    test('第 1 首第 1 节第 2 行 = 31.5 em', () {
      const enc = '   5.t    5  5 \\ !/7  5\\2    5  6.t\\5///\\';
      expect(scoreLineEm(enc), 31.5);
    });

    test('零宽修饰符不占宽（修饰符叠加在前一字符上）', () {
      expect(scoreLineEm('5'), 1.0);
      expect(scoreLineEm("5'"), 1.0); // 高音点
      expect(scoreLineEm('58'), 1.0); // 低音点
      expect(scoreLineEm('5('), 1.0); // 连音线弧
      expect(scoreLineEm('5='), 1.0); // 双下划线
      expect(scoreLineEm('5='), scoreLineEm('5'));
    });

    test('空格 = 0.5 em，小节线/延音线/附点各占 1 em', () {
      expect(scoreLineEm('  '), 1.0);
      expect(scoreLineEm('\\'), 1.0);
      expect(scoreLineEm('/'), 1.0);
      expect(scoreLineEm('5.'), 2.0);
      expect(scoreLineEm('5///|'), 5.0);
    });

    test('第 12 首首行（字母组合字形 = 数字+下划线）', () {
      const enc = '  tiyi \\ 1  1  1  eq \\ 68  yiojk   yiti';
      expect(scoreLineEm(enc), 23.5);
    });
  });

  group('歌词行 em 宽度（汉字 1em / 半角 0.5em）', () {
    test('第 1 首首行歌词 = 16.0 em（含 2 个对齐空格）', () {
      expect(lyricLineEm('  圣哉，圣哉，圣哉，全能大主宰！'), 16.0);
    });

    test('全角标点按汉字计宽，半角空格按 0.5 计', () {
      expect(lyricLineEm('，！？'), 3.0);
      expect(lyricLineEm(' '), 0.5);
      expect(lyricLineEm('A1'), 1.0);
      expect(lyricLineEm(''), 0.0);
    });

    test('节标签行（如「(副歌)」）', () {
      expect(lyricLineEm('  (副歌)'), 4.0);
    });
  });

  group('行 / 页聚合', () {
    test('PptLine：谱行 em 与词行 em 分别计算', () {
      const line = PptLine(
        scoreEnc: '1  1    3  3 \\ 5/5/\\6/6  6\\5/3/\\',
        lyric: '  圣哉，圣哉，圣哉，全能大主宰！',
      );
      expect(line.isScoreLine, isTrue);
      expect(line.scoreEm, 26.0);
      expect(line.lyricEm, 16.0);
    });

    test('PptLine：仅歌词行（节标签）谱行 em = 0', () {
      const line = PptLine(scoreEnc: '', lyric: '  (副歌)');
      expect(line.isScoreLine, isFalse);
      expect(line.isLyricOnly, isTrue);
      expect(line.scoreEm, 0.0);
      expect(line.lyricEm, 4.0);
    });

    test('PptSlide：页内最宽谱行/词行', () {
      const slide = PptSlide(
        slideNo: 1,
        header: '1、颂赞独一真神  降E大调 4/4  ♩=76',
        pageMark: '1/3',
        lines: [
          PptLine(
            scoreEnc: '1  1    3  3 \\ 5/5/\\6/6  6\\5/3/\\',
            lyric: '  圣哉，圣哉，圣哉，全能大主宰！',
          ),
          PptLine(
            scoreEnc: '   5.t    5  5 \\ !/7  5\\2    5  6.t\\5///\\',
            lyric: ' 天上、地下、海中万物，颂主高名；',
          ),
          PptLine(scoreEnc: '', lyric: '  (副歌)'),
        ],
      );
      expect(slide.maxScoreEm, 31.5);
      expect(slide.maxLyricEm, 16.5);
      expect(slide.lines.length, 3);
      expect(slide.pageMark, '1/3');
    });

    test('PptDoc：一首歌多节', () {
      const doc = PptDoc(hymnNumber: '1', slides: [
        PptSlide(slideNo: 1, lines: [PptLine(scoreEnc: '5', lyric: '圣')]),
        PptSlide(slideNo: 2, lines: [PptLine(scoreEnc: '6', lyric: '哉')]),
      ]);
      expect(doc.slides.length, 2);
      expect(doc.slides[1].slideNo, 2);
    });
  });

  group('字号比（PPT 同构约束）', () {
    test('歌词字号 = 2 × 简谱字号（全库 6249 行拟合中位数）', () {
      expect(kPptLyricFontRatio, 2.0);
    });

    test('简谱字体零宽码位集合包含全部叠加修饰符', () {
      for (final ch in ["'", '"', '8', '9', '+', '=', ',', '-', ':', 'P', '(', ')']) {
        expect(kJianpuZeroWidth.contains(ch.codeUnitAt(0)), isTrue,
            reason: '零宽修饰符 $ch 应参与叠加');
      }
      for (final ch in ['1', '5', 't', '/', '\\', '|']) {
        expect(kJianpuZeroWidth.contains(ch.codeUnitAt(0)), isFalse,
            reason: '$ch 应占一列');
      }
    });
  });
}
