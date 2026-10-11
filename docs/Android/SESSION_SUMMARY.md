# EchoHymn Android 开发总结（2026-09-11 立项 ~ 当前）

> 本文档是 **Android 平台开发总结**（里程碑 / 决策 / 教训留档），供新会话续接 Android 开发时阅读。
> **路线图与阶段任务以同目录 [ANDROID_PLAN.md](ANDROID_PLAN.md) 为准**（2026-10-11 重订版：手机 / 平板双分支 + 阶段 A~E + 里程碑 M0~M6；含目标系统基线、基线盘点、UI 设计、功能实现、代码管理、模拟测试、软件发布、风险清单），本文档不重复搬运，只记"发生过什么、为什么、结论是什么"。
> Windows 主线总结见 `docs/Windows/SESSION_SUMMARY.md`（跨平台工程史主档）。

---

## 一、里程碑

| 日期 | 提交 | 内容 |
| --- | --- | --- |
| 2026-09-11 | （立项会话） | **Android 移植立项**：确立"开发环境全家部署 D 盘（`D:\Android`）+ 官方模拟器 AVD 调试"路线；移植计划落档 `ANDROID_PLAN.md`（初版分四阶段：环境 → 最小可跑 → 数据链路 → UI 移动化；**2026-10-11 已重订为阶段 A~E 双分支版**） |
| 2026-09-11 | `c94bcfb` | **阶段 0 环境搭建完成**：纯命令行工具链（弃 Android Studio GUI）、Microsoft OpenJDK 17、AVD `echohymn_avd`（Pixel 7 / API 34）冷启动成功；`flutter doctor` Android toolchain 全绿，`flutter devices` 可见 `emulator-5554` |
| 2026-10-11 | （本次会话，未提交） | **计划重订：手机 / 平板双分支（手机优先）** —— `docs/Android/ANDROID_PLAN.md` 重写为「UI 设计 / 功能实现 / 代码管理 / 模拟测试 / 软件发布」五环节 + 阶段 A~E + 里程碑 M0~M6；立项初版归档为 `ANDROID_PLAN_2026-09-11_初版.md`。同时核实：TJC 参考 APK 现存 `E:\真教会\赞美诗\com.tinanlin.tjc_hymn_cn_v2.4.2.apk`（23.50MB，1522 条目 / `assets/` 994 个），并已补 Copies 到 `~/Downloads` 使 `tools/import_apk_csv.py` 默认路径可用（实测 `--check` 通过） |

## 二、阶段 0 环境操作记录（要点存档，实况细节以 ANDROID_PLAN.md 为准）

- **工具链选型决策**：Android Studio GUI **不安装**——官方新版安装器为 CrossInstall 框架、不支持静默指定安装目录，且模拟器全链路（sdkmanager / avdmanager / emulator）命令行即可覆盖；后续如需 GUI 调试器再手动补装，不阻塞开发。
- **落盘布局**：SDK ≈5.9GB → `D:\Android\Sdk`（cmdline-tools/latest + platform-tools 37.0.1 + platforms 34/36 + build-tools 34/36 + emulator 37.1.11 + 系统镜像 34 google_apis x86_64）；AVD → `D:\Android\avd`；JDK → `D:\Java\jdk-17.0.20.1+1`（ZIP 免管理员）；User 级环境变量 `ANDROID_HOME` / `ANDROID_AVD_HOME` / `JAVA_HOME` + PATH；`flutter config --android-sdk D:\Android\Sdk`。
- **验证口径**：`flutter doctor` 全绿 + `flutter devices` 出现 `sdk gphone64 x86 64 (mobile) • emulator-5554 • android-x64 • Android 14` + adb `sys.boot_completed=1`。
- **复装备用**：`D:\Android\install_sdk.bat`（sdkmanager 一键复装脚本）。
- **踩坑教训**（复装必读，全文见 ANDROID_PLAN.md「阶段 0 踩坑记录」）：① winget 脱离控制台安装失败——安装类操作一律前台跑；② cmd 拼参数被空格截断曾致组件装错位置——复装走独立 .bat；③ Flutter 3.44 要求 **compileSdk 36**，只装 API 34 镜像不够；④ 有依赖关系的命令必须串行，并行工具调用不保顺序。
- **运行时判定范式**（防"以为在跑 Android 其实跑的是 Windows"）：构建 target（`flutter devices` + `.apk` 产物）/ 运行时系统（虚拟手机画面）/ 代码层（`Platform.isAndroid`，即 `AppPaths.isMobile` 分流依据）三层确认。

## 三、Windows 主线已做的 Android 铺垫（跨平台决策溯源）

以下决策出自 Windows 主线会话（源见 `docs/Windows/SESSION_SUMMARY.md` 对应行），对 Android 移植直接有效：

| 铺垫 | 出处（Windows 总结） | 对 Android 的意义 |
| --- | --- | --- |
| **内置字体 EchoSans**（Noto Sans SC 子集，OFL，真 400/500/700） | v1.5.0 方案 B×2（`ca00532`+`4ffe140`） | 字体自足不依赖目标机器，迁移/Android/鸿蒙渲染一致 |
| **音量模型 `_systemVolumeAvailable` 自动退化**：无系统音量通道的平台退化为应用增益模式 | v1.5.x 音量模型修复 | Android 音频链路预留完成，接入即测 |
| **简繁转换纯 Dart 查表 + 日志/状态纯 Dart**（`state.json` 原子写 + `AppStateService.shared` 全进程唯一串行队列） | v1.1.0 / v1.5.2 稳健性修复 | 无平台插件依赖，Android 侧只需验证 `AppPaths` mobile 分支落点 |
| **目标平台定稿：Windows + Android + 鸿蒙，Web 移除** | `67e1bab`（v1.0.2） | Android 为一等目标平台 |

## 四、当前进度与待办（2026-10-11 重订口径：阶段 A~E / 里程碑 M0~M6）

- ✅ 阶段 0：环境搭建（2026-09-11 完成，`flutter doctor` 全绿）
- ✅ **M0 计划封版（2026-10-11）**：手机 / 平板双分支（手机优先）计划落档，立项初版归档
- ⬜ **阶段 A / M1 最小可跑**：补 `system-images;android-36;google_apis;x86_64` + AVD `echohymn_phone36`；**`WindowControls` 抽象**（`home_screen.dart:27` 与 `audio_service.dart:12` 两处硬编码 `echo_hymn/window` 通道必须条件导入隔离，否则 Android 启动必崩）；`applicationId` → `com.echohymn.app`；`compileSdk`/`targetSdk` **36** + `minSdk` 26
- ⬜ 阶段 B / M2 数据与素材链路：`tjc_hymn.db`（25.53MB）asset 首启拷贝 → `getApplicationSupportDirectory()`；`state.json` mobile 分支验证；素材（3378.9MB / 3682 文件）走「样本内置 + 外部导入（SAF）」两步
- ⬜ 阶段 C / M3 UI 移动化（工作量主体）：顶栏 56 + 版本行 + 模式 TabBar + 主体 + 播放条 64；左右双抽屉；四模式页（歌词/曲谱网格/简谱·五线谱扫描图）；搜索全屏页；设置页；歌单全屏页；手册移动版；多尺寸 × 四级字号走查
- ⬜ 阶段 D / M4 系统集成：音频焦点（`audio_session`）、媒体通知 + 锁屏、前台服务（`foregroundServiceType="mediaPlayback"`）、媒体键/耳机线控、预测性返回手势、生命周期保活
- ⬜ 阶段 F / M5 手机版发布：keystore + `key.properties`、`tools/publish_android.ps1`、§7.4 发布前清单、`android-v1.9.0` tag
- ⬜ 阶段 E / M6 平板分支（`android/tablet`，手机版验收后启动；断点 `<600` / `600~839` / `≥840` dp）
- 遗留确认：`minSdk` 最终值（建议 26）、素材商店方案与**版权评审**（上架前强制项）

> 完整任务清单、风险与缓解措施：见 [ANDROID_PLAN.md](ANDROID_PLAN.md)（**2026-10-11 重订版**，含 UI 设计 / 功能实现 / 代码管理 / 模拟测试 / 软件发布 五环节）；
> 立项初版全文（阶段 0 全流程实况与踩坑原文）见 [ANDROID_PLAN_2026-09-11_初版.md](ANDROID_PLAN_2026-09-11_初版.md)。

## 五、更新记录

- 2026-09-13：本文档建立（docs 按平台归档拆分——自 `docs/Windows/SESSION_SUMMARY.md` 抽取 Android 关联内容并汇总立项以来的操作留档）。
- 2026-10-11：里程碑新增「计划重订（手机 / 平板双分支，手机优先）」；进度口径由「阶段 0~3」改为「阶段 A~E / 里程碑 M0~M6」（初版计划归档为 `ANDROID_PLAN_2026-09-11_初版.md`）；同日细化 §3.1 UI 设计稿（竖屏 9 张 + 横屏 2 张 + 沉浸态 1 张 + 手势/横竖屏策略）、**移动版字号档位重定为 1.00/1.10/1.20/1.30（不照搬 Windows 的 1.0/1.3/1.6/1.9）**、确立「不注册边缘手势、全部图标点击」与「设置页集中调整 + 实时预览」两项定稿。
- 2026-10-11（追加）：确立 **有音频版 / 无音频版双变体**（2 平台分支 × 2 变体 = **4 个发布变体**）—— 新增 §1.4（变体矩阵 / 资产实测：有音频 ≈2.95GB、无音频 ≈0.52GB / 功能差异 / 实现方式）与 §3.1.15（无音频版三张设计稿）；**变体不进 Git 分支**，用 Gradle flavor + `kHasAudio` 区分；新增任务 A6/B7/B8/C12/E6，风险 R11/R12。
- 2026-10-11（追加 2）：**更正上一版错误表述**（「Android 无法自动翻页」→ 实为「无音频版无播放进度」；有音频版 Android 与 Windows 同源同效）；查证进度链条（`audioplayers.onPositionChanged` → `_positionCtrl` → `_applyAutoPage` → `autoPageIndexFor` + DB `audio_durations`）并落档；「当前播放」定性为**语义漂移（只改 UI 文案、`state.json` 字段不动）**；底部导航条定稿为「**双态 + 响应系统导航键**」（有导航键→底部放条；手势导航→一条不占全给主体区），判定三层（原生 `navigation_mode` → `MediaQuery` insets → 用户设置兜底）；无音频版自动翻页推荐 **方案 C（虚拟进度复用 `autoPageIndexFor`）**；新增任务 **A7**。
- 2026-10-11（追加 3）：**实测音频共 11 种版本**（鋼琴版 473/1145.4MB、人聲版 461/884.8MB、四部合唱版 47/118.1MB、合唱与四部合唱分声部各 4 种共 323/398.5MB，合计 1257/2428.7MB）→ 交付体积重算：**全量随包 ≈3.00GB / 仅鋼琴版随包 ≈1.72GB（省 44%）/ 无音频版 ≈0.58GB**；明确「只留鋼琴版**必须同步裁剪 DB**（否则版本行露出点不通的空版本，R14）」；**系统导航栏可隐藏**（`immersiveSticky`）→ 定稿「默认隐藏系统导航栏 + 我们的底部条默认总是隐藏 + 一键恢复开关」（§3.1.16，风险 R13）；新增任务 **A8**。
- 2026-10-11（追加 4）：**三变体定稿**（手机为例，平板同构）—— 全量音频版 3.00GB / 钢琴版 1.72GB（原缺 `249`）/ 人声版 1.46GB（原缺 13 首），名称加尾缀（`.piano` / `.vocal` / `.lite`）；**单音频版 UI 重新设计：无音频版本选择**（版本行整行移除、播放条去 `👥`，新增 §3.1.17）；缺口清单经"DB `audio_versions` 路径逐首核对 + DB 标注"双口径交叉验证；新增任务 **A6 补回（四变体）**、**C13**、测试位 **V8/V9**、风险 **R15**；产物矩阵改 full/piano/vocal/lite。*（缺口数与可播数已被追加 5 的替代规则更新，见下）*
- 2026-10-11（追加 5）：**替代规则与补全入档** —— `3`/`389` 的**四部合唱版视同人声版**；缺口在 App 内**互补替代**（人声版缺→鋼琴版、钢琴版缺→人聲版，不做跳转指引）⇒ 三音频变体 **474/474 全曲目可播**；数据侧：`62` 补入人聲版、**`305` 重新下载后入库**（原 `305_鋼琴版.mp3` 系错件 → 更正为 `.m4a`；`305_人聲版.mp3` 为真·人声版）、**`349`「奇妙的耶穌」重新入库**（`tjc_hymn` + 默认歌单「颂赞/赞美耶稣」+ `jianpu_*` 网格 40 行/749 格），`jianpu_*` 全量重建 **474 首 / 21819 行 / 321703 格（L0 零差异）**；无音频版保留并新增 §3.1.18；新增附录 C（`api_cache`、`_misc` exe、`201_人聲版.mp4` 已删除）。
- 2026-10-11（追加 6）：**计划自检与精简**（1470→1360 行）—— 删除全部协商过程叙述（"三问澄清"问答体、时间戳后缀、`用户定稿/请择一/我上一版` 等），去重（§3.1.18 版面图归并 §3.1.15；§1.4 ④ 与 ⑤ 合并；删除旧"有音频版/无音频版"矩阵），补漏（新增 **A9 数据侧一致性收口**、§3.1.18 设置页分组行），统一口径（`kHasAudio`→`kAudioVariant`、四变体/8 个变体、版本+模式合并行 44dp、`474 首` 基线）；UI 定稿：竖屏与横屏均为「版本 + 模式」合并一行。
- 2026-10-11（追加 7）：**349 目录改名 + 环节扩为 9 个** —— ① 目录 `354_349救主正在等候` → `354_349奇妙的耶穌`（同步 DB 4 个谱面路径 + `audio_versions` 3 个音频路径；旧路径残留 **0**；checksums **7 条目 PASS**）；② 计划新增 **§〇·五「9 环节 × 阶段 A~F 矩阵」** 与 **§十一~§十四**（需求基线与变更记录 / 数据与内容治理 / 安全与合规 / 运维与反馈闭环）；③ §五 补 CI 口径、§六 补无障碍专项与跨平台回归、§十 补 **M7**；文档 1360 → **1502 行**。
- 2026-10-11（追加 8）：**349 曲名以现实为准** —— 目录 `354_349奇妙的耶穌` → **`354_349救主正在等待`**；`tjc_hymn.title` 同步为「救主正在等待」；5 个路径字段（谱面 4 + 音频 3）同步；**默认歌单成员标题同步**（`{'救主正在等待': '349'}`）；校验：7 条路径全存在、旧目录名/旧标题残留 **0**、目录 checksums **7 条目 PASS**；文档 5 + 7 处同步 + §11.2 变更记录登记；`api_raw` 源站快照按规则不改。
