# Android 开发状态（唯一续接入口）

**更新**：2026-10-18 21:4x ｜ **阶段**：**M1 最小可跑 ✅（A-1~A-4 全部完成）** → 待启动 M2 ｜ **分支**：`main` ｜ **最后提交**：见 `git log -1`

## 当前

- **M1 已完成（4/4 工单）**：
  - **A-1 环境 ✅** —— API 36 镜像（4.3 GB）· AVD `echohymn_phone36` · 模拟器 **Android 16 / API 36** · NDK 28.2 · CMake 3.22.1 · Gradle 腾讯镜像 · Maven 阿里云
  - **A-2 `WindowControls` 抽象 ✅** —— 三件套；13 处调用收敛；analyze 0 / test 62 通过；**实机 logcat 无 `MissingPluginException`**
  - **A-3 工程标识 + 4 flavor ✅** —— `com.echohymn.app[.piano|.vocal|.lite]`；4 变体 APK 全部构建通过（aapt2 校验包名互异）
  - **A-4 启动不崩 + 体积实测 ✅** —— 装 `full` 到模拟器：**pid 存活、Impeller 渲染正常、无 FATAL/未捕获异常**；**release arm64 APK = 46.5 MB**（debug 172.4 MB）；`files/tjc_hymn.db` 已落点但为**空库 12 KB**（B-1 未做 → 首屏显示"数据加载失败"，预期行为）
- **A-5 目录与发布治理 ✅**（计划外工单，2026-10-24）——
  `release/` 按平台分层（`windows/` · `android/` · `ohos/` 预留）；
  新增 `tools/publish_android.ps1`（4 变体 APK + SHA256SUMS + BUILD-INFO）与 `tools/publish_all.ps1`（一次 commit 双平台对齐）；
  post-commit 钩子入库存放 `tools/git-hooks/`，配 `tools/install_git_hooks.ps1`（`core.hooksPath` 已启用）；
  `lib/platform/` 成为平台能力唯一落点（`window_controls*` 三件套迁入，2 处 import 收敛）；
  installer 明确「仅打 tag 产出」；边界与职责见 `docs/knowledge/PROJECT_LAYOUT.md`
- **B-1 DB asset 首启拷贝 ✅**（2026-10-24）—— 新增 `lib/services/db_bootstrap.dart`（版本戳 `assetVersion=1` + `.tmp` 原子写 + 失败不崩）、
  `tools/sync_db_asset.ps1`（**单一数据源** `data/tjc_hymn.db` → assets，资产本身不入库，避免仓库存两份 25 MB）、
  `SqliteRepository.open()` 接入；顺带修复 `LogService` 在 Android 落盘（原用 `Platform.resolvedExecutable` 目录 → 系统路径不可写，日志全丢）
  - **实测**（`pm clear` 模拟首装，日志 `files/logs/app_2026-10-24.log`）：
    `首启安装内置数据库完成｜26775552 字节 → /data/user/0/com.echohymn.app/files/tjc_hymn.db（版本 1）` →
    `数据库数据加载完成｜诗歌 474 首 / 分类 47 条` → `HomeScreen 初始化完成｜诗歌总数: 474` → `加载诗歌：第 1 首《頌讚獨一真神》`
- **B-2 素材样本 + 路径复测 ✅**（2026-10-24）—— 新增 `tools/sync_audio_samples.ps1`（固定 12 首样本、**按变体裁剪**：
  full 双版本 / piano 仅钢琴 / vocal 仅人声 / lite 零音频）+ `lib/services/media_bootstrap.dart`
  （按 `assets/media/index.json` 把扁平 asset 还原为 `files/Hymn_Downloads/<中文目录>/<中文文件名>`；只补齐不清理，大小一致即跳过）
  - **实测（模拟器 full）**：`内置音频样本安装完成｜新增 22 / 跳过 0 / 失败 0（共 22 条，版本 1）`；
    落点 `files/Hymn_Downloads/001_1頌讚獨一真神/1_鋼琴版.m4a`（2 209 669 B）与 `1_人聲版.mp3`（670 746 B）与索引一致；
    特殊命名 `052_51_b萬古靈磐乙/51_b_*.mp3` 正常
  - **播放 / seek**：`播放诗歌 → 文件路径 /data/user/0/com.echohymn.app/files/Hymn_Downloads/001_1頌讚獨一真神/1_鋼琴版.m4a` → `播放成功`；
    拖动进度条 → `跳转播放位置 → 125.6 秒`
  - **lite 验收**：`index.json` = `[]`（2 B）；lite APK 内 `assets/media` **仅 1 条目**，无任何音频文件
  - **变体体积实证**（commit `4e79380`，arm64 release）：**lite 53.59 / vocal 57.32 / piano 68.64 / full 72.36 MB** —— 差异正好等于各变体音频（人声 3.7 / 钢琴 15.1 MB）
  - 顺手：`AudioService.seek` 补日志（原无记录，不便取证）；播放库日志文案改平台中立
- **B-3 扫描图链路 + 大图解码 ✅**（2026-10-24）—— `tools/sync_audio_samples.ps1` 扩展：12 首的**简谱/五线谱 PNG 全变体内置**
  （lite 也带图 —— 无音频版 = 扫描图 + DB）；`_ScoreImageView` 改为**按显示宽解码**
  （`ResizeImage(width: 视口宽×dpr×2, clamp 320~2048)`，`_resolve` 与 `_buildImage` 共用同一 provider 以共享 ImageCache）
  + 补「谱面图片解码完成」日志；`main()` 移动端把 `imageCache.maximumSizeBytes` 降到 80 MB
  - **实测**：原图 2173×3213（全尺寸 26.6 MB）→ 解码 **2048×3028（24.8 MB）**；连续 3 首（第 1/2/9 首）全部
    `谱面图片解码完成`，TOTAL PSS **311.8 / 303.0 / 321.4 MB**，无 OOM
  - **顺带修 `AppStateService`**（即 ANDROID_PLAN「`state.json` mobile 验证」）：原用 `Platform.resolvedExecutable` 目录，
    Android 上不可写 → 状态永远存不住；改移动端走应用私有目录（`ensurePath()`）。实测 `files/state.json` 生成，
    且重启后能恢复 `displayMode=staff`（这也是本轮扫描图验证的入口）
  - **变体体积**（commit `c28d9d4`，含 24 张扫描图 9.3 MB）：**lite 62.90 / vocal 66.62 / piano 77.94 / full 81.66 MB**
- **下一工单**：**B-4 曲谱小节切分（B9）** —— 页数 = 各块页数之和；切页 ≤16 ms
- **必读章节**：`ANDROID_PLAN.md` §4.3（阶段 B：B4~B9）+ §3.14（曲谱按小节分页）

## 环境变更（换机/清缓存时需复原）

| 项 | 值 / 说明 |
| --- | --- |
| **`PUB_CACHE`** | **`E:\pub-cache`（用户级）** —— 原中文路径导致 `:jni` CMake 崩溃（`MalformedJsonException`） |
| `kotlin.incremental` | **false**（`android/gradle.properties`）—— 跨盘符 Kotlin 增量编译抛 `different roots` |
| native-assets | **保持启用** —— `objective_c` 强制要求 |
| NDK / CMake | `D:\Android\Sdk\ndk\28.2.13676358` · `cmake\3.22.1` |
| APK 产物 | `hymn_app\build\app\outputs\flutter-apk\`（release：lite 62.9 / vocal 66.6 / piano 77.9 / full 81.7 MB，含库+样本；debug 172.4 MB） |

## 阻塞 / 待确认

| 项 | 影响 | 需要谁定 |
| --- | --- | --- |
| 应用名按变体区分（现统一 `EchoHymn`） | C 阶段前 | 你（建议 `manifestPlaceholders` 注入后缀） |
| Windows 实机不退化验证（A-2 仅 analyze/test） | A-2 收尾 | 你抽空开一次 exe |
| 349「救主正在等待」歌词/作者/源考是否更新 | B-1（不阻塞） | 你 |
| 素材体积方案（样本内置 + SAF 导入）落地细节 | B-2/B-3 | 可先按计划执行 |

| 窄屏布局溢出（`RenderFlex overflowed 75 / 21 px`，首屏右侧） | M3 UI 适配 | 计划内，M3 处理 |
| 日志文案「音频播放库加载完成（audioplayers / Windows Media Foundation）」在 Android 上不准确 | 小瑕疵 | B-2 顺手改 |

## 最近里程碑

| M0 计划 | M1 最小可跑 | M2 数据链路 | M3 UI | M4 系统集成 | M5 发布 | M6 平板 |
| --- | --- | --- | --- | --- | --- | --- |
| ✅ | ✅ | ⬜ | ⬜ | ⬜ | ⬜ | ⬜ |

## 会话约定（摘要，详见 IMPLEMENTATION_PLAN §四）

- 一会话做 **1~2 个工单**；里程碑完成或压缩 2 次 → 换会话
- 收尾：更新本文件 → `git status` 干净 → 写会话日志
- 启动：读本文件 → 读实施计划当前阶段节 → 按「必读章节」读片段 → `git log -3` + `git status`
- **当前日志卷**：`docs/sessions/2026-10/2026-10-18_20-49-20.md`（卷 1 `2026-10-11_11-42-34.md` 已于 2026-10-18 封卷，只读）
