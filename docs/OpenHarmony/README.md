# 📦 OpenHarmony（鸿蒙）版开发目录（占位）

> **状态**：未开发。平台工程目录 `hymn_app/ohos/` 同为占位（仅 README）。
> 本目录为鸿蒙移植文档归档位：立项后将开发计划、环境搭建、适配记录统一放入此处。

## 已知接入前提（2026-09 现状盘点）

1. **Flutter SDK**：OpenHarmony 上运行 Flutter 需使用社区维护的
   **OpenHarmony 版 Flutter SDK**（gitee `openharmony/sigma_flutter_flutter` / `flutter_flutter` 仓库群），
   官方 flutter 不直接支持鸿蒙 target。
2. **工具链**：DevEco Studio + OpenHarmony SDK（hvigor 构建）。
3. **插件兼容性校验**（立项第一步）：
   - `audioplayers`（当前音频链路）鸿蒙实现是否存在，或换用官方 AVPlayer 插件；
   - `sqlite3_flutter_libs` 的鸿蒙 so 构建；
   - Windows 专属 `echo_hymn/window` MethodChannel 需条件导入隔离（同 Android 计划阶段 1 方案，
     见 [`../Android/ANDROID_PLAN.md`](../Android/ANDROID_PLAN.md)）。
4. **天然无碍项**：简繁转换（纯 Dart 查表）、状态持久化（原生 `state.json` 原子写）、
   日志（`LogService` 纯 Dart）——均无平台插件依赖。

## 待办（立项时展开为正式计划文档）

- [ ] `OHOS_PLAN.md`：分阶段移植计划（对齐 Android 计划的阶段结构）
- [ ] 环境搭建记录（SDK 版本、镜像源、`flutter config --ohos-sdk`）
- [ ] `AppPaths` 鸿蒙分支（应用私有目录 + `data/tjc_hymn.db` 首启拷贝链路）
- [ ] 素材（约 3 GB）分发方案（大包安装 / 首启下载）
