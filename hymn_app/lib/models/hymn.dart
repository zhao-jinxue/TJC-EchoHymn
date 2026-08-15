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
      audioVersionList: parseAudioVersionList(str('audio_version_list')),
      downloadStatus: str('download_status'),
      integrityStatus: str('integrity_status'),
    );
  }
}
