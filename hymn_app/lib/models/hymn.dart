import 'dart:convert';

/// 诗歌数据模型（对应数据库 tjc_hymn 表）
class Hymn {
  final int id;
  final String hymnNumber;
  final String title;
  final String lyricist;
  final String composer;
  final String sourceInfo;
  final int verseCount;
  final List<String> verses;
  final String staffImgPath; // 五线谱 PDF
  final String numberedImgPath; // 简谱 PDF
  final String staffPngPath; // 五线谱 PNG
  final String numberedPngPath; // 简谱 PNG
  final Map<String, String> audioVersions; // 版本名 → 文件路径
  final List<String> audioVersionList;

  /// 副歌原文（`tjc_hymn.chorus`，繁体，行间以 \n 分隔；无副歌为空串）
  final String chorus;

  /// 各音频版本的时长（秒）：版本名 → seconds（`tjc_hymn.audio_durations`）
  final Map<String, double> audioDurations;
  final String downloadStatus;
  final String integrityStatus;

  const Hymn({
    required this.id,
    required this.hymnNumber,
    required this.title,
    required this.lyricist,
    required this.composer,
    required this.sourceInfo,
    required this.verseCount,
    required this.verses,
    required this.staffImgPath,
    required this.numberedImgPath,
    required this.staffPngPath,
    required this.numberedPngPath,
    required this.audioVersions,
    required this.audioVersionList,
    this.chorus = '',
    this.audioDurations = const {},
    required this.downloadStatus,
    required this.integrityStatus,
  });

  // ---- 兼容字段（新版用 lyricist/composer，旧代码用 author） ----
  String get number => hymnNumber;
  String get author => lyricist;
  String get category => '';
  String get audio => '';

  /// 列表展示名：编号 · 标题
  String get nameWithNumber => '$hymnNumber · $title';

  /// 底部状态栏信息：第 N 首 · 标题 · 词：作词 · 曲：作曲
  String get statusMeta =>
      '第 $hymnNumber 首 · $title · 词：$lyricist · 曲：$composer';

  /// 解析 audio_versions JSON 字符串 => Map
  static Map<String, String> parseAudioVersions(String raw) {
    if (raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded.map((k, v) => MapEntry(k, v.toString()));
      }
    } catch (_) {}
    return const {};
  }

  /// 解析 audio_version_list JSON 字符串 => List<String>
  static List<String> parseAudioVersionList(String raw) {
    if (raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded.map((e) => e.toString()).toList();
      }
    } catch (_) {}
    return const [];
  }

  /// 指定版本名的音频文件路径（若有）
  String? audioPathOf(String version) => audioVersions[version];

  /// 指定版本名的音频时长（秒）；无记录返回 null
  double? durationOf(String version) => audioDurations[version];

  /// 副歌（已去首尾空白）
  String get chorusText => chorus.trim();

  /// 歌词分页（**一页 = 一节完整歌词**）
  ///
  /// 数据库 `tjc_hymn.chorus` 是副歌文本；有副歌时每一节都要把副歌接在正歌后面
  /// 才构成完整的一节，因此分页单位是「节」而不是「首」。
  /// 无正歌但有副歌（罕见）→ 退化为单页副歌；两者皆空 → 空列表（UI 显示「暂无歌词」）。
  List<LyricPage> get lyricPages {
    final body = <String>[
      for (final v in verses)
        if (v.trim().isNotEmpty) v.trim(),
    ];
    final ch = chorusText;
    if (body.isEmpty) {
      return ch.isEmpty ? const [] : [LyricPage(0, '', ch)];
    }
    return [
      for (var i = 0; i < body.length; i++)
        LyricPage(i, body[i], ch),
    ];
  }

  /// 从 SQLite 行（按列名索引的 Map）构建
  factory Hymn.fromDbRow(Map<String, Object?> row) {
    String str(String key) => (row[key] as String?) ?? '';
    int intVal(String key) => (row[key] as int?) ?? 0;

    final verses = <String>[
      for (var i = 1; i <= 10; i++) str('verse_$i'),
    ].where((v) => v.trim().isNotEmpty).toList();

    return Hymn(
      id: intVal('id'),
      hymnNumber: str('hymn_number'),
      title: str('title'),
      lyricist: str('lyricist'),
      composer: str('composer'),
      sourceInfo: str('source_info'),
      verseCount: intVal('verse_count'),
      verses: verses,
      staffImgPath: str('staff_img_path'),
      numberedImgPath: str('numbered_img_path'),
      staffPngPath: str('staff_png_path'),
      numberedPngPath: str('numbered_png_path'),
      audioVersions: parseAudioVersions(str('audio_versions')),
      audioVersionList: parseVersionList(str('audio_version_list')),
      chorus: str('chorus').trim(),
      audioDurations: parseAudioDurations(str('audio_durations')),
      downloadStatus: str('download_status'),
      integrityStatus: str('integrity_status'),
    );
  }

  /// 解析 audio_version_list JSON 字符串 => List<String>（兼容旧字段名）
  static List<String> parseVersionList(String raw) =>
      parseAudioVersionList(raw);

  /// 解析 audio_durations JSON（`{"鋼琴版": 144.171, "人聲版": 167.163}`）
  static Map<String, double> parseAudioDurations(String raw) {
    if (raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded.map(
          (k, v) => MapEntry(k, (v as num?)?.toDouble() ?? 0),
        );
      }
    } catch (_) {}
    return const {};
  }
}

/// 一页歌词 = 一节正歌 + 副歌（副歌为空时仅正歌）
///
/// 数据库里 `verse_N` 存正歌各节、`chorus` 存副歌；实际演唱每节都要接副歌，
/// 故「节」才是歌词翻页的单位。`stanzaIndex` 为 0 基节号（显示时 +1）。
class LyricPage {
  const LyricPage(this.stanzaIndex, this.verse, this.chorus);

  /// 第几节（0 基）
  final int stanzaIndex;

  /// 正歌文本（可含 \n 分行）
  final String verse;

  /// 副歌文本（可含 \n 分行；无副歌为空串）
  final String chorus;

  bool get hasChorus => chorus.trim().isNotEmpty;

  /// 正歌行（去空行）
  List<String> get verseLines =>
      verse.split('\n').where((l) => l.trim().isNotEmpty).toList();

  /// 副歌行（去空行）
  List<String> get chorusLines => hasChorus
      ? chorus.split('\n').where((l) => l.trim().isNotEmpty).toList()
      : const [];

  /// 本页总行数（字号铺满算法用：正歌行 + 副歌行 + 副歌间隔留白）
  ///
  /// 2026-09-21：歌词页已删除「副歌」标题行，副歌仅以颜色区分；
  /// 此处仍按 1 行折算副歌前后的间隔留白（宁小不大，避免字号溢出）。
  int get lineCount =>
      verseLines.length + chorusLines.length + (hasChorus ? 1 : 0);

  /// 本页最长行的显示宽度（CJK 记 2、拉丁记 1；用于「不换行」的宽度约束）
  int get maxDisplayWidth {
    var w = 0;
    for (final l in [...verseLines, ...chorusLines]) {
      final lw = displayWidthOf(l);
      if (lw > w) w = lw;
    }
    return w;
  }

  /// 东亚显示宽度（汉字/全角标点 = 2 列，其余 = 1 列）
  static int displayWidthOf(String s) {
    var w = 0;
    for (final r in s.runes) {
      w += _cjkWidth(r) ? 2 : 1;
    }
    return w;
  }

  static bool _cjkWidth(int rune) =>
      (rune >= 0x1100 && rune <= 0x115F) ||
      rune == 0x2329 ||
      rune == 0x232A ||
      (rune >= 0x2E80 && rune <= 0xA4CF && rune != 0x303F) ||
      (rune >= 0xAC00 && rune <= 0xD7A3) ||
      (rune >= 0xF900 && rune <= 0xFAFF) ||
      (rune >= 0xFE30 && rune <= 0xFE6F) ||
      (rune >= 0xFF00 && rune <= 0xFF60) ||
      (rune >= 0xFFE0 && rune <= 0xFFE6);
}

/// 自动翻页的页码换算：把音频总时长按页数等分，进度落在第几段就是第几页
///
/// 用户口径示例：一首歌 4 分钟、共 4 节 → 第 1 分钟第 1 节，进度到第 2 分钟切第 2 节。
/// 返回 0 基页码；[totalSeconds] <= 0 或 [pageCount] <= 1 时恒返回 0（不翻页）。
int autoPageIndexFor({
  required Duration position,
  required double totalSeconds,
  required int pageCount,
}) {
  if (pageCount <= 1 || totalSeconds <= 0) return 0;
  final per = totalSeconds / pageCount;
  if (per <= 0) return 0;
  final idx = (position.inMilliseconds / 1000.0 / per).floor();
  return idx.clamp(0, pageCount - 1);
}

/// 歌词铺满算法的高度上限：`lineCount` 行 × 2.0 倍字号 ≤ 可用高
/// （行距 1.8 → 每行约占 2.0 倍字号）
double lyricMaxFontByHeight(double availH, int lineCount) =>
    lineCount > 0 ? availH / (lineCount * 2.0) : 40.0;

/// 歌词铺满算法的宽度上限（**保证每行不换行**）：
/// 一个汉字占位 ≈ 1 个字号宽，`displayWidth` 以「半角=1 / 全角=2」计，
/// 故字号 ≤ 可用宽 × 2 ÷ 最长行 displayWidth，再留 3% 余量防标点字距误差。
double lyricMaxFontByWidth(double availW, int maxDisplayWidth) {
  if (maxDisplayWidth <= 0) return 40.0;
  return availW * 2.0 / maxDisplayWidth * 0.97;
}
