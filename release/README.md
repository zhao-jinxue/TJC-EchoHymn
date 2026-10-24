# release/ — 多平台发布产物目录

> 本目录**不入库**（`.gitignore` 的 `release/*`，仅放行本文档与 `ohos/README.md`）。
> 产物由 git 钩子自动生成，可随时删除重建。

## 目录布局（2026-10-18 起按平台分层）

```
release/
├── README.md                  ← 本文档（入库）
├── auto-release-summary.log    ← 双平台汇总日志（每次 commit 覆盖）
├── windows/                    ← Windows 桌面版
│   ├── auto-release.log
│   └── echohymn_win_<yyyyMMdd-HHmmss>_<短sha>/
│       ├── echo_hymn.exe
│       ├── data/               ← flutter_assets + 引擎资产 + tjc_hymn.db + Hymn_Downloads
│       └── ...
├── android/                    ← Android 手机版（4 变体）
│   ├── auto-release.log
│   └── echohymn_android_<yyyyMMdd-HHmmss>_<短sha>/
│       ├── EchoHymn-full-v<ver>-<sha>.apk    （com.echohymn.app）
│       ├── EchoHymn-piano-v<ver>-<sha>.apk   （com.echohymn.app.piano）
│       ├── EchoHymn-vocal-v<ver>-<sha>.apk   （com.echohymn.app.vocal）
│       ├── EchoHymn-lite-v<ver>-<sha>.apk    （com.echohymn.app.lite）
│       ├── SHA256SUMS.txt
│       └── BUILD-INFO.txt
└── ohos/                       ← OpenHarmony 预留（当前无产物，见 ohos/README.md）
```

## 产出规则

| 触发时机 | 产物 | 脚本 |
| --- | --- | --- |
| **每次 commit 到 master/main** | `windows/` + `android/` 双平台 | `tools/publish_all.ps1`（post-commit 钩子，后台执行） |
| 手动单平台 | 仅某一平台 | `tools/publish_windows.ps1` / `tools/publish_android.ps1` |
| **定版本打 tag（`vX.Y.Z`）** | **installer 安装包**（`installer/output/EchoHymn_Setup_v*.exe` + `EchoHymn_Data_v*.7z`） | `tools/build_installer.ps1` + `tools/verify_installer.ps1` |

**installer 不在 commit 流程内**：安装包含 3 GB 级数据载荷（AES-256 加密 7z），每次 commit 重打既慢又占空间，只在发版时产出。

## 保留策略

- 每个平台只保留**最近 5 个**版本目录（`-KeepCount` 可调），旧目录自动删除。
- 目录名以时间戳开头（`20261018-214128`），按名称排序即时间排序，最新在最前。

## 换机后启用自动发布

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File tools\install_git_hooks.ps1
```

该命令设置 `core.hooksPath = tools/git-hooks`（钩子随仓库入库），并规范 `post-commit` 换行为 LF。

## 环境前提（Android 构建）

```powershell
$env:PUB_CACHE = 'E:\pub-cache'   # 中文用户名路径会让 :jni 的 CMake 崩溃
```
`publish_android.ps1` 已内置回落逻辑（未设置且 `E:\pub-cache` 存在时自动使用）。
