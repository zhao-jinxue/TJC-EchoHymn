# 简谱谱面自测方案（APK CSV 网格管线）

> **2026-09-22 数据源切换**：谱面数据源由「印刷 PDF 抽取管线」改为
> **第三方 TJC 赞美诗 APK 的 `assets/NNN.csv` 谱面网格**（474 首）
> —— 机制见 `docs/knowledge/TJC_APK_JIANPU_RENDER.md`。
> 旧管线（`hymn_score*` / `hymn_codepoint_map` 表 + `tools/score_selftest.py`）
> **已停用并删除数据**，其代码与结论保留在 git 历史中
> （回看：`git log -- tools/score_selftest.py`、`git show <commit>:docs/Windows/SCORE_SELFTEST.md`）。

## 一、数据流

```text
APK(assets/NNN.csv)  →  tools/import_apk_csv.py  →  data/tjc_hymn.db
                                                    ├── jianpu_score （一首一行：行数/列数/块数/节数/对齐标记）
                                                    ├── jianpu_row   （一行一格：行类型/节号/列数/原样文本）
                                                    └── jianpu_cell  （列 = 拍点：音符/记号/小节线/歌词音节）
                                     ↓
        SqliteRepository.loadJianpuScore()  →  JianpuScore  →  JianpuGridView（EchoHymn 风格渲染）
```

**核心不变式：同一列 = 同一拍点。** 音符、记号（减时线 / 低·高音点 / 延长记号）、
小节线（`rowspan` 跨行）、歌词音节全部落在同一列 —— 对齐来自**数据**，
渲染层不做任何时间→像素换算。

## 二、自测层级（`tools/jianpu_csv_selftest.py`）

| 层 | 内容 | 命令 |
| --- | --- | --- |
| L0 | **DB ↔ CSV 逐格一致**：全库 474 首，逐行「原样文本」+ 逐格 `kind/sym/degree/beams/dots/fermata/rowspan` 比对 | `python tools/jianpu_csv_selftest.py` |
| L1 | **列对齐不变式**：同一块（同一次 `<table>`）内各行单元格数一致 | 同上 |
| L2 | **可读网格**：指定一首按「行 × 列」打印（人眼复核记号/音符/歌词位置） | `--hymn 009` |
| L3 | **实机交叉验证**：与 `uiautomator dump` 的 WebView 元素级快照逐元素比对（`<img>` 的 text = 图片文件名；行带按内容累加配对） | `--hymn 009 --ui <ui8.xml>` |

> L3 的证据文件（uiautomator XML）在逆向工作区 `E:\apk_re_tjc`（仓库外）。

### 当前基线（2026-09-22）

| 项 | 值 |
| --- | --- |
| CSV 文件数 | 474（`001`~`469` + 5 组甲乙变体 `051a/051b/…`） |
| 库内诗歌 | 473 首（第 349 首按用户要求整首移出；CSV 有 `349`，属预期「库外」） |
| 谱面行 | **21819 行**（主旋律行 7715 / 歌词行 5585 / 记号行 8515） |
| 单元格 | 583699 格（**入库 321703 格**；空单元格与被小节线覆盖的占位格不落库） |
| 单块列宽 | 13 ~ 50（中位 22）；每首块数 2 ~ 8 |
| L0 / L3 | **PASS**（L0 差异 0；L3 第 9 首 30/30 行逐元素一致） |
| L1 例外 | 3 份源数据自身块内行宽不一致（`163`/`197`/`297`），渲染按块内最大列宽处理 |

## 三、App 侧验证

| 项 | 命令 | 基线 |
| --- | --- | --- |
| 静态分析 | `cd hymn_app && flutter analyze` | **No issues found** |
| 单元/组件测试 | `cd hymn_app && flutter test` | **42 通过**（含实库网格断言、歌词音节列 == 音符列、渲染后同列同一 x、按节过滤、块内行宽差异歌渲染） |
| 版式快照 | `flutter test --update-goldens test/jianpu_golden_test.dart` | `jianpu_009.png`（整页=曲谱）/ `jianpu_009_stanza2.png`（一页一节=简谱）/ `jianpu_163.png`（块内行宽差异歌，按块宽渲染） |

关键测试文件：`hymn_app/test/jianpu_grid_test.dart`、`hymn_app/test/jianpu_golden_test.dart`

### 按节显示（一页一节）

- 实现：`JianpuGridView(stanza: k)` 过滤**歌词行**；`hymn_display` 里 `_pageCount = 谱面节数`，
  复用歌词页的翻页条与 `autoPageIndexFor`（自动模式跟随播放进度切节）。
- **数据前提（务必理解）**：全库 474 首实测**没有**「一块一节」结构（每块仅 1 节歌词且节号互异 = 0 首），
  即**一段旋律承载多节歌词** → 按节过滤只减少歌词行数，**谱面内容不随节变化**；
  切到某节时若某块缺该节歌词（副歌/叠句块只写一行词），该块只有谱行、无歌词（同印刷本）。
- 节号标签 `(k)` 只在每首**第 1 个乐句块**里给出（其余块直接写音节）→ 断言/统计需按此口径。
- **模式归属（v1.7.2 对调）**：一页一节网格挂在「**曲谱**」按钮；「**简谱**」按钮恢复为
  扫描图片（印刷四声部谱，参考图）；整页多节并列形态移除（用户不要"多声部"观感，
  网格只呈现 CSV 的主旋律**单声部** + 一页一行歌词）。

### 按块宽渲染（2026-09-23，v1.7.1）

- 每个乐句块用**自己的列数**铺满可用宽（与 APK 每表独立排布同构；列数少的块字号更大）；
- 块内行宽差异（`163`/`197`/`297`，源数据自身问题）按**块内最大行宽**（`JianpuBlock.colCount`）处理：
  窄行右侧留空、同列仍同 x、不与其它行错位；
- 总像素高超过可用高时**整体等比收缩**（保持块间字号比例），否则纵向滚动；
- 「播放时高亮当前拍点/乐句」经用户确认**不做**（已从遗留清单移除）。
- **单声部过滤（v1.7.3）**：源 CSV 为**四部合唱谱**（每块 = S,A,词,T,B 五行组）；
  `JianpuScore.build(firstVoiceOnly: true)` 每块只保留第一个「记号上+音符+记号下」声部组
  + 全部歌词行（「曲谱」模式使用）；小节线跨行 = 块内连续乐谱行数（过滤后 3 / 全声部 6，
  与源 `rowspan` 等价）。全声部形态 = `firstVoiceOnly: false`（组件快照/自测）。
- **垂直居中（v1.7.4）**：曲谱页内容不足一屏时**整块垂直居中**（与歌词页同口径：
  `ConstrainedBox(minHeight: 视口净高)` + `MainAxisAlignment.center`）；超一屏从顶滚动、不裁顶。

> ⚠️ **字体码位坑**（2026-09-22 实测）：印刷记谱字体 `EchoJianpu` 的数字字形挂在
> **CJK 码位**（`0x4e52` = `1` … `0x4e5d` = `7`；`0x5d4c` = `0`；`0x5d1f` = 增时线；
> `0x5d3d` = 附点），**不是** U+0031 等 ASCII 码位。
> 视图必须按码位取字形（`String.fromCharCode(...)`），否则整行数字静默不可见
> （golden 快照正是为捕捉此类"编译通过但看不见"的问题而设）。

## 四、变更谱面数据时

1. 改 `tools/import_apk_csv.py`（解析规则 / 表结构）后 **必须重跑 L0 + L1**；
2. 表结构变更后同步改 `SqliteRepository.loadJianpuScore()` 与 `lib/models/jianpu_grid.dart`；
3. 新增记号语义时，同时补 `JianpuGridView` 绘制分支与 `test/jianpu_grid_test.dart` 断言；
4. 数据侧统计口径变化（行数/格数/列宽）→ 更新本文档「当前基线」表。
