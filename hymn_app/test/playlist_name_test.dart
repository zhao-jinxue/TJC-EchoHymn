import 'package:flutter_test/flutter_test.dart';
import 'package:echo_hymn/services/sqlite_repository.dart';

/// 歌单名称入参防御测试（v1.8.0 加固，见 docs/Windows/CODE_REFERENCE.md「五」）。
///
/// 背景：歌单名称此前只在 UI（`TextField.maxLength` + `onChanged` 里 trim）
/// 做校验，仓储层无兜底。新增 `normalizePlaylistName` 把「trim + 30 字上限」
/// 下沉到仓储层，使「空名/超长名」无法经任何调用方写入数据库。
void main() {
  group('normalizePlaylistName（仓储层入参防御）', () {
    test('去首尾空白', () {
      expect(normalizePlaylistName('  诗班歌单  '), '诗班歌单');
    });

    test('空串 / 纯空白归一化为空串', () {
      expect(normalizePlaylistName(''), '');
      expect(normalizePlaylistName('   '), '');
      expect(normalizePlaylistName('\t\n '), '');
    });

    test('超过 30 字截断到上限，且上限常量为 30', () {
      expect(kPlaylistNameMaxLength, 30);
      final long = 'a' * 40;
      final out = normalizePlaylistName(long);
      expect(out.length, kPlaylistNameMaxLength);
      expect(out, 'a' * 30);
    });

    test('恰好 30 字原样保留（边界内不截断）', () {
      final exactly = 'x' * 30;
      expect(normalizePlaylistName(exactly), exactly);
    });

    test('中文名称按字符计数（30 个汉字不截断）', () {
      final cn = '赞' * 30;
      expect(normalizePlaylistName(cn), cn);
      expect(normalizePlaylistName('赞' * 31).length, 30);
    });
  });
}
