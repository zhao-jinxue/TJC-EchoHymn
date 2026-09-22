import 'package:flutter_test/flutter_test.dart';
import 'package:echo_hymn/models/hymn_category.dart';
import 'package:echo_hymn/models/hymn_ref.dart';
import 'package:echo_hymn/models/playlist.dart';

/// 歌单成员编号（hymns JSON）类型放宽守卫测试（2026-09-22）。
///
/// 背景：站方存在 `51_a` / `124_b` 这类甲乙变体编号，而旧实现要求
/// `hymns` 值为整数（`(v as num).toInt()`），导致这 10 首无法进入
/// 「默认歌单」二级目录、加入个人歌单时还会把 id 当编号存错。
/// 现在统一用**编号字符串**，并兼容旧库里的整数。
void main() {
  test('整数编号与变体编号都能解析为编号字符串', () {
    final refs = parseHymnRefs('[{"赞美天父": 4}, {"万古灵磐(甲)": "51_a"}]');
    expect(refs.length, 2);
    expect(refs[0].key, '赞美天父');
    expect(refs[0].value, '4'); // 旧库 int → 字符串
    expect(refs[1].value, '51_a'); // 变体编号原样保留
  });

  test('HymnCategory.fromDbRow 同时兼容整数与字符串编号', () {
    final cat = HymnCategory.fromDbRow({
      'id': 1,
      'category': '颂赞',
      'subcategory': '赞美天父',
      'hymns': '[{"颂赞独一无二神": 1}, {"万古灵磐(甲)": "51_a"}]',
    });
    expect(cat.category, '颂赞');
    expect(cat.hymns.map((e) => e.value).toList(), ['1', '51_a']);
  });

  test('Playlist.fromDbRow 解析旧整数格式不丢成员，写回为字符串', () {
    final pl = Playlist.fromDbRow({
      'id': 7,
      'name': '我的歌单',
      'created_at': 't0',
      'updated_at': 't1',
      'hymns': '[{"耶稣爱我": 27}, {"实行爱心(乙)": "124_b"}]',
    });
    expect(pl.count, 2);
    expect(pl.hymns.map((e) => e.value).toList(), ['27', '124_b']);
    // 序列化后编号为字符串 → 再解析仍一致（往返无损）
    final round = parseHymnRefs(Playlist.hymnsToJson(pl.hymns));
    expect(round.map((e) => e.value).toList(), ['27', '124_b']);
    expect(round.map((e) => e.key).toList(), pl.hymns.map((e) => e.key).toList());
  });

  test('脏数据容错：非法 JSON / 空值 / 缺字段', () {
    expect(parseHymnRefs(''), isEmpty);
    expect(parseHymnRefs('not-a-json'), isEmpty);
    expect(hymnRefNumber(null), '');
    expect(hymnRefNumber(12), '12');
    expect(hymnRefNumber('51_b'), '51_b');
    final cat = HymnCategory.fromDbRow({'id': 3, 'hymns': '[]'});
    expect(cat.hymns, isEmpty);
    expect(cat.category, '');
  });
}
