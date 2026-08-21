# 🛠 推荐的 MCP 服务器与 VS Code 插件（Flutter 应用）

针对 **Flutter（Dart UI）+ 纯 Dart 数据处理** 架构，以下工具组合可显著提升开发效率。

> **架构现状（2026-08-21）**：本项目已**无 C++ 原生引擎依赖**——简繁转换为纯 Dart 查表、数据访问直接走 SQLite、状态/日志为原生文件。下方 C++/FFI 相关内容仅保留历史参考。

---

## 一、MCP 服务器推荐

### 1. 官方基础类

| MCP 服务器 | 用途 | 安装建议 |
| --- | --- | --- |
| `@modelcontextprotocol/server-filesystem` | 文件系统访问 | ✅ 已配置 |
| `@modelcontextprotocol/server-memory` | 记住跨会话的关键决策（构建路径、发布机制等） | ✅ 已配置 |
| `@modelcontextprotocol/server-github` | GitHub 仓库/Issue/PR 管理 | 使用 GitHub 时启用 |
| `@modelcontextprotocol/server-git` | Git 操作（提交/分支/日志） | 推荐 |
| `fetch-mcp` | 抓取 Web 文档（Flutter API 参考） | ✅ 已配置 |

### 2. Flutter / Dart 专属

| MCP 服务器 | 用途 |
| --- | --- |
| `@baidu/mcp-server-baidu-analyze` | 百度开源的多功能代码分析服务器，支持 Dart 静态分析 |
| `@kaguya-ai/mcp-server-dart` | Dart 包管理（pub.dev 搜索、依赖版本检查） |

### 3. 增强效率类

| MCP 服务器 | 用途 |
| --- | --- |
| `playwright` / `puppeteer` MCP | Flutter Web/UI 自动化回归测试（按需启用） |
| `@modelcontextprotocol/server-fetch` | 抓取 Web 文档（Flutter API 参考） |

> 以上均为社区常用 MCP，安装命令均为 `npx -y <包名>` 或通过 VS Code「MCP 市场」一键添加。具体以各仓库 README 为准。

---

## 二、VS Code 插件推荐

### 1. 必备（核心开发）

| 插件 | 推荐理由 |
| --- | --- |
| **Flutter**（Dart Code 官方） | Dart/Flutter 智能补全、调试、热重载 |
| **Error Lens** | 行内错误/警告展示 |

### 2. 强烈推荐

| 插件 | 用途 |
| --- | --- |
| **Better Comments** | 彩色注释，标记 `TODO` / `FIXME` / 架构说明 |
| **GitLens** | 代码溯源、提交历史、Blame |
| **Flutter Riverpod Snippets** | 若后续采用 Riverpod 状态管理 |

### 3. JSON / 数据

| 插件 | 用途 |
| --- | --- |
| **JSON Tools** | 格式化/校验 `data/tjc_hymn.db` 相关 JSON（个人歌单成员） |
| **YAML** | 高亮 `pubspec.yaml` 语法 |

### 4. 代码质量 / 测试

| 插件 | 用途 |
| --- | --- |
| **flutter_uml** | 生成 Flutter 项目类图（架构文档） |
| **Dart Data Class Generator** | 快速生成模型类代码 |

### 5. 调试配置建议（.vscode/launch.json）

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
      "flutterMode": "release"
    }
  ]
}
```

---

## 三、推荐的 .mcp.json 配置

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
      "disabled": false,
      "autoApprove": []
    }
  }
}
```

> 说明：
>
> - Flutter/Dart 专属 MCP 服务器大多依赖 Flutter SDK 路径，安装配置与系统环境相关，建议使用 VS Code MCP 市场图形化添加。

---

## 四、环境准备清单（首次运行前）

| 步骤 | 命令 |
| --- | --- |
| 安装 Flutter SDK | 官网下载 zip，解压并配置 `PATH` |
| 验证 Flutter | `flutter doctor` |
| 安装 CMake | `winget install Kitware.CMake`（或直接用 VS 内置，见 `docs/INSTALL_CMAKE.md`） |
| 安装 C++ 编译器 | Visual Studio Build Tools（含 MSVC，Flutter Windows 构建必需） |
| 下载依赖 | `cd hymn_app && flutter pub get` |
| 静态分析 | `cd hymn_app && flutter analyze` |
| 运行应用 | `cd hymn_app && flutter run -d windows` |

> 说明：本项目**不需要**单独构建 C++ 库（native/ 目录为历史可选组件）。Windows 构建只依赖 VS 工具链 + Flutter。

---

## 五、工作流建议

```text
修改 Dart 源码（lib/）
    ↓
flutter analyze（0 issues）
    ↓
flutter build windows --release
    ↓
运行 echo_hymn.exe（exe 同级 state.json / logs/）
    ↓
git commit → 自动发布（release/echohymn-win-*）
```

> 纯 Dart 架构：所有逻辑（简繁转换 / 搜索 / 状态 / 日志）均在 Dart 层，无需维护 FFI 符号表或原生构建产物。
