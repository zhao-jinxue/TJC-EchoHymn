import 'dart:convert' as convert;

import 'package:flutter/services.dart' show rootBundle;

import '../models/hymn.dart';

/// 引擎适配器抽象基类（stub：纯 Dart JSON 解析，用于 web 等无 FFI 平台）
class EngineAdapter {
  List<Hymn> hymns = const [];
  String? error;

  /// 当前是否为 C++ 原生引擎（stub 恒为 false）
  bool get isNativeEngine => false;

  /// 加载诗歌数据（从 Flutter asset）
  Future<bool> loadFromAsset() async {
    try {
      final jsonStr = await rootBundle.loadString('assets/data/hymns.json');
      return loadFromJson(jsonStr);
    } catch (e) {
      error = e.toString();
      return false;
    }
  }

  /// 纯 Dart 适配器（web）不支持本地文件
  Future<bool> loadFromFile(String path) async {
    error = '此平台不支持从本地文件加载';
    return false;
  }

  bool loadFromJson(String json) {
    try {
      final decoded = convert.jsonDecode(json);
      final list = decoded is List ? decoded : const <dynamic>[];
      hymns =
          list.map((e) => Hymn.fromJson(e as Map<String, dynamic>)).toList();
      return true;
    } catch (e) {
      error = e.toString();
      return false;
    }
  }

  /// 搜索：标题 / 编号 / 作者 / 分类
  List<Hymn> search(String keyword) {
    final kw = keyword.trim().toLowerCase();
    if (kw.isEmpty) return hymns;
    return hymns.where((h) {
      return h.number.toString().contains(kw) ||
          h.title.toLowerCase().contains(kw) ||
          h.author.toLowerCase().contains(kw) ||
          h.category.toLowerCase().contains(kw);
    }).toList();
  }

  /// 按 id 查找
  Hymn? byId(int id) {
    for (final h in hymns) {
      if (h.id == id) return h;
    }
    return null;
  }

  /// 释放资源（stub 无需操作）
  void dispose() {}
}

/// 工厂：返回纯 Dart 适配器（stub 平台）
EngineAdapter createEngineAdapter() => EngineAdapter();

/// 当前是否为 C++ 原生引擎（stub 恒为 false）
bool get isNativeEngine => false;
