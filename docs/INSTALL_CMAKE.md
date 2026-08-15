# 🛠 CMake 安装教程（手动版）

> **背景**：你的项目有两条构建路径：
>
> | 路径 | 命令 | 是否依赖 PATH 中的 cmake |
> | --- | --- | --- |
> | Flutter Windows 应用 | `flutter build windows` | ❌ 不需要（Flutter 自动用 VS 内置 CMake） |
> | C++ 原生引擎 | `cmake -S . -B build` | ✅ **需要**（这个命令要自己敲） |
>
> 因此，命令行里需要能敲出 `cmake`。下面是三种手动方案，**推荐方案一**（零下载、最省事）。

---

## ✅ 方案一（强烈推荐）：直接用 VS 2026 自带的 CMake【零下载】

反正你**必须安装 VS 2026**（才能构建 Windows 桌面应用），而 **VS 2026 的「使用 C++ 的桌面开发」工作负载内置了 CMake**。装完后只需把它加进 PATH 即可，完全不用额外下载任何东西。

### 第 1 步：确认/安装 VS 2026（见 `docs/INSTALL_VISUAL_STUDIO.md`）

### 第 2 步：找到 VS 内置的 cmake.exe

```text
C:\Program Files\Microsoft Visual Studio\2026\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin
```

> 若安装时改过目录，请到对应位置的
> `Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin` 下找 `cmake.exe`。
> 如果装的是 Build Tools 2026，把 `Community` 换成 `BuildTools`。

### 第 3 步：把该目录加入用户 PATH

1. 按 `Win + R`，输入 `sysdm.cpl` 回车
2. 切到 **「高级」** 选项卡 → 点 **「环境变量(N)…」**
3. 在 **「用户变量」** 区域选中变量 **`Path`** → 点 **「编辑(I)…」**
4. 点 **「新建(N)」**，粘贴上面第 2 步的完整路径 → **「确定」** 一路保存
5. **关闭并重新打开终端**（让 PATH 生效）

### 第 4 步：验证

```powershell
cmake --version
```

能看到版本号（如 `cmake version 3.3x.x`）即成功。

---

## 🅱️ 方案二（推荐）：从清华 PyPI 手动下载官方 CMake 二进制

> 为什么走 PyPI：你的网络访问 GitHub / cmake.org 很慢（之前测试只有 ~16 KB/s），
> 而清华 PyPI 是国内 CDN，速度快得多。这里面的 wheel 就是 **CMake 官方预编译版**，
> 内含 `cmake.exe`，和官网 ZIP 完全一样。

### 第 1 步：浏览器下载 wheel

打开：

```text
https://pypi.tuna.tsinghua.edu.cn/simple/cmake/
```

找到：

```text
cmake-4.4.2-py3-none-win_amd64.whl
```

点击下载（约 30 MB）。

> 如果打开慢，也可用下面的命令直接下载（复制到 PowerShell）：
>
> ```powershell
> curl.exe -L -o "$env:TEMP\cmake-4.4.2.whl" "https://pypi.tuna.tsinghua.edu.cn/packages/06/9e/3e572a9a8966eec43b6d75b8b8d9543ca2182ec4006a538fb239e004a3cf/cmake-4.4.2-py3-none-win_amd64.whl"
> ```

### 第 2 步：解压

whl 本质是 zip。选中文件 → 右键 → **「全部解压缩」**，或复制到终端解压：

```powershell
Expand-Archive -Path "$env:TEMP\cmake-4.4.2.whl" -DestinationPath "$env:TEMP\cmake-wheel" -Force
```

### 第 3 步：把 cmake.exe 放到 D:\CMake

解压后进入：

```text
cmake-4.4.2.data\data\bin\
```

里面有 `cmake.exe`、`ctest.exe`、`cpack.exe`。把整个 `bin` 目录内容复制到：

```text
D:\CMake\
```

使最终路径为：`D:\CMake\cmake.exe`

> 也可以不解压到 D 盘；你只需要记着你放哪，把 **含 `cmake.exe` 的文件夹** 加进 PATH 即可。

### 第 4 步：把 `D:\CMake` 加入用户 PATH

同方案一的第 3 步，新建一条路径 `D:\CMake`（或你实际解压的位置）→ 保存 → 重开终端。

### 第 5 步：验证

```powershell
cmake --version
```

---

## 🅲 方案三（最懒但可用）：`pip install cmake`

你本机有 Python，一条命令靠清华 pip 源装，安装到 `--user` 目录（无需管理员）：

```powershell
pip config set global.index-url https://pypi.tuna.tsinghua.edu.cn/simple
pip install --user cmake
```

装完 cmake.exe 一般在：

```text
%APPDATA%\Python\Python3xx\Scripts\cmake.exe
```

把它加进 PATH 或直接用完整路径调用。验证：

```powershell
%APPDATA%\Python\Python3xx\Scripts\cmake --version
```

> 缺点：可执行文件名、版本跟随 pip 包，且需自己找 Scripts 目录；适合想用命令行管理工具的开发者。

---

## 📋 三种方案对比

| 方案 | 额外下载 | 复杂度 | 说明 |
| --- | --- | --- | --- |
| **一、VS 内置 CMake** | 0 | 最低 | **首选**。反正要装 VS 2026，一条 PATH 搞定 |
| 二、清华 PyPI wheel | ~30 MB | 中 | 独立于 VS，版本最新，国内下载快 |
| 三、pip install | ~30 MB | 中 | 适合习惯 pip 的用户 |

---

## ❓ 常见问题

### Q1：为什么 winget 装 CMake 失败了？
>
> 你之前在非管理员终端执行，MSI 安装器写 HKLM 注册表失败（错误码 1603）。
> 上述方案一/二/三都不需要管理员权限。

### Q2：方案一加的还是"内部路径"，会不会失效？
>
> VS 升级一般会保留该路径；即使变了也只是重新加一次 PATH。装 VS 2026 时**必须**勾选
> 「使用 C++ 的桌面开发」工作负载，否则没有 CMake 子目录。

### Q3：要不要把 `D:\CMake` 也放进系统 PATH？
>
> 不用。放在**用户变量 Path** 就够你的当前用户用了，也更安全。

### Q4：装完 CMake 后如何完整验证项目？

```powershell
Set-Location e:\EchoHymn\hymn_app\native
cmake -S . -B build
cmake --build build --config Release
```

看到生成 `build\Release\hymn_engine.dll` 即全链路 OK。
