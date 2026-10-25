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
- **B-4 曲谱小节切分（B9）✅**（2026-10-24）—— 新增 `lib/models/jianpu_pagination.dart`
  （`JianpuPage` / `JianpuPagination`：按小节线切小节 → 每 k 小节一页，k∈2~4 自适应或固定 2/3/4；
  **块间不拼页**，块 = 乐句系统）+ `test/jianpu_pagination_test.dart`（**13 例**：小节划分 / 末尾无右线 /
  无小节线 / k=2·3·4 / 1~8 钳制 / 多块页数之和 / 空谱 / 自适应 2~4 / 性能）
  - **真实数据对照**（python 独立实现，全库 474 首）：**1932 块**；每首小节 **7~48（中位 20）**；每块 **2~9（中位 5）**；
    全库 **9324 小节**；**每页 2 小节 → 4700 页（均 9.9 页/首）**、k=3 → 3294（6.9）、k=4 → 2412（5.1）
  - **耗时**：96 页（24 块 × 8 小节）单次 **≤16 ms**（单测断言；`build()` 内写日志「曲谱分页计算完成：N 页 / M 小节 / 耗时 x ms」）
  - 渲染接入（页窗口切片 + 翻页条「第 k/N 页（第 a~b 小节）」）属 **C15**
- **B-5 `state.json` mobile 冷启动恢复 ✅**（2026-10-24）—— 路径修复见 B-3；本轮补齐**逐项取证**与两条恢复日志
  （`main.dart` 记「恢复上次状态｜配色 X / 字号 Y」；`HomeScreen 初始化完成` 追加「锚点 / 版本 / 模式 / 左侧栏」）
  - **实测两轮**（`state.json` 预设后冷启动）：
    ① `配色 midnightDark / 字号 xlarge（×1.9）` + `锚点: 第 2 首 / 版本: 人聲版 / 模式: staff / 左侧栏: 展开`；
    ② `配色 warmGold / 字号 normal（×1.0）` + `锚点: 第 1 首 / 版本: 鋼琴版 / 模式: staff / 左侧栏: 收起`
  - `manualOnStart=false` → 无「启动自动弹出用户手册」日志 ✓；状态文件回写路径 = `files/state.json` ✓
  - **顺带修**：字号 ×1.9 + 左栏展开时内容区仅 ~82dp，扫描图解码宽被压到 432px；若视口随后变宽会明显模糊 →
    `_ScoreImageView` 增加「视口宽变化 >50% 则重新解码」（实测 normal/收起侧栏时回到 2048×3028）
- **B-6 打包白名单校验脚本 ✅**（2026-10-24）—— 新增 `tools/verify_android_package.ps1`：
  ① 禁止类型（`.pdf/.exe/.mp4/.zip/...`）② `flutter_assets` 库外路径（白名单 `assets/data|media|fonts`、`shaders`、`packages`、`fonts`
  + 框架根文件含 `NativeAssetsManifest.json`）③ **M2 数据基线** 474 / 21819 / 321703（解包内 DB 用 python 查）；
  已接入 `publish_android.ps1`（每变体校验，基线只跑一次）
  - **正向实测**（4 变体 APK）：禁止类型 0 / 库外路径 0；基线 **474 / 21819 / 321703 全部一致** → 退出码 0
  - **负向实测**（构造含 `.pdf` + `assets/secret/leak.txt` 的假 APK）：两项均被检出，退出码 1 ✓（证明不是"永远通过"）
- **M2 出口**：**数据链路全通 + §12.2 基线一致 ✅**（474 / 21819 / 321703 在 Android 侧 APK 内实测一致）；
  剩余「UI 确认单像素校准 ±2dp」随 M3 完成
- **C-1 手机布局壳（竖屏）✅**（2026-10-24）—— `home_screen.dart` 按**宽度断点 600dp** 分流：
  窄屏走「`SafeArea` → 顶栏 56 → 主体」，桌面（最小 850 宽）走原有 30px 标题栏 + 40px 功能栏 + 30px 状态栏，**桌面代码路径零改动**
  - 新增 `_buildMobileTopBar()`（56dp：≡ 诗歌列表 / 标题（当前诗歌）/ ⋮ 更多 → 手册·配色·字号·源考）
  - `_buildBody(mobile: true)`：内容区**始终满宽**，左/右栏改为**覆盖层**（84% / 92% + 半透明遮罩点击关闭）——
    原桌面 Row 挤压式布局在 411dp 屏上会把内容压到 ~60dp
  - `_buildLeftPanel` / `_buildRightPanel` 增加可选 `width` 参数（桌面仍按物理宽 ÷ dpr）
  - `hymn_display`：合并行 44 改**横向滚动**（原 `Spacer` 固定 Row 在窄屏溢出、末尾按钮不可点）；
    播放条 padding 收紧 + `SafeArea(bottom)`；窄屏隐藏音量百分比把 38dp 让给滑轨
  - **实测**：`RenderFlex overflowed` **从 4~6 条降为 0**；顶栏 ≡ 可点（`展开左侧栏目`）；
    模式按钮可点（`切换歌词显示模式: jianpu` → `1_简谱.png → 1984x3025`）；遮罩点击关闭（回写 `showLeft:false`）
  - **桌面回归**：`flutter build windows --release` 成功（32.8s）；`analyze` 0 / `test` 75 —— **Windows 实机运行仍待你验证**
- **C-2 横屏布局 ✅**（2026-10-24）—— 断点判定改为**最短边**（`shortestSide < 600` = 手机，横屏也算）：
  原「宽度 < 600」会把手机横屏（914dp）误判成桌面三栏
  - 横屏（手机且 width ≥ 600）：**双栏**，左栏**常驻 260dp**（§3.0.6 / §3.1.10），内容占余，源考仍为覆盖层
  - 播放条：横屏 **64dp 单行**（进度 + 紧凑控制组 `_buildControlsCompact`：静音 / 上一首 / 播放·暂停 / 下一首 / 👥）
  - 新增「布局模式切换」日志（仅变化时记）：`桌面三栏` / `手机横屏双栏` / `手机竖屏单列`（带 dp 尺寸）
  - **实测**：`手机横屏双栏（914×411dp）` → 旋回 `手机竖屏单列（411×914dp）`，全程 `overflow 0`；
    截图 `_shots/android/c2_landscape.png`、`c2_portrait_after.png`
  - **桌面回归**：`flutter build windows --release` ✓（32.5s）；`analyze` 0 / `test` 75
- **C-3 双抽屉 + 返回栈 ✅**（2026-10-24）—— 按 §3.9 实现**系统返回六条优先级**（`PopScope(canPop:false)` 统一裁决）：
  ① 软键盘弹起 → 先收键盘 ② 弹层（Flutter 自带）③ **抽屉打开 → 只关抽屉** ④ 页面栈（未落地）
  ⑤ 沉浸态（未落地）⑥ 主界面 → `SystemNavigator.pop()` 交系统退后台
  - **左右互斥**：开左抽屉自动关右、开右自动关左（§3.9 表）
  - 顶栏高度按令牌 `bar.top`：竖屏 56 / **横屏 48**
  - **实测**：点 ≡ → `展开左侧栏目` → 按返回 → `系统返回：关闭抽屉` + 回写 `showLeft:false`；
    再按返回（无抽屉）→ activity 退到后台、进程保留（`pid 6260`）
  - **踩坑修正**：首版用 `FocusManager.primaryFocus.hasFocus` 判「键盘弹起」——Flutter 的 FocusScope **恒有焦点**，
    导致返回键永远只"收键盘"、抽屉永远关不掉；改用 `MediaQuery.viewInsetsOf(context).bottom > 0`
  - **桌面回归**：`flutter build windows --release` ✓；`analyze` 0 / `test` 75
- **C-4 四模式页（进行中）**（2026-10-24）—— 分两半做：
  - **① 扫描图缩放包络 ✅**（§3.11）：手机改用 `InteractiveViewer`（`minScale 1.0` / **`maxScale 3.0×`** /
    `boundaryMargin 24dp` 回弹 / 双击复位到 contain）+ 右上角 **＋/－ 按钮**（以视口中心缩放，兼作自动化验证入口）；
    桌面仍走原有「滚轮缩放 + 纵向滚动」，**行为零改动**
    - 实测：双击 → `谱面缩放复位 1.00×`；＋×2 → `1.25× → 1.56×`；－×1 → `1.25×`
    - 桌面回归：`flutter build windows --release` ✓；`analyze` 0 / `test` 75
  - **② 曲谱按小节分页渲染 ✅**（§3.14 / B9 / C15）：`JianpuPagination.pageScore()` 把某页切成**独立子谱面**
    （单块、列从 0 起、小节线随切片平移）→ `JianpuGridView` 零改动即得「页内同列同 x」；
    `_pageCount` 曲谱模式返回 `pageCount`；翻页条文案「第 k/N 页（第 a~b 小节）」
    - 实测：`曲谱分页计算完成｜第 1 首：8 页 / 16 小节 / 每页 2 小节 / 耗时 0.597 ms`；
      `曲谱页渲染｜块 0 列 0~10（第 1~2 小节）→ 子谱 blocks=1 rows=4 colCount=11`
    - 单测：`pageScore` 切片 2 例（列平移 / 小节线过滤 / 块号不存在→空谱），全量 **77/77**
  - **顺带修 P1 缺陷**：未加载音轨时拖动进度条 → `AudioService.seek` 抛异步异常（日志实测有异常栈）；
    已加「无当前曲目直接忽略 + try/catch 记日志」
  - **遗留**：翻页按钮的实机点击坐标未探明（自动点击连扫 30+ 点未命中，功能代码已就绪）；
    §3.14 六条判据中「自动翻页与进度一致」「每页 2/3/4 与自适应设置项」待 C-6（设置项）+ 试用期人工走查
- **C-5 四页面（进行中）**（2026-10-25）——
  - **① 搜索页 ✅**（§3.1.6）：新增 `lib/screens/search_page.dart`——全屏；顶栏 56（← / 圆角搜索框 / ✕）；
    表头 40（编号 | 诗歌名称 | 歌词）；行高 72 双行 + 关键字高亮（歌名命中红、歌词命中主题色，均加粗）；
    页脚 40「共 N 条结果」；输入回车即搜，**纯数字走编号定位**、中文走 `HymnSearchService` 模糊搜索；
    单击 = 进入并播放（以全库为上下文）。移动顶栏新增 🔍 入口
    - 实测：`打开搜索页` → `搜索（编号定位）编号「9」→ 1 条` → `搜索页选中：第 9 首《向主歡呼》`
      → `搜索命中播放…全库位置 8 / 474` ✅
  - **② 设置页 ✅**（§3.1.7）：新增 `lib/screens/settings_page.dart`——全屏；顶栏 56（← / 设置 / 完成）；
    分组「外观（配色 5 套 chips + 字号 4 档，文案改为 标准/大/特大/最大）· 实时预览（200dp 卡，按 0.55× 缩放，
    用真实配色/字号令牌渲染）· 播放（默认音频版本 chips；后台播放/屏幕常亮**置灰并注明 M4 实现**）·
    帮助（用户手册 / 启动时显示手册开关 → `ManualPrefs.set`）· 关于（版本 v1.8.5 + 数据来源致谢）」；
    **点选即生效、无保存按钮**（`ThemeController` / `FontScaleController` / `onSaveState`）
  - 顶栏 ⋮ 菜单按 §3.1.7 精简为 **诗歌源考 / 设置 / 关于**（原手册·配色·字号项已收进设置页）
    - 实测：`顶栏菜单：settings` → `打开设置页`（页面渲染正常，截图 `_shots/android/c5_settings.png`）
    - **未取证**：配色/字号 chips 的点击坐标未命中（Flutter 无语义树 + 盲点），逻辑走的是桌面已验证多年的
      `ThemeController` / `FontScaleController`，风险低但需试用期人工点验
  - ③ 歌单管理适配（§3.1.9）⬜ —— 手册全屏页暂以对话框形式从设置页打开（§3.1.8 的全屏化待做）
- **下一工单**：**C-5 收尾**（歌单管理适配 + 手册全屏页）→ 随后 **C-6 设计基础** 与 **C-7 变体外壳**
- **必读章节**：`ANDROID_PLAN.md` §3.1.8~3.1.9 / §3.0（设计基础）

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
