import 'package:flutter/services.dart' show rootBundle;

import '../models/hymn.dart';
import 'engine_adapter.dart';

/// 数据加载策略
enum DataSource {
  /// 使用 C++ 引擎（FFI）加载与搜索（原生平台）
  cppEngine,

  /// 使用 Flutter Dart 内置 JSON 解析（web 等无 FFI 平台）
  assetJson,
}

/// 诗歌仓库：统一封装数据加载、搜索
/// 通过条件导入的 [EngineAdapter] 决定底层引擎：
///   - 原生平台 → C++ 引擎（FFI）
///   - web/无 FFI → 纯 Dart JSON 解析
class HymnRepository {
  final EngineAdapter _adapter;

  HymnRepository._(this._adapter);

  /// 创建仓库
  static Future<HymnRepository> create() async {
    final adapter = createEngineAdapter();
    final repo = HymnRepository._(adapter);

    // 加载 asset 中的 JSON（解析由各平台适配器完成）
    final jsonStr = await rootBundle.loadString('assets/data/hymns.json');
    final ok = adapter.loadFromJson(jsonStr);
    if (!ok) {
      throw StateError('数据加载失败: ${adapter.error ?? '未知错误'}');
    }
    return repo;
  }

  /// 当前是否正在使用 C++ 引擎
  bool get usingCppEngine => _adapter.isNativeEngine;

  /// 全部诗歌（按编号排序）
  List<Hymn> get hymns {
    final sorted = [..._adapter.hymns]
      ..sort((a, b) => a.number.compareTo(b.number));
    return sorted;
  }

  /// 搜索：编号 / 标题 / 作者 / 分类
  List<Hymn> search(String keyword) => _adapter.search(keyword);

  Hymn? byId(int id) => _adapter.byId(id);

  void dispose() => _adapter.dispose();
}
