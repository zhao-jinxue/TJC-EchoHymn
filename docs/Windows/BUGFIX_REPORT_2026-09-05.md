# EchoHymn 修复报告（2026-09-05 全局 Bug 诊断）

> 本报告为 2026-09-05 会话「全局诊断与安全修复」的正式存档。
> **修复提交**：`e22d8b4` `fix(robustness)` ｜ **回滚检查点**：tag `pre-bugfix-2026-09-05` @ `88d396e`
> **诊断范围**：`hymn_app/lib` 全部 20 个业务源文件（services×7 / screens / widgets×5 / panels×4 / models×3 / app / main / theme）。

## 一、诊断结论总览

| 级别 | 数量 | 说明 |
| --- | --- | --- |
| P0 阻断级 | **0** | 启动链路兜底完整；`flutter analyze` 0 issues、单测 18/18、实机全量回归已验收 |
| P1 高危级 | 1 | state.json 双写队列竞态（数据丢失风险） |
| P2 优化级 | 4 | 判定不一致 / 状态残留 / 回调泄漏 / 非原子建库 |

## 二、逐项修复说明

### 1.（P1）state.json 双串行写队列竞态 — `screens/home_screen.dart`

- **问题**：HomeScreen 持有私有 `AppStateService()` 实例，而 `ManualPrefs`（手册"启动时显示"勾选框）走 `AppStateService.shared`。两条独立 `_writeChain` 会对同一 `state.json.tmp` 并发「写临时文件 → rename」：rename 冲突时 catch 分支**先删除 `state.json` 主文件、再改名已不存在的 tmp** → 状态文件整体丢失；且「单键读-改-写」与「全量写」交错会互相覆盖字段（丢失更新）。
- **触发条件**：手册弹窗勾选框即时写与切歌/换肤/字号变更的状态保存并发发生。
- **修复方式**：HomeScreen 改用 `AppStateService.shared` 单例——全进程写入收敛到**同一条 Future 串行链**，从调度结构上消灭并发窗口（非加锁补丁）。`app_state_service.dart` 文件头注释本已声明该设计意图，属实现遗漏的回归。

### 2.（P2）谱面网络来源判定不一致 — `widgets/hymn_display.dart`

- **问题**：`_buildScore` 空态判定用 `abs.contains('http')`，`_ScoreImageView` 选数据源用 `startsWith('http')`。本地路径中段含 "http"（如目录名 `https_cache`）时：空态检查被跳过 → 走到 `FileImage` 加载不存在文件 → 显示破图而非「暂无简谱」。
- **修复方式**：两处统一 `startsWith('http')`（URL 语义判定正确化）。

### 3.（P2）换谱面滚动位置残留 — `widgets/hymn_display.dart`

- **问题**：`_ScoreImageView.didUpdateWidget` 换歌时复位了缩放（`_zoom=1`），但垂直滚动 offset 未复位——放大停在谱尾时切歌，旧 offset 被新内容尺寸钳位到不确定位置而非顶部。
- **修复方式**：`didUpdateWidget` 补排帧回调 `addPostFrameCallback → jumpTo(0)`（等新谱面高度布局完成后生效），与缩放复位语义对齐。

### 4.（P2）窗口通道回调未注销 — `screens/home_screen.dart`

- **问题**：`initState` 经 `_windowChannel.setMethodCallHandler` 注册原生→Dart 回调，dispose 未注销。State 销毁后闭包仍持有死对象（内存滞留），native 的 `onWindowMaximizedChanged` 事件继续向已销毁 State 投递（虽有 mounted 守卫不致崩溃）。
- **修复方式**：`dispose()` 首行 `setMethodCallHandler(null)`。

### 5.（P2）新建歌单非原子双写 — `services/sqlite_repository.dart` + `widgets/playlist_dialog.dart`（级联）

- **问题**：新建流程 = `createPlaylist(name)`（INSERT 空成员 `'[]'`）→ `updatePlaylist(id, name, hymns)`（UPDATE 补成员）。两次写库间进程被杀/磁盘异常 → 库中残留"有名无成员"的半创建歌单。
- **修复方式**：`createPlaylist(String name, [List<MapEntry<String,int>> hymns = const []])` 增可选成员参数，名称+成员**单次 INSERT 原子落库**；成员明细日志上移至仓库层单点记录。改动前 grep 确认 `createPlaylist` 全库仅 1 处调用，级联修改对话框：删除二次 `updatePlaylist`。

## 三、评估后有意不改（防止过度修复）

| 位置 | 现象 | 不改理由 |
| --- | --- | --- |
| `hymn_list_panel._buildPageList` | build 过程中直接钳制 `_listPage`（不 setState） | 同帧内 `_buildPagination` 即读取该值，功能正确；经 K 系列全量实机回归，改动引入风险大于收益 |
| `audio_service._pollSystemVolume` | 轮询 ±2% 容差同步 | 音量方案 A 已实机 Q01~Q08 全 OK 验收，属设计权衡 |

## 四、验证与回滚

- **验证**：`flutter analyze` 0 issues ｜ `flutter test` 18/18 全过 ｜ `flutter build windows --release` 成功 ｜ 提交推送后核对 `release/auto-release.log` 发布完成。
- **过程拦截**：编辑中相邻字符串字面量拼接失误与 `id` 级联引用遗漏，均被 analyze 即时拦截，未进入提交。
- **回滚**：`git revert e22d8b4`（推荐，保历史）；或 `git restore --source=pre-bugfix-2026-09-05 -- <路径>`（单文件回退）。
- **遗留**：state.json 竞态属低概率时序场景，实机难以直接复现，以代码评审 + 编译/测试验证背书。

---

*详细问答与思路过程见 `docs/sessions/2026-09-05_22-08-32.md` 任务 7。*