import '../models/hymn.dart';
import '../native/hymn_engine_bindings.dart';
import 'engine_adapter_stub.dart' as stub;

/// C++ 引擎适配器（原生平台 FFI）；继承自 [stub.EngineAdapter]
class NativeEngineAdapter extends stub.EngineAdapter {
  HymnEngineNative? _native;

  @override
  bool get isNativeEngine => true;

  /// 从本地文件加载（C++ 引擎直接读文件）
  @override
  Future<bool> loadFromFile(String path) async {
    try {
      final native = HymnEngineNative.load();
      _native = native;
      final ok = native.loadFromFile(path);
      if (ok) {
        hymns = _allFromNative(native);
        return true;
      }
      error = 'C++ 引擎加载文件失败';
      return false;
    } catch (e) {
      error = e.toString();
      return false;
    }
  }

  @override
  bool loadFromJson(String json) {
    try {
      final native = HymnEngineNative.load();
      _native = native;
      final ok = native.loadFromJson(json);
      if (!ok) {
        error = 'C++ 引擎解析 JSON 失败';
        return false;
      }
      hymns = _allFromNative(native);
      return true;
    } catch (e) {
      error = e.toString();
      return false;
    }
  }

  List<Hymn> _allFromNative(HymnEngineNative native) {
    final result = <Hymn>[];
    for (var id = 1; id <= native.count; id++) {
      final title = native.getTitle(id);
      if (title == null) continue;
      result.add(Hymn.fromNative(
        id: id,
        number: native.getNumber(id),
        title: title,
        author: native.getAuthor(id) ?? '',
        composer: native.getComposer(id) ?? '',
        category: native.getCategory(id) ?? '',
        audio: native.getAudio(id) ?? '',
        lyrics: native.lyrics(id),
      ));
    }
    return result;
  }

  /// 搜索：优先 C++ 引擎，失败回退 Dart 过滤
  @override
  List<Hymn> search(String keyword) {
    final kw = keyword.trim().toLowerCase();
    if (kw.isEmpty) return hymns;

    final native = _native;
    if (native != null) {
      try {
        final ids = native.search(kw);
        return ids
            .map((id) => hymns.where((h) => h.id == id).firstOrNull)
            .whereType<Hymn>()
            .toList();
      } catch (_) {
        // 回退到 Dart 过滤
      }
    }

    return hymns.where((h) {
      return h.number.toString().contains(kw) ||
          h.title.toLowerCase().contains(kw) ||
          h.author.toLowerCase().contains(kw) ||
          h.category.toLowerCase().contains(kw);
    }).toList();
  }

  @override
  Hymn? byId(int id) {
    for (final h in hymns) {
      if (h.id == id) return h;
    }
    return null;
  }

  @override
  void dispose() {
    _native?.dispose();
    _native = null;
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final it = iterator;
    return it.moveNext() ? it.current : null;
  }
}

/// 工厂：返回 C++ 引擎适配器（native 平台）
stub.EngineAdapter createEngineAdapter() => NativeEngineAdapter();

/// 是否原生引擎（native 恒为 true）
bool get isNativeEngine => true;
