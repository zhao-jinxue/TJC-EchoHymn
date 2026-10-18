# Android 开发状态（唯一续接入口）

**更新**：2026-10-18 20:5x ｜ **阶段**：**M1 进行中**（A-1 ✅ / A-2 ✅）｜ **分支**：`main`（A-3 前切 `android/phone`）｜ **最后提交**：见 `git log -1`

## 当前

- **已完成工单**：
  - **A-1 环境补件 ✅** —— licenses 全接受；`system-images;android-36;google_apis;x86_64` 安装完成（**4.3 GB**）；AVD `echohymn_phone36` 创建；模拟器实测 **Android 16 / API 36**（`emulator-5554`）；Gradle 发行版切腾讯镜像、Maven 加阿里云镜像（官方兜底）
  - **A-2 `WindowControls` 抽象 ✅** —— 新增 `services/window_controls.dart`（接口+工厂）/`_windows.dart`（MethodChannel）/`_stub.dart`（Noop）；`home_screen.dart` 与 `audio_service.dart` 共 **13 处**调用改为抽象；**`flutter analyze` 0 issues**、**`flutter test` 62/62 通过**、通道残留 0
- **下一工单**：**A-3 工程标识 + 4 flavor 骨架** —— `applicationId=com.echohymn.app`、`productFlavors{full/piano/vocal/lite}`、`kAudioVariant`
- **必读章节**：`ANDROID_PLAN.md` §4.2（A3/A4）+ §1.4 ⑤（四变体矩阵）；`IMPLEMENTATION_PLAN.md` §三 M1
- **A-3 验收命令**：`flutter build apk --debug --flavor full|piano|vocal|lite` ×4 全过；4 个 `applicationId` 互异

## 阻塞 / 待确认

| 项 | 影响 | 需要谁定 |
| --- | --- | --- |
| **4 个 `applicationId` 与应用名后缀定稿** | **A-3 立即需要** | 你（建议：`com.echohymn.app[.piano|.vocal|.lite]`；名称 `（钢琴版）/（人声版）/读谱版`） |
| Windows 实机不退化验证（A-2 只跑了 analyze/test） | A-2 收尾 | 你抽空开一次 exe 验播放/切模式 |
| 349「救主正在等待」歌词/作者/源考是否更新 | B-1（不阻塞） | 你 |
| APK 本体体积实测 | A-4 | — |

## 最近里程碑

| M0 计划 | M1 最小可跑 | M2 数据链路 | M3 UI | M4 系统集成 | M5 发布 | M6 平板 |
| --- | --- | --- | --- | --- | --- | --- |
| ✅ | 🟡 A-1/A-2 完成，待 A-3/A-4 | ⬜ | ⬜ | ⬜ | ⬜ | ⬜ |

## 会话约定（摘要，详见 IMPLEMENTATION_PLAN §四）

- 一会话做 **1~2 个工单**；里程碑完成或压缩 2 次 → 换会话
- 收尾：更新本文件 → `git status` 干净 → 写会话日志
- 启动：读本文件 → 读实施计划当前阶段节 → 按「必读章节」读片段 → `git log -3` + `git status`
- **当前日志卷**：`docs/sessions/2026-10/2026-10-18_20-49-20.md`（卷 1 `2026-10-11_11-42-34.md` 已于 2026-10-18 封卷，只读）
