import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

/// C ABI 函数签名（对应 native/hymn_engine/hymn_engine_capi.h）
typedef _CreateNative = Pointer<Void> Function();
typedef _CreateDart = Pointer<Void> Function();

typedef _DestroyNative = Void Function(Pointer<Void>);
typedef _DestroyDart = void Function(Pointer<Void>);

typedef _LoadJsonNative = Int32 Function(Pointer<Void>, Pointer<Utf8>);
typedef _LoadJsonDart = int Function(Pointer<Void>, Pointer<Utf8>);

typedef _LoadFileNative = Int32 Function(Pointer<Void>, Pointer<Utf8>);
typedef _LoadFileDart = int Function(Pointer<Void>, Pointer<Utf8>);

typedef _CountNative = Int32 Function(Pointer<Void>);
typedef _CountDart = int Function(Pointer<Void>);

typedef _SearchNative = Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>);
typedef _SearchDart = Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>);

typedef _GetFieldNative = Pointer<Utf8> Function(Pointer<Void>, Int32, Pointer<Utf8>);
typedef _GetFieldDart = Pointer<Utf8> Function(Pointer<Void>, int, Pointer<Utf8>);

typedef _StanzaCountNative = Int32 Function(Pointer<Void>, Int32);
typedef _StanzaCountDart = int Function(Pointer<Void>, int);

typedef _LineCountNative = Int32 Function(Pointer<Void>, Int32, Int32);
typedef _LineCountDart = int Function(Pointer<Void>, int, int);

typedef _LyricsLineNative = Pointer<Utf8> Function(Pointer<Void>, Int32, Int32, Int32);
typedef _LyricsLineDart = Pointer<Utf8> Function(Pointer<Void>, int, int, int);

/// HymnEngine 的 Dart FFI 封装
class HymnEngineNative {
  late final DynamicLibrary _lib;

  late final _CreateDart _create;
  late final _DestroyDart _destroy;
  late final _LoadJsonDart _loadJson;
  late final _LoadFileDart _loadFile;
  late final _CountDart _count;
  late final _SearchDart _search;
  late final _GetFieldDart _getField;
  late final _StanzaCountDart _stanzaCount;
  late final _LineCountDart _lineCount;
  late final _LyricsLineDart _lyricsLine;

  Pointer<Void>? _handle;

  HymnEngineNative._(this._lib) {
    _create = _lib.lookupFunction<_CreateNative, _CreateDart>('hymn_engine_create');
    _destroy = _lib.lookupFunction<_DestroyNative, _DestroyDart>('hymn_engine_destroy');
    _loadJson = _lib.lookupFunction<_LoadJsonNative, _LoadJsonDart>('hymn_engine_load_from_json');
    _loadFile = _lib.lookupFunction<_LoadFileNative, _LoadFileDart>('hymn_engine_load_from_file');
    _count = _lib.lookupFunction<_CountNative, _CountDart>('hymn_engine_count');
    _search = _lib.lookupFunction<_SearchNative, _SearchDart>('hymn_engine_search');
    _getField = _lib.lookupFunction<_GetFieldNative, _GetFieldDart>('hymn_engine_get_field');
    _stanzaCount = _lib.lookupFunction<_StanzaCountNative, _StanzaCountDart>('hymn_engine_lyrics_stanza_count');
    _lineCount = _lib.lookupFunction<_LineCountNative, _LineCountDart>('hymn_engine_lyrics_line_count');
    _lyricsLine = _lib.lookupFunction<_LyricsLineNative, _LyricsLineDart>('hymn_engine_lyrics_line');

    _handle = _create();
  }

  /// 加载动态库。
  /// 优先使用 [overridePath]；否则按平台在标准位置查找。
  factory HymnEngineNative.load({String? overridePath}) {
    if (overridePath != null) {
      return HymnEngineNative._(DynamicLibrary.open(overridePath));
    }

    final String libName;
    if (Platform.isWindows) {
      libName = 'hymn_engine.dll';
    } else if (Platform.isMacOS) {
      libName = 'libhymn_engine.dylib';
    } else {
      libName = 'libhymn_engine.so';
    }

    // 1) 当前目录
    try {
      return HymnEngineNative._(DynamicLibrary.open(libName));
    } on ArgumentError {
      // 2) 常见构建输出目录
      final candidates = <String>[
        '../native/build/hymn_engine.dll',
        '../native/build/Debug/hymn_engine.dll',
        '../native/build/Release/hymn_engine.dll',
        'native/build/$libName',
      ];
      for (final c in candidates) {
        try {
          return HymnEngineNative._(DynamicLibrary.open(c));
        } on ArgumentError {
          continue;
        }
      }
    }
    throw StateError('无法加载 hymn_engine 原生库，请先构建 native/ 目录（见 README.native.md）');
  }

  /// 从 JSON 字符串加载数据
  bool loadFromJson(String json) {
    final jsonPtr = json.toNativeUtf8();
    try {
      return _loadJson(_handle!, jsonPtr) != 0;
    } finally {
      malloc.free(jsonPtr);
    }
  }

  /// 从文件加载数据
  bool loadFromFile(String path) {
    final pathPtr = path.toNativeUtf8();
    try {
      return _loadFile(_handle!, pathPtr) != 0;
    } finally {
      malloc.free(pathPtr);
    }
  }

  int get count => _count(_handle!);

  /// 搜索，返回排序后的 id 列表
  List<int> search(String keyword) {
    final kwPtr = keyword.toNativeUtf8();
    try {
      final resultPtr = _search(_handle!, kwPtr);
      if (resultPtr == nullptr) return const [];
      try {
        final ids = resultPtr.toDartString();
        if (ids.isEmpty) return const [];
        return ids
            .split(',')
            .map((e) => int.tryParse(e.trim()))
            .whereType<int>()
            .toList();
      } finally {
        malloc.free(resultPtr);
      }
    } finally {
      malloc.free(kwPtr);
    }
  }

  /// 获取字符串字段；字段不存在返回 null
  String? getField(int id, String field) {
    final fieldPtr = field.toNativeUtf8();
    try {
      final resultPtr = _getField(_handle!, id, fieldPtr);
      if (resultPtr == nullptr) return null;
      try {
        return resultPtr.toDartString();
      } finally {
        malloc.free(resultPtr);
      }
    } finally {
      malloc.free(fieldPtr);
    }
  }

  int getNumber(int id) => int.tryParse(getField(id, 'number') ?? '') ?? 0;

  String? getTitle(int id) => getField(id, 'title');
  String? getAuthor(int id) => getField(id, 'author');
  String? getComposer(int id) => getField(id, 'composer');
  String? getCategory(int id) => getField(id, 'category');
  String? getAudio(int id) => getField(id, 'audio');

  /// 歌词段数（不存在返回 -1）
  int stanzaCount(int id) => _stanzaCount(_handle!, id);

  int lineCount(int id, int stanza) => _lineCount(_handle!, id, stanza);

  String? lyricsLine(int id, int stanza, int line) {
    final resultPtr = _lyricsLine(_handle!, id, stanza, line);
    if (resultPtr == nullptr) return null;
    try {
      return resultPtr.toDartString();
    } finally {
      malloc.free(resultPtr);
    }
  }

  /// 读取完整歌词 [[段 -> [行]]]
  List<List<String>> lyrics(int id) {
    final stanzas = <List<String>>[];
    final nStanzas = stanzaCount(id);
    if (nStanzas <= 0) return stanzas;
    for (var s = 0; s < nStanzas; s++) {
      final lines = <String>[];
      final nLines = lineCount(id, s);
      for (var l = 0; l < nLines; l++) {
        final line = lyricsLine(id, s, l);
        if (line != null) lines.add(line);
      }
      stanzas.add(lines);
    }
    return stanzas;
  }

  void dispose() {
    if (_handle != null) {
      _destroy(_handle!);
      _handle = null;
    }
  }
}