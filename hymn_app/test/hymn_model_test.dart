import 'package:echo_hymn/models/hymn.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Hymn 模型', () {
    test('fromJson 解析完整数据', () {
      final hymn = Hymn.fromJson({
        'id': 1,
        'number': 1,
        'title': '天父世界真美丽',
        'author': 'Maltbie D. Babcock',
        'composer': 'Franklin L. Sheppard',
        'category': '赞美',
        'audio': 'https://example.com/a.mp3',
        'lyrics': [
          ['这是天父世界，', '我们侧耳要听。'],
          ['这是天父世界，', '我心满有安宁。'],
        ],
      });

      expect(hymn.id, 1);
      expect(hymn.number, 1);
      expect(hymn.title, '天父世界真美丽');
      expect(hymn.author, 'Maltbie D. Babcock');
      expect(hymn.composer, 'Franklin L. Sheppard');
      expect(hymn.category, '赞美');
      expect(hymn.audio, 'https://example.com/a.mp3');
      expect(hymn.lyrics.length, 2);
      expect(hymn.lyrics[0], ['这是天父世界，', '我们侧耳要听。']);
      expect(hymn.lyrics[1][1], '我心满有安宁。');
    });

    test('fromJson 容错缺失字段', () {
      final hymn = Hymn.fromJson({
        'id': 2,
        'number': 2,
        'title': '无元数据',
      });

      expect(hymn.id, 2);
      expect(hymn.title, '无元数据');
      expect(hymn.author, '');
      expect(hymn.composer, '');
      expect(hymn.category, '');
      expect(hymn.audio, '');
      expect(hymn.lyrics, isEmpty);
    });

    test('nameWithNumber 与 meta', () {
      final hymn = Hymn.fromJson({
        'id': 3,
        'number': 7,
        'title': '安静认识神',
        'author': '传统赞美诗',
        'composer': '传统赞美诗',
        'category': '灵修',
        'lyrics': [],
      });

      expect(hymn.nameWithNumber, '7 · 安静认识神');
      expect(hymn.meta, '第 7 首 · 灵修 · 词：传统赞美诗 · 曲：传统赞美诗');
    });
  });
}