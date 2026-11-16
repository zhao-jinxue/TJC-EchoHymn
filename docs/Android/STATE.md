# Android 开发状态（唯一续接入口）

**更新**：2026-11-16 ｜ **阶段**：**M5 发布（v1.9.2 · 主体 APK + installer 数据包 · 运行时能力检测）** ｜ **分支**：`main` ｜ **最后提交**：见 `git log -1`

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
  - **③ 歌单管理全屏化 ✅**（§3.1.9）：`CreatePlaylistDialog` 增加 `fullscreen` 参数——
    手机经 `playlist_editor_launcher.dart::showPlaylistEditor()` 以路由压栈呈现（`SafeArea + SizedBox.expand`），
    桌面仍走原 520×420 弹窗，**编辑逻辑（名称 30 字 / 搜索添加 / 去重 / 移除 / 删除 + 二次确认 / Toast 就地提示）零分叉**
    - 顺带修：`my_playlists_panel` 两处调用统一走 `showPlaylistEditor`（原来直接 `showDialog`）
    - **未取证**：实机点击（入口在 左抽屉 → 我的歌单 Tab 深层，坐标探测成本过高）；`analyze` 0 / `test` 77 / Windows 构建 ✓
  - **④ 手册全屏页 ✅**（§3.1.8）：`UserManualDialog` 增加 `fullscreen`——手机经
    `manual_launcher.dart::showManualPage()` 走路由压栈（`Scaffold + SafeArea` 提供有界上下文），
    顶栏 56（← 用户手册），**移除「重选关闭行为」**（Android 无"关闭到托盘"概念），内容与
    「启动时显示本手册」开关逻辑与桌面弹窗**共用一份**；手机启动自动弹出也改走全屏页
    - 实测：`启动自动弹出用户手册` → `打开用户手册（全屏）`，**无 overflow**（截图 `c5_manual_fullscreen.png`）
    - **踩坑**：首版用 `SafeArea + SizedBox.expand` 承载 → Column 拿到无界高度，溢出 **99206px**；
      换成 `Scaffold(body: SafeArea(...))` 后正常
- **C-5 四页面全部完成 ✅**（搜索 / 设置 / 歌单 / 手册）
- **C-6 设计基础（进行中）**（2026-10-25）——
  - **① 深色谱面 ✅**（§3.10 定稿「原色 + 20% 黑遮罩」）：新增 `lib/theme/score_display_prefs.dart`
    （`dim` 默认 / `original` / `invert` 实验三档 + `dimAlpha = 0.20` 令牌）；
    `AppState` + `saveAll` + `load` 增加 `scoreDarkMode` 字段（兼容旧 state.json，缺失回退 `dim`）；
    `_ScoreImageView._applyDarkTreatment()` 在**深色主题**下按设置叠加
    （浅色主题原样返回；曲谱网格不受影响，自绘取语义色）；设置页新增「显示 → 深色下谱面显示」chips
    - **确定性验证**（像素平均亮度，`System.Drawing` 采样 y400~1700 / x50~1000）：
      `dim = 192.31` vs `original = 240.26` → **比值 0.800**（理论 0.80 = 精确 20% 黑遮罩）✅
      （截图 `dark_dim.png` / `dark_original.png` 在 `D:\Android\logs\`）
  - **② 五态统一 ✅**（§3.0）：新增 `lib/widgets/state_views.dart`（`LoadingView` / `EmptyView` / `ErrorView` /
    `FallbackView`；Offline 对本地应用不适用，素材缺失归 Fallback）并替换关键 5 处：
    - **数据加载失败 → `ErrorView` 带〔重试〕**（此前只有一行文字，用户无路可走；点击重试 → `_init()` 重来）
    - 简谱加载 → `LoadingView`；无歌词 → `EmptyView`（带图标）；无谱面 → `FallbackView`（**静默不弹错**）
  - **③ 令牌一致性抽查 ✅**：新增 `tools/check_design_tokens.ps1`——把 §3.0.1 令牌表的关键值
    与代码常量静态比对（断点 600 / 横屏左栏 260 / `bar.top` 56·48 / `bar.combined` 44 / `bar.play` 64 /
    `chip.height` / `page.padding` 16 / 简谱 `padX` / `image.dim` 0.20 / `maxScale` 3.0 / 字号四档）
    - 结果：**FAIL 0 / WARN 2** —— `chip.height` 32（令牌 26，**触控优先有意放宽**）、
      简谱 `padX` 18（令牌 16，**Windows 排版基线 + golden 快照依赖**）；两项均已在脚本内注明原因
  - **④ 动效 ✅（部分）**：`LoadingView` 加 **>300ms 才显示**（§3.0 防闪烁；`delay: Duration.zero` 便于测试）
  - **⑤ 无障碍 ✅（部分）**：播放进度 / 音量 Slider 补 `semanticFormatterCallback`
    （TalkBack 读「播放进度 1 分 23 秒」「音量 50%」）；其余按钮已有 tooltip 作语义标签。
    **TalkBack 实机走查未做**
- **C-6 五项完成 ✅**（① 深色谱面 · ② 五态 · ③ 令牌抽查 · ④ 动效防闪 · ⑤ 滑块语义）
- **C-7 变体外壳（进行中）**（2026-10-25）——
  - **① 结构显隐 ✅（lite 变体已实机验证）**：`kHasAudio` → 播放条整条不渲染、设置页无「播放」分组；
    `kFullAudioVariant` → 单音频版（piano/vocal）隐藏版本 chips 与 `👥`
    - **lite 实机**：装 `com.echohymn.app.lite` → `Hymn_Downloads/001.../` **只有 2 张 PNG、无音频**；
      `内置样本素材安装完成｜新增 24`（12 首 × 2 图）；`诗歌 474 首`；无 overflow
  - **② 替代音频 ✅（代码完成；实测待 F-2）**：
    - **修正真实缺陷**：`_currentAudioVersion` 原硬编码 `'鋼琴版'` → **人声版包会优先播鋼琴音频**；
      改为**变体感知默认版本**（vocal → `人聲版`）
    - 新增 `_hasAudioFile()`：判定依据从「DB 有键」改为「**文件真存在**」——
      实测第 `249` 首在钢琴版包里 DB 仍记着 `鋼琴版` 键，但文件根本不在包里
    - `loadHymn` / `playHymn` 均按文件存在性解析版本；缺口时按候选顺序**替代**并记
      `替代音频：期望 X → 实际 Y`；顶栏标题追加「（替代音频）」（`isSubstitutedVersion`）
    - **实测受限**：当前只有 12 首样本音频，`249` 两版文件都缺 → 走不到替代分支；
      **需 F-2 完整素材 + 裁剪库才能实测**
  - **③ lite「浏览」语义 ✅**：无音频版下移动顶栏与桌面顶栏标题加 **`浏览 · `** 前缀
    （§3.1.15：lite 的当前曲目语义是「当前浏览」而非「正在播放」）；列表行 `isCurrent` 高亮本就中性，未改
- **C-7 变体外壳 ✅ —— M3 UI 移动化全部完成（C-1~C-7）**
- **M4 系统集成（进行中）**
  - **D-1 音频焦点 ✅**（零依赖，走 `audioplayers` 自带的 `AudioContext`）：
    `_applyAndroidAudioContext()` 在 `_init()` 首步配置
    `audioFocus: gain`（来电/他 App 播放时系统要求让出焦点 → 自动暂停）、
    `usageType: media` + `contentType: music`（音量键调媒体音量、通知分组、蓝牙路由正确）、
    `stayAwake: true`；桌面 `Platform.isAndroid` 直接跳过
    - **实测**：日志 `音频上下文已配置（Android）`；系统日志出现
      `MediaFocusControl: ... from uid/pid 10216/15087 clientId=android.media.AudioManager@...`
      （audioplayers 的 Android 侧已通过 `AudioManager` 申请焦点）✅
  - **D-2 媒体通知 + 锁屏 + 后台播放 ✅（核心完成）**：
    - 新增依赖 `audio_service ^0.18.19`（+ `audio_session 0.2.4` 传递依赖）与 `permission_handler ^11.3.1`
      —— 后者**必须降到 11.x**：最新版要求 `compileSdk 37`，本项目是 36（实测 Gradle 直接失败）
    - 新增 `lib/services/audio_handler.dart::EchoHymnAudioHandler extends BaseAudioHandler`（**App 主导、最小侵入**）：
      播放内核仍在 `AudioService`，handler 只做系统侧门面 ——「系统→App」转发 play/pause/next/prev/seek，
      「App→系统」由 `AudioService._pushMediaSession()` 推送 `mediaItem` + `playbackState`（进度**节流 1s**）
    - `main.dart`（仅 Android）`await media.AudioService.init<EchoHymnAudioHandler>(...)` + **运行时请求
      `POST_NOTIFICATIONS`**；`HomeScreen._init` 里 `audio.attachMediaHandler(handler)`
    - `AndroidManifest` 增加 `WAKE_LOCK` / `FOREGROUND_SERVICE` / `FOREGROUND_SERVICE_MEDIA_PLAYBACK` /
      `POST_NOTIFICATIONS` 权限 + `com.ryanheise.audioservice.AudioService`（`foregroundServiceType=mediaPlayback`）
      + `MediaButtonReceiver`
    - **实测**：`媒体会话已就绪（通知栏/锁屏可控）`；`dumpsys media_session` 出现
      `media-session com.echohymn.app/media-session/9`；`dumpsys notification` 的 `importance` 从
      **NONE → DEFAULT**（预授权 `pm grant POST_NOTIFICATIONS` 后）
    - **顺带修掉 B-2 遗留的并发缺陷**：`MediaBootstrap` 的 `.tmp + rename` 在多协程下互相删除临时文件
      → 88 条 `PathNotFoundException`；改为**直接覆盖写**（素材只读、可自愈）+ `ensureSamples()` 并发复用同一 Future
      → 复测 `新增 46 / 失败 0`、**PathNotFound = 0**
    - **未验证**：① 通知卡片/锁屏的**内容**未目视（只有 importance 与 MediaSession 证据）；
      ② 30 分钟后台播放不被杀（§6.4 要求）；③ 首次 `media.AudioService.init` 会抛一次 `PlatformException`
      随后重试成功（日志有噪声，未深究）
  - **D-3 媒体键 / 耳机线控 / 返回手势 ✅（媒体键实测）**：
    - `MediaButtonReceiver` 随 D-2 落地 → 本轮用 `adb shell input keyevent` 做**确定性验证**：
      ```
      11:36:09 通知栏/媒体键：播放     ← KEYCODE_MEDIA_PLAY_PAUSE
      11:36:11 通知栏/媒体键：下一首   ← KEYCODE_MEDIA_NEXT
      11:36:13 通知栏/媒体键：上一首   ← KEYCODE_MEDIA_PREVIOUS
      11:36:15 通知栏/媒体键：暂停     ← KEYCODE_MEDIA_PLAY_PAUSE
      ```
      → MediaSession 接收媒体键 → handler 转发 AudioService → 播放/暂停/上下首全部可用 ✅
    - 耳机线控走同一 `MEDIA_BUTTON`/transport 路径（机制已覆盖，真机待验）
    - 返回手势：C-3 的六条优先级 + Flutter Navigator 页面栈；**10 条逐条走查未做**
- **M4 系统集成完成 ✅（D-1 音频焦点 · D-2 媒体通知/锁屏/后台播放 · D-3 媒体键）**
- **M5 发布（进行中）**
  - **F-1 keystore + 签名配置 ✅**：
    - 生成 `android/keystore/echohymn-release.jks`（RSA 2048 / 有效期 10000 天 / alias `echohymn`），
      随机 24 位强口令写入 `android/key.properties`
    - **两者已加 `hymn_app/.gitignore`**（`android/keystore/`、`android/key.properties`、`android/local.properties`、`*.jks`）
    - `build.gradle.kts`：读 `key.properties` → `signingConfigs.create("release")`；
      **缺失时回退 debug 签名**（新机 / CI 仍可构建）
    - **实测**：`flutter build apk --release --flavor full --target-platform android-arm64` 成功；
      `apksigner verify --print-certs` → **`CN=EchoHymn, OU=Mobile, O=EchoHymn, L=Local, ST=Local, C=CN`**
      （SHA-256 `39d686f0…ce131`），不再是 `CN=Android Debug` ✅
    - **口令**：见交付说明（**不入库、不入文档**，已单独告知用户，需自行另存）
  - **F-2 构建治理 + 4 变体体积对齐 ✅（裁剪库延后）**：
    - 新增 **`tools/build_android_release.ps1`（唯一推荐出包入口）**：`sync 素材 → touch pubspec → build → 体积下限校验 → 签名校验`
    - **根治「素材与变体错配」两处根因**：
      1. `flutter build apk` 不同步 `assets/media` → 脚本内先按变体 sync
      2. **`flutter build` 的 asset bundle 增量缓存**：只改目录内容不失效 →
         实测 full 与 lite 打出同样 63.52 MB；脚本内 **touch `pubspec.yaml`** 强制重打包 → full 恢复 82.29 MB
    - **4 变体实测（arm64 release，正式签名）**：
      | 变体 | 实测 | §1.4 预期 | 偏差 |
      | --- | --- | --- | --- |
      | full | **82.29 MB** | 81.66 | +0.8% |
      | piano | **78.56 MB** | 77.94 | +0.8% |
      | vocal | **67.24 MB** | 66.62 | +0.9% |
      | lite | **63.52 MB** | 62.90 | +1.0% |
      （+0.8~1.0% 来自 D-2 新增的 audio_service / Kotlin 代码）
    - **裁剪库脚本（`build_android_variant_db.py`）延后**：它的用途是「**完整素材大包**」按变体裁剪素材与 DB
      （§7.5 方案 ②）；当前试用包只内置 12 首样本，裁库反而会让其余曲目连"记录"都没有 → 等 SAF 导入或大包方案再落地
  - **F-3 发布前清单核对 ⚠️ 部分通过 / tag 未打**（§7.4 共 12 条 · **历史快照，已被下方 2026-11-11 走查更新**）：
    | 结论 | 条目 |
    | --- | --- |
    | ✅ 已过（6） | `analyze` 0 + `test` 77（含 golden）· 后台播放/媒体通知/音频焦点（模拟器证据）· `applicationId`/`versionName`/`versionCode`/应用名 · 4 个 applicationId 各就位 + **lite 包内无音频** · **SHA256 留档 + `release/android/android-release.log`** · 文档与会话日志更新 |
    | ⚠️ 未充分（4）→ **2026-11-11 已收敛 3 项** | 真机走查（只做模拟器）· ~~安装/升级/卸载三步~~ ✅ · ~~lite 自动翻页与源考「当前浏览」一致性~~ ✅ · ~~16KB page size 校验~~ ✅ |
    | ❌ 未过（2）→ **2026-11-11 收敛 1 项 · 2026-11-13 全部收敛** | ~~多尺寸 × 四档字号走查~~ ✅（五视口 × 三档，15/15）· ~~替代音频 474 全可播 + 角标数~~ ✅（见下） |
    - **结论：按 §7.4 无法全勾 → `android-v1.9.0-phone` tag 不打**（符合「试用通过才算版本」的既定原则；2026-11-11 后仅剩「真机走查 + 替代音频」两项未过）
  - **F-3 走查（2026-11-11）✅ 4 项 ⚠️ 收敛 + 7 项缺陷修复**，详见 `docs/Android/F3_DEVICE_WALKTHROUGH_2026-11-11.md`：
    - **16KB page size ✅**：`zipalign -c -P 16` → Verification successful；arm64 各 `.so` LOAD `p_align` 65536/16384（仅 32 位 v7a sqlite3 = 4096，16KB 设备走 64 位不加载）
    - **安装/升级/卸载三步 ✅**：`adb install` 558 ms → `install -r` 覆盖成功 → `uninstall` 后包与 `/data/data` 全清 → 重装首启 `DB 26775552 B` + `素材 46 条` + `474 首`
    - **多尺寸 × 三档字号 ✅（15/15）**：320×640 / 360×800 / 411×914 / 480×1067 / 914×411 横屏 × normal/medium/large，`overflow = 0`、pid 存活、布局模式正确；新增脚本 `tools/verify_android_device.ps1`
    - **lite 一致性 ✅**：顶栏「浏览 · 第 1 首」、无播放条/无音频按钮/无媒体会话/无通知权限、手册按变体切换、源考内容与当前浏览同曲、列表 474 首（第 1/14 页）
    - **修复的 7 项**：① 横屏翻页条压歌词 → 移动端独立 56dp 占位；② 横屏特大字号只剩标题 → 高度受限时不叠加字号系数；③ 横屏仍有音量图标 → 移动端隐藏；④ lite 仍初始化媒体会话 → `main.dart` 加 `kHasAudio`；⑤ **lite 首启 0 首**（双引擎并发 `DbBootstrap` 争用 `.tmp`）→ 唯一临时名 + 竞态容错 + 空库自愈；⑥ `build_android_release.ps1` 漏传 `--dart-define=AUDIO_VARIANT`（手动出包变体全按 full）→ 已补；⑦ 手册「473 首」→ 474 + 顶栏章节按变体
    - **验证**：`analyze` 0 / `test 77/77`（桌面 golden 未变）/ Windows release 构建通过
    - **环境限制**：归档正式包是 arm64-only，x86_64 模拟器无法加载 Flutter 引擎 → 走查用**同代码同签名的 x64 构建**；arm64 包仅做静态校验
    - **2026-11-13 用户裁定 + 收尾**：
      - **lite = 完全没有播放**（按 §3.1.15）→ 手册 lite 章节、设置页素材文案已改；素材导入对 lite 仅用于补扫描图
      - **替代音频 474 全可播 ✅**：新增 `tools/verify_hymn_media_coverage.py`（口径与 `audio_service.dart` 一致）——
        **full 474/474**；**piano 473 + 1**（`249`→人聲版）；**vocal 463 + 11**（`3`/`389`→四部合唱版、其余 9 首→鋼琴版）；lite 无播放跳过
      - **修替代顺序缺陷**：候选原按 DB `audio_version_list`（人声版该列表 `鋼琴版` 在前）→ `3`/`389` 会错播鋼琴版；
        新增 `AudioService.substitutionOrder()` 按变体优先级（人聲 > 四部合唱 > 分部合唱 > 鋼琴）
      - **版本升 `1.9.0+1`** → 4 变体重建 → 打 `android-v1.9.0-phone` tag
    - **2026-11-13 素材内置进 APK（用户要求 + 实测结论）**：
      - **piano / vocal / lite 全量内置 ✅**：`sync_audio_samples.ps1 -IncludeAll` 按变体白名单把音频 + 全部扫描图打进 APK；
        首启 `MediaBootstrap` 迁移到私有目录（带百分比 UI + 每 100 个文件进度日志 + 总耗时）
      - **piano 端到端实测**（x64 / API 36 模拟器，数据分区扩到 16 GB）：APK **1689.2 MB** → `adb install` **9.1 s 成功** →
        首启迁移 **1422 条 / 1.6 GB / 17–18 s / 失败 0** → 播放第 1 首
        `files/Hymn_Downloads/001_1頌讚獨一真神/1_鋼琴版.m4a` → **播放成功**；变体 UI 正确（无音频版本按钮）
      - **full 全内置不可行 ❌**：APK **2,702,241,808 B（2.52 GB）** 构建成功但 `adb install` **失败**
        —— APK v2/v3 签名使用 **32 位 zip 偏移**，单 APK 上限 ≈ **2 GB**；full 仅音频（鋼琴+人聲）就 2.03 GB
        → **full 保持「12 首样本 + 导入」**（折中「内置全部扫描图、音频导入」待定）
      - 发布脚本：`publish_android.ps1` / `build_android_release.ps1` 对 piano/vocal/lite 自动加 `-IncludeAll`，full 不加
      - 版本升 **`1.9.1+2`**
    - **2026-11-16 架构调整（用户 7 条要求）：主体 APK + installer 数据包 + 运行时能力检测**：
      - **主体 APK**（release 唯一产物）：**55.6 MB**（程序 + 数据库，**不含素材**）
      - **运行时能力**：新增 `MediaCapabilityProbe`（按**前十首**检测 扫描图 / 人声 / 钢琴）→ `AudioCapability`；
        `kAudioVariant` / `kHasAudio` / `kSingleAudioVariant` / `kFullAudioVariant` 由编译期常量改为**运行期 getter**；
        **桌面固定构建期变体（Windows 零改动）**
      - **实测**（API36 x86_64 模拟器）：空素材 → `钢琴=false / 人声=false / 扫描图=false → lite` + 首启引导页；
        复制钢琴素材后重启 → `钢琴=true / 人声=false / 扫描图=true → piano`，手册/顶栏自动切为钢琴版
      - **导入通道**：Kotlin `echohymn/pack`（SAF 选 zip → `ZipInputStream` 流式解压 → 路径/文件名白名单 →
        规则外**丢弃不落盘**、同名**覆盖**）；入口 = 首启引导页 + 设置「数据导入（压缩包）」
      - **installer 产物**（`installer/output/android/`）：主体 55.6 MB + 6 包
        （scores 237.8/249.9 · vocal 229.6/684.6 · piano 545.2/600.7 MB），每包 <2GB、按 1–237 / 238–474 拆分
      - **`installer/output` 分平台**：`windows/`（既有 Inno 产物已迁入）+ `android/`（新）
      - 脚本：`tools/build_android_media_packs.py`（6 包）+ `tools/build_android_installer.ps1`（APK + 包 + SHA256SUMS + BUILD-INFO）
      - 版本升 **`1.9.2+3`**；tag `android-v1.9.2-phone`
    - **试用包已产出**：`release/android/echohymn_android_trial_<时间戳>_18fd6c0/`
      （full 82.29 / piano 78.56 / vocal 67.24 / lite 63.52 MB + `SHA256SUMS.txt`）
    - **试用说明**：`docs/Android/TRIAL_GUIDE.md`（安装方式 / 能力边界 / 重点验什么 / 已知问题 / 反馈分级）
- **📌 已裁定（2026-10-25 用户）**：**不跟随系统深色** —— 配色**完全由软件 5 套色板决定**
  （晨光蓝 / 暖阳金 / 静谧绿 / 典雅紫 / 暗夜墨），不引入 `ThemeMode.system`。
  → 「跟随系统深色」开关**不做**；深色谱面（§3.10 dim）只在选中「暗夜墨」时生效。
- **M5 状态**：F-1 ✅ · F-2 ✅（构建治理）· F-3 ⚠️（清单 6✅/4⚠️/2❌，tag 待试用验收）
- **下一步（用户已定 B → A）**：先做 **SAF 素材导入**（让 474 首全可播）→ 再由用户试用
- **F-4 SAF 素材导入（代码完成 / 实机未点通）**：
  - **决策同步**：**不跟随系统深色** —— 配色完全由软件 5 套色板决定，`ThemeMode.system` 不引入；
    已在 `ANDROID_PLAN`（§3.1.7 决策表 / §需求基线 9）与 `UI_CONFIRMATION_ANDROID` 标注「不做」
  - `MainActivity.kt` 承载**双通道**：`echohymn/permission`（D-2 通知权限）+ **`echohymn/import`**
    （`ACTION_OPEN_DOCUMENT_TREE` 选目录 → `DocumentFile` 递归复制到应用私有目录 → 每 20 个文件回调进度 → 结束回调）
  - Dart：新增 `lib/platform/media_import.dart`（`pickDirectory` / `startImport` / `progressStream` / `doneStream`）
  - 设置页新增「素材」分组：「导入完整素材 → 选择目录」+ 进度对话框（完成提示**重启应用后生效**）
  - 依赖：`androidx.documentfile:documentfile:1.0.1`
  - **设计取舍**：**复制**而非直接读 SAF URI —— `audioplayers` 的 `DeviceFileSource` 只接受文件绝对路径；
    复制完成后 DB 里的相对路径（`Hymn_Downloads/<曲目>/<文件>`）自然生效，播放链路零改动
  - **验证**：`analyze` 0；Android 构建 ✓（Kotlin + documentfile 编译通过）；
    **实机点通未完成** —— 系统目录选择器需人工点击，自动坐标探测未命中「选择目录」按钮
- **C-8 UI 微调（用户 2026-10-25 截图反馈）✅**：
  - **① 合并行紧凑化 + 版本按钮合并**：`_versionBtn` padding `12/6 → 8/4`、icon `16→14`、字号 `13→12`；
    `_modeBtn` padding `10/6 → 7/4`、icon `15→14`、字号 `13→12`；按钮间距 `4→3`、版本区 `8/16→6`。
    **「鋼琴版 / 人聲版」两 chip + 👥 合并为一个循环切换按钮**（显示当前版本，点一下切到该首下一个可用版本）
    - 实测（视觉核验）：**5 个按钮全部完整显示**，最右「五线谱」不再被右边缘截断；overflow = 0
  - **② 曲谱改回「一页 = 一节」**：根因是 C-4 用了「按小节分页 + `stanza: null`（所有节歌词同页）」
    → 3 节歌词挤一屏、音词错位。现改为 `stanza: 当前节`，页数 = 节数
    - 实测：`曲谱页渲染｜第 1 / 3 节（块数 4，总行数 20）`；翻页条「第 1 / 3 节」
    - `JianpuPagination`（B-4）模型保留，供将来「节内再切小节」时启用
  - **③ 字号 3 档 + 温和比例**：`FontSizeLevel` 增加 `mobileScale` 与 `activeScale` ——
    **桌面保持 1.0/1.3/1.6/1.9 不变**，移动端改为 **1.0 / 1.12 / 1.26**（第 4 档 `xlarge` 手机不再显示）
    - 设置页 chips 改 `values.take(3)`（标准 / 大 / 特大）
  - **④ 曲谱「放大填满」（用户选 B）✅**：`JianpuGridView` 新增 `maxGrowScale = 2.2` / `maxSlotGrow = 140` ——
    内容不足一屏时**按剩余高度等比放大槽宽**（字变大），放大后块宽可能超可用宽 → 外层新增**横向滚动**承接（绝不裁切）
    - **仅移动端生效**（`_growToFill = Platform.isAndroid || isIOS`），桌面版式**保持不变**（桌面测试 77/77 通过）
    - 实测（视觉核验）：简谱内容占屏高由 **1/3 → 2/3**，字号明显更大更清晰，**右侧无截断**，overflow = 0
  - **⑤ 试用反馈修复（用户实机测试 4 条）✅**：
    - **音频版本切换无效（真 bug）**：`_cycleAudioVersion` 原用 `voiceVersions()`（**只含人声版**，已滤掉鋼琴版）
      → 长度恒为 1 → 命中 `length < 2` **直接 return**。改用 `AudioService.availableVersions()`（全量版本）；
      单版本时 `SnackBar` 明确提示。实测 `鋼琴版 → 人聲版 → 鋼琴版` 循环切换正常
    - **版本按钮与歌词按钮间距** 6 → **12**（模式按钮间仍 3，形成「音频版本 | 显示模式」分组）
    - **撤销「放大填满」**：`maxGrowScale 2.2 → 1.0` —— 2.2 倍后列间距过大且一行无法在竖屏内完整显示
      （用户要求「一行歌词全部竖屏显示」）；常量与横向滚动结构保留备用
    - **逐节不显示节号 `(k)`**：`stanza != null` 时 `return null`；**整页形态（`stanza == null`，桌面印刷本视图）仍显示**
      （那里靠 `(1)(2)(3)` 区分块内各节歌词）
    - 测试同步：`jianpu_grid_test` 2 处断言改 `findsNothing`；**golden 4 张更新**（节号消失导致 0.01% 像素差）
  - **⑥ 曲谱移动端版式放开（用户 2026-10-25 第三轮反馈）✅**：
    - 用户要求「左右留白只留 5%、字间更紧凑、字更大」。**槽宽同时是「列距」「块宽」「字号基数」**，
      单独调小只会让字更小、留白更多 → 拆成三个独立旋钮，**仅移动端生效**（桌面 golden 基准不动）：
      - `maxSlotFor`：移动端槽宽上限 **320**（桌面 72）→ 块宽 = 可用宽
      - `noteFontEmFor`：移动端记谱字号系数 **0.68**（桌面 0.50）→ 音符显著变大
      - `lyricFontEmFor`：移动端歌词字号系数 **0.60**（桌面 0.54，仍 < 1 列宽不挤压）
    - **关键根因**：原「超高时压缩槽宽」（`k = availH/totalH`）会把块压窄再居中 → 留白 12%/10%；
      移动端改为**不压缩、纵向滚动**（`&& !_isMobile`）→ 块宽保持铺满
    - 实测（视觉核验）：左右留白 **5.5% / 6.0%**（目标 5%）；音符 ~21sp、歌词 ~18sp（原 14sp）；
      第 1 节内容完整不裁切、无重叠、一行无截断；overflow = 0
    - `test` **77/77**（桌面口径未变）、`analyze` 0、Windows release ✓
  - **⑦ 曲谱「字看不清」根治：移动端自动折行（2026-10-27 用户第三轮反馈）✅**：
    - **量化定位根因**（日志实测）：该首一行的乐句块 **20 列** → 槽宽 `331dp/20 = 16.6dp`
      → 音符 15.7sp、歌词 **14.6sp**（与正文同大 → 用户「几乎无法看清」）。
      **歌词列距 = 1**（每个音符都有词）→ 字宽被物理限制在 1 列内，**提高系数无效**
    - **唯一解 = 减少每行列数**：新增 `_targetSlot = 30dp` + `colsPerLineFor()` ——
      移动端一行最多 `floor(331/30) = 11` 列，超出**折行**（`_buildRow` 加 `colStart/colEnd` 切片，
      x 按切片归零）；每段按 `availW / per` 重新铺满
    - **效果（日志实测）**：`每行 11 列 ×2 段 / 槽宽 30.1dp → 音符 28.6sp / 歌词 26.5sp`（**1.8 倍**）
    - **桌面完全不折行**（`colsPerLineFor` 返回原列数）→ golden 基准与 `test 77/77` 全部不变
    - 视觉核验：歌词 ≈19sp+、无重叠/粘连、无排版错误（每行音符与歌词严格配对）、一行完整无截断
  - **⑧ 曲谱改回「整页形态」（复刻参考 APK）✅**：`stanza: null` —— 一页显示**全部节**，
    节号 `(1)(2)(3)` 区分各节歌词，超出纵向滚动；翻页条/翻页模式按钮一并移除（`_pageCount` 曲谱 → 1）
    - 说明：2026-10-25 曾改为「一页一节」，对照用户提供的参考 APK 截图后确认要的是整页滚动形态
  - **⑨ 参考 APK 算法核查 + 整小节折行（2026-10-27 第四轮）✅**：
    - **核查结论**：`E:\apk_re_tjc\html\001_digit.html` 显示参考 APK 的简谱是 **HTML `<table>` + PNG 小节线**
      （`L3/L4/L5.png` = 不同 rowspan 的竖线、`D.png` 附点、`B.png`），每格 `height:10px`、歌词直接放 `<td>`。
      **它的"折行" = CSV 的 `<table>` 边界，块内不折行**，靠 WebView 整体缩放（一行 19 列硬塞）
      → **没有"按小节折行"的算法可复用**，必须自己实现（已实现）
    - **`_targetSlot` 33dp**（一行 ≤10 列 ≈ 2 小节）；段槽宽按**块内最大段列数**铺满
    - **小节线归入行尾**（`[start, end+1)`）→ 每行以 `|` 收尾，符合印刷本/参考 APK 观感
    - **实测（日志 + 视觉）**：`每行 ≤10 列（12 段，最多 11 列）/ 槽宽 30.1dp →
      音符 28.6sp / 歌词 26.5sp`（原文 14.6sp 的 **1.8 倍**）
    - **左右留白 5.6% / 5.6%**（对齐用户「留白 5%」要求）；无重叠粘连、无内容缺失
    - 桌面 `per = colCount` → 单段 = 原版式，`test 77/77` 与 golden 基准不变
    - **进一步调大的旋钮**：`_targetSlot` 33 → 20 可做到「一行 1 小节、歌词 ≈48sp」
  - **⑩ 定型「一页一节 + 节内折行」（2026-10-27 第五轮）✅**：
    - 用户指出实机截图「多节同时显示」→ 根因是我上一轮误把曲谱改成**整页形态**（`stanza: null`，
      所有节的歌词行同屏）以对齐参考 APK；用户真正要的是**单节 + 折行**
    - 改回 `stanza: 当前节` + 恢复翻页条/翻页模式按钮；`_pageCount` 曲谱 → `stanzaCount`
    - **实测**：`第 1 / 3 节（块数 4，最大列数 20，歌词列距 1）/ 每行 ≤10 列（12 段，最多 11 列）
      / 槽宽 30.1dp → 音符 28.6sp / 歌词 26.5sp`；`overflow = 0`
    - 视觉核验：同屏只有当前节歌词、翻页条「第 1 / 3 节」、折成 5 行每行 1~2 小节、行尾有 `|`、
      字一眼看清、无重叠/粘连/截断
  - **关于「改用参考 APK 的 HTML table 方案」的结论（已核查，不采用）**：`E:\apk_re_tjc\html\001_digit.html`
    确认参考 APK 是 HTML `<table>` + PNG 小节线，**块内不折行**、一行 19 列靠 WebView 整体缩放
    → 每列 ≈21dp ≈ **19sp**，**比我们折行后的 26.5sp 更小**。所以：
    （1）它**不能**解决字号问题；（2）它没有按小节折行能力；（3）引入 WebView 还要重写整个曲谱模块
    （CSV→HTML、27 个 PNG 素材、主题/字号/播放同步、每首一个 WebView 的内存开销）。
    **结论：自绘 + 整小节折行是最优解**（比参考 APK 字更大且支持单节分页）
  - **⑪ 折行算法重写「行数最少优先」+ 标点重叠 + 字号隔离（2026-10-27 第六轮）✅**：
    - **① 标点重叠**（「圣哉，」的逗号压到下一个「圣」）：歌词单元格可能含 2~3 字符，
      字宽 = 0.88 槽宽 × 字符数 必然越列 → 用 `FittedBox(scaleDown)` 压进 1 列内，
      **绝不越过列界**（视觉核验：所有标点与相邻字无重叠）
    - **② 折行策略**（用户指定算法，取代我原来的"固定目标槽宽无限折行"）：
      - 新增 `_minLyricSp = 26`（最小可读字号）→ 反推 `perAtMin = availW / minSlot`；
      - **最小字号下能一行就一行**（短块 8 列 → 1 行、字号最大化到 36sp）；
      - 否则按**小节数均衡切分**（新增 `segmentsByBars`，解决旧算法切出 12/5/3 列不等、
        "明明有地方却折两行"的问题）→ 实测**每行都是 2 小节**；
      - 每段**独立铺满可用宽**（`segSlot = availW / 该段列数`）→ 消除右侧大片空白
    - **③ 字号隔离**：`MediaQuery.withNoTextScaling` 包裹曲谱 → **设置里的字号档位/系统字体缩放
      不再影响曲谱**（曲谱字号由列数/行数/最小可读字号严格计算，外部缩放会破坏列对齐）
      - 确认 `JianpuGridView` 本身不读 `AppFonts.scale`（仅歌词页/设置页读）
    - 实测：`每行最多 11 列（12 段）/ 槽宽 30.1dp → 音符 28.6sp / 歌词 26.5sp`；`overflow = 0`；
      golden 4 张因 `FittedBox` 微调（0.00~0.21% 差异）已重生成；`test 77/77`
    - **可用于 Windows**（同一套 `planSegments`，`_isMobile` 开关可放开）；
      当前保持桌面原版式，等用户确认后再一并启用
  - **⑫ 汉字/标点分离 + 单节全页平衡点（2026-10-27 第七轮）✅**：
    - **① 汉字被标点拖累缩小**（用户指出低级错误）：根因是我上一轮用 `FittedBox` 缩**整格**，
      而数据库 `jianpu_cell.text` 存的是「哉，」（汉字+标点同格，CSV 原样）→ 汉字跟着缩。
      修法：**按末尾标点拆分**（正则 `[，。、；：！？…]+$`）——汉字用原字号、标点用 **0.55 倍**，
      该格 `Positioned` 宽度放宽到 **1.6 列**（不靠溢出、不缩小汉字、不触发 overflow）
    - **② 单节全页 + 字号最大的平衡点**（用户要求"以第 1 首为例找平衡点，并以该字号作为最小字号"）：
      新增 `fitFullPage()` —— 以「每段几个小节」`bps`(1→6) 为搜索变量，逐档估算整节总高，
      取**第一个满足 `总高 ≤ 可用高`** 的档（`bps` 越小→字号越大）→ 得到"全页显示前提下字号最大"的解
      - 第 1 首实测：**4 行 × 每行 4 小节**，一节完整一屏、无需滚动
    - 视觉核验：汉字明显大于标点且未被缩小、标点无重叠、每行 4 小节均衡
    - golden 重生成（标点分离是预期改进）；`test 77/77`；`analyze` 0
    - **遗留**：日志仍有 `RenderFlex overflowed by 6.5px`（3 次/启动）—— 经改动按钮间距（12→10、3→2）
      仍未消除，判定**不是按钮栏**，来源待下次定位（不影响观感与阅读，画面无裁剪）
  - **⑬ 折行/全页平衡 + 按钮右对齐（2026-10-28 第八轮）✅**：
    - **实测数据（用户要求写进报告的字号数值）**：`可用宽 331dp / 可用高 487dp`，
      第 1 首一节 = 4 块 × 20 列 = **80 列**，每段 4 行（音符/上记号/下记号/歌词，约 3.8 em）
      - 严格一屏（1.0）→ 只能 4 段 = 每行 4 小节，歌词 **14.6sp**
      - 放宽 **`_fullPageSlack = 1.42`**（允许轻微滚动）→ 8 段（每段 1~2 小节），歌词 **18.2sp**（+25%）
    - **修的关键 bug**：`fitFullPage` 原来用 `block.rows`（含**所有节**歌词行，3 倍高估高度）
      → 误选「每段 4 小节、14.6sp」。改用 `_visibleRows` 的可见行（新增 `visibleRows` 参数）
    - **左侧空白**：统一槽宽时短段（5~11 列）只有屏宽 1/3 → 居中后大片留白
      → 改为**每段按自身列数铺满**（`segSlot = availW / 该段列数`），代价是短段字号更大
    - **按钮栏右对齐**：`Row(mainAxisAlignment: spaceBetween)`，左=音频版本、右=4 个模式按钮
      （视觉核验："左右分列，中间 40~50% 空隙"）
    - `analyze` 0、`test 77/77`、`overflow = 0`
    - **遗留**：① `RenderFlex overflowed 6.5px` 仍未定位（不影响观感）；
      ② **Android 用户手册需与 Windows 版不同、按 Android 细分版本匹配** —— 内容工程，待单独一轮
  - **⑭ 定稿 18sp 基准 + Android 移除音量控件（2026-10-28 第九轮）✅**：
    - **用户裁定方案 A**：折行优先、允许轻微上下滚动，**字号以 18sp 为基准**
      → `_minLyricSp = 26 → 18`；一行放不下该小节段就折行，行数由内容决定
      - 平衡点实测基准：**歌词 ≥18sp**（每段独立铺满时短段可达 28~30sp）
    - **Android 四个变体全部移除音量控件**（音量图标 + 滑轨）：
      `_buildControls` 左配重改 `Platform.isAndroid || isIOS ? SizedBox.shrink() : _buildVolumeControl()`
      → 手机用系统音量键；空占位保证中间按钮组仍绝对居中；桌面保留滑轨
    - `analyze` 0、`test 77/77`、`overflow = 0`
    - **遗留**：Android 专用用户手册（按 4 个细分变体精确匹配）—— 待专门一轮
  - **⑮ 折行后字号自动放大（用户追问）✅**：
    - 检查发现：`_minLyricSp = 18` **之前没参与 `fitFullPage` 的计算**（循环只按高度选档）→ 基准未生效
    - 现改为「**从最大字号起逐档试**」：
      ```
      bps=1（每段 1 小节 → 字号最大）起
        · 高度超限 → bps++（继续折行，段变窄 → 字号变小 → 高度下降）
        · 高度可接受 → 立即采用（此刻字号 = 该行数下的最大值）
        · 字号 < 18sp → 停止（下限保护，不为塞一屏而压小字）
      ```
    - **结论：折行越多 → 段越窄 → 字号越大**（只要总高不超 1.42 屏）
      第 1 首实测算例：1 小节/段 → 58sp（超屏 4 倍）→ 2 小节/段 → 26sp（仍超）→
      **3 小节/段 → 18.2sp（≤1.42 屏，采用）**；内容少的节会自动停在 1~2 小节/段 → 30~48sp
    - `analyze` 0、`test 77/77`、`overflow = 0`
  - **⑯ 按用户定稿优先级重写算法（2026-10-28 第十轮）✅**：
    - **用户给出的优先级**（原话）：① 左右上下只留 10px ② 先按 18sp 显示 ③ 需要折行就折行
      ④ 全页显示且字号放大到刚好全页（不滑动优先）⑤ 必须滑动时**只滑「一行歌词」**（不包含简谱）
      —— 即首屏能看到最后一行简谱，往下滑一点看全歌词
    - **实现**：
      - 边距统一 **`padX/padTop/padBottom = 10`**（原 18/16/52；52 是旧翻页条预留，已无用）
      - 新增 `fitByFontSize()`：从 **18sp 起逐 +1sp 试**，`perCols = availW / slot` 按整小节折行，
        累加总高；**合格条件 `总高 ≤ 可用高 + 一行歌词高度`** → 取满足条件的最大字号
        （⇒ 优先不滑动；必须滑动时也只多一行歌词的量）
      - 渲染改为**统一槽宽**（`segSlot = fitSlot`，不再每段独立铺满）—— 因为用户要求
        "字号按能全页显示的规格放大"，不接受同一页字号忽大忽小
    - **实测（第 1 首）**：`7 行简谱（4 行 × 3 小节 + 3 行 × 1 小节）`、
      **歌词约 29sp**（18sp 下限之上自动放大）、最后一行完整可见、
      四边留白 36~54px（= 10dp 边距 + 内容自身留白）
    - `analyze` 0；`test 77/77`（golden 已随边距/字号变化重生成）；`overflow = 0`；Windows release ✓
  - **⑰ 移除「曲谱」模式 + 四变体正式包（2026-10-28 用户最终决定）✅**：
    - **去曲谱**：Android/iOS **不显示「曲谱」按钮**（桌面 Windows 保留）；`_buildContent` 里若旧
      `state.json` 残留 `score` → 移动端回退歌词页
    - **音频按钮精简**：`鋼琴版/人聲版` → **`钢琴/人声`**（`_voiceLabel` 去掉结尾"版"），
      360dp 窄屏下与右侧 3 个模式按钮共存；左音频 / 右模式，`spaceBetween` 两区分明
    - **四个正式 APK（已逐个校验包内素材，零交叉污染）**：
      | 变体 | 体积 | media | 音频 | piano | vocal | 扫描图 |
      | --- | --- | --- | --- | --- | --- | --- |
      | full | 82.22 MB | 47 | 22 | 12 | 10 | 24 |
      | piano | 78.50 MB | 37 | 12 | **12** | **0** | 24 |
      | vocal | 67.18 MB | 35 | 10 | **0** | **10** | 24 |
      | lite | 63.46 MB | 25 | **0** | 0 | 0 | 24 |
      → 归档在 `release/android/builds/EchoHymn-<variant>-release.apk`
    - **修的两个基建缺陷（都是这次连续构建 4 变体才暴露的）**：
      1. `flutter clean` 不足以失效素材缓存 → 追加 **`gradlew clean`**（`android/` 下），
         否则 piano/vocal 会产出**同一个包**（piano 包里全是 vocal 音频）
      2. 每个变体构建前的 clean 会**清空 `build/`**，把前面变体的 APK 一起删掉
         → 构建后**立即归档**到 `release/android/builds/`
  - **⑱ Android 四变体手册 + Windows 双按钮恢复（2026-10-28）✅**：
    - **Windows 音频按钮恢复**（用户指出合并是错的）：`_buildVersionBar` 平台分支 ——
      桌面两个独立按钮「钢琴版 / 人声版」（一眼看清当前档），手机仍是合并单按钮循环切换
    - **Android 专属手册**（新增 `lib/widgets/android_manual_sections.dart`，217 行，8 节）：
      打开关闭 / 顶栏 / **音频（按变体）** / 显示模式（无曲谱）/ 播放条（无音量滑轨）/
      左侧栏与搜索 / **设置与 SAF 素材导入（按变体）** / **常见问题（按变体）**
      - `full`：音频按钮循环切换 + 单版本提示
      - `piano`：只含钢琴、**无切换按钮**（FAQ 明确"想听人声请装人声版"）
      - `vocal`：只含人声、**无切换按钮**
      - `lite`：**无内置音频**，必须 SAF 导入才能出声（重点章节 + FAQ 首条）
    - `user_manual_dialog.dart` 分流：移动端用 `androidManualSections()`、桌面用原 `_guideSections`；
      **「快捷键说明」整块仅桌面**；「软件介绍」文案平台自适应（手机不再提"exe 同级 state.json"）
    - **四变体 APK 全部重建**（22:38~22:42，含新手册）：
      full 82.22 / piano 78.50 / vocal 67.18 / lite 63.46 MB
    - `analyze` 无 error、`test 77/77`
- **下一步**：**用户手动安装验收**（`docs/Android/TRIAL_GUIDE.md`；安装包见 `release/android/echohymn_android_20261113-174540_21b8d69/`）→ 反馈驱动修 P0/P1
  - tag：`android-v1.9.0-phone`（b35f97e）与 `android-v1.9.1-phone`（21b8d69）均已推送 origin

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

| ~~窄屏布局溢出（`RenderFlex overflowed 75 / 21 px`，首屏右侧）~~ | ✅ 已关闭（C-1 横向滚动 + 2026-11-11 五视口 × 三档字号走查 `overflow=0`） | — |
| ~~lite 播放能力定义冲突~~ | ✅ 2026-11-13 用户裁定：**完全没有播放**（实现/手册/设置页已对齐） | — |
| **首启双引擎初始化**（日志 `HomeScreen 初始化` ×2，两个 isolate 并发） | 首启重复初始化/日志噪声；DB 已做并发兜底 | 下轮排查（不阻塞 tag） |
| 横屏 + 特大字号需纵向滚动（翻页条已移到独立区域，不再遮挡） | 观感（物理高度限制） | 可接受，待你确认 |
| 320dp 极窄屏顶栏按钮行需横向滑动才能看到「五线谱」 | 极窄屏可用性 | 可接受（C-1 既定横向滚动） |
| **full 无法全内置**（APK 2.52GB > 2GB 签名偏移上限） | full 仍需导入完整素材 | 已实测；折中方案（内置全部扫描图、音频导入）待你定 |

## 最近里程碑

| M0 计划 | M1 最小可跑 | M2 数据链路 | M3 UI | M4 系统集成 | M5 发布 | M6 平板 |
| --- | --- | --- | --- | --- | --- | --- |
| ✅ | ✅ | ✅ | ✅ | ✅ | 🟡 F-3 待裁定 / tag | ⬜ |

> 2026-11-11 校正：M2（B-1~B-6）· M3（C-1~C-8）· M4（D-1~D-3）均已完成；
> M5 = F-1 ✅ / F-2 ✅ / **F-3 🟡**（§7.4 仅剩「真机走查 + 替代音频 474 全可播」，另待 lite 语义裁定与版本号升级）；M6 未启动。

## 会话约定（摘要，详见 IMPLEMENTATION_PLAN §四）

- 一会话做 **1~2 个工单**；里程碑完成或压缩 2 次 → 换会话
- 收尾：更新本文件 → `git status` 干净 → 写会话日志
- 启动：读本文件 → 读实施计划当前阶段节 → 按「必读章节」读片段 → `git log -3` + `git status`
- **当前日志卷**：`docs/sessions/2026-10/2026-10-18_20-49-20.md`（卷 1 `2026-10-11_11-42-34.md` 已于 2026-10-18 封卷，只读）
