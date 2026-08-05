/// 诗歌数据模型
class Hymn {
  final int id;
  final int number;
  final String title;
  final String author;
  final String composer;
  final String category;
  final String audio;
  final List<List<String>> lyrics; // 每段歌词

  const Hymn({
    required this.id,
    required this.number,
    required this.title,
    required this.author,
    required this.composer,
    required this.category,
    required this.audio,
    required this.lyrics,
  });

  String get nameWithNumber => '$number · $title';

  /// 播放器元信息
  String get meta =>
      '第 $number 首 · $category · 词：$author · 曲：$composer';

  factory Hymn.fromJson(Map<String, dynamic> json) {
    return Hymn(
      id: json['id'] as int,
      number: json['number'] as int,
      title: json['title'] as String? ?? '',
      author: json['author'] as String? ?? '',
      composer: json['composer'] as String? ?? '',
      category: json['category'] as String? ?? '',
      audio: json['audio'] as String? ?? '',
      lyrics: ((json['lyrics'] as List?) ?? const [])
          .map((stanza) =>
              ((stanza as List?) ?? const []).map((e) => e.toString()).toList())
          .toList(),
    );
  }

  /// 从 FFI（C++ 引擎）读取字段
  factory Hymn.fromNative({
    required int id,
    required int number,
    required String title,
    required String author,
    required String composer,
    required String category,
    required String audio,
    required List<List<String>> lyrics,
  }) {
    return Hymn(
      id: id,
      number: number,
      title: title,
      author: author,
      composer: composer,
      category: category,
      audio: audio,
      lyrics: lyrics,
    );
  }
}