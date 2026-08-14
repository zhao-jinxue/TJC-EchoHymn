# 🎵 EchoHymn · 赞美诗与颂歌

一个简洁优雅的经典赞美诗聆听应用，支持诗歌列表浏览、歌词展示与音频播放。

> **架构升级**：现已支持 **Flutter + C++** 原生架构，原纯 HTML 版已迁移至 `html/` 目录。

---

## 📁 项目结构

```text
EchoHymn/
├── hymn_app/                  # 🚀 Flutter + C++ 应用（主推）
│   ├── lib/
│   │   ├── main.dart          # 入口
│   │   ├── app.dart           # 应用根组件
│   │   ├── screens/           # 界面（主屏）
│   │   ├── widgets/           # 组件（列表 / 播放器 / 歌词）
│   │   ├── models/            # 数据模型（Hymn）
│   │   ├── services/          # 服务层（仓库 / 音频）
│   │   └── native/            # Dart FFI 绑定
│   ├── native/                # C++ 原生引擎（核心逻辑）
│   │   ├── hymn_engine/       # 引擎实现 + C ABI
│   │   ├── test/              # C++ 单元测试
│   │   └── CMakeLists.txt
│   ├── assets/data/hymns.json # 诗歌数据
│   ├── test/                  # Flutter 单元测试
│   └── pubspec.yaml
│
├── html/                      # 💻 原纯 HTML/CSS/JS 版本（已迁移）
│   ├── index.html
│   ├── css/style.css
│   ├── js/app.js
│   └── data/hymns.js
│
├── docs/
│   ├── RECOMMENDED_TOOLS.md   # 🛠 MCP 服务器 & VS Code 插件推荐
│   ├── README.native.md       # C++ 引擎构建指南
│   └── DEPLOY.md              # 📦 打包与迁移部署指南
│
├── tools/
│   ├── 打包.bat               # 🚀 一键打包 Web 迁移包（双击运行）
│   └── package_web.ps1        # Web 迁移包打包脚本
│
└── README.md
```

---

## 🚀 运行方式

### 方式一：Flutter + C++（推荐）

前置：安装 [Flutter SDK](https://flutter.dev)、CMake、C++ 编译器（VS Build Tools）。

```bash
# 1) 构建 C++ 原生引擎
cd hymn_app/native
cmake -S . -B build
cmake --build build --config Release

# 2) 运行 Flutter 应用
cd ../..
cd hymn_app
flutter pub get
flutter run -d windows        # 或 -d chrome / -d android 等
```

> C++ 引擎加载失败时自动回退为纯 Dart JSON 解析，功能不受影响。

### 方式二：HTML 版（轻量）

直接使用浏览器打开 `html/index.html`，或本地静态服务器预览：

```bash
python -m http.server 8000
# 访问 http://localhost:8000
```

---

## ✨ 功能

- 📜 **诗歌列表**：侧边栏展示编号与标题，支持搜索（编号 / 标题 / 作者 / 分类）
- 🎼 **歌词显示**：选择诗歌后，分节展示歌词
- ▶️ **音频播放**：播放 / 暂停、上一首 / 下一首、进度拖动、音量调节
- 🧠 **C++ 引擎**：JSON 解析与搜索排序由 C++ 完成，通过 FFI 供 Flutter 调用
- 📱 **响应式布局**：桌面双栏 / 移动端抽屉

---

## 🔧 技术栈

| 层 | 技术 |
| --- | --- |
| UI | Flutter / Dart |
| 音频 | just_audio |
| 原生核心 | C++17（JSON 解析、搜索；无第三方依赖，自带轻量 JSON 解析器） |
| 原生桥接 | `dart:ffi` + C ABI |
| 构建 | CMake ≥ 3.14 |

---

## 📌 添加诗歌

编辑 `hymn_app/assets/data/hymns.json`（Flutter 版）或 `html/data/hymns.js`（HTML 版），按以下格式：

```json
{
  "id": 9,
  "number": 9,
  "title": "诗歌标题",
  "author": "作词者",
  "composer": "作曲者",
  "category": "分类",
  "audio": "https://example.com/audio.mp3",
  "lyrics": [
    ["第一行歌词", "第二行歌词"],
    ["第二段第一行", "第二段第二行"]
  ]
}
```

存储的数据会自动被 C++ 引擎解析（Flutter 版）。

---

## 📦 打包与迁移到其他设备

### ⚡ 每次 git commit 自动发布（已内置钩子）

本仓库内置 **git post-commit 钩子**，每次 `git commit` 成功后自动：

1. 构建最新 Web 版本
2. 发布到 `release\<短commit>-<时间戳>\` 版本化目录
3. **自动清理，只保留最近 5 份**（脚本内 `KeepCount` 可调）

- 安装钩子（一次性）：双击 `tools/install_hooks.bat`（已安装则跳过）
- 手动发布：`pwsh -NoProfile -File tools\publish_release.ps1`
- 钩子模板：`tools/git-hooks/post-commit`

详见 **[docs/DEPLOY.md](docs/DEPLOY.md)**。速览：

| 目标平台 | 依赖 | 产物 |
| --- | --- | --- |
| **Web**（推荐，立即可用） | 目标机只需 Python | `release/echohymn-web-1.0.0.zip` —— 双击 `tools/打包.bat` 一键生成 |
| **Windows 桌面** | 开发机需 VS + 开发者模式 | `hymn_app/build/windows/x64/runner/Release/` 整体拷贝 |
| **Android** | 开发机需 Android Studio | `build/app/outputs/flutter-apk/app-release.apk` 直接安装 |

> 一键生成 Web 迁移包：**双击 `tools/打包.bat`** → 得到 `release/echohymn-web-1.0.0.zip` → 拷贝到目标电脑解压 → 双击「开始使用.bat」即可。

---

## 🛠 开发工具

推荐 MCP 服务器与 VS Code 插件配置详见 **[docs/RECOMMENDED_TOOLS.md](docs/RECOMMENDED_TOOLS.md)**，C++ 引擎构建详见 **[docs/README.native.md](docs/README.native.md)**。

---

## ⚠️ 说明

- 演示音频使用 Pixabay 的公有领域古典乐资源，仅用于演示播放功能。
- 如需正式使用，请替换为自有或正版授权的音频文件。
