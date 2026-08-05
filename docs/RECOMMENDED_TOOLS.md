# 🛠 推荐的 MCP 服务器与 VS Code 插件（Flutter + C++ 架构）

针对 **Flutter（Dart UI）+ C++（原生核心引擎）** 架构，以下工具组合可显著提升开发效率。

---

## 一、MCP 服务器推荐

### 1. 官方基础类

| MCP 服务器 | 用途 | 安装建议 |
| --- | --- | --- |
| `@modelcontextprotocol/server-filesystem` | 文件系统访问 | ✅ 已配置 |
| `@modelcontextprotocol/server-github` | GitHub 仓库/Issue/PR 管理 | 使用 GitHub 时启用 |
| `@modelcontextprotocol/server-git` | Git 操作（提交/分支/日志） | 推荐 |

### 2. Flutter / Dart 专属

| MCP 服务器 | 用途 |
| --- | --- |
| `@baidu/mcp-server-baidu-analyze` | 百度开源的多功能代码分析服务器，支持 Dart 静态分析 |
| `@kaguya-ai/mcp-server-dart` | Dart 包管理（pub.dev 搜索、依赖版本检查） |

### 3. C++ 开发类

| MCP 服务器 | 用途 | 推荐理由 |
| --- | --- | --- |
| `@modelcontextprotocol/server-memory` | 记住跨会话的关键决策（构建路径、FFI 符号表等） | **强烈推荐**：FFI 符号名跨会话维护困难 |
| `@CMakeMCP` | CMake 目标查询与构建配置 | 帮助生成/维护 native/CMakeLists.txt |
| `@GitHub-MCP` 的 CodeQL | 原生代码安全扫描 | C++ 层安全 |

### 4. 增强效率类

| MCP 服务器 | 用途 |
| --- | --- |
| `playwright` / `puppeteer` MCP | Web 版（html/ 目录）自动化回归测试 |
| `@modelcontextprotocol/server-fetch` | 抓取 Web 文档（Flutter API 参考） |

> 以上均为社区常用 MCP，安装命令均为 `npx -y <包名>` 或通过 VS Code「MCP 市场」一键添加。具体以各仓库 README 为准。

---

## 二、VS Code 插件推荐

### 1. 必备（核心开发）

| 插件 | 推荐理由 |
| --- | --- |
| **Flutter**（Dart Code 官方） | Dart/Flutter 智能补全、调试、热重载 |
| **C/C++**（Microsoft） | C++ 语法高亮、IntelliSense、调试（配合 `launch.json` 使用） |
| **CMake Tools**（Microsoft） | native/ 目录 CMake 构建与调试一体化 |

### 2. 强烈推荐

| 插件 | 用途 |
| --- | --- |
| **Error Lens** | 行内错误/警告展示，Dart 与 C++ 都适用 |
| **Better Comments** | 彩色注释，标记 `TODO` / `FIXME` / 架构说明 |
| **GitLens** | 代码溯源、提交历史、Blame |
| **Flutter Riverpod Snippets** | 若后续采用 Riverpod 状态管理 |
| **coc.nvim / clangd**（可选） | 偏好 Vim 键位时启用 clangd 替换 C/C++ 插件 |

### 3. JSON / 数据

| 插件 | 用途 |
| --- | --- |
| **JSON Tools** | 格式化/校验 `assets/data/hymns.json`（维护诗歌数据） |
| **YAML** | 高亮 `pubspec.yaml`、`CMakeLists.txt` 语法 |

### 4. 代码质量 / 测试

| 插件 | 用途 |
| --- | --- |
| **flutter_uml** | 生成 Flutter 项目类图（架构文档） |
| **Dart Data Class Generator** | 快速生成模型类代码 |

### 5. 调试配置建议（.vscode/launch.json）

> ⚠️ **C++ 调试依赖**：`cppvsdbg` 调试类型由 **Microsoft C/C++ 扩展** 提供，使用前必须先安装该扩展。未安装时若在 launch.json 中引用会导致 "The debug type is not recognized" 告警。

```json
{
  "version": "0.2.0",
  "configurations": [
    {
      "name": "Flutter (Windows)",
      "type": "dart",
      "request": "launch",
      "program": "hymn_app/lib/main.dart",
      "cwd": "hymn_app",
      "flutterMode": "debug"
    }
    // 安装 Microsoft C/C++ 扩展后，取消注释以下 C++ 调试配置：
    // {
    //   "name": "C++ Native 测试 (VS)",
    //   "type": "cppvsdbg",
    //   "request": "launch",
    //   "program": "${workspaceFolder}/hymn_app/native/build/Release/hymn_engine_test.exe",
    //   "args": [],
    //   "cwd": "${workspaceFolder}/hymn_app/native/build",
    //   "console": "externalTerminal",
    //   "stopAtEntry": false,
    //   "preLaunchTask": "cmake-build-native"
    // }
  ]
}
```

---

## 三、推荐的 .mcp.json 配置

将 `.mcp.json` 更新为如下内容（按需启用）：

```json
{
  "mcpServers": {
    "filesystem": {
      "command": "npx",
      "args": [
        "-y",
        "@modelcontextprotocol/server-filesystem",
        "E:\\EchoHymn"
      ],
      "disabled": false,
      "autoApprove": []
    },
    "memory": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-memory"],
      "disabled": true,
      "autoApprove": []
    }
  }
}
```

> 说明：
>
> - `memory` 服务器默认设为 `disabled: true`，需要时打开。
> - Flutter/Dart 专属 MCP 服务器大多依赖 Flutter SDK 路径，安装配置与系统环境相关，建议使用 VS Code MCP 市场图形化添加。

---

## 四、环境准备清单（首次运行前）

| 步骤 | 命令 |
| --- | --- |
| 安装 Flutter SDK | 官网下载 zip，解压并配置 `PATH` |
| 验证 Flutter | `flutter doctor` |
| 安装 CMake | `winget install Kitware.CMake` |
| 安装 C++ 编译器 | Visual Studio Build Tools（含 MSVC） |
| 下载依赖 | `cd hymn_app && flutter pub get` |
| 构建 C++ 库 | `cmake -S native -B native/build && cmake --build native/build --config Release` |
| 运行测试 | `cd hymn_app && flutter test` |
| 运行应用 | `cd hymn_app && flutter run -d windows` |

---

## 五、工作流建议

```text
编辑 C++ 引擎 (hymn_engine.cpp)
    ↓
CMake 增量构建 → native/build/hymn_engine.dll
    ↓
flutter run -d windows（FFI 自动加载新 DLL）
    ↓
flutter test / C++ test_main 单元测试
```

> C++ 引擎修改后，Dart 侧无需修改即可复用；同理纯 UI 改动不影响原生层。这正是 Flutter + C++ 架构的收益。
