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

/// 印刷 PDF 简谱字体的**权威码本**（`hymn_codepoint_map` 同源，2026-09-21 按字形几何重建）
///
/// 旧映射把带装饰的合成字形当成纯音级（如 `4ef0` 记为 `5`），
/// 导致曲谱缺时值下划线、缺低/高音点。现按字体轮廓还原：
/// - 低音点 = 数字框下方点 → `,`；高音点 = 上方点 → `^`；
/// - 一条时值线 = `_`，两条 = `=`，附点 = `.`（与 `_GlyphDeco.parse` 同口径）；
/// - 连音线/弧线等纯装饰字形 → 空串（占列但不显示，避免破坏逐字对位）。
const Map<String, String> kSeedCodepoints = {
  '3021': '|', '4e42': '7,', '4e43': '7,', '4e45': '1,', '4e47': '2,', '4e48': '3,',
  '4e4b': '4,', '4e4d': '5,', '4e4e': '6,', '4e4f': '7,', '4e52': '1', '4e53': '2',
  '4e56': '3', '4e58': '4', '4e59': '5', '4e5c': '6', '4e5d': '7', '4e5e': '1^',
  '4e5f': '2^', '4e69': '3^', '4e73': '4^', '4eda': '1_', '4edc': '2_', '4edd': '3_',
  '4ede': '4_', '4edf': '5_', '4ee1': '6_', '4ee3': '7_', '4ee4': '1_', '4ee5': '2_',
  '4ee8': '3_', '4ee9': '4_', '4ef0': '5_', '4ef1': '6_', '4ef2': '7_', '4ef3': '1^_',
  '4ef4': '2^_', '4ef5': '3^_', '4ef6': '4^', '4f52': '1,=', '4f53': '2,=', '4f54': '3,=',
  '4f55': '4,=', '4f56': '5,=', '4f57': '6,=', '4f58': '7,=', '4f59': '1=', '4f5a': '2=',
  '4f5b': '3=', '4f5c': '4=', '4f5d': '5=', '4f5e': '6=', '4f5f': '7=', '4f60': '1^=',
  '4f61': '2^=', '4f62': '3^=', '531c': '3', '5d1f': '-', '5d26': '#', '5d27': 'b',
  '5d29': '#', '5d2e': 'b', '5d39': '-', '5d3a': '=', '5d3d': '.', '5d3f': '._',
  '5d42': '.', '5d49': '_', '5d4c': '0', '5d4e': '0_', '5dd5': '=', '5df4': '',
  '5df7': '', '5e15': '', '5e28': '', '5e59': '', '5e5c': '', '5e5d': '', '5e5f': '',
  '5e60': '', '5e61': '', '5e62': '', '5e63': '', '5e66': '', '5e67': '', '5e68': '',
  '5e69': '', '5e6a': '', '5e6b': '', '5e6c': '', '5e6d': '', '5e6e': '', '5e80': '',
  '5e9a': '', '600b': '|', '601a': '|', '601d': '|', '602a': '|', '602d': '|',
  '6032': '|', '6047': '|',
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

/// 码位序列（`code_seq`，空格分隔；元素可含 '+' 连接的多码位）→ 元素记号序列
///
/// [dbMap] 为库内 `hymn_codepoint_map`（优先级高于种子，与爬虫入库同序）。
/// 单码位元素未解码 → `?`；多码位组合元素（音符+修饰）未知修饰 → 跳过。
List<String> decodeScoreElements(String codeSeq, Map<String, String> dbMap) {
  final cps = codeSeq.trim().isEmpty ? const <String>[] : codeSeq.trim().split(RegExp(r'\s+'));
  if (cps.isEmpty) return const [];
  return [
    for (final tok in cps)
      if (!tok.contains('+'))
        normalizeScoreSym(dbMap[tok] ?? kSeedCodepoints[tok] ?? '?')
      else
        [
          for (final cp in tok.split('+'))
            if ((dbMap[cp] ?? kSeedCodepoints[cp]) != null)
              normalizeScoreSym(dbMap[cp] ?? kSeedCodepoints[cp]!),
        ].join(),
  ];
}

/// 谱行的一行歌词在某节下的「列位（元素序号）→ 显示文本」
///
/// - 第 1 节：直接用 `hymn_score_char` 的几何对位真值；
///   标点行（note_index < 0）并入前一字的显示文本（不占列位）；
/// - 第 k 节：按字序落到第 1 节的列位模板上（一谱多词，各节字数相等），
///   文本中的标点后附到前一字。
Map<int, String> stanzaCells(
    List<ScoreChar> chars, String text, int stanzaNo) {
  if (stanzaNo == 1) {
    final out = <int, String>{};
    int? last;
    for (final c in chars) {
      if (c.noteIndex >= 0) {
        out[c.noteIndex] = c.syllable;
        last = c.noteIndex;
      } else if (last != null && c.syllable.isNotEmpty) {
        out[last] = '${out[last]}${c.syllable}';
      }
    }
    return out;
  }
  final slots = [for (final c in chars) if (c.noteIndex >= 0) c.noteIndex];
  final toks = <String>[];
  for (final r in text.runes) {
    if (_isSpace(r)) continue;
    final ch = String.fromCharCode(r);
    if (_isCjk(r)) {
      toks.add(ch);
    } else if (toks.isNotEmpty) {
      toks[toks.length - 1] = '${toks.last}$ch';
    }
  }
  final out = <int, String>{};
  for (var i = 0; i < slots.length && i < toks.length; i++) {
    out[slots[i]] = toks[i];
  }
  return out;
}

bool _isSpace(int rune) =>
    rune == 0x20 || rune == 0x09 || rune == 0x0A || rune == 0x0D || rune == 0x3000;

bool _isCjk(int rune) => rune >= 0x4e00 && rune <= 0x9fff;

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
