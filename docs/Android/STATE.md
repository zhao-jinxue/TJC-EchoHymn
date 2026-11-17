# Android 开发状态（唯一续接入口）

**更新**：2026-11-17 ｜ **阶段**：**M5 发布（v1.9.3 · 主体 APK + installer 数据包 + 逐文件校验）** ｜ **分支**：`main` ｜ **最后提交**：见 `git log -1`

## 当前

- **版本**：`pubspec 1.9.3+4`；tag `android-v1.9.0-phone` / `v1.9.1-phone` / `v1.9.2-phone` / `v1.9.3-phone`（均已推送 origin）
- **release 主体**：`release/android/echohymn_android_<时间戳>_<sha>/EchoHymn-full-v1.9.3-<sha>.apk` —— **54.2 MB**（程序 + 数据库，无素材）
- **installer**：`installer/output/android/` —— 主体 APK + 6 个数据包 + `SHA256SUMS.txt` + `BUILD-INFO.txt`
- **M5**：F-1 ✅ · F-2 ✅ · F-3 ✅（§7.4 仅「真机走查」待用户；替代音频已逐首核对 474/474）

## 架构定稿（2026-11）

| 项 | 定稿 |
| --- | --- |
| 素材分发 | **主体 APK（无素材）+ installer 数据包**：扫描图 / 人声 / 钢琴，各拆 `0-237` 与 `238-474`（每包 <2 GB） |
| UI 形态 | **运行时能力检测**（首启按前十首）→ full / piano / vocal / lite；不再用 Gradle flavor 区分 UI |
| 导入入口 | 首启引导页 + 设置「数据导入（压缩包）」；SAF 选 zip → Kotlin 流式解压 |
| 导入规则 | 只接受 `Hymn_Downloads/<目录>/<编号>_<类型>.<ext>` 且类别匹配；规则外**丢弃不落盘**；同名**覆盖**；目录**自动创建** |
| 完整性 | zip 首条目 `ECHOHYMN-MANIFEST.json`（逐文件 sha256）→ 导入时逐文件校验；设置「素材自检」全量核对 |
| full 音频口径 | **鋼琴版 + 人聲版**（合唱类不打包；仅 `3`/`389` 四部合唱版作人声版替代音源） |
| 替代规则 | piano 1 首（`249`→人聲版）；vocal 11 首（`3`/`389`→四部合唱、9 首→鋼琴）；`substitutionOrder` 按变体优先级 |
| lite | **完全没有播放功能**（无播放条 / 媒体会话 / 通知权限） |
| 曲谱模式 | **仅 Windows**；Android/iOS 无按钮，残留 `score` 状态回退歌词 |
| 桌面 | 固定构建期变体（full）；Windows 功能零改动 |

## 实测基线

| 项 | 数据 |
| --- | --- |
| 数据 | 474 首 / 21819 行 / 321703 格（APK 内基线校验通过） |
| 主体 APK | 54.2 MB（arm64，正式签名 `CN=EchoHymn`） |
| 数据包 | scores 237.9/249.9 · vocal 229.6/684.6 · piano 545.3/600.7 MB |
| 首启迁移（piano 全量） | 1422 条 / 1.6 GB / 17–18 s / 失败 0（模拟器） |
| 校验 | `piano-0-237` 清单 237 条 → **237/237 哈希一致，0 缺失 0 损坏** |
| UI 走查 | 5 视口 × 3 档字号 = 15/15，`overflow = 0` |
| 16KB page | `zipalign -c -P 16` 通过；arm64 `.so` LOAD `p_align` ≥ 16384 |

## 阻塞 / 待确认

| 项 | 影响 | 需要谁 |
| --- | --- | --- |
| **真机走查**（含 SAF 选包 / 素材自检按钮） | F-3 最后一项 | **你**（手动） |
| 首启双引擎初始化（`HomeScreen 初始化` ×2） | 日志噪声；DB 已做并发兜底 | 下轮排查（不阻塞） |
| 导入后需**重启**才重新检测能力 | 体验 | 可改动态刷新（待定） |
| 横屏 + 特大字号需纵向滚动；320dp 顶栏需横向滑动 | 观感 | 可接受 |
| Windows 实机不退化验证（v1.9.3） | 桌面对齐 | 你抽空开一次 exe |

## 环境变更（换机 / 清缓存时需复原）

| 项 | 值 |
| --- | --- |
| `PUB_CACHE` | `E:\pub-cache`（中文路径会导致 `:jni` CMake 崩溃） |
| `kotlin.incremental` | `false`（跨盘符增量编译报 `different roots`） |
| native-assets | 保持启用（`objective_c` 强制要求） |
| NDK / CMake | `D:\Android\Sdk\ndk\28.2.13676358` · `cmake\3.22.1` |
| AVD | `echohymn_phone36`（API 36；数据分区 16 GB / RAM 4 GB，用于大包验证） |
| 后台构建 | `Start-Process` 会话 PATH 必须含 `System32` + Git，否则 flutter 报 `Unable to find git` |

## 最近里程碑

| M0 | M1 | M2 | M3 | M4 | M5 | M6 |
| --- | --- | --- | --- | --- | --- | --- |
| ✅ | ✅ | ✅ | ✅ | ✅ | ✅（F-3 待真机走查） | ⬜ |

## 会话约定（摘要）

- 一会话 1~2 个工单；收尾：更新本文件 → `git status` 干净 → 写会话日志
- 启动：读本文件 → `IMPLEMENTATION_PLAN.md` 当前阶段节 → `ANDROID_PLAN.md` 相关片段 → `git log -3` + `git status`
- 当前日志卷：`docs/sessions/2026-11/2026-11-11_20-32-06.md`（任务 1~6）
