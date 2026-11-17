# EchoHymn Android 版开发计划（手机 / 平板双分支，手机优先）

> **文档定位**：Android 平台的**需求基线、架构与发布口径**。
> 进度与续接 → [STATE.md](STATE.md)；工单与验收 → [IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md)；
> 界面稿 → [UI_CONFIRMATION_ANDROID.md](UI_CONFIRMATION_ANDROID.md)。
> **现行基线（2026-11）**：Android **v1.9.5**（主体 APK ≈54 MB + installer 6 个数据包）；Windows **v1.8.x** 功能全集。
> **三大参照**：① 参考 APK `com.tinanlin.tjc_hymn_cn_v2.4.2.apk`（机制见 `docs/knowledge/TJC_APK_JIANPU_RENDER.md`）；
> ② Windows 定稿（`docs/Windows/UI_CONFIRMATION.md`）；③ `hymn_app/lib/`（474 首）。

---

## 〇、环节 × 阶段矩阵（总纲）

> **环节 = 横向职能**（每个阶段都要逐项对照）；**阶段 = 纵向时序**（§四 的 A~F）。两者交叉即本计划的工作面。

| 环节 | 主要落点 | 阶段 | 章节 |
| --- | --- | --- | --- |
| **需求与验收管理** | 需求基线冻结 · 变更记录 · 移动端确认单闭环 | 贯穿（M2 前出确认单） | §十一 |
| **UI 设计** | **设计基础（令牌/五态/动效/图标/无障碍/适配/多语言/公差/资源）** + 16 张设计稿 + 导航状态机 + 深色谱面 + 缩放包络 + widget 映射 + 平板草图 | C（M3 定稿） | §三 |
| **功能实现** | 4 变体 × 阶段 A~E 任务清单 | A~E | §四 |
| **代码管理** | 分支 / flavor / 版本单源 / tag / 构建脚本 | A 起 | §五 |
| **数据与内容治理** | 数据管线 · 双口径基线 · 裁剪库 · 版权台账 | B（M2）/ F | §十二 |
| **模拟测试** | V1~V9 矩阵 · 自动化 · 走查 · 性能 / 无障碍 | 每阶段末 | §六 |
| **安全与合规** | 隐私 · 权限矩阵 · 签名密钥 · 上架材料 · 入参安全 | A / F | §十三 |
| **软件发布** | 4 变体产物 · 分发渠道 · 发布前清单 · 素材方案 | F（M5） | §七 |
| **运维与反馈闭环** | 日志导出 · 崩溃捕获 · 更新 · 回退 · 内测反馈表 | F 之后（长期） | §十四 |

> 阶段出口（M0~M6）见 §十。每个阶段收尾时按上表**逐行自检**：本阶段该环节该做的做了没有。

---

## 一、目标、范围与验收总纲

### 1.1 目标平台与系统基线（以最新 Android 为目标）

| 项 | 取值 | 说明 |
| --- | --- | --- |
| 目标系统 | **Android 16（API 36）** 为编译/目标基线；**Android 8.0（API 26）** 为最低支持 | API 36 = 当前最新；环境已装 `platforms;android-36` |
| `compileSdk` | **36** | 环境已装（Flutter 3.44 亦要求 ≥36） |
| `targetSdk` | **36** | 跟随最新；须正面适配下方五项「新系统硬要求」 |
| `minSdk` | **26**（落地时最终确认） | 更低需额外兼容分支且收益极低；素材/解码链路无 26 以下诉求 |
| ABI | `arm64-v8a` + `armeabi-v7a` + `x86_64`（模拟器） | 注意 **16 KB page size** 要求（见下） |

**新系统硬要求清单（targetSdk 35/36 必须正面处理，不能靠默认行为）**

| # | 要求 | 对 EchoHymn 的影响 | 落地要点 |
| --- | --- | --- | --- |
| 1 | **强制 edge-to-edge**（API 35+，无法 opt-out） | 标题栏/状态栏/播放条会与系统栏重叠 | 全屏 `SafeArea` + `SystemUiOverlayStyle`（透明栏 + 亮/暗图标随 `AppPalette.brightness` 切换）；**弃用桌面自绘 30px 标题栏**（§3.1） |
| 2 | **预测性返回（Predictive Back）** | 返回手势会先「预览」上一界面 | Manifest 加 `android:enableOnBackInvokedCallback="true"`；可返回点改 `PopScope(canPop:, onPopInvokedWithResult:)` |
| 3 | **前台服务类型**（API 34+ 强制声明原因） | 后台播放必须 `foregroundServiceType="mediaPlayback"` | 需 `FOREGROUND_SERVICE` + `FOREGROUND_SERVICE_MEDIA_PLAYBACK` 权限；配媒体通知（§4.5） |
| 4 | **通知权限运行时申请**（API 33+） | 媒体通知不申请则不显示 | `POST_NOTIFICATIONS` 首次播放前弹一次；拒绝后给设置页入口（降级为仅前台播放） |
| 5 | **16 KB memory page size**（Play 2025-11 起新应用/更新强制） | `sqlite3_flutter_libs` 等含原生库依赖必须 16KB 对齐 | 升 NDK ≥ 27；`flutter build apk --analyze-size` + 16KB 校验纳入发布前基线 |

> `READ_MEDIA_AUDIO`（API 33+）仅当读取**外置**音频时申请；素材全在应用私有目录（推荐，见 §7.5）时**无需任何存储权限**。

### 1.2 双分支产品形态（手机 / 平板）

| 维度 | 📱 手机版（先做） | 平板版（预留，后做） |
| --- | --- | --- |
| 屏幕取向 | 竖屏为主（默认 `portrait`，按需放开横屏） | 横屏为主 + 竖屏可用 |
| 信息架构 | **单主体三段式**：顶栏（歌名/搜索）+ 主体（歌词/谱面）+ 播放条；侧栏 = **抽屉 / 底部弹层** | **双栏或三栏并列**：左栏（诗歌/歌单）+ 主体 + 右侧源考（可折叠） |
| 谱面区 | 单页；一页一节 / 一屏一行；双指缩放 | 可双页并排 / 谱面+歌词同屏（Windows「曲谱+歌词」思路的平板回补） |
| 播放条 | 底部常驻紧凑条（进度 + 三键 + 音量入口） | 底部完整播放条（含音量滑条，对齐 Windows） |
| 目标设备 | 手机 4.7~6.9 吋 | 平板 7~13 吋（含折叠屏展开态） |
| Git 分支 | `android/phone` | `android/tablet`（自 phone 验收后切出） |

> **折叠屏**：以「**宽度断点**」而非「设备类型」判布局（见 §5.2），折叠屏展开态自然落到平板布局，无需第三条分支。

### 1.3 三大参照基线与「取什么、不取什么」

| 参照 | 取 | 不取 |
| --- | --- | --- |
| **TJC APK**（`com.tinanlin.tjc_hymn_cn_v2.4.2`） | CSV 网格「列 = 拍点」数据模型（**已入库** `jianpu_score/row/cell`）· 同列对齐校验思路 · 网格调试图法 | **WebView + 动态 HTML 表格**渲染（黑底白字、`String.replace` 拼 HTML）；EchoHymn 用 Flutter 原生自绘（`JianpuGridView`） |
| **Windows 定稿 v1.8.0** | 功能全集与交互语义（四模式 / 五配色 / 四级字号 / 搜索 / 歌单 / 源考 / 手册）· 配色与字号规范 · 状态持久化语义 · 验收清单写法 | 自绘窗口标题栏 · 全局快捷键 · `Transform.scale` 窗口等比缩放 · 系统托盘（Android 改为**媒体通知常驻**） |
| **现有代码资产** | `models/` `services/` `data/`（库与查表）· `widgets/jianpu_grid_view.dart` `hymn_display.dart` 主体 · 6 个 Dart 测试 + 3 张 golden | 桌面专属耦合（`AppPaths` 桌面向上查找、`echo_hymn/window` 通道、`kBaseWindowWidth/Height` 常量） |

### 1.4 音频变体与体积（全量 / 钢琴版 / 人声版 / 无音频版）

> 手机版与平板版**各自再分四个变体**：**全量音频版 / 钢琴版 / 人声版 / 无音频版**（发布矩阵与打包口径见 ⑤）；无音频版在 UI 上**不提供任何播放能力**。
> **硬约束**：各变体 `applicationId` 必须互异（4 个变体要能**同时安装**在同一设备上）。

**资产体积实测（`data/Hymn_Downloads/`，2026-10-11 扫描 3682 个文件）**

| 资产类型 | 文件数 | 体积 | 有音频变体 | 无音频版 |
| --- | --- | --- | --- | --- |
| **音频（11 种版本**：鋼琴版 / 人聲版 / 四部合唱版 / 合唱-N部版×4 / 四部合唱-N部版×4**）** | **1257** | **2428.7 MB** | ✅ 全量需要；**推荐只留鋼琴版** | ❌ **不需要** |

> **打包口径（2026-11）**：只取 **鋼琴版 + 人聲版**（合唱类不打包；仅 `3`/`389` 的四部合唱版作人声版替代音源）。
| └ 其中 **仅鋼琴版** | 473 | **1145.4 MB** | ✅ ★推荐口径 | ❌ |
| └ 人聲版 | 463 | ≈890 MB | ⚠️ 可选（独立素材包） | ❌ |
| └ 合唱类 9 种（四部合唱 + 分声部） | 323 | 398.5 MB | ⚠️ 可选（独立素材包） | ❌ |
| 扫描图 `.png`（简谱 + 五线谱） | 948 | **487.5 MB** | ✅ 需要 | ✅ **需要** |
| `.pdf`（简谱/五线谱打印版） | 948 | 412.3 MB | ❌ 不需要（Android 不用 PDF） | ❌ 不需要 |
| `checksums.json` | 526 | 3.2 MB | ⚠️ 校验用，可选 | ⚠️ 同 |
| `.exe` / `.mp4` / `.txt`（`_misc` 杂物） | 3 | 47.2 MB | ❌ **打包必须排除** | ❌ 同 |

| 版本形态 | 数据资产（估） | 与全量差异 |
| --- | --- | --- |
| **有音频形态 · 全量** | 音频 2.03 GB（鋼琴+人聲）+ 扫描图 0.49 GB + DB 25.5 MB ≈ **2.55 GB**（**历史测算**；现行为主体 APK + 数据包） | 基准 |
| **★ 有音频版 · 仅鋼琴版** | 音频 **1.12 GB** + 扫描图 0.49 GB + DB 25.5 MB ≈ **1.66 GB** | **省 1.29 GB（44%）** |
| **无音频版** | 扫描图 0.49 GB + DB 25.5 MB ≈ **0.52 GB** | 省 2.43 GB |

> 含 APK 本体与随包资源的**完整交付体积口径**见本节 **④**（含字体、APK 估算与"数据侧裁剪"配套说明）。
> ⚠️ 另发现素材目录被污染：`data/Hymn_Downloads/_misc/` 内有 `Clash.Verge_2.5.2_x64-setup.exe`（44.8 MB）等杂物 → 打包/分发脚本**必须按扩展名白名单取件**（风险 R11）。

**功能差异（有音频版 vs 无音频版）**

| 功能 | 有音频版 | 无音频版 | 实现方式 |
| --- | --- | --- | --- |
| 播放 / 暂停 / 上一首 / 下一首 | ✅ | ❌ **UI 不出现** | 播放条整块条件渲染（`if (kAudioVariant == AudioVariant.lite)`） |
| 进度条 / 时间 / 拖拽 seek | ✅ | ❌ | 同上 |
| 音量面板 `🔊` / 静音 | ✅ | ❌ | 同上 |
| 音频版本 chips（`鋼琴版`/`人聲版`）+ `👥` | ✅ | ❌ **整行版本行移除** | 版本行条件渲染 |
| 音频版本切换、`audio_versions` 读取 | ✅ | ❌ | `AudioService` 在无音频版**不实例化**（stub） |
| 媒体通知 / 锁屏 / 后台播放 / 音频焦点 / 媒体键（阶段 D） | ✅ | ❌ 不适用 | 阶段 D 全部任务标记「仅音频版」 |
| 歌词 / 曲谱分节翻页 | ✅ 手动 + **自动跟随播放进度** | ✅ 手动 + **自动需另定时间基准**（见下） | 见 §1.4（虚拟进度） |
| 显示模式 | 四模式（歌词 / 曲谱 / 简谱 / 五线谱） | **三模式（歌词 / 简谱 / 五线谱）**；**「曲谱」仅 Windows** | 2026-10-28 定稿，2026-11-17 收紧为仅 Windows |
| 搜索 / 歌单 / 源考 / 五套配色 / 四档字号 / 手册 | ✅ | ✅ | 全保留 |
| 屏幕常亮 | ✅ | ✅（移到"显示"分组） | 看谱同样需要 |
| 状态持久化字段 | 配色/字号/模式/锚点/手册开关 + 播放位置 | 配色/字号/模式/锚点/手册开关 + **上次浏览的节** | 无音频版不写 `position` |

**自动翻页与进度来源（代码事实）**

| 环节 | 实现 | 位置 |
| --- | --- | --- |
| 进度来源 | `AudioPlayer.onPositionChanged` → `_positionCtrl` | `lib/services/audio_service.dart`（L30 / L70~75） |
| 对外接口 | `positionStream` / `durationStream` / `currentHymn` | 同上 |
| 消费点 | 订阅为 `_pos` → `_applyAutoPage()` 重算页码 | `lib/widgets/hymn_display.dart` L194~205 |
| 换算函数 | `autoPageIndexFor({position, totalSeconds, pageCount})`（**等分推算**） | `lib/models/hymn.dart`（契约见 `CODE_REFERENCE.md`） |
| 总时长来源 | **优先取 DB 预存**：`hymn.durationOf(version)` ?? `audioDurations.values.first` | `hymn_display.dart` L186~190（`tjc_hymn.audio_durations`） |

- `audioplayers` 是跨平台插件（Windows 走 Media Foundation、Android 走 ExoPlayer/MediaPlayer）⇒ **有音频变体的自动翻页在 Android 与 Windows 表现一致，零改动可用**。
- **无音频版没有进度流**（不播放音频）⇒ 自动翻页采用**「虚拟进度」**方案：内部时钟按 DB `audio_durations` 的总时长推进，**复用同一个 `autoPageIndexFor`**；零新增数据、翻页节奏与有音频版一致；界面**不出现任何播放控件**，仅由翻页条的「手动 / 定时」开关控制。

**「当前状态」语义（无音频版沿用，只改文案）**

| 用途 | 实现 | 无音频版 |
| --- | --- | --- |
| 顶栏「第 N 首《标题》」 | `AudioService.currentHymn` | ✅ 保留（文案改为「当前浏览」） |
| 列表高亮与滚动定位 | 按 `currentHymn` 联动（测试用例 G10/G11） | ✅ 保留 |
| 重启恢复锚点 | `state.json`：`hymnNumber` / `playlistIndex` / `playlistName` / `subcategory` | ✅ 保留（**字段名不变**，各变体共用同一结构） |

> 变体差异只在**触发来源**（播放/切歌 → 点选/搜索/翻页）与**文案**；`state.json` **不分叉**。

**实现方式（技术定稿）**

| 项 | 定稿 |
| --- | --- |
| 能力开关 | `enum AudioVariant { full, piano, vocal, lite }` + `kAudioVariant = AudioVariant.values.byName(String.fromEnvironment('AUDIO_VARIANT', defaultValue: 'full'))`（编译期常量，可 tree-shake） |
| 构建命令 | `flutter build apk --release --flavor <full/piano/vocal/lite> --dart-define=AUDIO_VARIANT=<同值>` |
| Gradle flavor | base `com.echohymn.app`（平板分支 `com.echohymn.pad`）+ `applicationIdSuffix` = `.piano` / `.vocal` / `.lite` |
| UI 收敛 | 变体判断**只允许出现在外壳**（播放条 / 版本+模式行 / 设置分组）与打包脚本；服务层用抽象 + stub（`WindowControls` 范式） |
| 素材与数据 | 素材差异由**素材包 + 白名单**承载（§7.5）；**DB 只有一份**（474 首；无音频版不读音频字段） |
| 标识 | 应用名带后缀（钢琴版 / 人声版 / 读谱版）；关于页显示变体；`state.json` 因包名不同天然隔离 |

**④ 音频版本构成与体积测算（实测）**

`data/Hymn_Downloads/` 实测含 **11 种**音频版本（**打包只取鋼琴版 + 人聲版**，其余仅作替代/素材留存）：

| 音频版本 | 文件数 | 体积 | 说明 |
| --- | --- | --- | --- |
| **鋼琴版** | **473** | **1145.4 MB** | 库内 474 首中的 473 首（仅 `249` 缺） |
| 人聲版 | 463 | ≈890 MB | 含补入的 `62`、`305`、`349` |
| 四部合唱版 | 47 | 118.1 MB | — |
| 合唱-1/2/3/4 部版 | 35 ×4 | 37.2 / 37.1 / 36.4 / 35.0 MB | 分声部练习用 |
| 四部合唱-1/2/3/4 部版 | 34 ×4 | 34.2 / 34.1 / 33.4 / 33.0 MB | 分声部练习用 |
| **小计** | **1257** | **2428.7 MB** | — |

**体积构成（随包口径）**

| 组成 | 体积 |
| --- | --- |
| 扫描图 `.png`（948 个） | 487.5 MB |
| `tjc_hymn.db` | 25.5 MB |
| 随包静态资产（字体等） | **34.5 MB**（`NotoSansSC` 29.5 + `lyric_kai` 4.94 + `jianpu_mmp2005` 0.06；`assets/opencc/*` 未被 `pubspec.yaml` 声明 → **不进包**） |
| APK 本体（按变体实测） | **lite 62.9 → vocal 66.6 → piano 77.9 → full 81.7 MB**（骨架 53.6 + 内置库 7.1 + 12 首样本：扫描图 9.3 / 人声 3.7 / 钢琴 15.1）；debug 172.4 MB（全 ABI + 调试符号） |

> APK 本体按变体实测（arm64 release，commit `c28d9d4`）：**lite 62.9 / vocal 66.6 / piano 77.9 / full 81.7 MB** —— 骨架 53.6 MB（原估算 25 MB）+ 内置库 7.1 MB + 12 首样本（扫描图 9.3 / 钢琴 15.1 / 人声 3.7）。叠加完整素材后各变体合计：**全量 ≈3.05 / 钢琴 1.76 / 人声 1.52 / 无音频 0.62 GB**（其余口径不变）。
> 只留鋼琴版相较全量**省 1283.3 MB（≈44%）**（人聲版 884.8 MB + 合唱类 9 种 398.5 MB）。各变体体积见 ⑤。

**⑤ 发布变体与音频覆盖（手机版为例，平板同构）**

> 手机版分**四个变体**（各自独立 app；**钢琴版 / 人声版 / 读谱版**名称带后缀）；钢琴版与人声版**无音频版本选择**（§3.1.17），无音频版为独立设计的读谱形态（§3.1.15 / §3.1.18）。

| # | 形态 | 触发条件（首启检测前十首） | UI | 素材来源 |
| --- | --- | --- | --- | --- |
| 1 | **全量形态** | 钢琴 + 人声都存在 | 版本循环切换 + 播放条 | 主体 APK + `piano`/`vocal`/`scores` 包 |
| 2 | **钢琴形态** | 仅钢琴 | 无版本按钮 + 播放条 | 主体 + `piano`/`scores` 包 |
| 3 | **人声形态** | 仅人声 | 无版本按钮 + 播放条 | 主体 + `vocal`/`scores` 包 |
| 4 | **读谱形态（lite）** | 两者都无 | **无播放条 / 媒体会话** | 主体 + `scores` 包 |

> **2026-11 架构变更（现行口径）**：不再按 Gradle flavor 发布 4 个 APK。release 只产出
> **主体 APK（≈54 MB，程序 + 数据库）**，素材由 installer 的 6 个数据包（扫描图/人声/钢琴 × 0-237/238-474）导入；
> 安装后由**运行时能力检测**决定上述形态。Gradle 的 4 个 flavor 仅保留 `full`（applicationId `com.echohymn.app`）。
>
> 早期「4 变体随包体积（full 2.52 / piano 1.68 / vocal 1.45 / lite 0.55 GB）」为历史测算，**不再是发布口径**；
> 现行数据包体积见 §7.5 / §7.6。

**缺口互补替代规则（App 内直接替代播放，不做跳转指引）**

| 变体 | 缺本版音频的曲目 | App 内处理 | **额外打包要求（实操备忘，勿漏）** |
| --- | --- | --- | --- |
| **钢琴版** | 1 首：`249 靈洗各人` | 用**人聲版**音频播放 | 额外打入 `249_人聲版.mp3`（1 个文件） |
| **人声版** | 11 首 | ① `3`、`389` → 用 **`*_四部合唱版.m4a`** 代替（**视同人声版**）；② 其余 **9 首** → 用 **鋼琴版** 音频代替 | 额外打入 `3_四部合唱版.m4a`、`389_四部合唱版.m4a` + **9 首鋼琴版** |

> **结果**：两个单音频版均 **474 / 474 全曲目可播**；**不出现任何"请改用另一个 app"的跳转提示**。

**可播口径**（DB 实测：库 **474 首**；`鋼琴版` 473 首、`人聲版` 463 首）

| 变体 | 真·本版音频 | 替代音频 | **合计可播** |
| --- | --- | --- | --- |
| 全量音频版 | 474 | — | **474 / 474** |
| 钢琴版 | 473 | 1 首（`249` → 人聲版） | **474 / 474** |
| 人声版 | 463 | 2 首（`3`/`389` → 四部合唱版）+ 9 首（→ 鋼琴版） | **474 / 474** |

**用户手册要求（人声版）**

- 新增章节「**关于本版音频**」：本版收录 **人聲版** 音频 **463 首**；另有 **11 首**云端未提供人声版，本版**使用替代音频播放**（清单附后）；如需对应原版音频，可用**钢琴版 / 全量音频版**：
  `3 亞伯拉罕的神`（替代：四部合唱版）、`103 快親近主`、`107 容我與主同行`、`178 趁還有今天`、`255 主今夜賜福`、`268 聽從主呼召`、`274_b 福音要傳遍(乙)`、`308 天父接納我`、`386 我得一友`、`387 求主對我述說`、`389 親近，更親近`（替代：四部合唱版）
- 钢琴版 App 手册同理列 **1 首**（`249 靈洗各人`，替代：人聲版）。

---

## 二、基线盘点（2026-10-11 实测）

### 2.1 可复用资产（关键数字）

| 资产 | 规模 | 复用方式 |
| --- | --- | --- |
| Flutter 代码 | `hymn_app/lib/` 27 个 dart 文件（`home_screen.dart` 45.6KB / `hymn_display.dart` 42KB） | 复用；`home_screen` 拆「移动壳 / 桌面壳」 |
| 依赖 | `audioplayers` / `sqlite3(+flutter_libs)` / `path_provider` / `ffi` | 全跨平台；补 `audio_session` |
| 字体 | `EchoSans`（3 字重）+ `EchoKai` + `EchoJianpu` 内嵌 | 字形自足，Android 一致 |
| 数据库 | `tjc_hymn.db` **25.53 MB**（474 首 + `hymn_category` 47 + `playlist_hymn` + `jianpu_*`） | 作 asset 首启拷贝 |
| 素材 | `Hymn_Downloads/` **≈3.25 GB**（音频 11 种版本 + 扫描图 948 个 + PDF） | 按类别拆 6 个数据包（§7.5） |
| 资源 | `hymn_app/assets/` 35.46 MB | 随包 |
| 测试 | 6 个 Dart 测试 + 3 张 golden + 手工清单 `v120~v151` | 复用 + 新增移动版 |
| 工具 | `import_apk_csv.py` / `jianpu_csv_selftest.py` / Windows 发布脚本 | 数据侧复用；发布侧另立 |

### 2.2 Android 工程现状与「模板默认值 → 目标值」待改点

| 文件 | 现状（实测） | 目标 | 阶段 |
| --- | --- | --- | --- |
| `android/app/build.gradle.kts` | `namespace`/`applicationId` = **`com.example.echo_hymn`**；`minSdk`/`targetSdk`/`compileSdk` 全取 `flutter.*` 默认；release **用 debug 签名** | `com.echohymn.app`；`compileSdk 36` / `targetSdk 36` / `minSdk 26`；release 走独立 keystore | A / F |
| `AndroidManifest.xml` | `label="echo_hymn"`；**零权限声明**；`launchMode=singleTop`；`configChanges` 齐全（✅ 保留） | `label="EchoHymn · 聆听赞美诗"`；补 `POST_NOTIFICATIONS`、`FOREGROUND_SERVICE(_MEDIA_PLAYBACK)`；加 `enableOnBackInvokedCallback`；声明媒体服务 | C / D |
| `MainActivity.kt` | `com.example.echo_hymn` 包下空模板 | 包名同步 + `configureFlutterEngine`（媒体会话 / 原生桥） | A / D |
| 图标 / 启动图 | `mipmap-*/ic_launcher.png`（Flutter 默认）+ `launch_background.xml` | EchoHymn 品牌图标（含 `adaptive-icon`）+ 启动图 | C / F |
| **`lib/` 桌面耦合** | `echo_hymn/window` MethodChannel **在 `home_screen.dart`（L27）与 `audio_service.dart`（L12）各硬编码一份**，仅 `kIsWeb` 早退 → **Android 上必然 `MissingPluginException`** | 抽 `WindowControls` 抽象 + 移动 stub（**阶段 A 第一件事**） | A |
| `AppPaths` | `isMobile = 非 Windows/Linux/macOS`；mobile 分支落 `getApplicationSupportDirectory()`（**逻辑已就绪**，但 DB 从未拷进去） | mobile 分支补 asset→私有目录首启拷贝 | B |
| 素材路径 | DB 内为**相对路径**（`Hymn_Downloads/001_.../1_鋼琴版.m4a`，`/` 分隔），由 `AppPaths.resolveAsset` 拼绝对路径 | Android 落点改「应用私有目录 + 素材根」 | B |

> ⚠️ **阶段 A 的头号崩溃点**：`_windowChannel.invokeMethod` 在 Android 无原生实现。必须先条件导入隔离，再谈「跑起来」。

### 2.3 参照 APK（曲谱显示方式的来源）

| 项 | 值 |
| --- | --- |
| 原件 | `E:\真教会\赞美诗\com.tinanlin.tjc_hymn_cn_v2.4.2.apk`（23.50 MB） |
| 副本（脚本默认路径） | `C:\Users\小蔡爱金雪\Downloads\com.tinanlin.tjc_hymn_cn_v2.4.2.apk` |
| 内容 | 1522 条目；`assets/` 994 = **474 CSV 网格 + 474 线谱 GIF + 符号 PNG** |
| 逆向工作区（仓库外） | `E:\apk_re_tjc\`（脚本 / 截图 / `ui*.xml` / 提取的 CSV 与 GIF） |
| 机制文档（仓库内） | `docs/knowledge/TJC_APK_JIANPU_RENDER.md` |

> **借鉴范围**：**仅曲谱的显示方式**（CSV 网格「列 = 拍点」、同列对齐、记号小图、小节线跨行）——EchoHymn 用 Flutter 自绘复刻该模型（`JianpuGridView`），**不采用其 WebView + HTML 表格实现**，也不采用"整首一屏"的分页方式（改为**按小节分页**，见 §3.14）。

### 2.4 环境现状（阶段 0 已完成，2026-09-11）

| 项 | 实况 |
| --- | --- |
| Flutter | 3.44.8 stable（`D:\flutter`），已 `enable-android` |
| Android SDK | `D:\Android\Sdk`：`platform-tools 37.0.1` · `platforms 34+36` · `build-tools 34.0.0+36.0.0` · `emulator 37.1.11` · `system-images;android-34;google_apis;x86_64` |
| JDK | `D:\Java\jdk-17.0.20.1+1`（`JAVA_HOME`） |
| AVD | `echohymn_avd`（Pixel 7 / API 34 / `D:\Android\avd`）冷启动成功（`adb sys.boot_completed=1`） |
| 采样设备 | `flutter devices` → `sdk gphone64 x86 64 (mobile) • emulator-5554 • android-x64 • Android 14` |
| 工具链选型 | **不装 Android Studio GUI**（CrossInstall 安装器不支持静默指定目录；命令行全链路可覆盖）；需要 GUI 调试器时再补 |
| 网络 | `dl.google.com` 直连正常；`github.com` 超时 → Gradle 依赖走**镜像** |
| 缺件（本计划要补） | API 36 系统镜像、平板 AVD、（发布用）keystore |

> 复装脚本 `D:\Android\install_sdk.bat`；阶段 0 四条踩坑（winget 脱控制台失败 / cmd 拼参数被空格截断 / compileSdk 必须 36 / 有依赖的命令必须串行）摘要见**附录 A**。

---

## 三、UI 规范（完整界面稿见 `UI_CONFIRMATION_ANDROID.md`）

| 项 | 规范 |
| --- | --- |
| 断点 | `shortestSide < 600dp` = 手机（竖屏单列 / 横屏双栏）；桌面三栏 |
| 竖屏骨架 | 顶栏 56 · 音频/模式行 44 · 主体 flex · 播放条 72 |
| 横屏骨架 | 顶栏 48 · 模式行 44 · 主体（左栏常驻 260dp）· 播放条 64 单行 |
| 显示模式 | 歌词 / 简谱 / 五线谱（**曲谱仅 Windows**） |
| 播放条 | 进度 + 上一首 / 播放暂停 / 下一首；**无音量控件**（系统音量键） |
| 字号 | 标准 1.00 / 大 1.12 / 特大 1.26（全局 `Transform.scale`） |
| 配色 | 晨光蓝 / 暖阳金 / 静谧绿 / 典雅紫 / 暗夜墨（不跟随系统深色） |
| 深色谱面 | 扫描图原色 + 20% 暗化（可切原色 / 反色） |
| 返回栈 | 键盘 → 弹层 → 抽屉（左右互斥）→ 页面栈 → 沉浸态 → 主界面退后台 |
| 触控 | 热区 ≥ 44dp；字号放大不改变控件几何 |
| 无扫描图 | 移动端隐藏简谱/五线谱按钮；无音频时整行隐藏（纯歌词模式） |

## 四、功能实现（阶段 A~F 已完成，工单/验收见 `IMPLEMENTATION_PLAN.md`、进度见 `STATE.md`）

- **A 最小可跑**：API 36 · `WindowControls` 抽象 · 4 flavor · 首个 APK
- **B 数据链路**：DB 首启拷贝（474 首）· 扫描图按显示宽解码 · `state.json` 冷启动恢复
- **C UI 移动化**：竖屏壳 / 横屏双栏 / 双抽屉 / 三模式 / 搜索 / 设置 / 手册 / 歌单
- **D 系统集成**：音频焦点 · 媒体通知 + 锁屏 + 后台播放 · 媒体键
- **F 发布**：正式签名 · 主体 APK + installer 数据包 · 发布清单 · tag

## 五、代码管理

### 5.1 分支策略

```text
main                      ← Windows 主线（v1.8.0 已发布），Android 分支自其切出；合并回 main 需 Windows 侧零退化
├── android/phone         ← 📱 手机版（当前主线，先做）       ← 本次目标
│     └── android/tablet  ← 平板版（手机版验收点后再切）
└── （Windows 修 bug）     ← 如需在 main 修 Windows bug，用 fix/win-* 分支，再 rebase 到 android/phone
```

| 规则 | 内容 |
| --- | --- |
| **切出点** | `android/phone` 自 `main` 的 v1.8.0 提交（`e8b893a`）切出；`android/tablet` 自 `android/phone` 的**手机版验收 tag** 切出 |
| **合并方向** | `android/*` → `main` **只允许「Windows 零退化」的提交**（共用代码修复）；布局壳类提交**不回 main** |
| **共享修复** | 数据/服务层 bug 在 `android/phone` 修好后 **cherry-pick 回 `main`**；避免 main 落后 |
| **提交粒度** | 一个任务（A1/A2/…）一个提交；提交信息带阶段号，如 `feat(android-A2): WindowControls 抽象与移动 stub` |
| **禁止** | 不在 `main` 上直接做 Android 布局改动；不用长生命周期的 `dev` 分支（两分支已是并行最小集） |
| **变体不进分支** | 音频变体（**full / piano / vocal / lite**）**不新建 Git 分支**：用 Gradle flavor（`applicationIdSuffix`）+ `--dart-define=AUDIO_VARIANT` 区分 → 仍是 2 个分支（phone / tablet）、每分支 3~4 个构建产物；差异只在「外壳条件渲染 + 打包白名单 + 裁剪 DB」 |
| **变体差异的写法** | 允许 `if (kAudioVariant == AudioVariant.lite)` 仅出现在**外壳 UI**（播放条/版本行/设置分组）与**打包脚本**；服务层（`AudioService` 等）用抽象 + stub（同 `WindowControls` 范式），**禁止**在业务逻辑里散落变体判断（风险 R12） |

### 5.2 目录与平台化改造原则

| 原则 | 做法 |
| --- | --- |
| **共核** | `lib/{models,services,data,theme}/` **两平台零分叉**（若必须分叉 → 抽象 + 条件导入，不写 `if (Platform.isAndroid)` 散点） |
| **外壳分层** | `lib/screens/desktop/`（现 `home_screen.dart` 归档）+ `lib/screens/mobile/`（新）+ 共享 `lib/widgets/`；`main.dart` 只做「按平台/宽度选壳」 |
| **断点判定** | 用**宽度**（`MediaQuery.size.width < 600`）而非设备型号；平台判定只用 `AppPaths.isMobile` 一处 |
| **条件导入范式** | 沿用项目既有手法（`chinese_convert_service.dart` + `_stub.dart` + `_native.dart` 三件套），`WindowControls` 照此办理 |
| **桌面不退化清单** | 每次改共用文件后必跑：`flutter analyze` + `flutter test` + Windows 实机一次（关键路径：播放/切模式/换肤/搜索） |

### 5.3 版本号与提交规范

| 项 | 定稿 |
| --- | --- |
| 版本号单源 | `hymn_app/pubspec.yaml`（`version: 1.9.0+1` 起）；Android `versionName` = `1.9.0`、`versionCode` 由 `+N` 提供 |
| Tag 策略 | **每平台一个 annotated tag**：`android-v1.9.0-phone` / `android-v1.9.0-tablet`；**变体体现在发布产物文件名**（`EchoHymn-1.9.0-phone-full.apk` / `-phone-piano.apk` / `-phone-vocal.apk` / `-phone-lite.apk`）——避免 tag 数量爆炸（备选：变体也进 tag，落地时定稿） |
| 提交规范 | 沿用现有 `<type>(<scope>): 中文描述`（`feat` / `fix` / `docs` / `build` / `test` / `chore`） |
| 自动发布 | Windows 的 commit→自动发布链路**不动**（`tools/publish_windows.ps1`）；Android 走**手动触发**脚本（避免每次提交都产 APK） |
| **CI / 构建自动化** | Android 侧**不接 CI**（单人项目 + 内测分发）；等价手段 = `tools/publish_android.ps1` 一键脚本（analyze → test → 生成裁剪库 → 4 变体构建 → 产物与 SHA256 归入 `release/android_*`）；**每次发布前必须手跑一次**（§7.4 第 1 项） |
| 会话日志 | 按 `.clinerules` 强制流程，日志随代码一起提交（`docs/sessions/`） |

### 5.4 与现有工具/文档的关系

| 现有物 | Android 侧处理 |
| --- | --- |
| `tools/publish_windows.ps1`、`build_installer.ps1`、`verify_installer.ps1` | 保持不动；新增 `tools/publish_android.ps1`（§7.2） |
| `tools/import_apk_csv.py`、`jianpu_csv_selftest.py` | 复用（谱面数据源不变，`DEFAULT_APK` 指向 Downloads 副本，实测可用） |
| `installer/`（Inno Setup） | Windows 专用，不参与 Android 构建 |
| `docs/Windows/*` | 不动；Android 新增文档统一进 `docs/Android/` |
| `docs/ruanzhu/`（软著） | 版本随 `pubspec.yaml` 单源；Android 版发布后按需补材料 |

---

## 六、模拟测试

### 6.1 测试矩阵（AVD × 系统版本 × 尺寸）

| 编号 | 载体 | 配置 | 用途 |
| --- | --- | --- | --- |
| V1 | `echohymn_avd`（已有） | Pixel 7 / API 34 / x86_64 | 兼容下限回归（Android 14 行为） |
| V2 | `echohymn_phone36`（新建） | Pixel 7 / API 36 | **主目标**（Android 16：edge-to-edge / 预测性返回 / 前台服务） |
| V3 | `echohymn_small`（按需） | Pixel 5 类 5.0 吋 / API 36 | 小屏 + 三档字号极限 |
| V4 | `echohymn_tablet`（阶段 E） | Pixel Tablet / API 36 | 平板布局（600/840 断点） |
| V5 | 真机 1 台 | Android 13~16 之一 | 真实音频链路（蓝牙耳机 / 后台 / 通知）+ 性能（**有音频版**） |
| V6 | 同 V2/D（**lite flavor**） | Pixel 7 / API 36 + `--dart-define=AUDIO_VARIANT=lite` | **无音频版（可选）**：无播放条/版本行、看谱链路完整、包体校验 |
| V7 | 同 V4（**lite flavor**） | Pixel Tablet / API 36 + 无音频 | 平板无音频版：双/三栏 + 无播放条布局 |
| V8 | 同 V2（**piano flavor**） | Pixel 7 / API 36 + `AUDIO_VARIANT=piano` | **钢琴版**：无版本行、`👥` 消失、`249` 单首角标「替代」、其余 473 首可播 |
| V9 | 同 V2（**vocal flavor**） | Pixel 7 / API 36 + `AUDIO_VARIANT=vocal` | **人声版**：同上，11 首角标「替代」、463 首可播、手册缺口章节正确 |

**命令基线**

```powershell
$adb = 'D:\Android\Sdk\platform-tools\adb.exe'
flutter devices                                  # 确认目标设备（mobile / android-x64）
flutter run -d echohymn_phone36                  # 调试
flutter build apk --debug                        # 产物验证
flutter build appbundle --release                # 发布产物（阶段 F）
& $adb shell am start -n com.echohymn.app/.MainActivity
& $adb logcat -s flutter:*                       # 运行日志
& $adb shell run-as com.echohymn.app ls files/   # 验 DB / state.json 落点
& $adb exec-out screencap -p > shots\phone_x.png # 截图取证（沿用 apk_re_tjc 的取证习惯）
& $adb shell settings put system accelerometer_rotation 0   # 锁竖屏，便于稳定截图
& $adb shell settings put system user_rotation 1            # 旋到横屏（M3 横屏走查用）
```

### 6.2 自动化测试

| 层 | 内容 | 命令 | 基线 |
| --- | --- | --- | --- |
| 单元 / Widget（**复用**） | 现有 6 个 Dart 测试：`jianpu_grid_test` / `jianpu_golden_test` / `hymn_search_service_test` / `font_size_level_test` / `hymn_ref_test` / `playlist_name_test` | `flutter test` | 全绿（Android 分支不许回退） |
| Golden（**复用 + 扩**） | `goldens/jianpu_009.png` 等 3 张；新增手机尺寸（如 412×915 dp）下的曲谱页 golden | `flutter test --update-goldens`（谨慎） | 像素比对 |
| 集成测试（**新增**） | `integration_test/`：启动 → 查库 474 首 → 播样本曲 → 切四模式 → 切配色/字号 → 杀进程重启验状态 | `flutter test integration_test -d echohymn_phone36` | 首条链路通过即建立基线 |
| 数据一致性（**复用桌面工具**） | `tools/jianpu_csv_selftest.py --apk <APK>`（L0 DB↔CSV / L1 列对齐 / L2 网格 dump / L3 实机无障碍树） | `python tools/jianpu_csv_selftest.py --apk "…apk"` | L0 差异 0（已达成） |
| 静态检查 | `flutter analyze`（0 issues 为基线）+ `dart format --set-exit-if-changed` | — | 0 issues |

> **L3 在 Android 上的等价物**：桌面用 uiautomator 无障碍树比对；Flutter Android 侧改用 `integration_test` 的元素级断言（比无障碍树更可靠、可复用 Windows 的期望值）。

### 6.3 手工走查与回归清单

| 清单 | 内容要点 |
| --- | --- |
| **手机版 UI 走查**（新建） | 逐屏：顶栏 / 抽屉（三 Tab）/ 四模式 / 播放条 / 搜索页 / 设置页（含实时预览）/ 手册 / 歌单管理 / 沉浸放大态；**竖屏 + 横屏各走一遍**；每项含「预期 + 实际 + 判定」列 |
| **多尺寸 × 横竖屏 × 字号矩阵** | 5.0 / 6.1 / 6.9 吋 × 竖/横 × 移动版四档（1.00 / 1.10 / 1.20 / 1.30）；横屏必查主体区高度是否够用（§3.1.10 的 ~184dp 口径） |
| **无障碍专项** | 开启 TalkBack 走一遍：播放/暂停/切歌/切模式可达且朗读正确；触控目标 ≥48dp；无"仅颜色"传达的信息（「替代」角标需可朗读） |
| **跨平台回归**（共用代码改动后必跑） | `flutter analyze` 0 issues + `flutter test` 全绿 + **Windows 实机**关键路径（播放 / 切模式 / 换肤 / 搜索 / 歌单）各一次 |
| **手势与系统冲突** | ① 左/右边缘起划 → 只应触发**系统返回**（无抽屉双响应）；② 抽屉打开时系统返回 → 关抽屉；③ 谱面中部捏合缩放正常、双击复位正常；④ 无任何隐藏手势依赖 |
| **系统行为走查** | 返回手势 10 条路径、旋屏、分屏、息屏、通知点击、耳机插拔、来电打断 |
| **数据回归** | 474 首可浏览；分类两级；个人歌单增删改；状态恢复 |
| **变体差异走查** | 无音频版：① 全界面**不出现**播放/进度/音量/版本 chips/`👥`；② 顶栏副行与列表 ● 语义为「当前浏览」；③ 设置页无「播放」分组、有「显示 > 自动翻页间隔」；④ 安装包内**无音频文件**；⑤ 无音频版与有音频版**可同时安装**（双 applicationId） |
| **设计基础走查** | ① **320dp 断点**：顶栏/模式按钮不重叠、热区 ≥44dp；② **深色（暗夜墨）**：简谱/五线谱不刺眼（暗化生效）且仍可读；③ **五态**各触发一次（删素材 / 空歌单 / 无网格 / 搜索无结果）；④ 系统"移除动画"后无卡顿与残影 |
| **曲谱小节分页走查（仅 Windows）** | ① 「第 k/N 页（第 a~b 小节）」与实际页对应；② 同页**同列同 x**；③ 歌词与音符同列；④ 记号不丢（八度点/减时线/延长/小节线）；⑤ 自动翻页与播放进度一致；⑥ 每页小节数 2/3/4 与自适应各验一次 |
| **沉浸式系统栏走查** | ① 默认进入**无系统导航栏**、可临时唤出；② 设置「显示系统导航栏」→ 常驻且 insets 正确（顶栏/播放条不被遮挡）；③ 旋屏、分屏、息屏恢复后系统栏状态不异常；④ 三键导航与手势导航两种设备各验一次 |
| **仅鋼琴版口径走查** | ① 版本行按裁剪库**整行消失**（不出现点不通的 chip）；② 全部 474 首**均可播放**；③ 包体/素材包体积与 §1.4 ④ 的实测口径一致（±5%） |
| **替代音频走查**（钢琴版 / 人声版各一次） | ① **全部 474 首均可播放**（无"点不动"的曲目）；② 列表「替代」角标仅出现在替代曲目上（钢琴版 1 首 `249`、人声版 11 首 = `3`/`389` + 9 首，与 §1.4 ⑤ 逐条对齐）；③ 点击替代曲目**正常出声**（人声版 `3`/`389` 为四部合唱音色、其余 10 首为钢琴音色；钢琴版 `249` 为人声音色）+ 首次 Toast；④ 替代曲目的歌词/曲谱/简谱/五线谱照常可用；⑤ 手册「关于本版音频」清单与 App 内角标数**一致**；⑥ **App 内无任何"改用另一个版本"的跳转指引** |
| **自测脚本** | `tools/` 里新增 `android_smoke.ps1`（可选）：一键 `flutter analyze` + `flutter test` + 装包 + 启动 + 截图 |

### 6.4 性能与质量指标（出口条件）

| 指标 | 目标 |
| --- | --- |
| 冷启动到首屏 | ≤ 3s（中端机） |
| 曲谱网格滚动 | ≥ 55 FPS（不需要 60 满帧，但不得明显掉帧） |
| 扫描图（≈2000px 宽 PNG）打开 | ≤ 800ms，且**不 OOM**（走 `cacheWidth`） |
| 常驻内存 | 播放中 ≤ 250MB |
| 后台播放 30 分钟 | 不被系统杀；耗电可接受（对比系统音乐 App 同量级） |
| 崩溃 | 主流程 0 崩溃；`flutter run` 无未捕获异常 |

---

## 七、软件发布

### 7.1 签名与 keystore（阶段 F 前置）

| 项 | 定稿 |
| --- | --- |
| keystore 生成 | `keytool -genkeypair -v -keystore echohymn-release.jks -alias echohymn -keyalg RSA -keysize 4096 -validity 10950` |
| 存放 | **仓库外**（如 `D:\Android\keystore\`）+ 备份；**绝不入库** |
| 配置 | `android/key.properties`（`storeFile` / `storePassword` / `keyAlias` / `keyPassword`）→ `key.properties` 入 `.gitignore`，`build.gradle.kts` 读它做 `signingConfigs.release` |
| 校验 | `apksigner verify --print-certs <apk>`；同一 keystore 后续所有版本（升级必须同签名） |
| 风险 | keystore 丢失 = 无法升级已发布应用 → 至少两处离线备份（对齐 Windows 发布规范里「产物留档」的谨慎度） |
| 变体与包名 | 4 变体共需 **4 个 `applicationId`**（`com.echohymn.app` / `.lite` / `.pad` / `.pad.lite`）；可用**同一个 keystore**签所有变体（也可为变体单独建）——同一 applicationId 的后续版本必须同签名 |

### 7.2 构建产物与发布脚本

| 产物 | 命令（`<V>` = `full` / `piano` / `vocal` / `lite`） | 用途 |
| --- | --- | --- |
| **APK（分 ABI · 全量音频）** | `flutter build apk --release --split-per-abi --flavor full --dart-define=AUDIO_VARIANT=full` | 对标 Windows 功能全集（474 首可播） |
| **APK（分 ABI · 钢琴版）** | `… --flavor piano --dart-define=AUDIO_VARIANT=piano` | 473 首本版音频 + 1 首替代（249） |
| **APK（分 ABI · 人声版）** | `… --flavor vocal --dart-define=AUDIO_VARIANT=vocal` | 463 首本版音频 + 11 首替代（手册说明） |
| APK（分 ABI · 无音频版，可选） | `… --flavor lite --dart-define=AUDIO_VARIANT=lite` | 只读谱/歌词 |
| **AAB**（各变体） | `flutter build appbundle --release --flavor <V> --dart-define=AUDIO_VARIANT=<V>` | 上架 Google Play（如走商店） |
| APK（通用，去 `--split-per-abi`） | 同上 | 兼容性兜底 |
| **发布变体矩阵** | 手机 × {full, piano, vocal(, lite)} = **3（或 4）个产物**；平板同构 | 见 §1.4 ⑤ |
| 新脚本 | `tools/publish_android.ps1`（规划） | 一键：`flutter analyze` → `flutter test` → 构建 → 产物归入 `release/android_<时间戳>_<短哈希>/` → 生成 `SHA256SUMS.txt` + 写 `release/android-release.log`（体例对齐 `release/auto-release.log`） |
| 版本号 | 取 `pubspec.yaml`（`1.9.0+1`） | 单一来源，不手改 Gradle |
| 16KB 校验 | `flutter build apk --analyze-size` + `zipalign -c -P 16 -v 4 <apk>` | 满足 Play 2025-11 起要求 |

### 7.3 分发渠道与内测策略

| 阶段 | 渠道 | 说明 |
| --- | --- | --- |
| 内测（推荐起步） | **APK 侧载**（本机 / 局域网 / 网盘）+ 真机 1~3 台 | 无审核、无体积限制；素材随包或独立导入 |
| 内测（**两变体并测**，2026-10-11 追加） | **有音频版** APK + **无音频版** APK 各一份（文件名带 `-lite` 后缀，如 `EchoHymn-1.9.0-phone-lite.apk`） | 同一批测试者对比两变体；无音频版体积 ≈1/6（0.52GB vs 2.95GB） |
| 灰度 | 华为 / 小米 / OPPO / vivo 应用市场（分渠道包） | 需软著/版权材料、隐私政策、备案（国内上架合规链最长） |
| 国际 | Google Play（AAB + Play Asset Delivery） | **素材体积与版权是硬门槛**（见 §7.5 与风险表） |

> **合规提示**：素材含**第三方扫描谱面/音频**（源自赞美诗网站抓取），公开上架存在版权风险 → **内测/私域分发优先**；上架前须逐项评估授权（此项列为发布前**强制评审点**）。

### 7.4 发布前验证基线（对齐 Windows `RELEASE_RULES.md` 精神，Android 版）

- [ ] `flutter analyze` = 0 issues；`flutter test` 全绿（含 golden）
- [x] 手机版走查清单全过（§6.3），三档字号 × 五视口（15/15，`overflow=0`）
- [ ] 冷启动 / 播放 / 切模式 / 搜索 / 歌单 / 状态恢复 六条主链路真机通过
- [ ] 后台播放 + 媒体通知 + 音频焦点 通过（阶段 D 出口条件）
- [ ] APK 安装 → 升级安装（同签名）→ 卸载 三步走通
- [ ] `applicationId` / `versionName` / `versionCode` / 图标 / 应用名 与发布说明一致
- [ ] **变体核对**：4 个 `applicationId` 各就位；**无音频版包内无音频文件**（白名单校验）；两变体可同时安装；无音频版全界面无播放相关图标
- [ ] **无音频版专属**：自动翻页（定时）可用或明确关闭；「当前浏览」语义在顶栏/列表/源考三处一致
- [ ] **替代音频核对（钢琴版 / 人声版）**：发布前用**裁剪脚本**生成库并逐首核对——**474 首全部可播**；替代键已改写为本版名（人声版：`3`/`389`→四部合唱版、9 首→鋼琴版；钢琴版：`249`→人聲版）；App 内「替代」角标数 = 手册清单数（钢琴版 **1** / 人声版 **11**）
- [ ] 16KB page size 校验通过（如目标 Play）
- [ ] 产物 SHA256 留档；`release/android-release.log` 记录（时间/提交/产物/大小）
- [ ] 会话日志与文档更新（`STATE.md` 阶段状态、`docs/sessions/` 会话日志）

### 7.5 素材（3.38GB）分发方案（关键决策点）

**定稿（2026-11-13 用户最终方案 · 主体 + 数据包）**：

**主体 APK（release 唯一产物，≈56 MB）**：程序 + 数据库，**不含任何素材**；安装后首启按**前十首**检测
「扫描图 / 人声 / 钢琴」是否存在，运行期决定 UI 形态（全量 / 钢琴 / 人声 / 读谱）——不再用 Gradle flavor 区分 UI。

**installer 产物（`installer/output/android/`）**：

| 文件 | 内容 | 体积 |
| --- | --- | --- |
| `EchoHymn-v<ver>.apk` | 主体（程序 + DB） | ≈56 MB |
| `scores-0-237.zip` / `scores-238-474.zip` | 扫描图（简谱 + 五线谱 PNG） | 237.8 / 249.9 MB |
| `vocal-0-237.zip` / `vocal-238-474.zip` | 人聲版 + `3`/`389` 四部合唱 + 9 首鋼琴替代 | 229.6 / 684.6 MB |
| `piano-0-237.zip` / `piano-238-474.zip` | 鋼琴版 + `249` 人聲替代 | 545.2 / 600.7 MB |

- 每个包均 **< 2 GB**（规避 APK 2GB 上限），按诗歌序号前半（1–237）/ 后半（238–474）拆分。
- 导入入口：**首启引导页** + **设置 → 数据导入（压缩包）**（扫描图 / 人声 / 钢琴各一个按钮）。
- 导入规则（用户 2026-11-13）：**只接受** `Hymn_Downloads/<目录>/<编号>_<类型>.<ext>` 且属于本类别的文件，
  同名**覆盖**，规则外**一律丢弃、不写入存储**；解压走 Kotlin 流式 `ZipInputStream`，带路径穿越防护。
- 脚本：`tools/build_android_media_packs.py`（6 包）+ `tools/build_android_installer.ps1`（APK + 包 + SHA256SUMS + BUILD-INFO）。
- `installer/output/` 已按平台分层：`windows/`（既有 Inno 产物）与 `android/`（本方案）。

**完整性与校验（2026-11-16 追加，方案 A + 自检）**：

- 每个 zip 的**第一个条目**是 `ECHOHYMN-MANIFEST.json`：包内每个文件的 `path / sha256 / bytes`
  （哈希优先取自原始素材目录的 `checksums.json`，缺失则打包时现算）。
- App 导入：**逐文件**边解压边算 SHA-256 → 与清单比对 → 不符则删临时文件、计入「校验失败」、**不落盘**；
  清单副本保存到 `files/pack_manifests/<name>.json`。
- **设置 → 素材自检**：按已保存清单全量核对**存在性 + SHA-256**，报告 正常 / 缺失 / 损坏（前 20 条明细）。
- 包外 `<name>.json` 仍保留**整包 SHA-256**（分发侧可先验整包）；`SHA256SUMS.txt` 覆盖 APK + 6 包。

> **落地口径**：阶段 B 走 **A**（样本 10~20 首，跑通全链路）；发布阶段按**内测**走 A + 可选手动导入完整素材；商店方案推迟到版权明确后。

**按变体的资产清单（2026-10-11 追加，实测体积）**

| 变体 | APK 内置（2026-11-13 定稿） | 首启迁移 | 合计 |
| --- | --- | --- | --- |
| 📱 **全量音频版** | **鋼琴版 + 人聲版**音频（不含合唱类）+ 全部 PNG + DB + 字体 | `MediaBootstrap` 复制到 `files/Hymn_Downloads/` | ≈ **2.52 GB** |
| 📱 **钢琴版** | `*_鋼琴版.*` + `249_人聲版.*`（替代）+ 全部 PNG + DB + 字体 | 同上 | ≈ **1.68 GB** |
| 📱 **人声版** | `*_人聲版.*` + `3`/`389` 四部合唱版 + 9 首鋼琴版（替代）+ 全部 PNG + DB + 字体 | 同上 | ≈ **1.45 GB** |
| 📱 **无音频版（读谱版）** | 全部 PNG + DB + 字体（**不含音频**） | 同上 | ≈ **0.55 GB** |

> **打包白名单（2026-11-13 定稿）**：**全量版** = `*_鋼琴版.*` ∪ `*_人聲版.*` ∪ `3_四部合唱版.*` ∪ `389_四部合唱版.*` ∪ `.png`（**不含其它合唱类**）；**钢琴版** = `*_鋼琴版.*` ∪ `249_人聲版.*` ∪ `.png`；**人声版** = `*_人聲版.*` ∪ `3_四部合唱版.*` ∪ `389_四部合唱版.*` ∪ 9 首鋼琴版（`103/107/178/255/268/274_b/308/386/387`）∪ `.png`；**无音频版** = `.png`；四者均**排除** `.pdf / .exe / .mp4 / .txt / checksums.json`。脚本：`tools/sync_audio_samples.ps1 -IncludeAll -Variant <v>`。
> **配套（2026-11-13 修订）**：DB **不裁剪**——单音频版的版本行在 UI 已隐藏（`kSingleAudioVariant`），替代由 `AudioService.substitutionOrder()` 在运行时按变体优先级完成（人声版 `3`/`389` → 四部合唱版、其余 9 首 → 鋼琴版；钢琴版 `249` → 人聲版），已用 `tools/verify_hymn_media_coverage.py` 逐首核对 **474/474**。手册按 §1.4 ⑤ 列明替代清单即可。

---

## 八、风险清单与缓解

| # | 风险 | 影响 | 缓解 |
| --- | --- | --- | --- |
| R1 | **`echo_hymn/window` 通道在 Android 抛异常** | 启动崩溃（P0） | 阶段 A2 **先做** `WindowControls` 抽象 + stub；启动即验 |
| R2 | Gradle 依赖走 `services.gradle.org` / `github.com` 超时 | 构建失败 | `gradle-wrapper.properties` 换镜像（腾讯/华为）+ `settings.gradle.kts` 仓库镜像；首次构建慢就错峰 |
| R3 | `targetSdk 36` 新行为（edge-to-edge / 预测性返回）未适配 | UI 重叠、返回异常 | §1.1 五项硬要求逐条纳入阶段 C/D 任务；V2（API 36）为**主测试载体** |
| R4 | 素材 3.25GB 无法随包（APK 上限约 2GB） | full 全内置不可行 | **2026-11-13 实测**：full 2.52GB APK 构建成功但 `adb install` **失败**（v2/v3 签名 32 位偏移上限）→ full 保持「样本 + SAF」；**piano/vocal/lite 全内置可行**（1.68 / 1.45 / 0.55 GB） |
| R5 | 大图（2000px 扫描谱）内存溢出 | 闪退 | `cacheWidth` 按屏宽解码 + 单页缓存（离开即释放）+ 真机内存走查 |
| R6 | 安卓碎片化（厂商音量/后台策略激进） | 后台播放被杀、音量行为不一致 | 前台服务 + 媒体通知（系统级保障）；在 2~3 个厂商真机上复核；音量走系统通道并保留应用增益退路 |
| R7 | 中文/繁体、空格路径在 Android 侧异常 | 音频加载失败 | 沿用 `DeviceFileSource` 直传路径（Windows 已证明有效）；阶段 B4 专项复测 |
| R8 | 两分支代码漂移 | 维护成本翻倍 | §5「共核 + 差异外壳」；禁止在 `lib/{models,services,data}` 里写平台分支散点；共用文件改动必跑桌面回归 |
| R9 | 版权/合规（扫描谱面与音频来源） | 无法公开上架 | 内测/私域优先；上架前强制评审（§7.3 合规提示） |
| R10 | keystore 丢失 | 无法升级已发布版本 | 仓库外 + 两处离线备份；发布前检查 `key.properties` 不入库 |
| **R11** | **素材目录被杂物污染**（实测 `_misc/` 内有 `Clash.…setup.exe` 44.8MB、`.mp4`、`.txt`） | 误入安装包 → 体积/合规问题 | 打包脚本按**扩展名白名单**取件（§1.4 / §7.5）；产物校验脚本扫描非白名单扩展名即报错（B8） |
| **R12** | **变体分叉导致代码腐化**（`if (kAudioVariant == AudioVariant.lite)` 到处散落） | 两变体行为不一致、维护翻倍 | 变体判断**只允许出现在外壳 UI 与打包脚本**；服务层走抽象 + stub（§5.1 条款）；走查表含「变体差异走查」专项（§6.3） |
| **R13** | **隐藏系统导航栏导致"退不出去"**（完全无系统栏 → 用户不知如何返回/回桌面）；部分 OEM 对沉浸模式有限制 | 用户困惑 / 无法操作 | 设置页必备「显示系统导航栏」开关（默认隐藏但一键可恢复）；手册新增「如何返回」说明；走查覆盖"临时唤出 → 恢复常驻" |
| **R14** | **只留鋼琴版但漏裁 DB** → 版本行露出点不通的空版本 | 点「人聲版」→ `Loading interrupted`（Windows 已有同类 NG 记录 C14） | 发布脚本把「DB 裁剪」列为**强制步骤**并与素材白名单同批校验（B8 扩展）；裁剪库需跑 `flutter test` 回归（版本行消失、钢琴版可播） |
| **R15** | **单音频版使用"替代音频"**（人声版 11 首 / 钢琴版 1 首）引发音色疑问或"是不是弄错了"的反馈 | 用户困惑：明明是人声版 app，怎么这首是钢琴声 | ① 列表**角标「替代」**+ 首次点击 Toast 说明；② **手册「关于本版音频」列全替代清单与来源**（并注明云端确无对应音频）；③ 裁剪库把替代**改写为本版版本名**（UI 无版本行、无特殊分支）；④ 清单由**实测脚本**产出（按 DB `audio_versions` 路径逐首核对），不得手抄；⑤ 若日后取到真·人声版，只需更新库与素材包即可消除替代 |

---

## 九、「跑的是 Android 而非 Windows」判定范式（沿用阶段 0 口径）

- **构建目标**：`flutter devices` 列出 `emulator-5554 / echohymn_phone36`（`mobile · android-x64`），`flutter run -d <id>` 产物为 `.apk`
- **运行时**：画面出现在 Android 虚拟手机系统内（状态栏 / 返回手势 / 通知栏均为 Android），与 `echo_hymn.exe` 窗口无关
- **代码层**：`AppPaths.isMobile == true`（mobile 分支生效）；`echo_hymn/window` 通道经条件导入**不参与 Android 编译**

---

## 十二、数据与内容治理

### 12.1 数据管线

```text
APK assets/NNN.csv ──tools/import_apk_csv.py──▶ jianpu_score / jianpu_row / jianpu_cell
Hymn_Downloads/<曲目>/ ──checksums.json──▶ 素材完整性基线
歌单与分类 ──hymn_category.hymns(JSON)──▶ 默认歌单（一级 13 / 二级 47 / 成员 474）
曲目主数据 ──tjc_hymn（含 audio_versions / audio_durations / *_png_path / api_raw）──▶ App
```

### 12.2 基线与门禁（每轮增补后必跑；缺一即阻断发布）

| 项 | 基线（2026-10-11 实测） | 校验手段 |
| --- | --- | --- |
| `tjc_hymn` | **474 首** | `select count(*)` |
| `jianpu_score` / `jianpu_row` / `jianpu_cell` | **474 首 / 21819 行 / 321703 格** | `python tools/jianpu_csv_selftest.py`（L0 行/格差异 0） |
| `hymn_category` 成员 | **474**（一级 13 / 二级 47） | 解析 `hymns` JSON 计数 |
| 各曲目目录 `checksums.json` | **全量 PASS** | 逐条重算 SHA256 |
| 音频覆盖 | 鋼琴版 **473** / 人聲版 **463**（库 474） | 按 `audio_versions` 路径逐首 `exists` |

### 12.3 变体裁剪库（阶段 F 必做）

| 项 | 说明 |
| --- | --- |
| 脚本 | `tools/build_android_variant_db.py`（规划）：读主库 → 按变体改写 `audio_versions`（**替代键改写为本版版本名**，如人声版下 `3` → `{"人聲版": "…/3_四部合唱版.m4a"}`）→ 输出 3 份裁剪库 |
| 配套 | 与素材白名单（§7.5）同批生成；产物随 APK/素材包分发 |
| 验收 | 裁剪库下**全曲目可播**、**版本行不出现**；主库不受影响 |

### 12.4 版权与授权台账（与 §十三 联动）

| 素材 | 来源 | 授权状态 | 影响 |
| --- | --- | --- | --- |
| 歌词 / 源考文本 | 赞美诗网站抓取 | ⚠️ 未明确 | 公开上架受限 |
| 音频（鋼琴版 / 人聲版 / 四部合唱版 / 分声部） | 同上 | ⚠️ 未明确 | 同上 |
| 扫描谱面（简谱 / 五线谱 PNG·PDF） | 同上 | ⚠️ 未明确 | 同上 |
| 字体（NotoSansSC / 标楷体 / MMP2005 子集） | OFL / 印刷件内嵌子集 | ⚠️ 后两者需评估 | 内测无碍 |
| 谱面网格数据（CSV 模型） | 第三方 TJC 应用 | ⚠️ 仅作**数据模型参考** | 不分发其原始文件 |

> **口径**：**内测 / 私域分发优先**；公开上架前逐项落实授权（§7.3 合规提示）。

---

## 十三、安全与合规

| 项 | 定稿 |
| --- | --- |
| **隐私政策** | **必备**（即使无账号、不联网）：声明"不收集任何个人信息；权限仅用于播放服务"；随 APK 内嵌（手册/关于页）+ 商店页面同步 |
| **权限矩阵** | `POST_NOTIFICATIONS`（媒体通知，运行时申请）· `FOREGROUND_SERVICE` + `FOREGROUND_SERVICE_MEDIA_PLAYBACK`（后台播放）· **不申请任何存储权限**（素材在应用私有目录）· 若走在线分发再评估 `INTERNET` |
| **签名密钥** | keystore 存**仓库外** + 两处离线备份；`key.properties` 入 `.gitignore`；发布前校验签名一致性（§7.1） |
| **上架材料** | 软著（`docs/ruanzhu/`）· APP 备案（国内渠道）· **版权授权**（§12.4）——三者齐备才可公开上架 |
| **入参安全** | 对齐 Windows `docs/Windows/CODE_REFERENCE.md` 的 SEC 风险表：SQL 参数化、路径拼接校验、JSON 容错解析、越界与空值防护 |
| **数据安全** | `state.json` 原子写（既有）；DB 只读打开（`file:…?mode=ro`）；**不落任何用户隐私数据** |
| **变体隔离** | 4 变体各自 `applicationId` → 私有目录天然隔离，互不污染 |
| **发布前强制评审点** | ① 版权/授权状态（§12.4）；② 权限最小化核对；③ keystore 备份与签名校验；④ 隐私政策随包 |

---

## 十四、运维与反馈闭环（发布之后）

| 项 | 定稿 |
| --- | --- |
| **日志导出** | `LogService` 落应用私有目录 → 「设置 · 关于」提供**导出日志**（分享/复制路径）；排障范式：`adb logcat -s flutter:*` + `adb shell run-as com.echohymn.app ls files/` |
| **崩溃捕获** | `FlutterError.onError` + `PlatformDispatcher.onError` → **本地落盘**（崩溃日志与普通日志分离）；**不做联网上报**（隐私友好，内测期足够） |
| **更新机制（内测期）** | 手动分发 APK（文件名带变体后缀）+ 「关于」显示 `versionName（build）`；后续如需应用内检查更新再评估服务端 |
| **回退预案** | 保留上一版 APK 与 SHA256；DB **schema 版本戳**（升级前备份 `state.json`）；数据不兼容时给出降级说明；发布包可整体回滚 |
| **内测反馈表** | 一列到底：`问题 → 复现步骤 → 影响变体（full/piano/vocal/lite）→ 结论（BUG / 需求 / 环境）→ 修复提交 → 复测结果` |
| **长期基线归档** | 每版本记录：产物 SHA256 + 数据基线（474 / 21819 / 321703）+ 走查结论 → 写入 `release/android-release.log`（体例对齐 `release/auto-release.log`） |
| **知识回流** | 决策同步 `docs/Android/STATE.md` 与 `docs/sessions/`；UI 口径同步 `UI_CONFIRMATION_ANDROID.md`；数据口径同步 §12.2 |

---
