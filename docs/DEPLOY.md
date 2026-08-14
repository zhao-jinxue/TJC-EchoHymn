# 📦 EchoHymn 打包与迁移部署指南

本文档说明如何将 **EchoHymn（Flutter + C++）** 打包，并迁移到相同系统的设备上继续使用。

---

## ⚠️ 当前环境约束（重要）

`flutter doctor` 确认本机环境：

| 项 | 状态 | 影响 |
| --- | --- | --- |
| Flutter 3.44.8 | ✅ 正常 | — |
| Chrome / Web | ✅ 正常 | **Web 版可立即打包迁移** |
| Visual Studio（Windows 桌面） | ❌ 未安装 | 暂时无法构建 Windows exe |
| Android SDK | ❌ 未安装 | 暂时无法构建 APK |

> **结论**：目前可直接迁移的是 **Web 版**（目标机只要装了浏览器即可，**零依赖**）。
> Windows 桌面版 / Android 版需先补齐工具链，步骤见下文。

---

## 〇、自动发布（每次 git commit 后自动打包发布）

本仓库已内置 **git post-commit 钩子**：每次 `git commit` 成功后，自动在后台执行发布流水线。

- **钩子安装**（一次性）：双击 `tools/install_hooks.bat`，或在仓库根执行：

  ```powershell
  Copy-Item tools\git-hooks\post-commit .git\hooks\post-commit -Force
  ```

- **发布流程** `tools/publish_release.ps1`：
  1. 仅当分支为 `master`/`main` 时触发
  2. `flutter build web --release` 构建最新代码
  3. 打包为版本化目录 `release\<短commit>-\<时间戳>\`（如 `release\echohymn-web-e26cb8c-20260814-214507\echohymn-web-e26cb8c-20260814-214507.zip`）
  4. **自动清理旧版本，只保留最近 5 份**（修改脚本顶部 `KeepCount` 可调）
- **手动发布**（等效）：

  ```powershell
  pwsh -NoProfile -ExecutionPolicy Bypass -File tools\publish_release.ps1
  ```

- 钩子模板存放于 `tools/git-hooks/post-commit`，便于版本管理；已安装副本在 `.git\hooks\post-commit`（不随仓库提交）。

---

## 一、方式一：Web 版打包迁移（✅ 立即可用，推荐）

Web 版产物是**纯静态文件**，拷贝到任意设备即可运行。

### 1. 构建 Web 发布版

```powershell
# 注意：使用官方源（镜像源 TLS 有问题）
$env:PUB_HOSTED_URL='https://pub.dev'
$env:FLUTTER_STORAGE_BASE_URL='https://storage.googleapis.com'
cd E:\EchoHymn\hymn_app
flutter build web --release
```

产物在 `hymn_app\build\web\`（含 `index.html`、`main.dart.js`、`canvaskit\`、`assets\` 等）。

### 2. 一键打包成迁移包

```powershell
# 一键生成 EchoHymn-Web-1.0.0.zip（含启动脚本，目标机无需装任何软件）
powershell -ExecutionPolicy Bypass -File E:\EchoHymn\tools\package_web.ps1
```

### 3. 在目标机使用

- 把 `EchoHymn-Web-1.0.0.zip` 拷到目标 Windows 设备（**无需安装 Flutter / Python / Node**）
- 解压后双击 `开始使用.bat`（或命令行执行 `start_web.cmd`）
- 浏览器自动打开 `http://localhost:8000` 即可使用

> ⚠️ 不建议直接双击 `index.html`（`file://` 协议），部分浏览器会限制脚本/资源加载，务必走 `start_web.cmd` 本地服务器。

---

## 二、方式二：Windows 桌面版打包迁移（需先装 Visual Studio）

### 1. 补齐工具链（仅首次，在开发机）

1. 安装 [Visual Studio 2022 Community](https://visualstudio.microsoft.com/)
   - 勾选 **“使用 C++ 的桌面开发”** 工作负载（含 MSVC 编译器 + Windows SDK）
2. 启用 Windows 开发者模式：`start ms-settings:developers`
3. 重新打开终端，确认 `flutter doctor` 中 Visual Studio 变为 ✅

### 2. 构建 C++ 原生引擎

```powershell
cd E:\EchoHymn\hymn_app\native
cmake -S . -B build
cmake --build build --config Release
# 产出：build\Release\hymn_engine.dll
```

### 3. 构建 Windows 桌面应用

```powershell
cd E:\EchoHymn\hymn_app
flutter build windows --release
```

产物在 `hymn_app\build\windows\x64\runner\Release\`，包含：

- `echo_hymn.exe`（应用主程序）
- `hymn_engine.dll`（C++ 引擎）
- 依赖的 Flutter 运行时文件

### 4. 迁移到目标机

- 把整个 `Release\` 文件夹拷到目标 Windows 设备
- **必须整体拷贝**（exe 依赖同目录的 DLL 与数据文件）
- 双击 `echo_hymn.exe` 即可运行，**目标机无需安装 Flutter**，也无需额外运行库

> 若想免安装绿色分发，可用 [Inno Setup](https://jrsoftware.org/isinfo.php) 或 [NSIS](https://nsis.sourceforge.io/) 打包成安装包。

---

## 三、方式三：Android 版打包迁移（需装 Android Studio）

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
- **注意**：当前 C++ 引擎尚未为 Android 配置 JNI/CMake 加载路径，Android 版默认走 **Dart 解析**（功能完整，见 `engine_adapter_native.dart` 自动回退机制）
- 若需在 Android 上启用 C++ 引擎，需在 `hymn_app\android\` 下补 CMake 集成（后续可选）

---

## 四、打包迁移速查表

| 目标平台 | 前置条件 | 产物位置 | 目标机要求 |
| --- | --- | --- | --- |
| **Web**（推荐） | 无需额外工具 | `build\web\` → zip | 仅浏览器，无任何依赖 |
| **Windows** | VS + 开发者模式 | `build\windows\x64\runner\Release\` | 无（整体拷 Release 夹） |
| **Android** | Android Studio + SDK | `build\app\outputs\flutter-apk\app-release.apk` | 安卓设备直接安装 |

---

## 五、常见问题

### Q1：迁移到目标机后 C++ 引擎不生效？

- Web 版：本来就使用 Dart 解析（`dart:ffi` 不支持 Web），属正常现象
- Windows 版：请确认 `hymn_engine.dll` 与 `echo_hymn.exe` **位于同一目录**；若 dll 缺失，应用会自动回退为 Dart 解析并正常显示“Dart 解析”徽标

### Q2：目标机没装 Python，Web 版能跑吗？

- `start_web.cmd` 会**优先尝试用系统自带 Python**；若无 Python，会尝试用可选的便携 Python；若两者都没有，则提示先装 Python 或直接拷贝 `build\web` 到任意静态服务器
- 最稳妥：目标机安装 [Python](https://www.python.org/)（勾选 Add to PATH）或用任何静态服务器（nginx、`npx serve` 等）托管 `build\web`

### Q3：构建时提示镜像 TLS 错误？

- 参考 README 或本仓库历史：设置 `PUB_HOSTED_URL=https://pub.dev` 使用官方源

### Q4：Web 版在低配设备上卡顿？

- 可在 `flutter build web --release` 后，参考 Flutter 官方优化（如开启 `--wasm` 需 Chrome/Edge 120+）：

  ```powershell
  flutter build web --release --wasm
