# EchoHymn 开发会话总结（2026-08-15 ~ v1.0.0）

> 本文档用于**新会话续接开发**。新会话开始时先读本文件 + `docs/UI_CONFIRMATION.md`（最终设计定稿），再 `git log --oneline -8` 查看提交。

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

**关键文件**：`hymn_app/lib/{screens/home_screen.dart, widgets/hymn_display.dart, widgets/playlist_dialog.dart, services/{sqlite_repository,audio_service,app_paths,chinese_convert_service,app_state_service}.dart, models/{hymn,hymn_category,playlist}.dart}`

## 二、当前技术栈（v1.0.0）

- **UI**：Flutter（Material），三栏布局（左 280 / 歌词 / 右 340），顶栏收起按钮 + 底部状态栏；窗口最小 1132×700
- **数据**：SQLite `tjc_hymn.db`（474 首）+ `AppPaths.resolveAsset`（Linux 相对路径 → Windows 分隔符，向上查找 12 层 data/）
- **繁转简**：OpenCC FFI（桌面）；Web 降级原文
- **音频播放**：`audioplayers` 6.8.1 → Windows 走 Media Foundation 系统解码器；`DeviceFileSource(abs)` 直读中文路径文件（m4a/mp3）
- **状态持久化**：shared_preferences（左栏 Tab/歌单/诗歌/音频版本/歌词模式）
- **依赖已移除**：just_audio / just_audio_windows / audio_session / rxdart（audioplayers 自带平台支持）

## 三、第 4 轮 + 发声修复 关键决策记录

1. **media_kit 方案已否决**（mpv 7z 完整性校验失败）→ 方案 A 回退 just_audio（可构建但中文路径无声）
2. **just_audio_windows「Loading interrupted」根因**：`AudioSource.uri(Uri.file(abs))` 对中文/繁体路径做 URI 百分号编码，just_audio_windows 的 MediaSource::CreateFromUri 端解码失败 → 静默中断（当时无 Toast 所以"无声且无提示"）
3. **方案 B（最终采用）**：`audioplayers` 的 `DeviceFileSource(path)` **直传平台原生文件路径**（不经 URI 编码），audioplayers_windows 直接用文件句柄/路径打开 → 中文路径完美支持
4. **Toast 修复仍保留**：`hymn_display.dart` statusStream 统一检测 `PlayerStatus.error` → 弹 Toast（含 lastError），覆盖初始化/列表点击/播放条/版本切换全路径

## 四、验证结果（v1.0.0）

```
cd hymn_app
flutter analyze            # 0 issues
flutter build windows --release   # √ Built echo_hymn.exe
# 产物: build\windows\x64\runner\Release\echo_hymn.exe
# 运行需 data\ 在 exe 的上级目录链中（AppPaths 向上找 12 层）
# 用户确认：声音正常播放 ✓
```

## 五、剩余/遗留任务清单

1. 【下次优先】**个人歌单 UI 展示/播放验证**：`playlist` 表有数据（创建弹窗正常写入），但 `playlist_hymn` 当前 0 行，且「个人歌单」Tab 点击歌单后**仅高亮**、未展示/播放其诗歌列表（第 1-3 轮聚焦其他反馈被搁置）
2. **Web 构建未通**：`sqlite3`/`flutter_opencc_ffi` 的 `dart:ffi` 在 Web 不可用——**桌面优先**，Web 可降级或暂不支持（audioplayers 本身支持 Web）
3. 音频「人声版」多版本已支持（播放条 groups 图标弹出列表），但**未验证切换发声**
4. 状态持久化已保存，但**跨会话恢复后列表高亮/滚动位置**未验证联动（`_syncListScroll` 仅对 playing/loading 触发）
5. `windows/runner/win32_window.cpp` 最小宽已改 1132，但未在**小屏实机**验证布局无溢出（歌词区 ConstrainedBox(minWidth:450) 已移除）

## 六、其他已知约束

- Windows 构建需要**开发者模式**（Flutter 插件符号链接）
- CMakeLists 已注入 `_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS` 与 `/utf-8`（原为解决 just_audio_windows 中文代码页 C4819，audioplayers 无需但仍保留无害）
- 数据库路径 Linux 相对路径 → `AppPaths.resolveAsset` 转平台分隔符；向上查找 12 层 data/
- 繁转简：桌面 OpenCC FFI；Web 降级原文

## 七、验证命令速查

```bash
cd hymn_app
flutter analyze            # 应 0 issues
flutter build windows --release
# 产物: build\windows\x64\runner\Release\echo_hymn.exe
# 运行需 data\ 在 exe 的上级目录链中（AppPaths 向上找 12 层）
```
