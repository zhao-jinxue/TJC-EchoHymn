# 🛠 安装 Visual Studio 工具链（Flutter + C++ → Windows 桌面应用）

> **目标读者**：本机已有 Flutter SDK + VS Code，`flutter doctor` 报告
> `Visual Studio not installed`，需要手动补齐 Windows 桌面构建能力。

---

## 〇、先弄清楚一件事：VS Code 和 Visual Studio 不冲突

| 工具 | 角色 | 你的日常工作 |
| --- | --- | --- |
| **VS Code** | **代码编辑器**（写 Dart / C++ / 配置） | ✅ **保持不变，继续用它写代码** |
| **Visual Studio / Build Tools** | **编译工具链**（MSVC 编译器 + Windows SDK + CMake + Ninja） | ⚠️ 只在后台被 `flutter build windows` / `cmake` 调用 |

安装完 Visual Studio 后，你的工作流不改变：

```powershell
# 依然在 VS Code 里写代码，然后执行（VS 只作为后台编译器被调用）：
cd hymn_app
flutter run -d windows        # 开发调试
flutter build windows --release   # 发布
```

> Visual Studio 的图形 IDE 界面**可以永远不用打开**。它安装后主要提供编译工具，跟 VS Code 和平共存。

---

## 一、两种安装方式（二选一，推荐 Build Tools）

> ✅ **关于「默认下载的是 Visual Studio Community 2026」：完全适配，放心装。**
> 你的 Flutter 3.44.8 已内置对 VS 2026（主版本号 18）的官方支持——
> 它的构建代码中专门为 VS 2026 映射了 CMake 生成器 `Visual Studio 18 2026`，
> 要求的工作负载/组件 ID 与 2022 版完全相同。因此本指南中的勾选步骤对 **2026 / 2022 / 2019 全部通用**。

| 方式 | 体积 | 适用场景 | 安装器入口 |
| --- | --- | --- | --- |
| **Build Tools 2026**（推荐） | 下载约 2–3 GB | 纯命令行/CI 构建，无 IDE，跟 VS Code 工作流最贴合 | <https://visualstudio.microsoft.com/zh-hans/downloads/> → 页面中部 **「Visual Studio Build Tools」→ 下载** |
| **Visual Studio Community 2026**（网站默认下载项） | 下载约 4–6 GB | UI 是中文的、适合你偶尔想打开 VS 图形界面调试 C++ | <https://visualstudio.microsoft.com/zh-hans/downloads/> → 顶部大按钮 **「下载 Visual Studio」→ 社区版** |

> 两者安装器的勾选界面几乎一样，以下步骤通用。
> 无论选哪个，**最终对 Flutter 而言效果相同**——都是提供 MSVC + Windows SDK + CMake + Ninja。

---

## 二、安装步骤（在安装器里勾选）

### 第 1 步：启动安装器，选择「工作负载（Workloads）」

在左侧 **「工作负载」** 选项卡中，**勾选这一个**：

```text
✅ 使用 C++ 的桌面开发   (Desktop development with C++)
```

这一个工作负载**自带**了 Flutter Windows 构建所需的全部组件（无需手动加）：

- `MSVC v143 - VS 2022 C++ x64/x86 生成工具`（编译器 cl.exe）
- `Windows 11 SDK`（系统头文件/库）
- `CMake 工具`（已捆绑，无需另装）
- `C++ 的 CMake 工具`
- `MSBuild` 生成工具
- `适用于最新 v143 生成工具的 C++ ATL / MFC`（与本项目无关，可不勾）

> ⚠️ 不要勾选「用于 Windows 的 C++ CMake 工具」以外的 Mobile / UWP / 其他 SDK 工作负载——用不到还浪费磁盘。

### 第 2 步：右侧「安装详细信息」确认（可选）

默认即可。若想精简，可在右侧把用不到的组件取消勾选（保留上述核心项即可）。
**建议保持默认，最省心。**

### 第 3 步：点「安装」

- 安装时长取决于网速，一般 **5–20 分钟**。
- 安装完成后，**关闭并重新打开所有终端窗口**（让 PATH 环境变量刷新）。

---

## 三、安装后验证

### 验证 1：flutter doctor 黄叉消失

```powershell
Set-Location e:\EchoHymn\hymn_app
flutter doctor -v
```

预期输出：

```text
[√] Visual Studio - develop Windows apps
    • Visual Studio 2022
    • Visual Studio Build Tools 2022
    • C++ 桌面开发 (Desktop development with C++)
```

### 验证 2：CMake / cl 可用

```powershell
cmake --version        # 输出 3.22+ 即正常
```

> 如果 `cmake` 提示找不到命令，说明只装了完整 VS（CMake 在 VS 内部路径）。Flutter 构建时会自动使用 VS 内嵌的 CMake，此命令找不到**不影响** `flutter build windows`。想让命令行也能用，可把 `C:\Program Files\Microsoft Visual Studio\2026\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin`（新版默认路径；若装的是 2022 则把 `2026` 换成 `2022`，Build Tools 同理）加入 PATH。

---

## 四、首次构建测试（走通全链路）

### 1) 构建 C++ 原生引擎

```powershell
Set-Location e:\EchoHymn\hymn_app\native
cmake -S . -B build
cmake --build build --config Release
```

产物：`hymn_app\native\build\Release\hymn_engine.dll`

### 2) 构建 Flutter Windows 桌面应用

```powershell
Set-Location e:\EchoHymn\hymn_app
flutter build windows --release
```

产物：`hymn_app\build\windows\x64\runner\Release\EchoHymn.exe`

> ⚠️ **别忘了发布时把 `hymn_engine.dll` 拷贝到 exe 同目录**，否则运行时会报"无法加载 hymn_engine 原生库"。参见 `docs/README.native.md`。

### 3)（可选）VS Code 里直接运行

- Flutter 侧：VS Code 打开 `hymn_app/`，按 `F5`（使用 Dart 配置）或 `flutter run -d windows`。
- C++ 侧调试：需安装 **Microsoft C/C++ 扩展**，然后取消注释 `docs/RECOMMENDED_TOOLS.md` 中的 `cppvsdbg` launch 配置。

---

## 五、常见问题（FAQ）

### Q1：装了 VS 后 VS Code 的 Flutter 插件要不要重装？

**不用。** 两者互不干扰，VS 只是提供编译工具。VS Code 插件（Flutter、C/C++、CMake Tools）原样照用。

### Q2：以后要不要"打开 Visual Studio"才能构建？

**不用。** 所有构建都从命令行/VS Code 触发，VS 在后台完成编译。除非你手动把 VS 设成默认 C++ 调试器，否则可以永远不打开它的界面。

### Q3：安装失败 / 被防火墙拦 / 需要管理员权限？

- 安装器需要**管理员权限**（右键 → 以管理员身份运行）。
- 若下载慢，可在安装器「下载位置」改到其它盘；镜像源可参考 `docs/DEPLOY.md` 中的网络配置说明。
- 公司网络有代理时，可能需要临时关代理或加白名单 `aka.ms`。

### Q4：装了 Build Tools 还是报找不到 VS？

重新打开终端窗口使 PATH 生效；仍不行则执行：

```powershell
flutter doctor -v    # 看它到底找哪个目录
```

Flutter 通过注册表 + 固定路径查找 VS（`C:\Program Files\Microsoft Visual Studio\2022\...`），只要安装在工作负载勾选正确，默认路径即可被识别。

### Q5：磁盘不够？

可以只装 **Build Tools**（比完整 VS 小）。`vs_BuildTools.exe` 是最小安装，同样覆盖 Flutter 的全部需要。

### Q6：网站默认下载的是 Visual Studio Community 2026，适配本项目吗？

**完全适配。** 依据是本机 Flutter 3.44.8 自带的检测源码（`D:\flutter\packages\flutter_tools\lib\src\windows\visual_studio.dart`）：

- 第 184–188 行：CMake 生成器映射里**专门写死了对 VS 2026 的支持**—— `18 => 'Visual Studio 18 2026'`；
- 第 317–318 行：最低支持 VS 2019（主版本 16），**新版无上限**；
- 第 278–281 行：要求的工作负载 `NativeDesktop`（使用 C++ 的桌面开发）和 `VCTools`，在 2026 版中 ID 不变；
- 第 311–314 行：要求的组件 `VC.Tools.x86.x64` + `VC.CMake.Project`，2026 版同样包含。

所以：**直接按本指南勾「使用 C++ 的桌面开发」安装即可**，装完 `flutter doctor` 会识别为可用工具链。

---

## 六、总结一句话

> 下载官方安装器 → 勾选 **「使用 C++ 的桌面开发」** → 安装 → 重开终端 → `flutter doctor` 变绿 → 开跑。
> VS Code 工作流、Flutter 插件、C++ 代码**全部不需要任何改动**。
