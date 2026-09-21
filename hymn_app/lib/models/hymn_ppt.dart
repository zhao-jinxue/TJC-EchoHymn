/// PPT 官方管线曲谱模型（数据源：`hymn_ppt` / `hymn_ppt_line`，见 docs 任务 6）。
///
/// 设计思路（参考并消化官方 PPT 的「字符编码 + 专用字体」方案）：
/// - 简谱以**编码串**存储（如 `1  1    3  3 \ 5/5/\6/6  6\5/3/\`），
///   显示时用内嵌的 `JianPu` 字体（`assets/fonts/jianpu.ttf`，与 PPT 同源）
///   直接渲染——数字/高低音点/时值下划线/小节线/延音线/反复记号全部由
///   字体 glyph 原生承载，零宽修饰符自动叠画在前一字符上；
/// - 歌词行保留 PPT 原串（含对齐空格），与简谱行共用 **0.5em 单位网格**：
///   全角字符 = 2 单位、半角空格 = 1 单位，两行天然逐列对齐；
/// - 一页 PPT = 一节（含可能的节标签行如「(副歌)」= 仅有歌词的行）。
library;

/// 简谱字体中**零宽**（叠加修饰）码位集合（cmap 实测 adv=0，2026-09-21）
const Set<int> kJianpuZeroWidth = {
  0x22, 0x27, 0x28, 0x29, 0x2A, 0x2B, 0x2C, 0x2D, 0x30, 0x38, 0x39, 0x3A,
  0x3C, 0x3D, 0x49, 0x4B, 0x4C, 0x4F, 0x50, 0x5F, 0x69, 0x6B, 0x7B, 0x7D,
  0x7E,
};

/// 两行字号比：**歌词行字号 = 2 × 简谱行字号**（2026-09-21 全库 6249 行对位
/// 最小二乘拟合中位数 R = 2.000，p10 2.00 / p90 2.10；与 PPT 内解析出的
/// 字号（歌词 21.02pt / 母版默认 10.28pt ≈ 1:2）一致）。
const double kPptLyricFontRatio = 2.0;

/// 简谱字体 em 宽度：空格 0.5、零宽修饰 0、其余 1.0（cmap/hmtx 实测）
double scoreLineEm(String enc) {
  var em = 0.0;
  for (final r in enc.runes) {
    if (r == 0x20) {
      em += 0.5;
    } else if (!kJianpuZeroWidth.contains(r)) {
      em += 1.0;
    }
  }
  return em;
}

/// 歌词字体 em 宽度：汉字/全角 1.0、半角（含空格）0.5（hmtx 实测）
double lyricLineEm(String lyric) {
  var em = 0.0;
  for (final r in lyric.runes) {
    em += _isWide(r) ? 1.0 : 0.5;
  }
  return em;
}

bool _isWide(int r) =>
    (r >= 0x1100 && r <= 0x115F) ||
    r == 0x2329 ||
    r == 0x232A ||
    (r >= 0x2E80 && r <= 0xA4CF && r != 0x303F) ||
    (r >= 0x3000 && r <= 0x303E) ||
    (r >= 0xAC00 && r <= 0xD7A3) ||
    (r >= 0xF900 && r <= 0xFAFF) ||
    (r >= 0xFE30 && r <= 0xFE6F) ||
    (r >= 0xFF00 && r <= 0xFF60) ||
    (r >= 0xFFE0 && r <= 0xFFE6);

/// 一行（简谱编码 + 歌词；标签行/空行仅有歌词）
class PptLine {
  const PptLine({required this.scoreEnc, required this.lyric});

  /// 简谱编码原串（PPT 原文；空串 = 仅歌词行）
  final String scoreEnc;

  /// 歌词原串（含对齐空格；仅简谱行时为 null）
  final String? lyric;

  bool get isScoreLine => scoreEnc.trim().isNotEmpty;
  bool get isLyricOnly => scoreEnc.trim().isEmpty;

  /// 简谱行 em 宽
  double get scoreEm => isScoreLine ? scoreLineEm(scoreEnc) : 0;

  /// 歌词行 em 宽
  double get lyricEm => (lyric ?? '').isEmpty ? 0 : lyricLineEm(lyric!);
}

/// 一页 PPT = 一节
class PptSlide {
  const PptSlide({required this.slideNo, this.header, this.pageMark, required this.lines});

  final int slideNo;

  /// 首页头行（编号、标题、调号、拍号、速度）
  final String? header;

  /// 页码标记（如 `1/3`）
  final String? pageMark;

  final List<PptLine> lines;

  /// 页内最宽简谱行（em）
  double get maxScoreEm =>
      lines.fold(0.0, (m, l) => l.scoreEm > m ? l.scoreEm : m);

  /// 页内最宽歌词行（em）
  double get maxLyricEm =>
      lines.fold(0.0, (m, l) => l.lyricEm > m ? l.lyricEm : m);
}

/// 一首歌的全部 PPT 页
class PptDoc {
  const PptDoc({required this.hymnNumber, required this.slides});

  final String hymnNumber;
  final List<PptSlide> slides;
}
