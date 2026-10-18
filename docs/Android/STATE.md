# Android 开发状态（唯一续接入口）

**更新**：2026-10-18 21:2x ｜ **阶段**：**M1 进行中**（A-1 ✅ / A-2 ✅ / A-3 ✅）｜ **分支**：`main`（A-4 后或 A-3 已改完，可随时切 `android/phone`）｜ **最后提交**：见 `git log -1`

## 当前

- **已完成工单**：
  - **A-1 环境补件 ✅** —— licenses 全接受；API 36 镜像（4.3 GB）；AVD `echohymn_phone36`；模拟器 **Android 16 / API 36**；NDK **28.2**（2.17 GB，Gradle 自动装）、CMake 3.22.1（自动装）；Gradle 发行版腾讯镜像、Maven 阿里云前置
  - **A-2 `WindowControls` 抽象 ✅** —— 三件套（接口+工厂 / Windows MethodChannel / Noop）；13 处调用收敛；analyze 0 / test 62 通过
  - **A-3 工程标识 + 4 flavor ✅** —— `applicationId=com.echohymn.app`、`namespace` 同步、`MainActivity` 迁 `com/echohymn/app`、`minSdk 26 / targetSdk 36 / compileSdk 36`、`productFlavors{full,piano,vocal,lite}`（`.piano/.vocal/.lite` 后缀）、`lib/app_feature.dart`（`AudioVariant` + `kAudioVariant`）；**4 个变体 APK 全部构建通过**
- **下一工单**：**A-4 启动不崩 + 首个 APK 实测体积**
- **必读章节**：`ANDROID_PLAN.md` §4.2（A5/A6）+ §1.4 ④（体积构成）

## 环境变更（重要，换机/清缓存时需复原）

| 项 | 值 / 说明 |
| --- | --- |
| **`PUB_CACHE`** | **`E:\pub-cache`（用户级环境变量）** —— 原在 `C:\Users\小蔡爱金雪\AppData\Local\Pub\Cache`（**中文路径**）导致 `:jni` 的 CMake 配置崩溃（`MalformedJsonException: Invalid escape sequence`）；迁移后解决 |
| `kotlin.incremental` | **false**（`android/gradle.properties`）—— Pub 缓存与项目跨盘符时 Kotlin 增量编译抛 `different roots` |
| native-assets | **保持启用**（`flutter config --enable-native-assets`）—— `objective_c` 包强制要求；关闭会导致 `dart_build` 失败 |
| NDK / CMake | `D:\Android\Sdk\ndk\28.2.13676358` · `cmake\3.22.1`（首次构建自动安装） |
| APK 产物目录 | `hymn_app\build\app\outputs\flutter-apk\`（**注意不是** `E:\EchoHymn\build`） |

## 阻塞 / 待确认

| 项 | 影响 | 需要谁定 |
| --- | --- | --- |
| 应用名后缀（现为 `android:label="EchoHymn"`，未按变体区分） | A-4 / C 阶段前 | 你（建议用 `manifestPlaceholders` 按 flavor 注入 `EchoHymn（钢琴版）` 等） |
| Windows 实机不退化验证（A-2 仅 analyze/test） | A-2 收尾 | 你抽空开一次 exe |
| 349「救主正在等待」歌词/作者/源考是否更新 | B-1（不阻塞） | 你 |
| Release 体积（当前 debug 172 MB） | A-4 实测 `--analyze-size` | — |

## 最近里程碑

| M0 计划 | M1 最小可跑 | M2 数据链路 | M3 UI | M4 系统集成 | M5 发布 | M6 平板 |
| --- | --- | --- | --- | --- | --- | --- |
| ✅ | 🟡 A-1~A-3 完成，待 A-4 | ⬜ | ⬜ | ⬜ | ⬜ | ⬜ |

## 会话约定（摘要，详见 IMPLEMENTATION_PLAN §四）

- 一会话做 **1~2 个工单**；里程碑完成或压缩 2 次 → 换会话
- 收尾：更新本文件 → `git status` 干净 → 写会话日志
- 启动：读本文件 → 读实施计划当前阶段节 → 按「必读章节」读片段 → `git log -3` + `git status`
- **当前日志卷**：`docs/sessions/2026-10/2026-10-18_20-49-20.md`（卷 1 `2026-10-11_11-42-34.md` 已于 2026-10-18 封卷，只读）
