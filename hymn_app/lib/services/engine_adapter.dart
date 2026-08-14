import 'engine_adapter_stub.dart';
import 'engine_adapter_stub.dart'
    if (dart.library.ffi) 'engine_adapter_native.dart' as impl;

export 'engine_adapter_stub.dart' show EngineAdapter;

/// 返回当前平台可用的适配器实例
///  - 原生平台（FFI 可用）→ C++ 引擎适配器
///  - web 等（无 FFI）   → 纯 Dart JSON 解析适配器
EngineAdapter createEngineAdapter() => impl.createEngineAdapter();

/// 供调试/UI 判断当前引擎类型
bool get isNativeEngine => impl.isNativeEngine;
