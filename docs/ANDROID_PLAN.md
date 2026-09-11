# EchoHymn Android 版开发计划（2026-09-11 立项）

> 目标：将 EchoHymn（Flutter）从 Windows 桌面移植到 Android。**开发环境全家部署到 D 盘**（`D:\Android`），调试载体为官方 Android 模拟器（AVD）。
> 当前基线：v1.5.2（Windows 已验收）；`hymn_app/android/` 为 `flutter create` 默认工程，尚未做任何适配。

---

## 〇、环境现状盘点（2026-09-11 实测）

| 项目 | 状态 |
| --- | --- |
| Flutter | ✅ 3.44.8 stable（D:\flutter），已启用 enable-android |
| `hymn_app/android/` | ✅ 存在（默认模板，applicationId=com.example.echo_hymn） |
| Android SDK | ❌ 未安装 → 本计划装到 **D:\Android\Sdk** |
| JDK 17 | ❌ 未安装 → 采用 Android Studio 捆绑 jbr（D:\Android\AndroidStudio\jbr） |
| 硬件虚拟化 | ✅ HypervisorPresent=True，模拟器走 Hyper-V/WHPX 加速 |
| 网络 | ✅ dl.google.com 直连 200；github.com 超时（构建期 Gradle 需镜像兜底） |
| D 盘空间 | ✅ 106GB 空闲（预留 15GB 给 SDK+镜像+AVD） |

### D 盘目录规划（阶段 0 执行后实况）

```
D:\Android\
├── Sdk\                  # ANDROID_HOME：cmdline-tools/latest + platform-tools + platforms(34/36) + build-tools(34/36) + emulator + system-images(34 x86_64) ≈5.9GB
├── avd\                  # ANDROID_AVD_HOME：echohymn_avd（Pixel 7, API 34 google_apis x86_64）
├── licenses\             # 许可（误装残留，无害）
├── logs\                 # 安装过程日志
└── install_sdk.bat       # sdkmanager 复装脚本（环境重建备用）
D:\Java\jdk-17.0.20.1+1\ # JAVA_HOME（Microsoft OpenJDK 17 ZIP 免安装版）
```

环境变量（User 级）：`ANDROID_HOME=D:\Android\Sdk`、`ANDROID_AVD_HOME=D:\Android\avd`、`JAVA_HOME=D:\Java\jdk-17.0.20.1+1`；PATH 追加 `Sdk\cmdline-tools\latest\bin`、`Sdk\platform-tools`、`Sdk\emulator`；Flutter 侧 `flutter config --android-sdk D:\Android\Sdk`。

> **与原计划差异**：Android Studio GUI 未装——官方新版安装器为 CrossInstall 框架不支持静默指定目录，且模拟器全链路（sdkmanager/avdmanager/emulator）命令行即可覆盖；后续如需 GUI 调试器再手动装 Studio，不影响开发。

---

## 一、阶段 0：环境搭建（✅ 完成 2026-09-11）

1. ~~winget 静默安装 Android Studio~~ → 改为纯命令行工具链（原因见上注）
2. ✅ commandline-tools（win-11076708_latest）→ `Sdk\cmdline-tools\latest`（sdkmanager 12.0 验证）
3. ✅ Microsoft OpenJDK 17.0.20 ZIP → `D:\Java\jdk-17.0.20.1+1`（免管理员）
4. ✅ 许可全接受；组件装齐：platform-tools 37.0.1 / platforms 34+36 / build-tools 34.0.0+36.0.0 / emulator 37.1.11 / system-images;android-34;google_apis;x86_64
5. ✅ AVD：`echohymn_avd`（Pixel 7）创建并成功冷启动（adb `sys.boot_completed=1`）
6. ✅ 终验：`flutter doctor` Android toolchain 全绿；`flutter devices` 出现 `sdk gphone64 x86 64 (mobile) • emulator-5554 • android-x64 • Android 14`；`flutter emulators` 列出 echohymn_avd

### 阶段 0 踩坑记录（复装时注意）

- winget 经 Start-Process 脱离控制台后报 "No package found"（前台正常）→ 安装类操作一律前台跑
- cmd `/c set X=Y&&` 拼参数会被空格截断 → sdkmanager 曾把组件装到 `D:\Android` 根，已移动归位；**复装请用独立 .bat**（`D:\Android\install_sdk.bat` 已备）
- Flutter 3.44 要求 compileSdk 36：只装 API 34 镜像不够，`platforms;android-36` + `build-tools;36.0.0` 必装
- 并行工具调用不保依赖顺序：下载未完成即执行解压会失败，有依赖的命令必须串行

## 二、阶段 1：最小可跑（模拟器出画面）

- `echo_hymn/window` MethodChannel（windows/runner C++）调用点**条件导入隔离**：`WindowControls` 抽象接口 + windows 实现 + 非桌面 stub；Android 隐藏自绘标题栏条（30px）
- 桌面专属逻辑空跑保护：全局快捷键、`Transform.scale` 窗口等比缩放（先原样跑，观感留阶段 3）
- `applicationId` 改 `com.echohymn.app`、label 改「EchoHymn」
- 验收：`flutter run -d emulator-5554` 启动不崩、LogService 正常落文件

## 三、阶段 2：数据链路落地

- **tjc_hymn.db**：作为 APK asset，首启复制到 `getApplicationSupportDirectory()`（`AppPaths` mobile 分支补链路；桌面「exe 同级向上查找」不动）
- **state.json**：走 mobile 分支（应用私有目录），验证 `AppStateService.shared` 串行写在 Android 同样成立
- **素材（2.96GB）**：两步走——先内置 10~20 首小样本 assets 跑通 `DeviceFileSource` 播放链路；大包方案（首启解压内置 7z / 后续在线下载）届时另行对齐
- 音频中文路径在 Android 侧复测；如读外置媒体需 `READ_MEDIA_AUDIO`（API 33+）再补权限流

## 四、阶段 3：UI 移动化（工作量主体，对齐 UI_CONFIRMATION.md 定稿出移动端版式）

- 竖屏布局：歌词/谱面区为主体；左栏（诗歌/默认歌单/我的歌单）与右栏改 **overlay 抽屉**；底部播放条常驻
- 触屏手势替代快捷键：切歌走播放条按钮；谱面双指缩放映射 `_ScoreImageView` 宽度驱动模型
- 换肤（AppPalette 5 套）/字号分级（FontSizeLevel）沿用，入口从标题栏迁到设置面板
- 遗留确认：release 签名 keystore、minSdk 版本策略——阶段 3 末尾再定

## 五、风险清单

| 风险 | 缓解 |
| --- | --- |
| Gradle wrapper 走 services.gradle.org 超时 | 镜像（Tencent/Huawei）替换 gradle-wrapper.properties 与 maven 仓库 |
| 系统镜像 ~1.5GB 下载慢 | dl.google.com 实测可达；错峰/断点续传 |
| 桌面 850×890 等比缩放模型与触屏竖屏冲突 | 阶段 1 先"能跑"，阶段 3 系统性改版式，不提前打补丁 |
| state.json/素材路径混用桌面逻辑 | 一律经 `AppPaths`，mobile 分支单独验证 |

## 六、如何判定"跑的是 Android 而非 Windows"

- **构建目标**：`flutter devices` 列出 `emulator-5554 (mobile) • android-x64`，`flutter run -d emulator-5554` 产物是 `.apk`
- **运行时**：画面出现在 Android 虚拟手机系统内（状态栏/返回键/通知栏均为 Android），与 `echo_hymn.exe` 窗口无关
- **代码层**：`Platform.isAndroid == true`（本项目 `AppPaths.isMobile` 即基于此分流）；Windows 专属的 `echo_hymn/window` 通道经条件导入根本不参与编译
