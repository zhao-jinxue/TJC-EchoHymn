import 'package:flutter_test/flutter_test.dart';
import 'package:echo_hymn/theme/app_fonts.dart';

/// v1.5.0 字号等级守卫测试：重复点击同一字号等级不会导致字号累加变大。
///
/// 设计依据：`FontScaleController.switchTo` 与 `_switchFontSize` 均有
/// `if (level == current) return;` 守卫；`AppFonts.scale` 只是当前等级的
/// 固定常量（无任何累乘状态）。本测试直接验证控制器层的行为。
void main() {
  setUp(() {
    // 每个用例前复位到默认，避免用例间污染
    FontScaleController.instance.switchTo(FontSizeLevel.normal);
  });

  test('重复点击同一字号等级，系数固定不变（不会连续变大）', () {
    expect(FontScaleController.instance.scale, 1.0);

    // 第一次切「大号」→ 1.6
    FontScaleController.instance.switchTo(FontSizeLevel.large);
    expect(FontScaleController.instance.current, FontSizeLevel.large);
    expect(FontScaleController.instance.scale, 1.6);

    // 连续重复点击「大号」→ 守卫直接 return，系数始终 1.6（绝非 1.6×1.6 累乘）
    for (var i = 0; i < 5; i++) {
      FontScaleController.instance.switchTo(FontSizeLevel.large);
      expect(FontScaleController.instance.scale, 1.6,
          reason: '第 ${i + 1} 次重复点击后系数必须仍是 1.6');
    }

    // 切走再切回 → 仍是固定 1.6
    FontScaleController.instance.switchTo(FontSizeLevel.medium);
    expect(FontScaleController.instance.scale, 1.3);
    FontScaleController.instance.switchTo(FontSizeLevel.large);
    expect(FontScaleController.instance.scale, 1.6);
  });

  test('四档字号系数均为固定常量', () {
    expect(FontSizeLevel.normal.scale, 1.0);
    expect(FontSizeLevel.medium.scale, 1.3);
    expect(FontSizeLevel.large.scale, 1.6);
    expect(FontSizeLevel.xlarge.scale, 1.9);
  });

  test('非法 id 回退默认（state.json 容错）', () {
    expect(fontSizeLevelById('random-bad-value'), FontSizeLevel.normal);
    expect(fontSizeLevelById(null), FontSizeLevel.normal);
    expect(fontSizeLevelById('large'), FontSizeLevel.large);
  });
}
