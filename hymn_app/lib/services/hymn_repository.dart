import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../models/hymn.dart';
import '../native/hymn_engine_bindings.dart';

/// 数据加载策略
enum DataSource {
  /// 使用 C++ 引擎（FFI）加载与搜索
  cppEngine,

  /// 使用 Flutter Dart 内置 JSON 解析（C++ 库未构建时的回退）
  assetJson,
}

/// 诗歌仓库：统一封装数据加载、搜索
class HymnRepository {
  final HymnEngineNative? _native;
  final DataSource source;

  List<Hymn> _hymns = const [];
  bool _loaded = false;
  String? _lastError;

  HymnRepository._(this._native, this.source);

  /// 创建仓库：优先 C++ 引擎，失败则回退到 Dart JSON
  static Future<HymnRepository> create({
    DataSource preferredSource = DataSource.cppEngine,
    String? nativeLibPath,
  }) async {
    HymnEngineNative? native;
    if (preferredSource == DataSource.cppEngine) {
      try {
        native = HymnEngineNative.load(overridePath: nativeLibPath);
      } catch (e) {
        native = null;
      }
    }
    final repo = HymnRepository._(
      native,
      native != null ? DataSource.cppEngine : DataSource.assetJson,
    );
    await repo._load(native);
    return repo;
  }

  bool get usingCppEngine => _native != null;
  String? get lastError => _lastError;

  Future<void> _load(HymnEngineNative? native) async {
    try {
      if (native != null) {
        // 方式一：C++ 引擎直接从 JSON 字符串加载（数据仍来自 Flutter asset，
        // 但解析/搜索由 C++ 完成，便于后续扩展为文件缓存等）
        final jsonStr = await rootBundle.loadString('assets/data/hymns.json');
        final ok = native.loadFromJson(jsonStr);
        if (ok) {
          _hymns = _loadAllFromNative(native);
          _loaded = true;
          return;
        }
        throw StateError('C++ 引擎解析 JSON 失败');
      }

      // 方式二：纯 Dart 解析
      final jsonStr = await rootBundle.loadString('assets/data/hymns.json');
      final list = (jsonDecode(jsonStr) as List)
          .map((e) => Hymn.fromJson(e as Map<String, dynamic>))
          .toList();
      _hymns = list;
      _loaded = true;
    } catch (e) {
      _lastError = e.toString();
      rethrow;
    }
  }

  List<Hymn> _loadAllFromNative(HymnEngineNative native) {
    final n = native.count;
    final result = <Hymn>[];
    for (var i = 1; i <= n; i++) {
      final id = i;
      final h = _hymnFromNative(native, id);
      if (h != null) result.add(h);
    }
    return result;
  }

  Hymn? _hymnFromNative(HymnEngineNative native, int id) {
    final title = native.getTitle(id);
    if (title == null) return null;
    return Hymn.fromNative(
      id: id,
      number: native.getNumber(id),
      title: title,
      author: native.getAuthor(id) ?? '',
      composer: native.getComposer(id) ?? '',
      category: native.getCategory(id) ?? '',
      audio: native.getAudio(id) ?? '',
      lyrics: native.lyrics(id),
    );
  }

  /// 全部诗歌（按编号排序）
  List<Hymn> get hymns {
    final sorted = [..._hymns]..sort((a, b) => a.number.compareTo(b.number));
    return sorted;
  }

  /// 搜索：编号 / 标题 / 作者 / 分类
  List<Hymn> search(String keyword) {
    final kw = keyword.trim().toLowerCase();
    if (kw.isEmpty) return hymns;
    if (source == DataSource.cppEngine && _native != null) {
      final ids = _native.search(kw);
      return ids
          .map((id) => _hymns.where((h) => h.id == id).firstOrNull)
          .whereType<Hymn>()
          .toList();
    }
    return hymns.where((h) {
      return h.number.toString().contains(kw) ||
          h.title.toLowerCase().contains(kw) ||
          h.author.toLowerCase().contains(kw) ||
          h.category.toLowerCase().contains(kw);
    }).toList();
  }

  Hymn? byId(int id) {
    for (final h in _hymns) {
      if (h.id == id) return h;
    }
    return null;
  }

  void dispose() {
    _native?.dispose();
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final it = iterator;
    return it.moveNext() ? it.current : null;
  }
}