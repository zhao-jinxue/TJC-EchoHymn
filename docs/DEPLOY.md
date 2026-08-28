# 📦 EchoHymn 打包与迁移部署指南

本文档说明如何将 **EchoHymn（Flutter）** 打包，并迁移到相同系统的设备上继续使用。

> **目标平台**：Windows（已开发）· Android（待开发）· OpenHarmony 鸿蒙（目录占位）
> **Web 已移除**（2026-08-16，`dart:ffi` 在 Web 不可用），不再提供 Web 版发布。

---

## 一、Windows 桌面版打包迁移（推荐，已开发）

### 1. 补齐工具链（仅首次）

1. 安装 [Visual Studio 2022 Community](https://visualstudio.microsoft.com/)
   - 勾选 **“使用 C++ 的桌面开发”** 工作负载（含 MSVC 编译器 + Windows SDK）
   - 详见 `docs/INSTALL_VISUAL_STUDIO.md`
2. 安装 [CMake](https://cmake.org/download/)（详见 `docs/INSTALL_CMAKE.md`）
3. 启用 Windows 开发者模式：`start ms-settings:developers`
4. 重新打开终端，确认 `flutter doctor` 中 Visual Studio 变为 ✅

### 2. 构建发布版

```powershell
cd E:\EchoHymn\hymn_app
flutter build windows --release
```

产物在 `hymn_app\build\windows\x64\runner\Release\`，包含：

- `echo_hymn.exe`（应用主程序）
- 依赖的 Flutter 运行时文件（audioplayers 走系统 Media Foundation，无需额外 DLL）

### 3. 迁移到目标机

- 把整个 `Release\` 文件夹拷到目标 Windows 设备
- **必须整体拷贝**（exe 依赖同目录的运行时文件）
- 运行需 `data\` 位于 exe 的上级目录链中（`AppPaths.resolveAsset` 向上查找 12 层）
- 双击 `echo_hymn.exe` 即可运行，**目标机无需安装 Flutter**

> 若想免安装绿色分发，可用 [Inno Setup](https://jrsoftware.org/isinfo.php) 或 [NSIS](https://nsis.sourceforge.io/) 打包成安装包。

---

## 二、Android 版打包迁移（目录已就绪，待开发）

### 1. 补齐工具链

1. 安装 [Android Studio](https://developer.android.com/studio)
   - 首次启动会自动安装 Android SDK
2. 在 Android Studio 中：`Settings → Languages & Frameworks → Android SDK` 至少安装：
   - Android SDK Platform（与 `minSdk` 匹配）
   - Android SDK Build-Tools
3. 配置 SDK 路径（若自动检测失败）：

   ```powershell
   flutter config --android-sdk "C:\Users\<你的用户名>\AppData\Local\Android\Sdk"
   flutter doctor --android-licenses   # 接受许可
   ```

### 2. 构建 APK

```powershell
cd E:\EchoHymn\hymn_app
flutter build apk --release
# 产物：build\app\outputs\flutter-apk\app-release.apk
```

### 3. 迁移到目标安卓设备

- 直接把 `app-release.apk` 传到手机/平板安装（开启“允许安装未知来源”）
- 数据库路径：Android 需要内置数据库或运行时拷贝 `data/tjc_hymn.db`（当前 SQLite 路径逻辑待 Android 适配，见遗留任务）

---

## 三、OpenHarmony（鸿蒙）接入（目录占位，待开发）

- 平台目录：`hymn_app/ohos/`（当前仅占位 README）
- OpenHarmony 上运行 Flutter 需使用社区维护的 **OpenHarmony Flutter SDK**（gitee `openharmony/flutter_flutter`），非官方 flutter 直接支持
- 届时需校验 `audioplayers` / `sqlite3_flutter_libs` 的鸿蒙插件支持情况（简繁转换已为纯 Dart 查表、状态持久化已为原生 `state.json`，均无平台插件依赖）
- 详见 `hymn_app/ohos/README.md`

---

## 四、打包迁移速查表

| 目标平台 | 前置条件 | 产物位置 | 目标机要求 |
| --- | --- | --- | --- |
| **Windows** | VS + 开发者模式 + CMake | `build\windows\x64\runner\Release\` | 无（整体拷 Release 目录 + 上级 data/） |
| **Android** | Android Studio + SDK | `build\app\outputs\flutter-apk\app-release.apk` | 安卓设备直接安装 |
| **鸿蒙** | OpenHarmony SDK + DevEco | 待接入 | — |

---

## 五、常见问题

### Q1：Windows 版双击 exe 后退出 / 闪退？

- 确认 `data\` 目录在 exe 的上级目录链中（`AppPaths.resolveAsset` 向上查找 12 层，如 `Release\..\..\..\..\..\data\`）
- 确认音频文件存在于 `data/Hymn_Downloads/`（数据库按相对路径引用）

### Q2：音频播放无声？

- audioplayers 走 Windows Media Foundation，m4a/mp3 系统解码器应可正常播放
- 若播放失败会弹 Toast 显示具体错误（`statusStream` 统一检测）

### Q3：构建时提示镜像 TLS 错误？

- 使用官方源：设置 `PUB_HOSTED_URL=https://pub.dev` 与 `FLUTTER_STORAGE_BASE_URL=https://storage.googleapis.com`

### Q4：之前提到的 Web 自动发布还能用吗？

- **不能**。Web 已从目标平台移除；但已恢复 **Windows 自动发布**：
  - 每次 `git commit` 到 master/main，post-commit 钩子自动运行 `tools/publish_windows.ps1`，构建 Windows 桌面版并发布到 `release/echohymn_win_<时间戳>_<短哈希>/`（保留 5 份）
  - 日志：`release/auto-release.log`
- 若日后需要 Web，需重新评估（`sqlite3` 的 `dart:ffi` 在 Web 不可用，需要做数据层降级/替换）
