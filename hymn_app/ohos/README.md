# OpenHarmony / 鸿蒙 平台目录

本目录为 **OpenHarmony（鸿蒙）** 平台预留目录，当前**仅作占位，不进行开发**。

## 目标平台

EchoHymn 目标平台为：

| 平台 | 状态 |
| --- | --- |
| Windows | ✅ 已开发（桌面优先，v1.0.x） |
| Android | ✅ 目录已存在（`hymn_app/android/`），后续开发 |
| OpenHarmony（鸿蒙） | 📁 本目录占位，后续开发 |
| ~~Web~~ | ❌ 已移除（2026-08-16，详见 docs/SESSION_SUMMARY.md） |

## 后续接入方式（供参考，暂不执行）

OpenHarmony 上运行 Flutter 需使用社区维护的 **OpenHarmony Flutter SDK**（gitee 的 `openharmony/flutter_flutter` 与 `flutter_flutter` 配套 plugin 分支），并非官方 flutter 直接支持。届时：

1. 安装 OpenHarmony 版 Flutter SDK 与 DevEco Studio
2. 在 `hymn_app/` 下执行对应 SDK 的 `flutter create --platforms ohos .` 生成 `ohos/` 目录
3. 校验 `audioplayers` / `sqlite3_flutter_libs` / `flutter_opencc_ffi` / `shared_preferences` 的鸿蒙插件支持情况（可能需要社区适配或替换方案）

> 在正式接入前，本项目不生成 `ohos` 完整工程，避免干扰 Windows 版本开发。
