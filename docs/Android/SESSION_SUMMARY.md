# EchoHymn Android 开发总结（2026-09-11 立项 ~ 当前）

> 本文档是 **Android 平台开发总结**（里程碑 / 决策 / 教训留档），供新会话续接 Android 开发时阅读。
> **路线图与阶段任务以同目录 [ANDROID_PLAN.md](ANDROID_PLAN.md) 为准**（计划内含 D 盘环境规划、阶段 0~3 执行实况、复踩坑记录与风险清单），本文档不重复搬运，只记"发生过什么、为什么、结论是什么"。
> Windows 主线总结见 `docs/Windows/SESSION_SUMMARY.md`（跨平台工程史主档）。

---

## 一、里程碑

| 日期 | 提交 | 内容 |
| --- | --- | --- |
| 2026-09-11 | （立项会话） | **Android 移植立项**：确立"开发环境全家部署 D 盘（`D:\Android`）+ 官方模拟器 AVD 调试"路线；移植计划落档 `ANDROID_PLAN.md`（分四阶段：环境 → 最小可跑 → 数据链路 → UI 移动化） |
| 2026-09-11 | `c94bcfb` | **阶段 0 环境搭建完成**：纯命令行工具链（弃 Android Studio GUI）、Microsoft OpenJDK 17、AVD `echohymn_avd`（Pixel 7 / API 34）冷启动成功；`flutter doctor` Android toolchain 全绿，`flutter devices` 可见 `emulator-5554` |

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

## 四、当前进度与待办

- ✅ 阶段 0：环境搭建（2026-09-11 完成，flutter doctor 全绿）
- ⬜ **阶段 1：最小可跑**——`echo_hymn/window` MethodChannel 条件导入隔离（`WindowControls` 抽象 + 非桌面 stub）、`applicationId` 改 `com.echohymn.app`、模拟器启动不崩
- ⬜ 阶段 2：数据链路落地（tjc_hymn.db asset 首启拷贝、state.json mobile 分支、素材样本两步走）
- ⬜ 阶段 3：UI 移动化（竖屏 + overlay 抽屉，对齐 `docs/Windows/UI_CONFIRMATION.md` 定稿出移动版式）
- ⬜ 遗留确认：release 签名 keystore、minSdk 版本策略（阶段 3 末尾定）

> 阶段拆分的完整任务清单、风险与缓解措施：见 [ANDROID_PLAN.md](ANDROID_PLAN.md)。

## 五、更新记录

- 2026-09-13：本文档建立（docs 按平台归档拆分——自 `docs/Windows/SESSION_SUMMARY.md` 抽取 Android 关联内容并汇总立项以来的操作留档）。
