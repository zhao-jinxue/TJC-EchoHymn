# 📚 EchoHymn 文档总纲（docs 主索引）

> 本文件是 `docs/` 目录的**唯一主文档（总纲 + 索引）**，按平台归档全部开发文档。
> 整理定稿：2026-09-13。规则：**Windows 开发归纳到 `Windows/`，Android 归纳到 `Android/`，
> 鸿蒙归纳到 `OpenHarmony/`，苹果归纳到 `iOS/`；跨平台通用知识在 `knowledge/`；会话档案在 `sessions/`（独立流程，不参与归档整理）**。

---

## 一、目录结构

```text
docs/
├── README.md                # 📍 本文件：文档总纲（目录索引 + 平台导航 + 附录：C++ 原生引擎）
├── Windows/                 # ✅ Windows 平台开发全套文档（主战场，v1.0~v1.5.2）
├── Android/                 # 🚧 Android 移植文档（2026-09-11 立项，阶段 0 已完成；含开发总结）
├── OpenHarmony/             # 📦 OpenHarmony 鸿蒙（占位，为后续开发做准备）
├── iOS/                     # 📦 苹果平台 iOS/macOS（占位，为后续开发做准备）
├── knowledge/               # 🛠 跨平台通用知识（与具体平台无关）
└── sessions/                # 🗂 逐会话开发档案（.clinerules 强制流程，目录独立）
```

## 二、各平台文档导航

### Windows（`Windows/`）

| 文档 | 用途 |
| --- | --- |
| [SESSION_SUMMARY.md](Windows/SESSION_SUMMARY.md) | 📋 **Windows 主线 + 跨平台工程史**开发总结（新会话续接**必读**）：完整里程碑、技术栈、逐会话决策、遗留任务（Android 侧记录见 `docs/Android/SESSION_SUMMARY.md`） |
| [UI_CONFIRMATION.md](Windows/UI_CONFIRMATION.md) | ✅ UI 还原确认单（最终定稿 v1.5.0），验收基准 |
| [UI_DESIGN_TEMPLATE.md](Windows/UI_DESIGN_TEMPLATE.md) | 🎨 UI 设计规范（组件/交互/主题/间距），迭代与人工验收基准 |
| [theme_preview.html](Windows/theme_preview.html) | 🎨 五套配色交互式效果图预览（与实机像素一致） |
| [DEPLOY.md](Windows/DEPLOY.md) | 🚚 绿色目录打包与跨机迁移（Windows） |
| [INSTALLER.md](Windows/INSTALLER.md) | 📦 安装/卸载指南（用户三步向导 + 发布者构建双产物安装包） |
| [RELEASE_RULES.md](Windows/RELEASE_RULES.md) | 📐 安装包发布规范 18 条 + 发布前验证基线 |
| [BUGFIX_REPORT_2026-09-05.md](Windows/BUGFIX_REPORT_2026-09-05.md) | 🩺 全局诊断修复报告（P0 零发现 / P1×1 / P2×4，回滚检查点 tag） |
| [INSTALL_VISUAL_STUDIO.md](Windows/INSTALL_VISUAL_STUDIO.md) | 🛠 VS 2022「C++ 桌面开发」安装步骤（Windows 构建前置） |
| [INSTALL_CMAKE.md](Windows/INSTALL_CMAKE.md) | 🛠 CMake 安装步骤（Windows 构建前置） |
| [RECOMMENDED_TOOLS.md](Windows/RECOMMENDED_TOOLS.md) | 🛠 推荐开发工具清单 |

### Android（`Android/`）

| 文档 | 用途 |
| --- | --- |
| [SESSION_SUMMARY.md](Android/SESSION_SUMMARY.md) | 📋 **Android 开发总结**（续接必读）：里程碑、阶段 0 环境操作留档、Windows 主线已做的 Android 铺垫、进度与待办 |
| [ANDROID_PLAN.md](Android/ANDROID_PLAN.md) | 🚧 Android 移植计划（2026-09-11 立项）：环境现状、阶段 0~3 执行实况与踩坑记录、风险清单 |

### OpenHarmony 鸿蒙（`OpenHarmony/`，占位）

| 文档 | 用途 |
| --- | --- |
| [README.md](OpenHarmony/README.md) | 📦 占位说明：接入前提（OpenHarmony Flutter SDK、插件支持校验） |

### 苹果平台（`iOS/`，占位）

| 文档 | 用途 |
| --- | --- |
| [README.md](iOS/README.md) | 📦 占位说明：iOS/macOS 接入前提与已知适配点 |

### 跨平台知识（`knowledge/`）

| 文档 | 用途 |
| --- | --- |
| [CLINE_CONTEXT_MINIMIZE.md](knowledge/CLINE_CONTEXT_MINIMIZE.md) | 🛠 Cline 新会话上下文最小化策略（规则分层、按需读取、会话日志机制） |

### 会话档案（`sessions/`，独立流程）

逐会话的提问 / 解决思路 / 最终结果留档，由 `.clinerules`「会话日志强制流程」驱动写入，
规范见 [sessions/README.md](sessions/README.md)，模板见 [sessions/_template.md](sessions/_template.md)。
**本目录不属于平台归档范围，保持平铺。**

---

## 三、新会话续接入口

1. 读 [Windows/SESSION_SUMMARY.md](Windows/SESSION_SUMMARY.md)（开发总结）——按需全文或关键章节
2. 读 [Windows/UI_CONFIRMATION.md](Windows/UI_CONFIRMATION.md) 的「最终设计定稿」章节
3. `git log --oneline -15` 查看提交历史

> **续接 Android 开发**时改读 [Android/SESSION_SUMMARY.md](Android/SESSION_SUMMARY.md) + [Android/ANDROID_PLAN.md](Android/ANDROID_PLAN.md)。

---

## 附录：C++ 原生引擎构建指南（hymn_engine）

> 本附录即原 `docs/README.native.md`（2026-09-13 并入本文档并更名）。

> ⚠️ **现状说明（2026-08-21）**：当前 Flutter 侧**已不再通过 `dart:ffi` 调用** `hymn_engine.dll`。
> 简繁转换已改为**纯 Dart 查表**（`lib/data/chinese_convert_map.dart`），搜索/排序全部在 Dart 层完成。
> `hymn_app/native/` 为**可选的历史组件**，保留源码与原生单元测试，如需恢复 FFI 调用可参考下文。

### 目录结构

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

### 依赖

- **CMake** ≥ 3.14
- **C++17 编译器**：
  - Windows：Visual Studio Build Tools（MSVC）
  - Linux：gcc / clang
  - macOS：Xcode Command Line Tools

### 构建（Windows 示例）

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

### 在 Flutter 中使用（如果恢复 FFI）

> 当前 Dart 侧**没有引用** `hymn_engine`（`lib/` 下无 `hymn_engine` / `HymnEngine` / `nativeLib` 符号）。
> 若未来恢复，需按以下方式接入：

1. 在 `lib/services/` 下新增 FFI 绑定文件，用 `DynamicLibrary.open` 加载动态库
2. `HymnEngineNative.load()` 自动按平台查找动态库；找不到时抛出提示
3. 手动指定路径（推荐开发阶段）：

```dart
// 直接传入构建产物路径
final engine = HymnEngineNative.load('native/build/Release/hymn_engine.dll');
```

### 架构说明（历史设计）

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

### 扩展指引（恢复时）

新增 C++ 能力时：

1. 在 `hymn_engine.h` / `.cpp` 中添加实现；
2. 在 `hymn_engine_capi.h` / `.cpp` 中导出 C ABI 函数；
3. 在 Dart 侧声明 `lookupFunction` 签名；
4. 在服务中调用。

> ⚠️ 修改 C ABI 签名后，Dart 侧必须同步更新，否则会导致运行时 `ArgumentError`。

### 当前替代方案（纯 Dart）

| 原 C++ 能力 | 当前实现 |
| --- | --- |
| JSON 解析 | Dart `jsonDecode`（`sqlite_repository.dart`） |
| 简繁转换 | 纯 Dart 查表（`chinese_convert_map.dart`，繁→简 1052 / 简→繁 1025） |
| 搜索排序 | Dart `where` / 前缀匹配（`hymn_list_panel.dart` 搜索定位） |

> 纯 Dart 方案无原生依赖、不阻塞 UI、跨平台稳定，是当前首选。
