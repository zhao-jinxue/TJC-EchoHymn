# 📦 EchoHymn 安装/卸载指南（Windows）

> 面向：普通用户（安装）与发布者（构建）。
> 分发形态（2026-09-05 起**双文件**）：`EchoHymn_Setup_v<版本>.exe`（约 30 MB，内嵌主程序）+ `EchoHymn_Data_v<版本>.7z`（约 3 GB，外置加密诗歌素材）。**两个文件必须放在同一目录**再双击安装包。

---

## 一、用户安装流程（三步向导）

> **安装前**：请确认 `EchoHymn_Setup_v<版本>.exe` 与 `EchoHymn_Data_v<版本>.7z` 已在同一个文件夹内——素材文件缺失时，第一步环境检查会显示 ✘ 并给出指引，补齐后点「重新检测」即可。素材拆分后安装包仅约 30 MB，双击后 UAC 授权弹窗基本即时出现（旧 3GB 单文件时代的 5~15 秒系统扫描空档已消除）。

1. **系统兼容性检查（首屏）**：自动检测 64 位系统、Windows 10+、Media Foundation（音频播放命脉，Win N/KN 版需先装"媒体功能包"）、**诗歌素材文件是否同目录就位**、磁盘空间（系统盘 ≥2GB 缓冲 / 安装盘 ≥ 素材 3GB + 程序 + 5GB 缓冲）、VC++ 运行库（随包内置无需安装）。全部 ✔ 才能继续；修复环境后可点「重新检测」。
2. **选择安装位置**：默认 `D:\Program Files\EchoHymn`；**无 D 盘或 D 盘剩余空间不足时自动回退 `C:\Program Files\EchoHymn`**，也可手动更改。
3. **誓言宣誓**：屏幕展示宣誓词（**只读展示，禁止复制/粘贴**），需照抄逐字输入。校验为"忽略空白 + 半角标点自动归一为全角"后的全文比对；输入有误会红字提示并停留在本页，**不会开始安装**。防旁路：展示框为静态文本（无右键菜单可复制）；输入框对**一切非键盘引发的内容变化**（右键粘贴、菜单删除/撤消、鼠标拖放）即时回滚并红字告警，仅逐字键入（含中文输入法）被接受。

安装过程分两段解密释放：先释放程序文件（秒级），再释放诗歌素材（约 3 GB，视磁盘速度需数分钟，页面显示百分比进度）。安装尾步：程序自动获得安装目录的 Users 修改权限（保障 `state.json` 与 `logs/` 可写）、创建开始菜单/桌面快捷方式，可选择立即启动。

### 升级安装

直接运行新版安装包即可：环境检查后选择同一目录，自动覆盖程序文件，**个人歌单数据库（`data/tjc_hymn.db`）、`state.json` 与日志自动保留**（安装前备份、解包后还原）。

### 静默安装（管理员/批量部署）

```
EchoHymn_Setup_v1.5.1.exe /VERYSILENT /NORESTART /TASKS="desktopicon"
```

前提同样是 `EchoHymn_Data_v<版本>.7z` 与安装包同目录（素材缺失时环境检查阻断，静默模式直接失败退出）。静默模式跳过誓言交互页（属发布者/批量部署通道；环境检查仍生效）；日志参数 `/LOG=C:\eh_install.log` 便于远程排障。

### SmartScreen 提示

安装包未购买代码签名证书，首次运行可能提示「Windows 已保护你的电脑 → 更多信息 → 仍要运行」，属正常现象。

---

## 二、卸载

开始菜单 `EchoHymn · 聆听赞美诗 → 卸载 EchoHymn`，或控制面板"程序和功能"。
卸载会询问**是否保留个人数据**（个人歌单数据库 + state.json + 日志），默认建议保留；选「否」则彻底删除整个安装目录。

---

## 三、发布者：构建安装包

### 前置一次性准备

1. 安装 **Inno Setup 6**（`winget install JRSoftware.InnoSetup`，需管理员）
2. 安装 Python 依赖：`pip install py7zr`

### 构建命令

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File E:\EchoHymn\tools\build_installer.ps1
```

流程（全自动）：读 `hymn_app/pubspec.yaml` 版本号 → 取最新 `release/echohymn_win_*` 为载荷源 → 按 `installer/payload_manifest.txt`（数据库实际引用清单；`Hymn_Downloads` 内只收引用文件，数据库与 Flutter 运行时资产全收）组装**双暂存区**（`staging`＝主程序区、`staging_data`＝素材区）→ 分别生成 AES-256 加密 7z（主载荷内嵌安装包，素材载荷外置）→ ISCC 编译 → 输出 `installer/output/` 下**双产物**：`EchoHymn_Setup_v<版本>.exe`（约 30 MB）+ `EchoHymn_Data_v<版本>.7z`（约 3 GB）+ 两份 `.sha256` 校验文件。中文语言文件为**仓库固化的官方简体中文翻译**（`installer/ChineseSimplified.isl`，Inno 6.5.0+ 配套，维护者 Zhenghan Yang/Kira，源: jrsoftware.org/files/istrans/；2026-09-05 起替代原离线生成器方案——后者只译 57 键导致向导内置页中英混杂与占位符错误，已删除）。

### 素材清单再生成

当歌曲/音频数据更新后，运行 `python tools/scan_db_refs.py` 重新扫描数据库引用并生成 `installer/payload_manifest.txt`，再执行构建。

### 安全说明（能力边界）

载荷使用 AES-256 + **加密头**（文件名列表不可见，主载荷与外置素材载荷同一口令），密钥以 XOR 混淆内嵌于安装向导——足以阻止普通用户右键解压/解包工具提取内容；但安装包必须可被任何用户免密安装，故**不具备对抗专业逆向的强度**，属"抬高门槛"级防护。分发时安装包与素材包各自的 `.sha256` 校验值须一并提供。

### 载荷密码

定义在 `installer/make_payload.py`（`PASSWORD`）与 `installer/echohymn.iss`（`DecodeKey` 的混淆字节数组，二者必须同步）。更换密码：改 `make_payload.py`，再把新口令逐字符 XOR `0x5A` 的结果填入 iss 的 `Enc` 数组。
