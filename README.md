# 🎵 EchoHymn · 赞美诗与颂歌

一个简洁优雅的经典赞美诗聆听应用，基于 **Flutter** 构建，支持诗歌列表浏览、歌词展示、简谱/五线谱与音频播放。

> **目标平台**：Windows（桌面优先，已开发）· Android（目录已就绪）· OpenHarmony 鸿蒙（目录占位）
> ~~Web~~ 已移除（2026-08-16），不参与目标平台。

---

## 📁 项目结构

```text
EchoHymn/
├── hymn_app/                  # 🚀 Flutter 应用（主推）
│   ├── lib/
│   │   ├── main.dart          # 入口
│   │   ├── app.dart           # 应用根组件
│   │   ├── screens/           # 界面（主屏）
│   │   ├── widgets/           # 组件（歌词 / 播放器 / 歌单弹窗）
│   │   ├── models/            # 数据模型（Hymn / Category / Playlist）
│   │   ├── services/          # 服务层（SQLite / 音频 / 繁转简 / 状态持久化）
│   │   └── native/            # Dart FFI 绑定
│   ├── android/               # 🤖 Android 平台目录
│   ├── windows/               # 🪟 Windows 平台目录
│   ├── ohos/                  # 📁 鸿蒙平台目录（占位，待开发）
│   ├── native/                # C++ 原生引擎（FFI）
│   ├── assets/data/hymns.json # 诗歌数据
│   ├── assets/                # 应用静态资源
│   ├── test/                  # Flutter 单元测试
│   └── pubspec.yaml
│
├── data/
│   └── tjc_hymn.db            # 赞美诗 SQLite 数据库（474 首）
│
├── docs/
│   ├── SESSION_SUMMARY.md     # 📋 开发会话总结（新会话必读）
│   ├── UI_CONFIRMATION.md     # 🎨 UI 设计定稿确认单
│   ├── DEPLOY.md              # 📦 打包与迁移部署指南
│   ├── INSTALL_CMAKE.md       # CMake 安装指南
│   ├── INSTALL_VISUAL_STUDIO.md # VS 安装指南
│   ├── RECOMMENDED_TOOLS.md   # 🛠 MCP 服务器 & VS Code 插件推荐
│   └── README.native.md       # C++ 引擎构建指南
│
├── tools/                     # 开发工具脚本
│   ├── inspect_db.py          # 数据库探查
│   ├── search_pub.py          # 依赖/补丁脚本
│   ├── patch_*.py             # 构建补丁脚本
│   └── update_doc.py
│
└── README.md
```

---

## 🚀 运行方式（Windows 桌面）

前置：安装 [Flutter SDK](https://flutter.dev)、CMake、C++ 编译器（VS Build Tools，见 `docs/INSTALL_VISUAL_STUDIO.md`）。

```bash
cd hymn_app
flutter pub get
flutter run -d windows        # 开发运行
```

构建发布版：

```bash
flutter build windows --release
# 产物: build\windows\x64\runner\Release\echo_hymn.exe
```

> 运行需 `data\` 在 exe 的上级目录链中（`AppPaths.resolveAsset` 向上查找 12 层）。

Android（后续开发）：

```bash
cd hymn_app
flutter build apk --release
# 产物: build\app\outputs\flutter-apk\app-release.apk
```

---

## ✨ 功能

- 📜 **诗歌列表**：按编号分页展示 474 首诗歌，支持搜索（编号 / 标题 / 作者 / 作曲）
- 🎼 **歌词显示**：歌词 / 简谱 / 五线谱三种模式切换（谱图来自数据库字段）
- ▶️ **音频播放**：播放 / 暂停、上一首 / 下一首、进度拖动，支持钢琴版 / 人声版多版本
- 🎵 **默认歌单**：按数据库分类目录（一级 → 二级）浏览诗歌
- 💾 **个人歌单**：创建 / 修改 / 删除歌单，添加诗歌并可播放歌单内诗歌
- 🔄 **繁→简转换**：标题 / 歌词 / 分类 / 源考经纯 Dart 字符映射表转为简体显示（无原生依赖）
- 💡 **状态持久化**：记住上次歌单 / 诗歌 / 音频版本 / 歌词模式，切换即保存（`exe` 同级 `state.json`）
- 📝 **应用日志**：`exe` 同级 `logs/` 目录按天输出日志（库加载 / UI / 交互 / 歌单 / 播放 / 异常），保留最近 7 份日志文件

---

## 🔧 技术栈

| 层 | 技术 |
| --- | --- |
| UI | Flutter / Dart（Material） |
| 音频 | audioplayers 6.x（Windows 走 Media Foundation，`DeviceFileSource` 直读中文路径） |
| 数据 | SQLite（`sqlite3` + `sqlite3_flutter_libs`，数据库 `data/tjc_hymn.db`） |
| 繁转简 | 纯 Dart 字符映射表（`lib/data/chinese_convert_map.dart`，由数据库全量字符生成） |
| 持久化 | 原生 `exe` 同级 `state.json`（原子写，无第三方依赖） |
| 日志 | 自研 `LogService`（`exe` 同级 `logs/`，按天轮转、保留 7 份、UTF-8 BOM） |

---

## 📦 打包与迁移

详见 **[docs/DEPLOY.md](docs/DEPLOY.md)**。速览：

| 目标平台 | 前置条件 | 产物 |
| --- | --- | --- |
| **Windows 桌面** | VS + 开发者模式 + CMake | `hymn_app/build/windows/x64/runner/Release/` 整体拷贝 |
| **Android** | Android Studio + SDK | `build/app/outputs/flutter-apk/app-release.apk` |
| **OpenHarmony 鸿蒙** | 待接入（目录占位） | — |

> **自动发布**：每次 `git commit` 到 master/main 会自动构建 **Windows 桌面版**并发布到 `release/echohymn-win-<短哈希>-<时间戳>/`（保留最近 5 份）。日志见 `release/auto-release.log`。
> 手动发布：`pwsh -NoProfile -ExecutionPolicy Bypass -File tools\publish_windows.ps1`

---

## 🛠 开发工具

推荐 MCP 服务器与 VS Code 插件配置详见 **[docs/RECOMMENDED_TOOLS.md](docs/RECOMMENDED_TOOLS.md)**，C++ 引擎构建详见 **[docs/README.native.md](docs/README.native.md)**。

---

## ⚠️ 说明

- 音频文件位于 `data/Hymn_Downloads/`，数据库按平台相对路径引用。
- Web 平台已从目标中移除（`sqlite3` 的 `dart:ffi` 在 Web 不可用）。
