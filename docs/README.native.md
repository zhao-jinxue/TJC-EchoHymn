# 🧪 C++ 原生引擎构建指南（hymn_engine）

> ⚠️ **现状说明（2026-08-21）**：当前 Flutter 侧**已不再通过 `dart:ffi` 调用** `hymn_engine.dll`。
> 简繁转换已改为**纯 Dart 查表**（`lib/data/chinese_convert_map.dart`），搜索/排序全部在 Dart 层完成。
> 本目录为**可选的历史组件**，保留源码与原生单元测试，如需恢复 FFI 调用可参考下文。

---

## 目录结构

```text
hymn_app/native/
├── CMakeLists.txt              # CMake 构建脚本
├── hymn_engine/
│   ├── hymn_engine.h           # C++ 引擎头文件（HymnEngine 类）
│   ├── hymn_engine.cpp         # 引擎实现（含轻量 JSON 解析器，无第三方依赖）
│   ├── hymn_engine_capi.h      # C ABI 头文件（供 dart:ffi 调用）
│   └── hymn_engine_capi.cpp    # C ABI 实现
└── test/
    └── test_main.cpp           # 原生单元测试
```

## 依赖

- **CMake** ≥ 3.14
- **C++17 编译器**：
  - Windows：Visual Studio Build Tools（MSVC）
  - Linux：gcc / clang
  - macOS：Xcode Command Line Tools

## 构建（Windows 示例）

```bash
# 在 hymn_app/native 目录执行
cd hymn_app/native

# 1) 配置
cmake -S . -B build

# 2) 构建动态库
cmake --build build --config Release

# 3) 构建并运行原生单元测试
cmake -S . -B build -DHYMN_ENGINE_BUILD_TESTS=ON
cmake --build build --config Release --target hymn_engine_test
./build/Release/hymn_engine_test.exe
```

构建产物：

| 平台 | 输出 |
| --- | --- |
| Windows | `build/Release/hymn_engine.dll` |
| Linux | `build/libhymn_engine.so` |
| macOS | `build/libhymn_engine.dylib` |

## 在 Flutter 中使用（如果恢复 FFI）

> 当前 Dart 侧**没有引用** `hymn_engine`（`search_files` 确认 `lib/` 下无 `hymn_engine` / `HymnEngine` / `nativeLib` 符号）。
> 若未来恢复，需按以下方式接入：

1. 在 `lib/services/` 下新增 FFI 绑定文件，用 `DynamicLibrary.open` 加载动态库
2. `HymnEngineNative.load()` 自动按平台查找动态库；找不到时抛出提示
3. 手动指定路径（推荐开发阶段）：

```dart
// 直接传入构建产物路径
final engine = HymnEngineNative.load('native/build/Release/hymn_engine.dll');
```

## 架构说明（历史设计）

```text
┌─────────────────────────────┐
│  Flutter / Dart（UI 层）      │
│  lib/main.dart               │
│  lib/screens/ (界面)          │
│  lib/widgets/ (组件)          │
├─────────────────────────────┤
│  lib/services/               │
│  SqliteRepository            │  ← 直接查 SQLite，不经过原生引擎
│  AudioService (audioplayers) │
├─────────────────────────────┤
│  native/ (C++ 引擎，可选)     │
│  hymn_engine_capi.h/cpp      │  ← C ABI 接口
│  hymn_engine.h/cpp           │  ← 核心逻辑
└─────────────────────────────┘
```

## 扩展指引（恢复时）

新增 C++ 能力时：

1. 在 `hymn_engine.h` / `.cpp` 中添加实现；
2. 在 `hymn_engine_capi.h` / `.cpp` 中导出 C ABI 函数；
3. 在 Dart 侧声明 `lookupFunction` 签名；
4. 在服务中调用。

> ⚠️ 修改 C ABI 签名后，Dart 侧必须同步更新，否则会导致运行时 `ArgumentError`。

## 当前替代方案（纯 Dart）

| 原 C++ 能力 | 当前实现 |
| --- | --- |
| JSON 解析 | Dart `jsonDecode`（`sqlite_repository.dart`） |
| 简繁转换 | 纯 Dart 查表（`chinese_convert_map.dart`，繁→简 1052 / 简→繁 1025） |
| 搜索排序 | Dart `where` / 前缀匹配（`hymn_list_panel.dart` 搜索定位） |

> 纯 Dart 方案无原生依赖、不阻塞 UI、跨平台稳定，是当前首选。
