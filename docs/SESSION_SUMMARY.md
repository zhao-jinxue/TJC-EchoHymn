# EchoHymn 开发会话总结（2026-08-15 ~ v1.0.3）

> 本文档用于**新会话续接开发**。新会话开始时先读本文件 + `docs/UI_CONFIRMATION.md`（最终设计定稿），再 `git log --oneline -8` 查看提交。
> **目标平台**：Windows（已开发）+ Android（目录就绪）+ OpenHarmony 鸿蒙（目录占位）。**Web 已移除**。
> **重要**：每次 git commit 到 master/main 会**自动触发 Windows 发布**（见「自动发布机制」章节），请提交后核对 `release/auto-release.log`。

## 一、已完成的里程碑

| 提交/tag | 内容 |
| --- | --- |
| `45c7b5a` | 全新 UI 搭建：Flutter + SQLite（`tjc_hymn` 474 首 / `hymn_category` 45 条）+ OpenCC 繁转简 + 三栏布局（左 350 / 歌词 / 右 400）+ 个人歌单表 `playlist`/`playlist_hymn` + 弹窗 |
| `9918dc5` | 第 1 轮反馈：顶栏收起按钮/转箭头、歌词区 min 450×450、响应式字号、Linux 路径转 Windows、人声多版本列表、状态持久化、默认歌单展示诗歌、播放条分层 |
| `00e985a` | 第 2 轮反馈：箭头方向反转、窗口最小 1000×700（win32 WM_GETMINMAXINFO）、添加 `just_audio_windows` + CMake 注入 `_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS` + `/utf-8`、人声列表移播放条、左栏 350px、分页 50/35、滚动条 13/10px |
| `0882f55` | 第 3 轮反馈：状态**切换即保存**、窗口最小宽 1202、音频改 `AudioSource.uri`、Toast 显示具体错误、恢复**人声版按钮**（切第 1 人声版）、分页 35 首/页 |
| `3df35e1` | UI_CONFIRMATION.md 同步第 3 轮最终定稿 |
| `39e5557` | 第 4 轮反馈（代码）：**方案 A 回退 media_kit → 恢复 just_audio 可构建**、修复播放失败**无声且无提示**根因（statusStream 统一检测 error 弹 Toast，覆盖初始化/列表点击/播放条/版本切换全路径）、左栏 280px、右栏 340px、移除歌词区 ConstrainedBox(minWidth:450) 防溢出、窗口最小 1132px、**上一首/下一首时左侧列表自动滚动到当前项高亮**（诗歌列表自动翻页 + 默认歌单诗歌列表联动） |
| `35d9a32` | docs: SESSION_SUMMARY 记录第 4 轮完成状态 |
| `ac10d65`（**tag: v1.0.0**） | 🎉 **音频真正发声**：换用 **audioplayers 6.8.1**（`DeviceFileSource(path)` 直传文件路径，不经 URI 编码），根治 just_audio_windows 对中文/繁体路径经 `Uri.file` 编码导致的 **「Loading interrupted」**。用户确认声音正常播放。**首版完成** |
| `ee5d7e6`（**v1.0.1**） | **个人歌单 UI 完善**：① 新建按钮从顶部 tab 行移位到歌单列表上方全宽固定位置；② 「诗歌列表/默认歌单/个人歌单」三按钮**等距占满整行**；③ 点击歌单**展示并播放**其诗歌列表（播放上下文=该歌单，含恢复会话、上一首/下一首滚动联动）；④ 行尾删除按钮 → **修改按钮**，复用同一弹窗（编辑模式预填名称+成员，底部追加「删除歌单」按钮，二次确认后删除） |
| `67e1bab`（**v1.0.2**） | **移除 Web、确立三平台目标**：① 删除 `hymn_app/web/`、`html/`（独立 Web 前端）、Web 发布流水线（`tools/publish_release.ps1`/`package_web.ps1`/`install_hooks.bat`/`git-hooks/post-commit`/`打包.bat`）；② `.metadata` 移除 web 平台条目；③ 删除 `release/` 本地产物；④ 新增 `hymn_app/ohos/` 鸿蒙占位目录（不做开发）；⑤ 重写 README.md / DEPLOY.md 匹配三平台目标 |
| `4c72014` | chore: 纳入 `.clinerules` 项目规则与 `data/tjc_hymn.db` 数据库变更 |
| `（本次提交，v1.0.3）` | **个人歌单表结构重构 + 恢复 Windows 自动发布**：① 将 `playlist` + `playlist_hymn` 双表**合并为单个 `playlist_hymn` 表**（字段 `id`/`name`/`hymns`(JSON `[{标题: 编号}]`，与 hymn_category 一致)/`created_at`/`updated_at`），代码含旧双表→新单表**自动迁移**；② 真实数据库已迁移（「测试」歌单保留）；③ 新增 `tools/publish_windows.ps1` + 重新安装 post-commit 钩子 → **每次 commit 自动构建并发布 Windows 桌面版**到 `release/echohymn-win-*`（保留 5 份） |

**关键文件**：`hymn_app/lib/{screens/home_screen.dart, widgets/hymn_display.dart, widgets/playlist_dialog.dart, services/{sqlite_repository,audio_service,app_paths,chinese_convert_service,app_state_service}.dart, models/{hymn,hymn_category,playlist}.dart}`

## 二、当前技术栈（v1.0.3）

- **UI**：Flutter（Material），三栏布局（左 280 / 歌词 / 右 340），顶栏收起按钮 + 底部状态栏；窗口最小 1132×700
- **数据**：SQLite `tjc_hymn.db`（474 首）+ `AppPaths.resolveAsset`（Linux 相对路径 → Windows 分隔符，向上查找 12 层 data/）
- **繁转简**：OpenCC FFI（桌面 FFI）
- **音频播放**：`audioplayers` 6.8.1 → Windows 走 Media Foundation 系统解码器；`DeviceFileSource(abs)` 直读中文路径文件（m4a/mp3）
- **状态持久化**：左栏 Tab/歌单/诗歌/音频版本/歌词模式/播放列表位置 → **`echo_hymn.exe` 同级目录 `state.json`**（便携，随程序拷贝；旧 `%APPDATA%\com.example\echo_hymn\shared_preferences.json` 首次启动自动迁移）
- **依赖已移除**：just_audio / just_audio_windows / audio_session / rxdart（audioplayers 自带平台支持）

## 三、第 4 轮 + 发声修复 关键决策记录

1. **media_kit 方案已否决**（mpv 7z 完整性校验失败）→ 方案 A 回退 just_audio（可构建但中文路径无声）
2. **just_audio_windows「Loading interrupted」根因**：`AudioSource.uri(Uri.file(abs))` 对中文/繁体路径做 URI 百分号编码，just_audio_windows 的 MediaSource::CreateFromUri 端解码失败 → 静默中断（当时无 Toast 所以"无声且无提示"）
3. **方案 B（最终采用）**：`audioplayers` 的 `DeviceFileSource(path)` **直传平台原生文件路径**（不经 URI 编码），audioplayers_windows 直接用文件句柄/路径打开 → 中文路径完美支持
4. **Toast 修复仍保留**：`hymn_display.dart` statusStream 统一检测 `PlayerStatus.error` → 弹 Toast（含 lastError），覆盖初始化/列表点击/播放条/版本切换全路径

## 四、验证结果（v1.0.3）

```text
cd hymn_app
flutter analyze            # 0 issues（v1.0.1 个人歌单改动后通过）
flutter build windows --release   # 桌面版可构建（audioplayers 方案）
# 产物: build\windows\x64\runner\Release\echo_hymn.exe
# 运行需 data\ 在 exe 的上级目录链中（AppPaths 向上找 12 层）
# 用户确认：声音正常播放 ✓（v1.0.0）
```

## 五、剩余/遗留任务清单

1. ✅（v1.0.1 已完成）个人歌单 UI 展示/播放（顶部新建按钮、tab 等距、点击歌单展示诗歌列表、修改弹窗复用+删除按钮）
2. ✅（v1.0.2 已完成）移除 Web（目标平台 = Windows + Android + 鸿蒙）
3. ✅（v1.0.3 已完成）个人歌单表结构重构（单表 playlist_hymn，hymns 存 `[{标题: 编号}]` JSON）+ 恢复 Windows 自动发布
4. ✅ 音频「人声版」多版本已支持（播放条 groups 图标弹出列表），**切换可正常发声**
5. ✅（本次修复）**跨会话恢复后列表滚动联动**：`_restoreFromInit` 恢复后主动调用 `_syncListScroll()`（原 `_syncListScroll` 仅对 playing/loading 触发，idle 恢复不滚动，已修复）
6. `windows/runner/win32_window.cpp` 最小宽已改 1132，小屏实机布局验证**暂不作为任务**
7. Android / 鸿蒙 **暂不作为当前任务**（目录占位）
8. ✅ **Windows 自动发布已实测通过**（提交 122bdec 与 8a966c9 两次均自动产出 `release/echohymn-win-*`）

## 六、其他已知约束

- Windows 构建需要**开发者模式**（Flutter 插件符号链接）
- CMakeLists 已注入 `_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS` 与 `/utf-8`（原为解决 just_audio_windows 中文代码页 C4819，audioplayers 无需但仍保留无害）
- 数据库路径 Linux 相对路径 → `AppPaths.resolveAsset` 转平台分隔符；向上查找 12 层 data/
- 繁转简：桌面 OpenCC FFI

## 七、平台规划（2026-08-16 定稿）

| 平台 | 状态 | 说明 |
| --- | --- | --- |
| **Windows** | ✅ 已开发（v1.0.x） | 桌面优先，audioplayers + SQLite + OpenCC FFI；**提交后自动发布** |
| **Android** | 📂 目录就绪，未开发 | `hymn_app/android/` 存在；待适配 `AppPaths`/数据库/音频路径 |
| **OpenHarmony（鸿蒙）** | 📁 占位，未开发 | `hymn_app/ohos/` 仅 README；需 OpenHarmony Flutter SDK |
| ~~Web~~ | ❌ 已移除 | `dart:ffi` 在 Web 不可用 |

## 八、自动发布机制（git post-commit hook，Windows）

> **新会话必读**：本项目每次 git commit 到 **master/main** 分支都会**自动触发 Windows 桌面版发布**，请在提交后核对结果。

### 触发链路

1. `tools/git-hooks/post-commit`（Git 钩子，已安装到 `.git/hooks/post-commit`）
2. 提交成功后自动后台运行：`pwsh -NoProfile -ExecutionPolicy Bypass -File tools/publish_windows.ps1`
3. 日志输出到：`release/auto-release.log`

### publish_windows.ps1 流程

1. 仅当当前分支为 **master/main** 才继续（特性分支跳过）
2. `flutter build windows --release` 构建桌面版
3. 将产物 `hymn_app/build/windows/x64/runner/Release/*` 连同 `data/`（数据库+音频）拷贝到 `release/echohymn-win-<短哈希>-<时间戳>/`
4. 只保留最近 **5** 个版本目录，旧的自动删除

## 九、验证命令速查

```bash
cd hymn_app
flutter analyze            # 应 0 issues
flutter build windows --release
# 产物: build\windows\x64\runner\Release\echo_hymn.exe
# 运行需 data\ 在 exe 的上级目录链中（AppPaths 向上找 12 层）
