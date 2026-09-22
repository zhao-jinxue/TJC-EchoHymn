# 🎵 EchoHymn · 赞美诗与颂歌

一个基于 **Flutter** 的 Windows 桌面赞美诗聆听应用：诗歌列表 / 分类歌单 / 个人歌单、
歌词·简谱·五线谱三模式显示、钢琴版·人声版音频播放，配套 Inno Setup 加密安装包对外分发。

> **当前版本**：**v1.6.1**（tag `v1.6.1`，2026-09-22）——版本号单源 = `hymn_app/pubspec.yaml`
> **内容规模**：473 首诗歌 · 分类两级（一级 13 → 二级 47）· 钢琴版/人声版音频 · 简谱与五线谱谱图 · 诗歌源考
> **目标平台**：Windows（✅ 已开发 + 提交自动发布）· Android（📂 目录就绪，未开发）· OpenHarmony 鸿蒙（📁 占位）· ~~Web~~（❌ 2026-08-16 移除）
> **许可**：个人学习参考免费，商业使用需授权 —— 见 [LICENSE](LICENSE)

---

## ✨ 功能一览

### 浏览与搜索

- 📜 **左栏三栏目**：`诗歌列表`（按编号分页展示 473 首）/ `默认歌单`（数据库分类一级 → 二级浏览）/ `个人歌单`（新建·改名·删除·加歌，单表 `playlist_hymn`）
- 🔢 **编号即时定位**：搜索框输入数字 → 翻页 + 滚动 + 高亮定位（不自动播放）
- 🔎 **歌名 + 歌词统一模糊搜索**：中文关键字回车 → 三列结果弹窗（编号 / 诗歌名称 / 歌词，640×560）
  - 歌名关键字**红色加粗**；歌词关键字**主题色加粗**并从命中节开窗显示（`…` 前缀）；双命中同行并存
  - 单击选中、**双击 = 左栏定位 + 播放**（弹窗是唯一播放入口，二次回车只重新弹窗）
  - 繁简双向匹配（纯 Dart 内存全扫，`HymnSearchService`）；无命中 → 左栏空态 + Toast

### 播放

- ▶️ 播放 / 暂停、上一首 / 下一首、进度拖动；**钢琴版 / 人声版**多版本切换（人声版 >1 时出现 👥 版本菜单）
- 🔊 **音量 = 系统音量镜像**（v1.5.x 方案 A）：系统音量为唯一响度旋钮、播放器增益恒 100%，与系统播放器听感一致；系统音量面板或媒体键改动实时跟随
- ⌨️ **全局快捷键**：`空格`/`Ctrl+P` 播放暂停、`Ctrl+→`/`Alt+→` 下一首、`Ctrl+←`/`Alt+←` 上一首、`Ctrl+↑↓` 音量、`Ctrl+M` 静音、`F1` 用户手册、通用媒体键；输入框聚焦时空格放行输入
- 🧷 **单实例保护**：已运行时再次双击启动自动聚焦既有窗口

### 歌词与谱面

- 🎼 三种显示模式：**歌词 / 简谱 / 五线谱**（谱图与源考取自数据库字段）
- 🔍 **谱面宽度驱动缩放**（v1.5.2）：最小宽 = 初始 contain 显示宽、最大宽 = 歌词区当前显示宽（随窗口拉伸与字号等级实时跟随）；**`Ctrl+滚轮` = 缩放、`滚轮` = 滚动**；超高出常显滚动条；换歌自动复位缩放与滚动位置

### 个性化

- 🎨 **5 套配色**：晨光蓝 · 经典（默认）/ 暖阳金 · 圣堂 / 静谧绿 · 草木 / 典雅紫 · 暮云 / 暗夜墨 · 深色
  - 语义色槽 27 色（含 8 个分区极浅底色 + 未选中控件底色/描边）；标题栏调色盘按钮即时换肤并持久化；暗夜墨同步 DWM 深色标题栏
- 🔠 **4 级字号**：×1.0 / ×1.3 / ×1.6 / ×1.9，整棵 UI 树（含弹窗/菜单/Toast）等比缩放；左栏宽随系数扩展，右栏固定 600（内容可滚动）
- 🔤 **内置字体 EchoSans**（Noto Sans SC 子集，OFL 许可，真 400/500/700 字面）：不依赖目标机字体，无雅黑环境表现一致
- 🎼 **「曲谱+歌词」字体原生渲染**：用印刷 PDF 内嵌简谱字体（`EchoJianpu`，随 App 内置、无需安装）（**该模式的界面入口已于 2026-09-21 撤下，视图代码与数据保留，见 `docs/Windows/UI_CONFIRMATION.md` §5.20**）
  直接绘制库内 `code_seq` 码位——**时值线、低/高音点、附点、小节线、连音弧全部由字形自带**；
  字体由 `tools/build_jianpu_font.py` 跨 475 份 PDF 合并子集而成（覆盖 code_seq 全部 80 个码位）
- 📖 **应用内用户手册**：软件介绍 / 操作说明（▶ 小节 → • 二级 → – 三级分层）/ 快捷键与滚轮表（12 行）/ 启动显示设置；`?` 或 `F1` 打开、`Esc`/✕ 关闭、启动自动弹出可关

### 数据与可靠性

- 💾 **状态持久化**：`echo_hymn.exe` 同级 `state.json`（原子写 `.tmp`+rename + **全进程唯一串行写队列 `AppStateService.shared`**）；重启恢复左栏 Tab / 歌单 / 子分类 / 诗歌 / 播放列表位置 / 音频版本 / 显示模式 / 侧栏展开 / 配色 / 字号 / 手册开关，且**恢复不自动播放**（进度从 0）
- 🧭 **恢复校验**：滚动偏移（误差 ≤2px）与锚点逐项比对，异常在底部状态栏报告
- 📝 **应用日志**：`exe` 同级 `logs/`（按天、UTF-8 BOM、保留最近 7 份），`FlutterError` 与平台通道异常全局捕获
- 🆎 **繁→简转换**：纯 Dart 全量字符映射表（无原生依赖，已弃用 OpenCC FFI）
- 🩹 **免运行库依赖**：MSVCP140 / VCRUNTIME140 / VCRUNTIME140_1 就近打进发布目录

---

## 🖥 界面与窗口

```text
┌── 自绘标题栏 30px：logo + 应用名 ………… 【? 手册】【－】【□/❐】【✕】（整条可拖拽、双击最大化）─┐
├───────────────┬───────────────────────────────────────────────────────┬─────────────────┤
│ 左栏 350       │ 顶栏 40px：⟨左栏⟩⟨右栏⟩ … 中央当前歌曲《标题》… ⟨⟩         │ 右栏 600        │
│ 诗歌列表       ├───────────────────────────────────────────────────────┤  诗歌源考       │
│ 默认歌单       │ 版本栏 44px：[钢琴版][人声版]   [歌词][简谱][五线谱]     │（词曲作者/      │
│ 个人歌单       ├───────────────────────────────────────────────────────┤ 背景/分类）     │
│               │ 歌词 / 简谱 / 五线谱 显示区（谱面 Ctrl+滚轮缩放）        │                 │
│               ├───────────────────────────────────────────────────────┤                 │
│               │ 播放条：[🔊][滑条][50%] [⏮][⏯][⏭] [👥]（上方进度条）  │                 │
├───────────────┴───────────────────────────────────────────────────────┴─────────────────┤
│ 底部状态栏 30px：播放信息 / 恢复校验报告 / 诊断提示                                         │
└──────────────────────────────────────────────────────────────────────────────────────────┘
```

- **基座画面**（双侧栏收起）固定 **850×890 物理像素**且始终居中；展开侧栏时窗口向两侧加宽（左 350 / 右 600）
- 最小客户区 850×890；拉伸或最大化 = `Transform.scale` **等比铺满**（不裁切不变形）
- 移除系统 `WS_CAPTION`，窗口控制走 `echo_hymn/window` 原生通道（setClientSize / minimize / maximizeToggle / close / startWindowDrag + 最大化状态推送）

---

## 📁 项目结构

```text
EchoHymn/
├── LICENSE                      # 📄 著作权声明与许可（个人学习可用 / 商业需授权）
├── hymn_app/                    # 🚀 Flutter 应用
│   ├── lib/
│   │   ├── main.dart / app.dart            # 入口 / 根组件（全局快捷键、字号 Transform.scale）
│   │   ├── screens/home_screen.dart        # 主屏协调者（标题栏·顶栏·状态栏·侧栏抽屉·状态存取）
│   │   ├── widgets/
│   │   │   ├── panels/                     # 左栏：left_panel_base（抽象基类）+ 三子类面板
│   │   │   ├── hymn_display.dart           # 内容区（版本栏 / 歌词 / _ScoreImageView 谱面 / 播放条）
│   │   │   ├── hymn_search_dialog.dart     # 歌名+歌词搜索结果三列弹窗
│   │   │   ├── playlist_dialog.dart        # 个人歌单新建/编辑弹窗
│   │   │   └── user_manual_dialog.dart     # 用户手册（三级结构 + 快捷键表 + 启动显示设置）
│   │   ├── services/                       # sqlite_repository · audio_service · hymn_search_service ·
│   │   │                                   # app_state_service · app_paths · chinese_convert_service · log_service
│   │   ├── models/                         # hymn · hymn_category · playlist
│   │   ├── theme/                          # app_palette（27 色槽 + 5 套预设 + ThemeController）
│   │   │                                   # app_fonts（FontSizeLevel 4 级 + FontScaleController + AppFonts）
│   │   └── data/chinese_convert_map.dart   # 繁→简 1052 / 简→繁 1025 映射（tools/gen_convert_map.py 生成）
│   ├── windows/runner/                     # C++ 宿主：去系统标题栏、单实例、850×890 客户区、窗口通道
│   ├── assets/{data,fonts}/                # hymns.json；内置字体 EchoSans / EchoKai / EchoJianpu
│   ├── android/ · ohos/                    # Android 目录就绪 / 鸿蒙占位（均未开发）
│   ├── native/                             # ⚠️ C++ hymn_engine 历史可选组件（当前不经 dart:ffi 调用）
│   └── test/                               # 单元测试 18 用例 + v120~v151 实机测试/回归清单
├── data/                        # tjc_hymn.db（473 首 / 45 分类 / 个人歌单）+ Hymn_Downloads（约 3GB 音频与谱图素材）
├── installer/                   # 📦 Inno Setup 工程：echohymn.iss（三页向导+誓言+两段解包）、
│                                #    prepare_staging.py / make_payload.py（主体+素材双载荷 AES-256）、
│                                #    payload_manifest.txt、ChineseSimplified.isl（官方翻译固化）、app_icon.ico、output/（双产物）
├── tools/                       # publish_windows.ps1（自动发布）· build_installer.ps1（一键双产物+SHA256）·
│                                # scan_db_refs.py（素材清单 payload_manifest.txt）· gen_convert_map.py ·
│                                # extract_ppt.py（PPT 编码解析）· build_jianpu_font.py（合并印刷简谱字体+字形度量）·
│                                # score_selftest.py（全库曲谱输出自测）· git-hooks/post-commit 等
├── release/                     # 🤖 提交自动发布的 Windows 绿色目录（保留最近 5 份）+ auto-release.log
└── docs/                        # 📚 文档（按平台归档：Windows/ Android/ OpenHarmony/ iOS/，总纲见 docs/README.md）
```

**架构要点**：左栏三个栏目 = `LeftPanel` 抽象基类（渲染接口 / 公共播放 / `scrollToCurrent` / `restoreSaved` / `syncWithPlayback`）

- `HymnListPanel` / `DefaultPlaylistsPanel` / `MyPlaylistsPanel` 三子类（各自独立状态与滚动恢复），`HomeScreen` 只做协调。

---

## 🚀 本地开发

**前置（仅首次）**：Flutter SDK · Visual Studio 2022「使用 C++ 的桌面开发」+ Windows SDK · CMake · 开启 Windows 开发者模式
（步骤见 [docs/Windows/INSTALL_VISUAL_STUDIO.md](docs/Windows/INSTALL_VISUAL_STUDIO.md) 与 [docs/Windows/INSTALL_CMAKE.md](docs/Windows/INSTALL_CMAKE.md)）

```bash
cd hymn_app
flutter pub get
flutter run -d windows            # 开发运行（热重载）
```

提交前的质量基线（应全绿）：

```bash
flutter analyze                   # 期望 0 issues
flutter test                      # 期望 18/18 通过
flutter build windows --release   # 期望构建成功
```

> - 运行需 `data\` 位于 exe 的上级目录链中（`AppPaths.resolveAsset` 向上查找 12 层）。
> - **改动没生效先重启程序**：Windows 的 Dart AOT 代码在 `data\app.so`（不在 exe 内），rebuild 后旧进程仍持启动时的代码。

## 📦 构建与分发

| 形态 | 命令 | 产物 | 用途 |
| --- | --- | --- | --- |
| **绿色目录** | `flutter build windows --release`（或提交自动触发） | `hymn_app\build\windows\x64\runner\Release\` → `release\echohymn_win_<时间戳>_<短哈希>\` | 开发自用 / 内部验证，整目录拷贝即可运行 |
| **安装包** | `pwsh -NoProfile -ExecutionPolicy Bypass -File tools\build_installer.ps1` | `installer\output\EchoHymn_Setup_v<版本>.exe`（≈33 MB）+ `EchoHymn_Data_v<版本>.7z`（≈3 GB）+ 两份 `.sha256` | 对外分发（v1.5.2 实测 32.7 MB / 3035 MB） |

安装包要点（操作手册 [docs/Windows/INSTALLER.md](docs/Windows/INSTALLER.md)，规范基线 [docs/Windows/RELEASE_RULES.md](docs/Windows/RELEASE_RULES.md) 18 条）：

1. **双文件同目录分发**：素材包必须与安装包放在同一文件夹，缺失时首屏环境检查 ✘ 阻断并给指引——主体/素材拆分（2026-09-05）根治了旧 3GB 单文件双击后 5~15 秒的系统扫描空档
2. **三步向导**：系统兼容性检查（64 位 / Win10+ / Media Foundation / 素材就位 / 磁盘空间 / VC 运行库内置说明）→ 安装位置（默认 `D:\Program Files\EchoHymn`，无 D 盘或空间不足自动回退 C 盘）→ **誓言宣誓**（只读展示禁复制粘贴、逐字键入 + 归一化全文比对，不通过不安装）
3. **两段解包**：先释放程序（秒级）再释放素材（带百分比，不过系统盘临时目录）；尾步 `icacls` 授权 Users 可写（Program Files 下 `state.json` 与 `logs/` 能写的前提）
4. **升级与卸载**：覆盖安装自动备份还原个人歌单库，`state.json`/日志天然保留；卸载询问是否保留个人数据（默认保留）；支持 `/VERYSILENT` `/DIR=` `/LOG=`（静默跳过誓言，环境检查仍生效）
5. **安全与校验**：载荷 AES-256 + 加密头（口令 XOR 混淆内嵌，定位"抬高门槛"级防护，不宣称不可破解）；对外分发必须同时提供两份 `.sha256`；未购代码签名证书，首次运行 SmartScreen「未知发布者」提示属正常
6. **构建前置**：`winget install JRSoftware.InnoSetup` + `pip install py7zr`；素材更新后先 `python tools/scan_db_refs.py` 重生成清单再构建

## 🔄 自动发布机制（Windows）

`git commit` 到 **master/main** → `.git/hooks/post-commit` 后台跑 `tools/publish_windows.ps1` →
`flutter build windows --release` → 拷贝产物与 `data/` 到 `release/echohymn_win_<时间戳>_<短哈希>/`（保留最近 5 份，目录名可直接排序）。
提交后请核对 `release/auto-release.log`。手动触发同一条脚本。**安装包构建不并入**自动发布（素材压缩耗时，保持手动）。

## 💾 运行时文件与数据

| 位置 | 内容 |
| --- | --- |
| `exe` 同级 `state.json` | `leftTab` / `subcategory` / `playlistName` / `hymnNumber` / `audioVersion` / `displayMode` / `playlistIndex` / `showLeft` / `showRight` / `appTheme` / `fontSizeLevel` / `manualOnStart`；缺失或损坏回退默认；首次自动从旧 `%APPDATA%` 的 shared_preferences 迁移 |
| `exe` 同级 `logs/` | 按天文本日志（UTF-8 BOM，保留 7 份）：库加载 / UI / 交互 / 歌单 / 播放 / 异常 |
| `data/tjc_hymn.db` | `tjc_hymn`（473 首：歌词十节、五线谱/简谱路径、`audio_versions` JSON、`source_info` 源考）· `hymn_category`（一级 13 → 二级 47，`category`/`subcategory`/`hymns(JSON，编号含 51_a 甲乙变体)`）· `playlist_hymn`（个人歌单，`id/name/hymns(JSON)/created_at/updated_at`） |
| `data/Hymn_Downloads/` | 音频（鋼琴版 m4a / 人聲版 mp3）、`简谱`/`五线谱` 的 png 与 pdf、每首一个 `checksums.json` |

## 🔧 技术栈

| 层 | 技术 |
| --- | --- |
| UI | Flutter / Dart（Material）；基座 850×890 + 抽屉式侧栏 + `Transform.scale` 等比缩放 |
| 窗口宿主 | Win32 C++（`windows/runner`）：去 `WS_CAPTION` 自绘标题栏、单实例 Mutex、`echo_hymn/window` 通道、DWM 深色随配色切换 |
| 音频 | `audioplayers` 6.x → Windows Media Foundation；`DeviceFileSource` 直读中文路径；响度走系统主音量（COM 读写 + 轮询同步） |
| 数据 | `sqlite3` + `sqlite3_flutter_libs`（`data/tjc_hymn.db`） |
| 搜索 | `HymnSearchService`（Dart 层歌名 + 歌词全扫，繁简双向映射） |
| 主题 / 字号 | `AppPalette` 语义色槽（27 色 / 5 套预设）+ `ThemeController`；`FontSizeLevel` + `FontScaleController`（均 `ValueNotifier` 驱动整树重建或缩放） |
| 简繁转换 | 纯 Dart 字符映射表 `lib/data/chinese_convert_map.dart`（弃用 OpenCC FFI） |
| 字体 | 内置 EchoSans（Noto Sans SC 子集，OFL）· EchoKai（標楷體，曲谱歌词）· EchoJianpu（印刷简谱字体，曲谱记号原生渲染） |
| 持久化 / 日志 | 自研 `AppStateService`（全进程唯一串行队列 + 原子写）/ `LogService`（轮转 + 全局异常捕获），无 `shared_preferences` 依赖 |
| 打包 | VC 运行库 CMake 就近安装；Inno Setup 6 + py7zr AES-256 双载荷 |
| 已移除依赖 | just_audio / just_audio_windows / audio_session / rxdart / shared_preferences / flutter_opencc_ffi |

## 🧪 测试

- **单元测试**（`flutter test`）：`hymn_app/test/font_size_level_test.dart`（3）+ `hymn_app/test/hymn_search_service_test.dart`（15）= **18 用例**
- **实机测试与回归清单**：`hymn_app/test/v120/`~`v151/`（窗口/歌词/搜索/弹窗/播放条 G 系列回归、配色 T/R 系列、字号 R37~R42、手册 M01~M15、音量 Q01~Q08、搜索 S01~S41 + 复测 R01~R20）
- **发布验证基线**：静默装到非默认目录核对文件数（完整安装 3040 文件）→ 以普通（非提权）权限启动确认 `state.json`/`logs/` 可写 → 静默卸载确认程序文件清空且个人数据保留 → 三页向导人工走查（详见 `docs/Windows/RELEASE_RULES.md` 第三节）
- **诊断存档**：[docs/Windows/BUGFIX_REPORT_2026-09-05.md](docs/Windows/BUGFIX_REPORT_2026-09-05.md)（P0 零发现 / P1×1 / P2×4，回滚检查点 tag `pre-bugfix-2026-09-05`）

## 🗺 平台规划

| 平台 | 状态 | 说明 |
| --- | --- | --- |
| **Windows** | ✅ 已开发 | 桌面优先；提交自动发布 + 手动安装包双通道 |
| **Android** | 🚧 已立项（2026-09-11） | 阶段 0 环境搭建完成（D 盘 SDK/JDK17/AVD，flutter doctor 全绿）；移植计划见 [docs/Android/ANDROID_PLAN.md](docs/Android/ANDROID_PLAN.md) |
| **OpenHarmony 鸿蒙** | 📁 占位，未开发 | `hymn_app/ohos/` 仅 README；接入须知见 [docs/OpenHarmony/](docs/OpenHarmony/README.md) |
| **苹果（iOS/macOS）** | 📁 占位，未立项 | 需 macOS + Xcode；接入须知见 [docs/iOS/](docs/iOS/README.md) |
| ~~Web~~ | ❌ 已移除 | `dart:ffi` 与桌面窗口通道不可用，目录与流水线已删 |

## 🏷 版本沿革

| tag | 日期 | 主题 |
| --- | --- | --- |
| v1.0.0 | 2026-08 | 音频真正发声（audioplayers + `DeviceFileSource` 直读中文路径） |
| v1.0.1 ~ v1.0.3 | 2026-08 | 个人歌单 UI 与表结构（单表 `playlist_hymn`）重构；确立 Win+Android+鸿蒙三平台目标；恢复自动发布 |
| v1.1.0 | 2026-08 | 纯 Dart 简繁转换 + 搜索定位跳转 + 切歌联动 + `state.json` 便携持久化 |
| v1.2.0 ~ v1.2.1 | 2026-08 | 日志系统；基座画面 850×890 + 抽屉式侧栏 + 等比缩放；四轮 UI 回归 |
| v1.3.0 | 2026-08-30 | 自定义标题栏 + 全局快捷键 + 应用内用户手册（+ v1.3.1 系统音量双向同步） |
| v1.4.0 | 2026-08-30 | 五套换肤配色（语义色槽 27 色）+ 标题栏调色盘 + 深色模式 |
| v1.5.0 | 2026-09-01 | 四级字号全局等比缩放 + 播放条镜像 Row + 内置 EchoSans + 手册重构与启动弹出 + 音量双重衰减根治 |
| v1.5.1 | 2026-09-02 | 歌名 + 歌词统一模糊搜索弹窗（红/蓝关键字加粗、双击唯一播放入口）+ 手册操作说明子项化 |
| v1.5.2 | 2026-09-05 | 谱面宽度驱动缩放与滚轮语义定稿 + 手册三级分层 + 全局稳健性修复（P1×1 / P2×4）；安装包主体/素材双载荷拆分 |
| **v1.6.0** | 2026-09-21 | **曲谱视图「字体原生渲染」定稿**（内置印刷简谱字体 `EchoJianpu` + 字形墨迹度量排版，连音弧/时值线/低音点全部由字形自带）+ 全库曲谱自测工具 `tools/score_selftest.py`；「曲谱+歌词」模式**从 UI 撤下**（视图代码与数据保留）+ 歌词页去「第 N 节」标签；第 349 首按用户要求整首移出（库内 **473 首**）；`tools/scan_db_refs.py` 恢复并新增手工保留项 |

| **v1.6.1** | 2026-09-22 | **默认歌单数据复原 + 甲乙变体编号纳入歌单**：`hymn_category` 误删的 `category`(一级)/`subcategory`(二级)/`hymns`(清单) 三列由 `tools/restore_hymn_category.py` **纯增列复原**（归属取自 git 老库、清单用 `api_cache` 列表页重建）→ 一级 13 类 / 二级 47 个 / 清单 **473 首 100% 覆盖**；歌单成员编号**放宽为字符串**（新增 `lib/models/hymn_ref.dart`，兼容旧库整数），`51_a`/`124_b` 等 **10 个甲乙变体编号**可在默认歌单与个人歌单中浏览·加入·还原；顺带修复「添加成员时变体编号退化成 hymn id」旧缺陷 |

## 📚 文档索引

`docs/` 已按平台归档（2026-09-13），**总纲与完整索引见 [docs/README.md](docs/README.md)**：

| 文档 | 用途 |
| --- | --- |
| [docs/README.md](docs/README.md) | 📍 文档总纲：目录索引 + 平台导航 + 附录（C++ `hymn_engine` 历史组件构建/恢复 FFI 路径） |
| [docs/Windows/](docs/Windows/) | 🖥 **Windows 开发全集**：开发总结（续接必读）· UI 定稿确认单 · UI 设计规范 · 配色效果图预览 · 打包迁移 · 安装/发布规范 · 诊断报告 · VS/CMake 环境安装 · 推荐工具 |
| [docs/Android/](docs/Android/) | 🚧 Android 移植计划（立项 2026-09-11）：环境现状、阶段 0~3、风险清单 |
| [docs/OpenHarmony/](docs/OpenHarmony/README.md) | 📦 鸿蒙占位：接入前提与待办 |
| [docs/iOS/](docs/iOS/README.md) | 📦 苹果平台占位：接入前提与待办 |
| [docs/knowledge/](docs/knowledge/) | 🛠 跨平台通用知识（Cline 上下文最小化等） |
| [docs/sessions/](docs/sessions/) | 🗂 逐会话开发档案（提问 / 解决思路 / 最终结果） |

## ⚠️ 说明与当前遗留

- 音频与谱图素材位于 `data/Hymn_Downloads/`（约 3 GB），数据库按平台相对路径引用；素材增删后需 `python tools/scan_db_refs.py` 重生成 `installer/payload_manifest.txt` 再构建安装包。
- `hymn_app/native/`（C++ 引擎与 C ABI 桥）与 `hymn_app/assets/opencc/` 属**历史保留**：当前 Flutter 侧不经 `dart:ffi` 调用，简繁转换与搜索全在 Dart 层完成，二者不参与 `flutter build`。
- Web 平台已彻底移除；Android / 鸿蒙仅目录占位。
- 待办：安装包实机 GUI 走查（UAC 即时性、素材缺失阻断指引、誓言粘贴回滚、两段解包进度）· 素材包分发通道（网盘 / U 盘）· OV 代码签名证书预算决策 · 小屏（可用区 < 850×890）布局验证。

## 📄 许可与版权

本软件源代码与设计的著作权归 **赵金雪** 所有，详见 **[LICENSE](LICENSE)**。

- ✅ 允许：下载、运行、阅读源代码，用于**个人学习、研究与技术参考**。
- ❌ 禁止：**任何商业使用**、二次分发、闭源衍生版本、冒用名称与界面装潢。
- 💼 商业授权：需事先联系著作权人签署《商业授权许可》——**1363343773@qq.com**。
- ™️ 第三方组件（Flutter 及各开源库）遵循各自原始许可证；诗歌文本、曲谱与录音素材的著作权归其原始权利人，本仓库不授予相关素材使用许可。
