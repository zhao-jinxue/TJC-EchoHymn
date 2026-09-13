# 📦 EchoHymn 打包与迁移部署指南（Windows）

> **平台范围：Windows 桌面版**（绿色目录打包与跨机迁移）。
> 其他平台部署：Android 见 [`docs/Android/ANDROID_PLAN.md`](../Android/ANDROID_PLAN.md) ·
> 鸿蒙见 [`docs/OpenHarmony/`](../OpenHarmony/README.md) · 苹果见 [`docs/iOS/`](../iOS/README.md)；
> 安装包分发（Inno Setup 双产物）见 [INSTALLER.md](INSTALLER.md) 与 [RELEASE_RULES.md](RELEASE_RULES.md)。

---

## 1. 补齐工具链（仅首次）

1. 安装 [Visual Studio 2022 Community](https://visualstudio.microsoft.com/)
   - 勾选 **"使用 C++ 的桌面开发"** 工作负载（含 MSVC 编译器 + Windows SDK）
   - 详见 [INSTALL_VISUAL_STUDIO.md](INSTALL_VISUAL_STUDIO.md)
2. 安装 [CMake](https://cmake.org/download/)（详见 [INSTALL_CMAKE.md](INSTALL_CMAKE.md)）
3. 启用 Windows 开发者模式：`start ms-settings:developers`
4. 重新打开终端，确认 `flutter doctor` 中 Visual Studio 变为 ✅

## 2. 构建发布版

```powershell
cd E:\EchoHymn\hymn_app
flutter build windows --release
```

产物在 `hymn_app\build\windows\x64\runner\Release\`，包含：

- `echo_hymn.exe`（应用主程序）
- 依赖的 Flutter 运行时文件（audioplayers 走系统 Media Foundation，无需额外 DLL）

> **当前架构为纯 Dart**：不需要手动构建 `hymn_app/native` 的 C++ 引擎，也无需拷贝任何 DLL
> （历史可选组件说明见 [docs/README.md 附录](../README.md)）。

## 3. 迁移到目标机

- 把整个 `Release\` 文件夹拷到目标 Windows 设备
- **必须整体拷贝**（exe 依赖同目录的运行时文件）
- 运行需 `data\` 位于 exe 的上级目录链中（`AppPaths.resolveAsset` 向上查找 12 层）
- 双击 `echo_hymn.exe` 即可运行，**目标机无需安装 Flutter**

> 对外分发推荐安装包形态（双文件 + SHA256），一键构建流程见 [INSTALLER.md](INSTALLER.md) 第三节。

## 4. 自动发布机制（Windows）

每次 `git commit` 到 master/main，post-commit 钩子自动运行 `tools/publish_windows.ps1`，
构建 Windows 桌面版并发布到 `release/echohymn_win_<时间戳>_<短哈希>/`（保留最近 5 份）。
日志：`release/auto-release.log`。安装包构建**不并入**自动发布（素材压缩耗时，保持手动触发）。

## 5. 常见问题

### Q1：双击 exe 后退出 / 闪退？

- 确认 `data\` 目录在 exe 的上级目录链中（`AppPaths.resolveAsset` 向上查找 12 层，如 `Release\..\..\..\..\..\data\`）
- 确认音频文件存在于 `data/Hymn_Downloads/`（数据库按相对路径引用）

### Q2：音频播放无声？

- audioplayers 走 Windows Media Foundation，m4a/mp3 系统解码器应可正常播放
- 若播放失败会弹 Toast 显示具体错误（`statusStream` 统一检测）

### Q3：构建时提示镜像 TLS 错误？

- 使用官方源：设置 `PUB_HOSTED_URL=https://pub.dev` 与 `FLUTTER_STORAGE_BASE_URL=https://storage.googleapis.com`

### Q4：Web 版还能用吗？

- **不能**。Web 已于 2026-08-16 移除（`dart:ffi` 系能力在 Web 不可用），不再提供 Web 版发布。
