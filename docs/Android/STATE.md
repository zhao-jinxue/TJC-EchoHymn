# Android 开发状态（唯一续接入口）

**更新**：2026-10-18 21:4x ｜ **阶段**：**M1 最小可跑 ✅（A-1~A-4 全部完成）** → 待启动 M2 ｜ **分支**：`main` ｜ **最后提交**：见 `git log -1`

## 当前

- **M1 已完成（4/4 工单）**：
  - **A-1 环境 ✅** —— API 36 镜像（4.3 GB）· AVD `echohymn_phone36` · 模拟器 **Android 16 / API 36** · NDK 28.2 · CMake 3.22.1 · Gradle 腾讯镜像 · Maven 阿里云
  - **A-2 `WindowControls` 抽象 ✅** —— 三件套；13 处调用收敛；analyze 0 / test 62 通过；**实机 logcat 无 `MissingPluginException`**
  - **A-3 工程标识 + 4 flavor ✅** —— `com.echohymn.app[.piano|.vocal|.lite]`；4 变体 APK 全部构建通过（aapt2 校验包名互异）
  - **A-4 启动不崩 + 体积实测 ✅** —— 装 `full` 到模拟器：**pid 存活、Impeller 渲染正常、无 FATAL/未捕获异常**；**release arm64 APK = 46.5 MB**（debug 172.4 MB）；`files/tjc_hymn.db` 已落点但为**空库 12 KB**（B-1 未做 → 首屏显示"数据加载失败"，预期行为）
- **下一工单**：**B-1 DB asset 首启拷贝** —— 把 25.53 MB `tjc_hymn.db` 打进 assets，首启校验（长度/版本戳）后拷到 `getApplicationSupportDirectory()`，替换现在的空库
- **必读章节**：`ANDROID_PLAN.md` §4.3（阶段 B：B1~B9）+ §12.2（数据基线 474 / 21819 / 321703）

## 环境变更（换机/清缓存时需复原）

| 项 | 值 / 说明 |
| --- | --- |
| **`PUB_CACHE`** | **`E:\pub-cache`（用户级）** —— 原中文路径导致 `:jni` CMake 崩溃（`MalformedJsonException`） |
| `kotlin.incremental` | **false**（`android/gradle.properties`）—— 跨盘符 Kotlin 增量编译抛 `different roots` |
| native-assets | **保持启用** —— `objective_c` 强制要求 |
| NDK / CMake | `D:\Android\Sdk\ndk\28.2.13676358` · `cmake\3.22.1` |
| APK 产物 | `hymn_app\build\app\outputs\flutter-apk\`（release 46.5 MB / debug 172.4 MB） |

## 阻塞 / 待确认

| 项 | 影响 | 需要谁定 |
| --- | --- | --- |
| 应用名按变体区分（现统一 `EchoHymn`） | C 阶段前 | 你（建议 `manifestPlaceholders` 注入后缀） |
| Windows 实机不退化验证（A-2 仅 analyze/test） | A-2 收尾 | 你抽空开一次 exe |
| 349「救主正在等待」歌词/作者/源考是否更新 | B-1（不阻塞） | 你 |
| 素材体积方案（样本内置 + SAF 导入）落地细节 | B-2/B-3 | 可先按计划执行 |

## 最近里程碑

| M0 计划 | M1 最小可跑 | M2 数据链路 | M3 UI | M4 系统集成 | M5 发布 | M6 平板 |
| --- | --- | --- | --- | --- | --- | --- |
| ✅ | ✅ | ⬜ | ⬜ | ⬜ | ⬜ | ⬜ |

## 会话约定（摘要，详见 IMPLEMENTATION_PLAN §四）

- 一会话做 **1~2 个工单**；里程碑完成或压缩 2 次 → 换会话
- 收尾：更新本文件 → `git status` 干净 → 写会话日志
- 启动：读本文件 → 读实施计划当前阶段节 → 按「必读章节」读片段 → `git log -3` + `git status`
- **当前日志卷**：`docs/sessions/2026-10/2026-10-18_20-49-20.md`（卷 1 `2026-10-11_11-42-34.md` 已于 2026-10-18 封卷，只读）
