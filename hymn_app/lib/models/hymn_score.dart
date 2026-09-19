/// 简谱曲谱 + 歌词逐字对位模型（数据源：`hymn_score_line` / `hymn_score_lyric` /
/// `hymn_score_char` / `hymn_codepoint_map`，见 `docs` 与爬虫侧 `tool/show_score.py`）。
///
/// 渲染原理（**不重新对位，只做还原**）：
/// - `hymn_score_char.note_index` = 该字对应元素在**行内元素序列**中的序号
///   （爬虫抽取时由 PDF 几何对位确定），于是谱行与词行共用同一套列位置；
/// - 元素边界取自 `hymn_score_line.code_seq`（空格分隔的逐元素码位）——
///   **不能**按 `notes` 串逐字符切分：合成字形（`5-`、`#1`）一个元素占两个字符；
/// - 记号还原 = 库内 `hymn_codepoint_map`（优先）+ [kSeedCodepoints]（兜底）
///   + [normalizeScoreSym]（PPT 合成字形归一化），与爬虫入库时同一口径
///   （实测 3316/3316 主旋律谱行还原结果与库内 `notes` 逐字一致）。
///
/// 一谱多词：`hymn_score_char` 只存**第 1 节**的几何对位，其余各节按字序落到
/// 第 1 节的列位模板上（标准唱法各节字数相等；实测 473/473 首全部一致）。
library;

/// 人工确认的「码位 → 记号」种子（与爬虫侧 `pdf_score.MANUAL_SEED` 同源，2026-09-15 目视对齐）
const Map<String, String> kSeedCodepoints = {
  '4e52': '1', '4e53': '2', '4e56': '3', '4e58': '4', '4e59': '5',
  '4e5c': '6', '4e5d': '7', '4e4c': '0',
  '4ee4': '1', '4ee5': '2', '4ee8': '3', '4ef0': '5',
  '5d1f': '-', '5d26': '#',
  '4e3c': '5', '5d4c': '0', '5d42': '7', '4e43': '6',
  '4e42': '7', '4ed9': '7', '5d27': 'b',
};

/// PPT 合成字形 → 简谱记号（与爬虫侧 `pdf_score._SYM_ALIASES` 同源）
///
/// `q w e r t y u` = 各音级 + 一拍延长；`Q W E R T Y U` = + 高音点；
/// `a d f g h j s` / 大写 = + 高音点 + 三拍延长。
final Map<String, String> kSymAliases = _buildSymAliases();

Map<String, String> _buildSymAliases() {
  const digits = '1234567';
  final out = <String, String>{};
  void add(String keys, String Function(String d) f) {
    for (var i = 0; i < keys.length; i++) {
      out[keys[i]] = f(digits[i]);
    }
  }

  add('qwertyu', (d) => '$d-');
  add('QWERTYU', (d) => '$d^-');
  add('adfghjs', (d) => '$d^---');
  add('ADFGHJS', (d) => '$d^---');
  return out;
}

/// PPT/PDF 记号 → 简谱记号（未收录者原样返回；`?` 表示该码位未解码）
String normalizeScoreSym(String sym) => kSymAliases[sym] ?? sym;

/// 码位序列（`code_seq`，空格分隔）→ 元素记号序列
///
/// [dbMap] 为库内 `hymn_codepoint_map`（优先级高于种子，与爬虫入库同序）。
List<String> decodeScoreElements(String codeSeq, Map<String, String> dbMap) {
  final cps = codeSeq.trim().isEmpty ? const <String>[] : codeSeq.trim().split(RegExp(r'\s+'));
  if (cps.isEmpty) return const [];
  return [
    for (final cp in cps)
      normalizeScoreSym(dbMap[cp] ?? kSeedCodepoints[cp] ?? '?'),
  ];
}

/// 谱行的一行歌词在某节下的「列位（元素序号）→ 字」
///
/// - 第 1 节：直接用 `hymn_score_char` 的几何对位真值；
/// - 第 k 节：按字序落到第 1 节的列位模板上（一谱多词，各节字数相等）。
Map<int, String> stanzaCells(
    List<ScoreChar> chars, String text, int stanzaNo) {
  if (stanzaNo == 1) {
    return {for (final c in chars) if (c.noteIndex >= 0) c.noteIndex: c.syllable};
  }
  final slots = [for (final c in chars) if (c.noteIndex >= 0) c.noteIndex];
  final syllables = [
    for (final r in text.runes)
      if (!_isSpace(r)) String.fromCharCode(r),
  ];
  final out = <int, String>{};
  for (var i = 0; i < slots.length && i < syllables.length; i++) {
    out[slots[i]] = syllables[i];
  }
  return out;
}

bool _isSpace(int rune) =>
    rune == 0x20 || rune == 0x09 || rune == 0x0A || rune == 0x0D || rune == 0x3000;

/// 逐字对位记录（`hymn_score_char` 行）
class ScoreChar {
  const ScoreChar(this.charNo, this.syllable, this.noteIndex);
  final int charNo;
  final String syllable;
  final int noteIndex;
}

/// 歌词行记录（`hymn_score_lyric` 行）
class ScoreLyric {
  const ScoreLyric(this.lineNo, this.stanzaNo, this.text);
  final int lineNo;
  final int stanzaNo;
  final String text;
}

/// 谱行记录（`hymn_score_line` 的主旋律行）
class ScoreLineRow {
  const ScoreLineRow({
    required this.lineNo,
    required this.phraseNo,
    required this.elements,
    required this.chars,
    required this.lyrics,
    required this.isChorus,
  });

  final int lineNo;

  /// 乐句号（同乐句的谱行视觉归组）
  final int phraseNo;

  /// 元素记号序列（与 `code_seq` 等长）
  final List<String> elements;

  /// 第 1 节逐字对位
  final List<ScoreChar> chars;

  /// 该行各节歌词文本（stanza_no → text）
  final Map<int, String> lyrics;

  /// 是否副歌行（各页都用第 1 节文本，不随节号变化）
  final bool isChorus;

  /// 某节的「列位 → 字」；副歌行恒用第 1 节
  Map<int, String> cellsFor(int stanzaNo) =>
      stanzaCells(chars, lyrics[isChorus ? 1 : stanzaNo] ?? '', isChorus ? 1 : stanzaNo);

  /// 该行参与对位的列位数（第 1 节模板字数）
  int get slotCount => chars.where((c) => c.noteIndex >= 0).length;
}

/// 一页曲谱 = 全部主旋律谱行 + 该节歌词（副歌行每页重复）
class ScorePage {
  const ScorePage({required this.stanzaNo, required this.lines});

  /// 节号（1 基）
  final int stanzaNo;
  final List<ScoreLineRow> lines;

  /// 页内最宽谱行的元素数（字号「不换行」约束的宽度基准）
  int get maxElements =>
      lines.fold(0, (m, l) => l.elements.length > m ? l.elements.length : m);

  /// 页内最长歌词字数（列宽需容纳一个汉字）
  int get maxCellDisplayWidth {
    var w = 2; // 汉字 = 2 个半角列
    for (final l in lines) {
      for (final e in l.elements) {
        final ew = displayWidth(e);
        if (ew > w) w = ew;
      }
    }
    return w;
  }
}

/// 由原始表行构建分页曲谱（每节一页）
///
/// [stanzas] 为该首正歌的节号集合（副歌行只有第 1 节，不计入页数）。
List<ScorePage> buildScorePages({
  required List<ScoreLineRow> lines,
}) {
  if (lines.isEmpty) return const [];
  final stanzas = <int>{};
  for (final l in lines) {
    if (l.isChorus) continue;
    stanzas.addAll(l.lyrics.keys);
  }
  if (stanzas.isEmpty) stanzas.add(1);
  final sorted = stanzas.toList()..sort();
  return [
    for (final st in sorted) ScorePage(stanzaNo: st, lines: lines),
  ];
}

/// 东亚显示宽度（汉字/全角 = 2 列，其余 = 1 列）——与爬虫侧 `show_score.display_width` 同口径
int displayWidth(String s) {
  var w = 0;
  for (final r in s.runes) {
    w += _isWide(r) ? 2 : 1;
  }
  return w;
}

bool _isWide(int r) =>
    (r >= 0x1100 && r <= 0x115F) ||
    r == 0x2329 ||
    r == 0x232A ||
    (r >= 0x2E80 && r <= 0xA4CF && r != 0x303F) ||
    (r >= 0xAC00 && r <= 0xD7A3) ||
    (r >= 0xF900 && r <= 0xFAFF) ||
    (r >= 0xFE30 && r <= 0xFE6F) ||
    (r >= 0xFF00 && r <= 0xFF60) ||
    (r >= 0xFFE0 && r <= 0xFFE6);
