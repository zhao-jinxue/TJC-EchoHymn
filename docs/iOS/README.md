# 📦 苹果平台（iOS / macOS）开发目录（占位）

> **状态**：未开发、未立项。本目录为苹果平台移植文档归档位：
> 立项后将开发计划、环境搭建、适配记录统一放入此处（iOS 与 macOS 可在本目录下分设子目录或前缀区分）。

## 已知接入前提（2026-09 现状盘点）

1. **硬件**：需 macOS 机器 + Xcode（当前开发机为 Windows，**无法本地构建** iOS/macOS 产物，为最大前置约束）。
2. **工程目录**：`hymn_app` 下尚无 `ios/`、`macos/` 平台目录，届时 `flutter create --platforms=ios,macos .` 生成。
3. **插件兼容性校验**（立项第一步）：
   - `audioplayers`：iOS/macOS 官方支持良好（AVPlayer 路线）；
   - `sqlite3_flutter_libs`：iOS/macOS 支持良好；
   - 桌面窗口通道 `echo_hymn/window` 为 Windows 专属，macOS 需另行实现或条件导入隔离
     （方案可复用 Android 计划阶段 1 的 `WindowControls` 抽象，见 [`../Android/ANDROID_PLAN.md`](../Android/ANDROID_PLAN.md)）。
4. **天然无碍项**：简繁转换（纯 Dart 查表）、状态持久化（原生 `state.json` 原子写）、
   日志（`LogService` 纯 Dart）、内置字体 EchoSans（OFL 许可，可随包分发）。
5. **分发约束**：iOS 上架需 Apple 开发者账号（$99/年）与签名证书；macOS 非上架分发需公证（notarization）。
   `state.json`/`logs/` 写"exe 同级"的便携设计在 iOS 沙盒下**必须**改应用私有目录（走 `AppPaths` mobile 分支）。

## 待办（立项时展开为正式计划文档）

- [ ] `APPLE_PLAN.md`：分阶段移植计划（建议 iOS 优先，与 Android 移动版式合并设计）
- [ ] 竖屏移动布局（与 Android 阶段 3 共享一套移动端 UI 规格，对齐 `../Windows/UI_CONFIRMATION.md` 定稿出移动版）
- [ ] `AppPaths` iOS/macOS 分支与素材（约 3 GB）分发方案
- [ ] 签名/公证/上架流程记录
