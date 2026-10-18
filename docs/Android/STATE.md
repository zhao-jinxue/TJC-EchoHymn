# Android 开发状态（唯一续接入口）

**更新**：2026-10-11 ｜ **阶段**：M0 ✅（计划封版）→ 待启动 M1 ｜ **分支**：`main`（M1 开始时切 `android/phone`）｜ **最后提交**：见 `git log -1`

## 当前

- **最后完成工单**：**WP-0.2** 实施计划（318 行）+ 本文件；此前 **WP-0.1** 开发计划（1352 行）+ UI 确认单（460 行）+ 曲谱按小节分页（§3.14）
- **下一工单**：**A-1 环境补件** —— 装 `system-images;android-36;google_apis;x86_64`、建 AVD `echohymn_phone36`、配 Gradle 镜像
- **必读章节**：`ANDROID_PLAN.md` §4.2（阶段 A 任务）+ §1.1（系统基线）+ §2.2（工程待改点）；`IMPLEMENTATION_PLAN.md` §三「M1 最小可跑」

## 验收命令（A-1）

- [ ] `flutter doctor -v` —— Android toolchain 全绿
- [ ] `flutter emulators` —— 列出 `echohymn_avd` 与 `echohymn_phone36`
- [ ] 模拟器内 `adb shell getprop ro.build.version.sdk` —— 输出 **36**
- [ ] `flutter run -d echohymn_phone36` —— 能启动到 Flutter 示例页（A-1 只验环境，不验业务）

## 阻塞 / 待确认

| 项 | 影响工单 | 需要谁定 |
| --- | --- | --- |
| 应用名后缀与 4 个 `applicationId` 最终定稿 | **A-3** | 你 |
| 349「救主正在等待」的**歌词 / 词曲作者 / 源考**是否按现实更新（现为旧数据且三者不匹配） | B-1（不阻塞） | 你 |
| APK 本体体积（现为估算 ≈25MB） | A-4 实测回填 | — |
| 曲谱每页小节数默认「自适应 2~4」是否合适 | C-4 | 你（可先按默认做） |

## 最近里程碑

| M0 计划 | M1 最小可跑 | M2 数据链路 | M3 UI | M4 系统集成 | M5 发布 | M6 平板 |
| --- | --- | --- | --- | --- | --- | --- |
| ✅ | ⬜ | ⬜ | ⬜ | ⬜ | ⬜ | ⬜ |

## 会话约定（摘要，详见 IMPLEMENTATION_PLAN §四）

- 一会话做 **1~2 个工单**；里程碑完成或压缩 2 次 → 换会话
- 收尾：更新本文件 → `git status` 干净 → 写会话日志
- 启动：读本文件 → 读实施计划当前阶段节 → 按「必读章节」读片段 → `git log -3` + `git status`
