# EchoHymn 开发会话总结（2026-08-15 ~ 当前）

> 本文档用于**新会话续接开发**。新会话开始时先读本文件 + `docs/UI_CONFIRMATION.md`（最终设计定稿），再 `git log --oneline -15` 查看提交。
> **目标平台**：Windows（已开发）+ Android（目录就绪）+ OpenHarmony 鸿蒙（目录占位）。**Web 已移除**。
> **重要**：每次 git commit 到 master/main 会**自动触发 Windows 发布**（见「自动发布机制」章节），请提交后核对 `release/auto-release.log`。
> **状态文件**：`echo_hymn.exe` 同级目录 `state.json`（便携）。
> **日志文件**：`echo_hymn.exe` 同级目录 `logs/`（文本日志，UTF-8 BOM，保留 7 份）。

---

## 一、已完成的里程碑

| 提交/tag | 内容 |
| --- | --- |
| `45c7b5a` | 全新 UI 搭建：Flutter + SQLite（`tjc_hymn` 474 首 / `hymn_category` 45 条）+ OpenCC 繁转简 + 三栏布局 + 个人歌单表 + 弹窗 |
| `9918dc5` / `00e985a` / `0882f55` | 第 1~3 轮反馈：顶栏收起/箭头、窗口最小、音频后端、人声多版本、状态持久化、分页、滚动条等 |
| `39e5557` | 第 4 轮反馈：音频错误 Toast 全路径、左栏 280/右栏 340、列表滚动高亮联动 |
| `ac10d65`（**tag v1.0.0**） | 🎉 **音频真正发声**：audioplayers `DeviceFileSource` 直读中文路径，根治 just_audio「Loading interrupted」 |
| `ee5d7e6`（v1.0.1） | 个人歌单 UI 完善：新建按钮移位、三个 tab 等距、点击歌单展示并播放、修改按钮复用弹窗（含删除） |
| `67e1bab`（v1.0.2） | **移除 Web、确立三平台目标**（Win+Android+鸿蒙）；删除 web/html/发布流水线；新增 `ohos/` 占位 |
| `4c72014` | chore: 纳入 `.clinerules` 与 `data/tjc_hymn.db` |
| `122bdec`（v1.0.3） | **个人歌单表结构重构**：双表 → 单表 `playlist_hymn`（`id/name/hymns(JSON [{标题:编号}])/created_at/updated_at`），含自动迁移；**恢复 Windows 自动发布**（`publish_windows.ps1` + post-commit 钩子） |
| `8a966c9` | **状态恢复优化**：① 恢复不自动播放（进度条从 0 起，`AudioService.loadHymn`）；② 按「播放来源」恢复左栏；③ 右侧栏 340→**480px** |
| `dd178cd` | 恢复记忆音频版本（人声版）+ 滚动联动考虑分页机制 |
| `eeb5dcb` | **锚点重构**：新增 `playlistIndex`（播放列表位置索引）持久化，统一锚点恢复 |
| `4386de4` | 锚点恢复一次同步左栏 Tab + 歌单展开 + 诗歌列表页码，分帧滚动定位 |
| `96d89ba` | **恢复校验机制**：滚动偏移校验（jumpTo 后读 `offset` 误差 ≤2px）+ 锚点统一校验 + 底部状态栏报告 |
| `9bc754f` | 恢复成功清空报告回归播放信息 + 滚动校验 `hasClients` 保护 + 播放清除报告 |
| `ca890de` | **状态存储改 `exe` 同级 `state.json`**（便携 + 原子写 + 容错 + 旧数据迁移） |
| `716fcd4` | **基类/子类重构**：左栏三栏目拆分为 `LeftPanel` 抽象基类 + 三个子类（共用播放/渲染/滚动入基类，独立显示/交互/恢复入子类），`HomeScreen` 精简为协调者 |
| `5433195`（**tag v1.1.0**） | **纯 Dart 简繁转换 + 搜索定位/切歌联动/状态稳定**：弃用 OpenCC FFI（本机 DLL 与 UI 线程不兼容）改用数据库全量字符映射表；搜索框「定位跳转」语义（编号即时定位/标题匹配列表/×保持定位）；切歌联动高亮滚动（避搜索框/标题栏）；state.json 串行写入防损坏；VC 运行库就近打包 |
| `e4e3875`（**tag v1.2.0**） | **日志系统 + 过时依赖清理**：`LogService` 文本日志（exe 同级 `logs/`，UTF-8 BOM，保留 7 份，全局异常捕获）；移除 `shared_preferences` 依赖；发布包可运行性修复（乱码/闪退） |
| `b39967f`~`06c61f5`（v1.2.x 窗口重构） | **基座画面 + 抽屉式侧栏 + 等比缩放**：基座画面物理像素 **850×890**；侧栏改为**抽屉式向两侧扩展**（左 350 / 右 600，窗口整体加宽，基座永远居中）；侧栏状态持久化（`showLeft/showRight`）；窗口**等比缩放**（`Transform.scale` 渲染层缩放，不再依赖布局约束）；最大化感知 + resize 后重建消除时序竞态 |
| `bb5a0e6`（tag v1.2.1） | **四轮 UI 回归测试收尾（2026-08-29~30）**：回归清单纯测试视角化；27 条 NG 分批修复——窗口单实例保护/最小尺寸随侧栏同步、歌词字号随窗口铺满 + 整体 +4、搜索回车与焦点保持、弹窗 Toast 就地/字数计数/重名检查/删除落库、播放条防抖/版本高亮、just_audio 残留清理 |
| `9a9452c`（v1.3.0，2026-08-30） | **自定义标题栏 + 全局播放快捷键 + 用户手册**：移除系统标题栏（`WS_CAPTION`），Flutter 顶栏自绘「用户手册 / 最小化 / 最大化·还原 / 关闭」按钮组，标题区空白处可拖拽窗口、双击最大化；全局快捷键（空格/Ctrl+P 播放暂停、Ctrl/Alt+方向键切歌、Ctrl+↑↓ 音量、Ctrl+M 静音、F1 手册、通用媒体键）；用户手册弹窗（软件介绍 / 操作说明 / 快捷键说明）；`AudioService` 新增音量/静音控制 |

**关键文件**：

- 面板：`hymn_app/lib/widgets/panels/{left_panel_base, hymn_list_panel, default_playlists_panel, my_playlists_panel}.dart`
- 协调者：`hymn_app/lib/screens/home_screen.dart`（含自定义标题栏/窗口按钮组）
- 全局快捷键：`hymn_app/lib/app.dart`（根 `Focus` 包裹 `MaterialApp` + `kNavigatorKey`）
- 用户手册弹窗：`hymn_app/lib/widgets/user_manual_dialog.dart`
- 其他：`widgets/{hymn_display, playlist_dialog}.dart`、`services/{sqlite_repository, audio_service, app_state_service, app_paths, chinese_convert_service, log_service}.dart`、`models/{hymn,hymn_category,playlist}.dart`
- 窗口控制：`windows/runner/{flutter_window, win32_window}.cpp`（自定义标题栏样式 + `echo_hymn/window` 通道：setClientSize / minimize / maximizeToggle / close / startWindowDrag + 最大化状态推送）

---

## 二、当前技术栈

- **UI**：Flutter（Material），**基座画面 850×890 物理像素** + 侧栏抽屉式展开（左 **350** / 右 **600**）；**自上而下四栏**：自绘窗口标题栏 **30px**（移除系统 `WS_CAPTION`，左侧 logo+应用名，右侧「用户手册 / 最小化 / 最大化·还原 / 关闭」按钮组，整条可拖拽/双击最大化）→ 顶栏 **40px**（左右侧栏切换 + 中央当前歌曲）→ 内容区 → 底部状态栏 **30px**；窗口**等比缩放**（`Transform.scale`，最大化铺满不裁切）；最小客户区 850×890
- **操作**：**全局快捷键**（v1.3.0）：空格/Ctrl+P 播放暂停、Ctrl+→ 或 Alt+→ 下一首、Ctrl+← 或 Alt+← 上一首、Ctrl+↑/↓ 音量、Ctrl+M 静音、F1 用户手册、通用媒体键；根 `Focus` 包裹 `MaterialApp`，任意焦点（含弹窗）事件冒泡统一处理；输入框聚焦时空格放行输入
- **用户手册**：顶栏「？」按钮或 F1 打开（软件介绍 / 操作说明 / 快捷键说明），Esc 或 ✕ 关闭
- **数据**：SQLite `tjc_hymn.db`（474 首）+ `AppPaths.resolveAsset`（向上查找 12 层 data/）
- **简繁转换**：**纯 Dart 查表**（`lib/data/chinese_convert_map.dart`，由 `tools/gen_convert_map.py` 从数据库全量字符生成：繁→简 1052 / 简→繁 1025）；**弃用 OpenCC FFI**（本机 opencc.dll 与 UI 线程不兼容，导致白屏/崩溃）
- **音频播放**：`audioplayers` 6.8.1 → Windows Media Foundation；`DeviceFileSource(abs)` 直读中文路径
- **状态持久化**：`echo_hymn.exe` 同级 `state.json`（**串行写队列**防并发损坏；左栏Tab/歌单/诗歌/音频版本/歌词模式/播放列表位置 `playlistIndex`/**侧栏展开状态 showLeft/showRight**）
- **日志**：`echo_hymn.exe` 同级 `logs/`（`LogService` 文本日志，UTF-8 BOM，保留 7 份；FlutterError / 平台通道异常全局捕获）
- **架构**：左栏三栏目 = 抽象基类 `LeftPanel` + 三子类（各自独立状态与滚动恢复）；切歌联动 `syncWithPlayback`（高亮滚动避开搜索框/标题栏）
- **发布包**：CMake 打包 VC 运行库（MSVCP140/VCRUNTIME140/VCRUNTIME140_1）就近加载
- **依赖已移除**：just_audio / just_audio_windows / audio_session / rxdart / shared_preferences（改原生 state.json）/ flutter_opencc_ffi（改用纯 Dart）

---

## 三、关键决策记录（2026-08-16 会话）

1. **音频方案**：media_kit 否决 → just_audio（中文路径无声）→ **audioplayers `DeviceFileSource` 直读路径** ✅；`hymn_display` 统一 error Toast
2. **播放恢复**：软件重启**不自动播放**（`loadHymn` 只加载，进度条 0 起），等用户点播放
3. **状态锚点**：记录「当前播放/选择的诗歌 + 音频版本 + 歌词模式 + 来源歌单 + **播放列表位置索引**」，重启后统一恢复并**校验**（滚动偏移/左栏/版本/位置逐项比对，底部状态栏异常报告）
4. **状态存储**：离开 `%APPDATA%` 改为 `exe` 同级 `state.json`（便携、原子写 `.tmp`+rename、加载失败兜底默认、旧数据自动迁移）
5. **架构拆分**（用户要求）：三个左栏栏目用 **Dart 基类/子类**拆开——`LeftPanel`（抽象基类，含 `buildHymnTile` 抽象渲染接口/`playHymn` 公共播放/`scrollToCurrent`/`restoreSaved`/`syncWithPlayback`）+ `HymnListPanel`/`DefaultPlaylistsPanel`/`MyPlaylistsPanel`（各自实现行渲染、滚动列、展开逻辑、交互、来源透传），防止改动互相影响
6. **自动发布**：git post-commit → `tools/publish_windows.ps1` → `flutter build windows --release` → `release/echohymn_win_<时间戳>_<短哈希>/`（保留 5 份；目录名按名称可直接排序）；Web 已移除不发布

### 2026-08-16 ~ 17 会话追加决策

1. **搜索框语义 = 定位跳转**（非过滤）：输入编号即时定位（翻页+滚动+高亮，不自动播放；回车播放）；输入标题显示匹配列表供点击选择；点「×」保持当前定位结果；定位后播放条/上一首/下一首从定位处开始
2. **简繁转换弃用 OpenCC FFI**：本机 opencc.dll 与 UI 线程不兼容（FFI 调用挂起致白屏，Bindings 一次性 lookup 缺符号致崩溃）；改用**纯 Dart 逐字查表**（数据库全量字符映射，无原生依赖、不阻塞、跨平台稳定）
3. **切歌联动**：基类监听 `AudioService.statusStream`，切歌先 `setState` 刷新高亮再 `scrollCurrentIntoView`（避开搜索框/标题栏）；HymnListPanel 支持跨页自动翻页
4. **state.json 串行写队列**：`AppStateService` 用 Future 链排队写入，杜绝并发写损坏；搜索结果播放不保存 `playlistIndex`（由 `hymnNumber` 定位恢复，避免跨列表索引错位）
5. **VC 运行库就近打包**：CMake 安装规则把 MSVCP140/VCRUNTIME140/VCRUNTIME140_1 拷入 exe 目录，不依赖系统是否安装 VC++ Redistributable

### 2026-08-18 ~ 21 会话追加决策（v1.2.x 窗口重构）

1. **基座画面固定**：画面逻辑尺寸固定 **850×890 物理像素**，歌词区永远是 850 宽，不再被侧栏挤压；侧栏改为**抽屉式**——展开时窗口整体加宽（左 350 / 右 600），基座画面中心始终对齐屏幕工作区中心
2. **窗口等比缩放**：整棵 UI 树用 `Transform.scale` 按「窗口客户区 / 内容基准尺寸」等比缩放（contain，不裁切不变形）；最大化/手动 resize 时内容跟随放大铺满
3. **侧栏状态持久化**：`state.json` 新增 `showLeft/showRight`，启动时恢复侧栏展开状态并同步窗口宽度
4. **时序竞态消除**：native 窗口 resize 完成后强制重建一次（`setState`），`LayoutBuilder` 拿最新 constraints 重算 scale；最大化感知（`IsZoomed` 时不改窗口尺寸，只重算画布比例）
5. **日志系统**：`LogService` 文本日志落地 `exe` 同级 `logs/`（UTF-8 BOM 防乱码，保留 7 份），`FlutterError.onError` + `PlatformDispatcher.onError` 全局捕获，错误不崩溃

### 2026-08-30 会话追加决策（v1.3.0 自定义标题栏 + 快捷键 + 用户手册）

1. **自定义标题栏方案**：`CreateWindow` 创建后 `style &= ~WS_CAPTION`（保留 `WS_THICKFRAME`/`WS_MINIMIZEBOX`/`WS_MAXIMIZEBOX`/`WS_SYSMENU`），窗口右上角改为 Flutter 顶栏自绘「用户手册 / 最小化 / 最大化·还原 / 关闭」按钮组；拖拽用 `ReleaseCapture + SendMessage(WM_NCLBUTTONDOWN, HTCAPTION)` 进入系统标题栏拖拽循环（最大化拖拽自动还原）；`SetMinClientSize` 改用**实际窗口样式**计算外框（无标题时不含标题高度），保证最小尺寸 = 基座 850×890 客户区 + 侧栏宽
2. **最大化状态同步**：native `WM_SIZE` 检测 `IsZoomed` 变化后经 `echo_hymn/window` 通道 `onWindowMaximizedChanged` 推送给 Dart（`last_maximized_` 去重），切换「最大化/还原」按钮图标，覆盖 Win+↑、拖到屏幕顶部等系统操作
3. **全局快捷键**：`app.dart` 用根 `Focus(autofocus, onKeyEvent)` 包裹 `MaterialApp`（`kNavigatorKey` 供 F1 弹窗），任意焦点（含弹窗路由）的事件沿 Focus 链冒泡统一处理；**切换类动作**（播放/暂停、切歌、静音）忽略 `KeyRepeat`，**音量允许长按**连续调节；**输入框聚焦时空格放行**（`_isTextInputFocused` 检测 `EditableText` 祖先），避免搜索/命名时误触发
4. **音量/静音**：`AudioService` 新增 `_volume/_muted` 与 `changeVolume/toggleMute`（快捷键用，不持久化）；`AudioService.instance` 静态引用供全局快捷键调用（dispose 清空）
5. **用户手册**：`widgets/user_manual_dialog.dart`（软件介绍 / 操作说明 / 快捷键说明），顶栏「？」按钮或 F1 打开、Esc/✕ 关闭；快捷键表与 `app.dart` 实现共用 `kShortcutList` 常量保持一致

### 2026-08-30 会话修正（v1.3.0 布局：标题栏与顶栏分离）

> 反馈：自定义标题栏与原顶栏「重叠」且标题栏 logo/名称消失。修正为**独立的自绘窗口标题栏 + 功能顶栏**两条栏。

1. **布局 = 自上而下四栏**：自绘窗口标题栏 **30px**（logo + 应用名 + 右侧窗口按钮组「用户手册/最小化/最大化/关闭」+ 整条拖拽/双击）→ 顶栏 **40px**（左右侧栏切换 + 中央显示当前播放/选中歌曲，无歌时显示应用名）→ 内容区 → 底部状态栏 **30px**（原 40 改为 30）；窗口最小客户区 850×890 **不变**，四部分在其内分配。
2. **切歌刷新顶栏中央**：`AudioService.onCurrentChanged` 回调中除 `_saveState()` 外补充 `setState`，使顶栏中央「第 N 首《标题》」（繁体转简体）随切歌联动刷新。
3. **窗口按钮尺寸**：随标题栏高度改为 42×30；标题栏与顶栏之间加 1px 分隔线。

### 2026-08-30 会话追加（首轮测试结果 + H11 修复 + 状态栏分隔线）

1. **首轮测试结果**：`hymn_app/test/v130_features_test_cases.md` 47 项实测 —— W(19)/S(17)/H(10) 全部 OK，**仅 H11 NG**（用户手册重复打开会叠加多个弹窗）。
2. **H11 修复**：`UserManualDialog.show` 增加静态 `_isOpen` 防重入标志（`whenComplete` 复位 + 异常兜底），手册已打开时 F1/？重复触发直接忽略，关闭后可再次打开。
3. **状态栏分隔线**：`home_screen.dart` 在内容区与 `_buildStatusBar` 之间新增 `Divider`，与标题栏/顶栏分隔线一致（#E5E6EB 1px）。
4. **复测清单**：新建 `hymn_app/test/v130_retest_checklist.md`（12 项：H11a~H11d 修复复测 / D01~D03 状态栏分隔线 / R01~R05 相关回归）。

### 2026-08-30 会话追加（v1.3.1 音量调节控件 + 快捷键联动）

1. **播放条音量控件**：播放条左侧新增音量调节（通用方案）= 静音图标 + 滑条 + 音量百分比文字（42px 内不挤压居中播放按钮组，与右侧人声版本按钮对称 Positioned）。
2. **单一音量数据源（关键设计）**：`AudioService` 增加 `volumeNotifier` / `mutedNotifier`（`ValueNotifier`），`setVolume` / `toggleMute` / `changeVolume` 全部更新并通知；播放条 UI 用 `ValueListenableBuilder` 监听——**快捷键（Ctrl+↑↓/Ctrl+M）与 UI 控件是同一系统**，任一方改变实时刷新另一方；设置非零音量自动取消静音。
3. **验证**：`flutter analyze` 0 issues；构建成功；SendKeys 模拟 Ctrl+↓×3（日志 100→95→90→85%）+ CopyFromScreen 真实屏幕截图 + 千问视觉识别确认 UI 显示 85%、滑条在 85% 位置（PrintWindow 截旧帧，故用真实屏幕截图验证）。
4. **测试清单**：新建 `hymn_app/test/v131_volume_test_cases.md`（20 项：V01~V07 音量控件 UI / V08~V14 快捷键联动 / V15~V20 布局回归）。

---

## 四、剩余/遗留任务清单

1. ✅ 个人歌单 UI / 表结构 / 播放上下文
2. ✅ 移除 Web，目标 = Windows + Android + 鸿蒙
3. ✅ 恢复不播放 + 按播放来源恢复左栏 + 右侧栏 480px（后重构为 600px 抽屉式）
4. ✅ 音频版本记忆（重启恢复人声版）+ 滚动联动
5. ✅ 锚点 playlistIndex + 统一恢复 + 校验机制 + 状态栏报告
6. ✅ 状态存储 exe 同级 state.json（便携）
7. ✅ 左栏三栏目基类/子类重构
8. ✅ **重构后逐项验证（v1.1.0 完成）**：搜索定位跳转、切歌联动高亮滚动、个人歌单编辑后播放顺序同步、状态恢复（含搜索结果由编号定位）
9. ✅ **v1.2.x 窗口重构**：基座画面 850×890、抽屉式侧栏、等比缩放、最大化/竞态处理、日志系统
10. ✅ **v1.2.1 四轮 UI 回归测试（2026-08-29~30）**：27 条 NG 分批修复并复测归档（窗口/歌词/搜索/弹窗/播放条）
11. ✅ **v1.3.0 自定义标题栏 + 全局快捷键 + 用户手册（2026-08-30）**：移除系统标题栏，Flutter 自绘窗口按钮组（用户手册在最小化左侧）；通用播放快捷键 + 媒体键；用户手册弹窗（软件介绍/操作说明/快捷键说明）
12. `windows/runner/win32_window.cpp` 最小 850×890 小屏实机布局验证（屏幕不足时最大化并等比内缩）——**暂不作为任务**
13. Android / 鸿蒙 ——**暂不作为当前任务**（目录占位）

---

## 五、平台规划（2026-08-16 定稿）

| 平台 | 状态 | 说明 |
| --- | --- | --- |
| **Windows** | ✅ 已开发 | 桌面优先；**提交后自动发布** |
| **Android** | 📂 目录就绪，未开发 | 待适配 `AppPaths`/数据库/音频路径 |
| **OpenHarmony（鸿蒙）** | 📁 占位，未开发 | `ohos/` 仅 README；需 OpenHarmony Flutter SDK |
| ~~Web~~ | ❌ 已移除 | `dart:ffi` 在 Web 不可用 |

---

## 六、自动发布机制（git post-commit hook，Windows）

> **新会话必读**：每次 `git commit` 到 **master/main** 会自动构建并发布 Windows 桌面版，提交后核对 `release/auto-release.log` 与 `release/echohymn_win_*` 目录。

### 触发链路

1. `tools/git-hooks/post-commit`（已安装 `.git/hooks/post-commit`）
2. 后台运行：`pwsh -NoProfile -ExecutionPolicy Bypass -File tools/publish_windows.ps1`
3. 日志：`release/auto-release.log`

### publish_windows.ps1 流程

1. 仅 master/main 分支触发
2. `flutter build windows --release`
3. 拷贝 `build/windows/x64/runner/Release/*` + `data/` → `release/echohymn_win_<时间戳>_<短哈希>/`
4. 保留最近 5 份，旧版本自动删除

---

## 七、状态存储（state.json）

- 位置：`echo_hymn.exe` 同级目录 `state.json`
- 字段：`leftTab` / `subcategory` / `playlistName` / `hymnNumber` / `audioVersion` / `displayMode` / `playlistIndex` / **`showLeft`** / **`showRight`**
- 写入：原子写（`.tmp` 临时文件 → 重命名替换）+ **串行写队列**，写失败不影响运行
- 读取：缺失/损坏 → 返回默认状态（不崩溃）；首次无新文件时从旧 `%APPDATA%\com.example\echo_hymn\shared_preferences.json` 自动迁移

---

## 八、日志（logs/）

- 位置：`echo_hymn.exe` 同级目录 `logs/`
- 文件：按日期命名，UTF-8 BOM（防 Windows 记事本乱码），保留最近 7 份自动轮转
- 内容：`时间 | 级别(tag) | 消息` + `detail` 多行详情；全局 `FlutterError` / `PlatformDispatcher` 异常捕获
- 用途：排查播放失败/闪退/状态恢复问题，无需远程调试

---

## 九、验证命令速查

```bash
cd hymn_app
flutter analyze            # 应 0 issues
flutter build windows --release
# 产物: build\windows\x64\runner\Release\echo_hymn.exe
# 运行需 data\ 在 exe 的上级目录链中（AppPaths 向上找 12 层）
# 日志输出: exe 同级 logs\

# 手动触发 Windows 发布（可选）
pwsh -NoProfile -ExecutionPolicy Bypass -File tools\publish_windows.ps1
# 结果与日志: release\auto-release.log
