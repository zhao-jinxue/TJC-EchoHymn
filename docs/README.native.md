# 🧪 C++ 原生引擎构建指南（hymn_engine）

Flutter 侧通过 `dart:ffi` 调用 C++ 引擎。C++ 层负责 **JSON 解析、搜索排序** 等核心逻辑，与 UI 完全解耦。

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
# 在项目根目录（E:\EchoHymn）执行
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

## 在 Flutter 中使用

`HymnEngineNative.load()` 会自动按平台查找动态库。找不到时抛出提示。

### **方案 A：手动指定（推荐开发阶段）**

```dart
// 直接传入构建产物路径
final repo = await HymnRepository.create(
  nativeLibPath: 'native/build/Release/hymn_engine.dll',
);
```

### **方案 B：自动查找**

将 DLL 放在以下任一位置即可被自动发现：

- 当前工作目录
- `../native/build/` 下的 Debug / Release 目录

## 架构说明

```text
┌─────────────────────────────┐
│  Flutter / Dart（UI 层）      │
│  lib/main.dart               │
│  lib/screens/ (界面)          │
│  lib/widgets/ (组件)          │
├─────────────────────────────┤
│  lib/services/               │
│  HymnRepository  ←→  FFI    │
│  AudioService (just_audio)  │
├─────────────────────────────┤
│  lib/native/                 │
│  hymn_engine_bindings.dart   │  ← dart:ffi 绑定
├─────────────────────────────┤
│  native/ (C++ 引擎)          │
│  hymn_engine_capi.h/cpp      │  ← C ABI 接口
│  hymn_engine.h/cpp           │  ← 核心逻辑
└─────────────────────────────┘
```

## 扩展指引

新增 C++ 能力时：

1. 在 `hymn_engine.h` / `.cpp` 中添加实现；
2. 在 `hymn_engine_capi.h` / `.cpp` 中导出 C ABI 函数；
3. 在 `hymn_engine_bindings.dart` 中声明 `lookupFunction` 签名；
4. 在 `HymnRepository` 或新服务中调用。

> ⚠️ 修改 C ABI 签名后，Dart 侧必须同步更新，否则会导致运行时 `ArgumentError`。
