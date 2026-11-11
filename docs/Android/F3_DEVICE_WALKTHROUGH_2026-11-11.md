# F-3 发布前清单 · 设备走查报告（2026-11-11）

> 对应 `ANDROID_PLAN §7.4` / `IMPLEMENTATION_PLAN F-3`。
> 本轮只做验证与缺陷修复，**不升版本、不打 tag**（版本仍 `1.8.5+1`）。

## 1. 环境与产物

| 项 | 值 |
| --- | --- |
| 设备 | 模拟器 `echohymn_phone36` · **Android 16 / API 36** · `sdk_gphone64_x86_64` |
| 物理视口 | 1080×2400 / density 420 = **411×914dp** |
| ABI 说明 | 归档正式包是 **arm64-only**；x86_64 模拟器无 ARM 转译加载 Flutter 引擎（`libflutter.so is for EM_AARCH64`），故走查使用**同代码、同签名、仅 ABI 不同**的 `android-x64` 构建（`build/app/outputs/apk/<variant>/release/`） |
| 已归档正式包 | `release/android/echohymn_android_20261029-192138_633f4b8/`（full 86.2 / piano 82.3 / vocal 70.4 / lite 66.5 MB） |
| 静态校验 | `zipalign -c -P 16` → **Verification successful**；arm64 `.so` LOAD `p_align` = 65536 / 16384（**满足 Android 15+ 16KB page size**） |

## 2. 安装 / 升级 / 卸载 三步

| 步骤 | 操作 | 结果 |
| --- | --- | --- |
| 安装 | `adb install`（干净设备） | `Success`，558 ms |
| 升级 | `adb install -r`（同 versionCode 覆盖，前一次为 arm64 包） | `Success`，`lastUpdateTime` 刷新，数据目录保留 |
| 卸载 | `adb uninstall com.echohymn.app` | `Success`；`/data/data/com.echohymn.app` **不存在**、包列表无残留 |
| 重装（首装路径） | `adb install` + 冷启动 | `首启安装内置数据库完成｜26775552 字节`、`样本素材安装完成｜新增 46 / 失败 0`、`数据库数据加载完成｜诗歌 474 首 / 分类 47 条`、`HomeScreen 初始化完成｜诗歌总数 474` |

## 3. 多尺寸 × 三档字号（15 组合）

脚本：`tools/verify_android_device.ps1`（新增，可复用；`adb root` 后运行，自动还原 `wm size/density`）。

| 视口 | 标准 | 大 | 特大 | 布局判定 |
| --- | --- | --- | --- | --- |
| 320×640 | ✅ | ✅ | ✅ | 竖屏单列 |
| 360×800 | ✅ | ✅ | ✅ | 竖屏单列 |
| 411×914 | ✅ | ✅ | ✅ | 竖屏单列（基准） |
| 480×1067 | ✅ | ✅ | ✅ | 竖屏单列（宽屏双音频按钮） |
| 914×411 | ✅ | ✅ | ✅ | 横屏双栏 |

- 判定口径：进程存活 + `RenderFlex overflowed` = 0（15/15 通过）。
- 顶栏按钮行按可用宽度自适应：≥480dp 显示「钢琴 / 人声」双按钮，≤411dp 合并为「钢琴版」单按钮（10-29 改动已在实机确认）。
- 截图：`release/android/device-verify/full-<时间戳>/*.png`（首轮）与 `full-20261111-205301`（修复后全量）、`-205716`（横屏复测）。

## 4. lite（无音频版）一致性

- 顶栏：**「浏览 · 第 1 首《颂赞独一真神》」**（非"正在播放"语义）✅
- 无音频版本按钮、**无播放条**、无音量控件 ✅
- 手册按变体切换：「音频（精简版：无内置音频）」+「顶栏与显示模式按钮」✅
- 源考：⋮ → 诗歌源考 → 内容为第 1 首源考，与顶栏「当前浏览」一致 ✅
- 左栏列表：**474 首 / 第 1/14 页** ✅
- 无 `媒体会话` / `通知权限` 日志（lite 不初始化媒体服务）✅

## 5. 本轮修复的缺陷

| # | 缺陷 | 根因 | 修复 |
| --- | --- | --- | --- |
| 1 | 横屏（914×411dp）翻页条**压住歌词** | 翻页条是 `Positioned` overlay，字号系数叠加使内容超出可用高 | `hymn_display.dart`：移动端为翻页条预留独立 56dp 区域（`navReserve`），歌词区不再被覆盖；桌面路径不变（golden 未变） |
| 2 | 横屏 + 特大字号**只剩标题可见** | 高度是瓶颈时仍叠加 `AppFonts.lyricsScale`，内容必然超高 | 同上文件：移动端 `heightBound = maxByH <= maxByW` 时不叠加字号系数、不加 4sp |
| 3 | 横屏播放条仍有**音量/静音图标**（违反 10-28 定稿） | `_buildControlsCompact` 未按平台分支 | 移动端隐藏该按钮，桌面保留 |
| 4 | **lite 仍初始化媒体会话 / 请求通知权限** | `main.dart` 只判 `Platform.isAndroid` | 加 `&& kHasAudio`（§3.1.15） |
| 5 | **lite 首启左栏 0 首（DB 空库）** | 首启 `HomeScreen` 被创建两次 → 两个 isolate 并发 `DbBootstrap` 共用同一 `.tmp` → 一方 rename 后另一方 `PathNotFoundException`，SQLite 打开空库 | `db_bootstrap.dart`：同 isolate 复用 in-flight Future + **唯一临时名** + rename 竞态容错；`sqlite_repository.dart`：检测「无核心表」→ 删库强制重装一次（自愈） |
| 6 | 手动出包（`build_android_release.ps1`）**漏传变体标识** | 脚本未传 `--dart-define=AUDIO_VARIANT`，产出的 lite/piano/vocal 运行时全按 `full` 渲染 | 构建命令补 `--dart-define=AUDIO_VARIANT=$Variant`（与 `publish_android.ps1` 对齐） |
| 7 | 手册文案：软件介绍/列表写「473 首」 | 与库内 **474** 不一致 | `user_manual_dialog.dart` 3 处改 474；Android 手册「顶栏」章节按变体描述 |

验证：`flutter analyze` 0 · `flutter test` **77/77** · Windows `flutter build windows --release` 通过。

## 6. 仍未关闭（不进 tag）

| 项 | 说明 |
| --- | --- |
| 真机走查 | 仅模拟器（Pixel 7 尺寸 + 5 视口） |
| 替代音频 474 全可播 + 角标数 | 需完整素材 + 裁剪库方案（F-2 延后项） |
| **lite 播放能力定义** | 文档冲突：§3.1.15「完全无播放能力」 vs B-2/⑱ 手册「SAF 导入后可出声」。当前实现为**无播放条**，需用户裁定 |
| **首启双引擎初始化** | 日志可见 `HomeScreen 初始化` 两次（两个引擎），已用并发安全修复兜住 DB，但根因（Activity/Engine 重建时机）未查 |
| 横屏 + 特大字号 | 歌词需纵向滚动（物理高度限制），翻页条已不再遮挡 |
| 320dp 顶栏按钮行 | 末位「五线谱」需横向滑动（C-1 既定的横向滚动设计） |
