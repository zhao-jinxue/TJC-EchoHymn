# EchoHymn 开发会话总结（2026-08-15 ~ 当前）

> 本文档用于**新会话续接开发**。新会话开始时先读本文件 + `docs/UI_CONFIRMATION.md`（最终设计定稿），再 `git log --oneline -15` 查看提交。
> **目标平台**：Windows（已开发）+ Android（目录就绪）+ OpenHarmony 鸿蒙（目录占位）。**Web 已移除**。
> **重要**：每次 git commit 到 master/main 会**自动触发 Windows 发布**（见「自动发布机制」章节），请提交后核对 `release/auto-release.log`。
> **状态文件**：`echo_hymn.exe` 同级目录 `state.json`（便携）。

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
| `716fcd4`（当前） | **基类/子类重构**：左栏三栏目拆分为 `LeftPanel` 抽象基类 + 三个子类（共用播放/渲染/滚动入基类，独立显示/交互/恢复入子类），`HomeScreen` 精简为协调者 |

**关键文件**：

- 面板：`hymn_app/lib/widgets/panels/{left_panel_base, hymn_list_panel, default_playlists_panel, my_playlists_panel}.dart`
- 协调者：`hymn_app/lib/screens/home_screen.dart`
- 其他：`widgets/{hymn_display, playlist_dialog}.dart`、`services/{sqlite_repository, audio_service, app_state_service, app_paths, chinese_convert_service}.dart`、`models/{hymn,hymn_category,playlist}.dart`

---

## 二、当前技术栈

- **UI**：Flutter（Material），三栏布局（左 280 / 歌词 / 右 **480**），顶栏收起按钮 + 底部状态栏；窗口最小 1132×700
- **数据**：SQLite `tjc_hymn.db`（474 首）+ `AppPaths.resolveAsset`（向上查找 12 层 data/）
- **繁转简**：OpenCC FFI（桌面 FFI）
- **音频播放**：`audioplayers` 6.8.1 → Windows Media Foundation；`DeviceFileSource(abs)` 直读中文路径
- **状态持久化**：`echo_hymn.exe` 同级 `state.json`（原子写；左栏Tab/歌单/诗歌/音频版本/歌词模式/播放列表位置 `playlistIndex`）
- **架构**：左栏三栏目 = 抽象基类 `LeftPanel` + 三子类（各自独立状态与滚动恢复）
- **依赖已移除**：just_audio / just_audio_windows / audio_session / rxdart / shared_preferences（改原生 state.json）

---

## 三、关键决策记录（2026-08-16 会话）

1. **音频方案**：media_kit 否决 → just_audio（中文路径无声）→ **audioplayers `DeviceFileSource` 直读路径** ✅；`hymn_display` 统一 error Toast
2. **播放恢复**：软件重启**不自动播放**（`loadHymn` 只加载，进度条 0 起），等用户点播放
3. **状态锚点**：记录「当前播放/选择的诗歌 + 音频版本 + 歌词模式 + 来源歌单 + **播放列表位置索引**」，重启后统一恢复并**校验**（滚动偏移/左栏/版本/位置逐项比对，底部状态栏异常报告）
4. **状态存储**：离开 `%APPDATA%` 改为 `exe` 同级 `state.json`（便携、原子写 `.tmp`+rename、加载失败兜底默认、旧数据自动迁移）
5. **架构拆分**（用户要求）：三个左栏栏目用 **Dart 基类/子类**拆开——`LeftPanel`（抽象基类，含 `hymnTile`/`playHymn`/`scrollToCurrent`/抽象 `restoreSaved`）+ `HymnListPanel`/`DefaultPlaylistsPanel`/`MyPlaylistsPanel`（各自滚动列、展开逻辑、交互），防止改动互相影响
6. **自动发布**：git post-commit → `tools/publish_windows.ps1` → `flutter build windows --release` → `release/echohymn-win-<hash>-<ts>/`（保留 5 份）；Web 已移除不发布

---

## 四、剩余/遗留任务清单

1. ✅ 个人歌单 UI / 表结构 / 播放上下文
2. ✅ 移除 Web，目标 = Windows + Android + 鸿蒙
3. ✅ 恢复不播放 + 按播放来源恢复左栏 + 右侧栏 480px
4. ✅ 音频版本记忆（重启恢复人声版）+ 滚动联动
5. ✅ 锚点 playlistIndex + 统一恢复 + 校验机制 + 状态栏报告
6. ✅ 状态存储 exe 同级 state.json（便携）
7. ✅ 左栏三栏目基类/子类重构
8. ⬜ **待验证（重构后）**：三个面板的显示/交互/恢复在新架构下逐项验证（尤其个人歌单展开、诗歌列表分页滚动）
9. `windows/runner/win32_window.cpp` 最小宽 1132 小屏实机布局验证——**暂不作为任务**
10. Android / 鸿蒙 ——**暂不作为当前任务**（目录占位）
11. 发布产物中残留 `just_audio_windows_plugin.dll` 旧缓存（无害，如需干净可 `flutter clean` 重建）

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

> **新会话必读**：每次 `git commit` 到 **master/main** 会自动构建并发布 Windows 桌面版，提交后核对 `release/auto-release.log` 与 `release/echohymn-win-*` 目录。

### 触发链路

1. `tools/git-hooks/post-commit`（已安装 `.git/hooks/post-commit`）
2. 后台运行：`pwsh -NoProfile -ExecutionPolicy Bypass -File tools/publish_windows.ps1`
3. 日志：`release/auto-release.log`

### publish_windows.ps1 流程

1. 仅 master/main 分支触发
2. `flutter build windows --release`
3. 拷贝 `build/windows/x64/runner/Release/*` + `data/` → `release/echohymn-win-<短哈希>-<时间戳>/`
4. 保留最近 5 份，旧版本自动删除

---

## 七、状态存储（state.json）

- 位置：`echo_hymn.exe` 同级目录 `state.json`
- 字段：`leftTab` / `subcategory` / `playlistName` / `hymnNumber` / `audioVersion` / `displayMode` / `playlistIndex`
- 写入：原子写（`.tmp` 临时文件 → 重命名替换），写失败不影响运行
- 读取：缺失/损坏 → 返回默认状态（不崩溃）；首次无新文件时从旧 `%APPDATA%\com.example\echo_hymn\shared_preferences.json` 自动迁移

---

## 八、验证命令速查

```bash
cd hymn_app
flutter analyze            # 应 0 issues
flutter build windows --release
# 产物: build\windows\x64\runner\Release\echo_hymn.exe
# 运行需 data\ 在 exe 的上级目录链中（AppPaths 向上找 12 层）

# 手动触发 Windows 发布（可选）
pwsh -NoProfile -ExecutionPolicy Bypass -File tools\publish_windows.ps1
# 结果与日志: release\auto-release.log
