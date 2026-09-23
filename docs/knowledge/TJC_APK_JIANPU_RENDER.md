# TJC 赞美诗 Android APK：简谱 / 歌词 / 五线谱 渲染机制（逆向复原）

> 逆向对象：`com.tinanlin.tjc_hymn_cn_v2.4.2`（TJC 赞美诗，纯 Java/Kotlin，单 `classes.dex`，无 native）
> 取证日期：2026-09-22；逆向工作区（仓库外）：`E:\apk_re_tjc`（脚本 + 截图 + ui dump 全部保留）
> 用途：EchoHymn 曲谱渲染的**对照参考**与**对齐校验思路**来源；EchoHymn 侧不直接采用其技术栈（见 §7）。

---

## 1. 结论速览

1. **「简谱与歌词同步显示」不是在运行时算出来的**：谱面数据 `assets/NNN.csv` 本身就是一张
   **二维网格（行 × 列）**，**同一列 = 同一音符位（同一拍点）**；简谱数字、八度点/减时线/延长记号、
   小节线、**歌词音节**全部写在**同一列**的单元格里 —— **对齐在数据里完成**。
2. 简谱页 = 把 CSV 逐行读入后**一串 `String.replace`** 拼成 HTML `<table>`，交给 `WebView` 渲染；
   **无 JS、无 CSS 定位、无图片坐标**。
3. 歌词页 = `Html.fromHtml(歌词)` 塞进 **纯 `TextView02`**（不是 WebView），底部按节翻页（`1/N`）+ 缩放按钮。
4. 五线谱页 = `WebView` 加载**印刷版整页扫描图** `assets/staff_NNN.gif`（原谱自带简谱数字行 + SATB + fermata）。
5. 谱面符号全部是 **10×10 / 2×N 像素的小 PNG**，文件名即"字形叠加"（如 `BBDD.png` = 两条减时线 + 两个低音点）；
   `E.png` = 弧线 + 圆点 = **延长记号（fermata）**。

---

## 2. 数据模型：`assets/NNN.csv`

- **474 份 CSV**（`assets/NNN.csv`，与 `staff_NNN.gif`、`res/raw/hymn_NNN.mid` 一一对应；
  `assets/` 目录共 994 个文件 = 474 CSV + 474 线谱 GIF + 符号/图标 PNG），UTF-8（带 BOM），**纯文本网格**，逗号分隔；
- 网格尺寸**随曲目可变**：行数 22~108、列数 15~52（中位 44 行 × 28 列）；
  **渲染列数 = 列数 − 2**（`T`/`R` 只做行首尾标记）：如 001 = 44×22 → 20 列，009 = 30×27 → 25 列；
- 每行首格 `T`、尾格 `R`；`K` 表示"此处换表（`</table><br>` + 新 `<table>`）"；
- 单曲示例（009「向主欢呼」）30 行 × 27 列，结构：

```text
row0 : T , '' , '' , L6 , '' , '' , '' , '' , L6 , '' , '' , MEN , '' , L6 , '' , '' , '' , '' , L6 , '' , '' , MEN , '' , '' , '' , '' , R
row1 : T , '' , 1  , X  , 1  , 7  , 6  , 5  , X  , 1  , 2  , 3   , 3  , X  , 3  , 3  , 2  , 1  , X  , 4  , 3  , 2   , '' , '' , '' , '' , R
row2 : T , '' , '' , X  , '' , MDN, MDN, MDN, X  , '' , '' , ''  , '' , X  , '' , '' , '' , '' , X  , '' , '' , ''  , '' , '' , '' , '' , R
row3 : T , '' , '' , X  , '' , '' , '' , '' , X  , '' , '' , MEN , '' , X  , '' , '' , '' , '' , X  , '' , '' , MEN , '' , '' , '' , '' , R
row4 : T , '' , 5  , X  , 5  , 5  , 3  , 3  , X  , 3  , 5  , 5   , 5  , X  , 5  , 1  , 7  , 1  , X  , 1  , 1  , 7   , …  , R
row5 : T , … , MDN …,                                                            // 低音点行
row6 : T , (1), 普 , '' , 世 , 万 , 族 , 向 , '' , 主 , 欢 , 呼， , 怀 , '' , 恩、 , 感 , 谢， , 庆 , '' , 幸 , 鼓 , 舞   , ！ , '' , '' , '' , R
row7 : T , (2), 应 , …
row8 : T , (3), 天 , …
```

- 行角色（同一"乐句块"内的固定次序）：
  `[音符上一行 = 高八度点/延长记号] [音符行] [音符下一行 = 减时线/低音点]` ×2，然后若干行歌词（每行 = 一"节"歌词）。
- **列角色**：第 1 列为节号/序号区；第 2~21 列为**音符区（20 个音符位）**；其后为尾巴区。
- `X` = 占位符，表示"此格被上方跨行的小节线图（`rowspan`）覆盖"，渲染时被**整段删除**（连逗号一起）。

---

## 3. 渲染算法（`OneHymnActivity.showView()`）

严格按反汇编顺序执行（顺序敏感，否则 `M…N` 会被 `,` 规则吃坏）：

```python
s = raw_csv
s = s.replace(',R', '</td></tr>')                                  # 行结束
s = s.replace('T,', '<tr style="height:10px"><td>')                # 行开始
for n in (7, 6, 5, 4, 3, 2):                                       # 小节线/终止线（长度递减）
    s = s.replace(f',L{n}', f'</td><td rowspan={n}>'
                            f'<img src="file:///android_asset/L{n}.png">')
s = s.replace(',X', '')                                            # 占位格删除
s = s.replace('M', '<img src="file:///android_asset/')             # 符号图（M…N 包裹）
s = s.replace('N', '.png">')
s = s.replace('K', '</table><br><table style="color:#FFFFFF;" cellpadding="0">')  # 换表
s = s.replace(',', '</td><td>')                                    # 单元格分隔
html = ('<html><body><table style="color:#FFFFFF;" cellpadding="0">' + s +
        '</table><br><br><br><br></body></html>')
webview.loadDataWithBaseURL(None, html, 'text/html', 'UTF-8', None)
```

- `has_border` 恒为假 → 用 `<table style="color:#FFFFFF;" cellpadding="0">`（白字、无边框、无内边距）；
- `WebView.setBackgroundColor(0)` → **纯黑底**；`TextView`（歌词页）另有 `setTextColor(0xFFFFFF80)` 等；
- `WebSettings.setBuiltInZoomControls(true)` + `setInitialScale(...)`（页面整体缩放，实机表宽约 1043px）；
- HTML 末尾 4 个 `<br>` = 让长页面底部可滚动到底（不是内容）。

**同步不变式（可机器校验）**：
`每行有效列数 = 本行 <td> 数 + 被上方 rowspan 持续覆盖的格子数` 应**恒定**
（009 = 25 列；其中音符区 20 列）。任何数据/规则改动破坏它 → 简谱与歌词立刻错位。

---

## 4. 符号字典（`assets/*.png`，共 29 张）

`M` + 字形序列 + `N` → `<img src="<字形序列>.png">`；**序列最后一位字形贴着音符**，更早的字形向外叠加。

| token | 图片 | 位图形状 | 语义 |
| --- | --- | --- | --- |
| `MBN` | `B.png` | 1 条横线 | 减时线（八分音符） |
| `MBBN` | `BB.png` | 2 条横线 | 十六分音符 |
| `MDN` | `D.png` | 1 个点 | 低八度点 |
| `MDDN` | `DD.png` | 2 个点 | 倍低八度 |
| `MBDN` | `BD.png` | 横线 + 点 | 八分 + 低八度 |
| `MBDDN` | `BDD.png` | 横线 + 2 点 | 八分 + 倍低八度 |
| `MBBDN` | `BBD.png` | 2 横线 + 点 | 十六分 + 低八度 |
| `MBBDDN` | `BBDD.png` | 2 横线 + 2 点 | 十六分 + 倍低八度 |
| `MUDN` | `UD.png` | 1 个点（偏下） | **高八度点**（音符上方） |
| `MEN` | `E.png` | **弧线 ⌒ + 弧下圆点** | **延长记号（fermata）** |
| `MEUDN` | `EUD.png` | ⌒+点 + 高八度点 | 延长记号 + 高八度点 |
| `,L2`~`,L7` | `L2..L7.png` | 2px 竖线（高 31/48/60/70/80/80px） | 小节线 / 终止线（配 `rowspan=N` 跨 N 行） |
| `num_0`~`num_9` / `num_bar` / `num_dot` | —— | —— | **遗留未使用**（数字已改用纯文本） |

判定方法与依据：

- **位图实测**：`sym_probe.py`（逐像素 `#/+`，输出 `sym_probe.txt`；`shots/sym_montage_big.png` 为 16× 放大图）；
- **位置统计**：`sym_rows.py` —— 全库 474 份 CSV、7715 个音符行，按「音符行的上一行 / 下一行」计数：

| 图片 | 上一行（音符上方） | 下一行（音符下方） |
| --- | --- | --- |
| `UD` | **5208** | 65 |
| `E` | **169** | 3 |
| `EUD` | **26** | 1 |
| `D` | 9530 | **23451** |
| `B` | 18989 | **27579** |
| `DD` | 19 | **35** |

- **MIDI 反证**：`midi_notes.py` 解析 `res/raw/hymn_NNN.mid`（format 1 / 4 轨 SATB / division 192），
  009 主旋律（track1，主音 = 67 = G4）前 16 音 = `1,1,7,6,5,1,2,3,3,3,3,2,1,4,3,2`，
  其中 `7/6/5` = `66/64/62`（低一个八度）↔ CSV 该三列恰为 `MDN`；而 `E` 所在两音（`71`/`69`）与相邻音同八度
  → `E` **不是**八度记号；又因 `EUD` = `E` + 八度点可共存 → `E` 与八度记号正交 ⇒ **延长记号**。

---

## 5. 三视图实现与实机实测

| 视图 | 承载控件 | 关键证据 | 内容 |
| --- | --- | --- | --- |
| 简谱 | `WebView`（黑底） | `ui7.xml`/`ui8.xml`：30 个 `<tr>`（= 30 行 CSV）、每行 21 或 25 个 `<td>`、91 个 `Image` 节点 | §3 生成的 HTML 表格 |
| 五线谱 | `WebView` 内 `<img>` | `ui9.xml`：`Image` 节点 `text='staff_009'`、bounds `(10,403)-(1080,?)` | 印刷版整页扫描图 `assets/staff_009.gif`（含原谱简谱数字行、SATB 四声部、乐句末 fermata） |
| 歌词 | **`TextView02`**（非 WebView） | `ui10.xml`：`TextView02` text = `'普世万族向主欢呼，怀恩感德，庆幸鼓舞！\n齐来主前放声歌颂，以灵以诚，敬拜天父。\n\n'`；同页 `TextViewSec` = `1/3`、`ButtonSecLeft/Right` | `Html.fromHtml(歌词)`；按节分页 + 缩放 |

- 顶部工具条按钮（`id`）：`ButtonHymnLeft`(上一首) / `ButtonMidi`(MIDI) / `ButtonMp3`(MP3) /
  `imageButton_change_view`(切换视图，`cx=756, cy=304`，1080×~2280 屏) / `ButtonHymnRight`(下一首)；
- 视图状态仅由 `TjcHymnApp.cur_mode` 一个 int 表达（实测点击循环：简谱 → 五线谱 → 歌词 → 简谱）；
- **全 DEX 内不存在 `Spannable`/`setSpan`**（`grep -c` = 0）→ 播放**不做**逐字/逐句高亮，
  简谱页是**静态页面**；"同步"完全由 §2 的列对齐承担。

---

## 6. 元素级验证证据（第 009 首）

`uiautomator dump` 的无障碍树把 WebView 内部结构还原为矩阵：`<tr>` = 一个 `View`、
**每个 `<td>` 也是一个 `View`（含空单元格）**、`<img>` = `Image` 且 **`text` = 图片文件名**。
据此把「App 实际渲染」与「CSV 推导」逐格比对（`ui_grid.py` / `table_dump.py`）：

| 实测（y 坐标 / 内容） | CSV 推导 | 判定 |
| --- | --- | --- |
| y=416 `[E] [E]` | row0 第 11/21 列 `MEN` | ✅ |
| y=427 `[L6] [L6] [L6] [L6]` | row0 第 3/8/13/18 列 `,L6`（rowspan=6） | ✅ |
| y=448 `1 1 7 6 5 1 2 3 3 3 3 2 1 4 3 2`（16 个文字节点） | row1 音符 16 个（同序列） | ✅ 逐字相同 |
| y=503 `[D] [D] [D]` | row2 第 5/6/7 列 `MDN` | ✅ |
| y=534 `[E] [E]` | row3 第 11/21 列 `MEN` | ✅ |
| y=563 `5 5 5 3 3 3 5 5 5 5 1 7 1 1 1 7` | row4 音符 16 个 | ✅ |
| y=618 `[D] ×11` | row5 `MDN` × 11 | ✅ |

**歌词与音符的同列关系**（第 009 首第 1 乐句）：
歌词音节落在第 `2,4,5,6,7,9,10,11,12,14,15,16,17,19,20,21` 列，
与音符行音符所在列**完全相同**（16 音节 ↔ 16 音符）；MIDI 主旋律音高序列亦与音符行逐音相同
→ **歌词 = 主旋律声部，按列同步**。

---

## 7. 对 EchoHymn 的对照与借鉴

| APK 做法 | EchoHymn 对应实现 | 结论 |
| --- | --- | --- |
| 网格**同列**隐式对齐（列 = 拍点），对齐信息不落库 | `data/tjc_hymn.db` → `hymn_score_char`（`syllable`/`note_index`/`beat`/`delta`/`span`/`align_ok`）**显式对齐元数据** | EchoHymn 的显式方案更可校验；**借鉴点在于"用网格做校验"**：把 `code_seq` 展成"列 = 拍点"的网格后校验**每行有效列数恒定**、`align_ok` 与网格一致 |
| 符号插图命名法（`B/D/U/E/L*`） | `hymn_codepoint_map`（`codepoint` ↔ `sym`）+ `EchoJianpu` 字体 | 用 APK 的符号分类**交叉校验** `code_seq` 码位语义（低音点/减时线/延长记号/小节线 的数量与位置应可互相印证） |
| 简谱页 = `WebView` + 动态 HTML 表格 | 曲谱视图 = **字体原生渲染**（v1.6.0，字形自带装饰 + 墨迹度量排版） | **不采用 WebView 路线**；仅借用"列 = 拍点"的数据/校验思路与"网格可视化调试"手法 |
| 歌词页 = 整块文本 + 按节翻页 + 缩放 | 歌词页已同形态（v1.6.2 整块垂直居中 + 底部翻页条） | 方向一致，无需改动 |
| 五线谱页 = 整页扫描图 + 缩放 | `_ScoreImageView`（宽度驱动缩放，Ctrl+滚轮） | 方向一致 |
| 符号 PNG 需自带缩放/DPI 适配 | 字体渲染分辨率无关 | 字体方案更优 |

**可落地的小工具建议（尚未实施）**：在 `tools/` 增加一个"网格不变式"自检脚本
（输入 `hymn_score_line/char` → 输出每行有效列数 + 与 `align_ok` 的差异清单），
与既有 `tools/score_selftest.py` 的元素级比对互补。

---

## 8. 复现 / 复查步骤

工作区：`E:\apk_re_tjc`（脚本均为 UTF-8，pwsh 下建议 `python 脚本.py > 输出.txt` 再读文件，避免终端编码噪声）。

```powershell
$adb = 'D:\Android\Sdk\platform-tools\adb.exe'
# 0) 装 APK（targetSdk=4，需绕过低 target 限制）
& $adb install --bypass-low-target-sdk-block "C:\Users\小蔡爱金雪\Downloads\com.tinanlin.tjc_hymn_cn_v2.4.2.apk"
& $adb shell am start -n com.tinanlin.tjc_hymn_cn/.HymnTabActivity

# 1) 数据面：CSV 网格 / token 全集
python csv_analyze.py shape            # 行数×列数分布（全库 994 份）
python csv_analyze.py file 009         # 单曲逐格矩阵
# 2) 算法面：复刻 HTML + 同步不变式校验（PASS/FAIL）
python render_digit_html.py 009 --dark
# 3) 呈现面：无障碍树 → 渲染矩阵（元素级）
& $adb shell uiautomator dump /sdcard/u.xml; & $adb pull /sdcard/u.xml ui8.xml
python ui_grid.py ui8.xml              # 按 y 分组的行内容（[图片名] / 文字）
python table_dump.py ui8.xml table_map.txt
# 4) 符号面
python sym_probe.py                    # 29 张 PNG 的精确位图 + 包围盒
python sym_rows.py                     # 全库「音符行上/下」位置统计
python sym_montage.py                  # shots/sym_montage_big.png（16× 放大）
# 5) 音频面（验证八度语义）
python midi_notes.py 009               # MIDI 音高序列 + 相对主音的八度/级数
# 6) 三视图切换取证
& $adb shell input tap 756 304         # imageButton_change_view
& $adb exec-out screencap -p > shots\s0X.png
```

---

## 9. 证据文件索引（`E:\apk_re_tjc`）

| 类别 | 文件 |
| --- | --- |
| 反汇编 | `dis_showview.txt`（`showView()`）、`dis_init.txt`、`dis_btn2.txt`、`dis_btn3.txt`、`grep_curmode.txt`、`grep_colors.txt`、`grep_span.txt`（空 = 无 Spannable） |
| 数据 | `csv_001.txt`、`csv_009.txt`、`csv_tokens.txt`（全库 token 全集 + 逐行分布）、`csv_shape.txt` |
| 渲染复刻 | `render_digit_html.py`、`render_001*.txt`、`validate_001.txt`/`validate_009.txt`（同步不变式 PASS）、`shape_range.py`（网格尺寸范围） |
| 无障碍树矩阵 | `ui7.xml`/`ui8.xml`（简谱）、`ui9.xml`（五线谱）、`ui10.xml`（歌词）、`ui_grid.py`、`table_dump.py`、`table_map.txt`、`texts_ui*.txt` |
| 符号 | `sym_probe.py/.txt`、`sym_rows.py/.txt`、`sym_montage.py`、`shots/sym_montage_big.png` |
| 音频 | `midi_notes.py`、`midi_notes.txt` |
| 截图 | `shots/s06.png`（简谱）、`s08_staff.png`（五线谱整页）、`s09_lyrics.png`（歌词页）、`s07.png`、`s05.png`、`s04.png` |
| 印刷原谱 | `staff/staff_009.gif`（从 APK `assets` 提取，含 fermata 对照） |

---

## 10. EchoHymn 落地实现（2026-09-22 定稿）

EchoHymn 已按本机制**重建简谱数据层与显示**（不再使用本仓库原有的 PDF 抽取管线）：

### 10.1 数据层（结构化入库，不是把 CSV 当文件用）

```text
APK assets/NNN.csv  →  tools/import_apk_csv.py  →  data/tjc_hymn.db
   ├── jianpu_score  hymn_number PK, source, row_count, col_count, block_count,
   │                 note_rows, mark_up_rows, mark_dn_rows, lyric_rows,
   │                 stanza_count, align_ok, updated_at
   ├── jianpu_row    (hymn_number, line_no) PK, block_no, kind, stanza_no,
   │                 col_count, raw（原样文本，供逐行自检）
   └── jianpu_cell   (hymn_number, line_no, col) PK, kind, sym, degree,
                     accidental, dot_len, octave, dots, beams, fermata,
                     rowspan, text
```

- `kind`（行）∈ `note | mark_up | mark_down | lyric | blank`；
- `kind`（格）∈ `note | rest | dash | mark | barline | text | stanza | accidental | dot_len | unknown`；
- **`col` 即拍点**；空单元格与「被小节线 `rowspan` 覆盖」的占位格**不入库**（渲染按 `rowspan` 补画竖线）；
- `octave` 是**派生**列：由同列的上/下记号行点数得出（正 = 高八度，负 = 低八度），便于非网格渲染复用；
- 编号映射：CSV `001`→`1`、`051a`→`51_a`；CSV 的 `349` 属"库外"（该首已整首移出本库）。

### 10.2 渲染层（融入 EchoHymn UI 风格，不照搬黑底 HTML 表格）

`lib/models/jianpu_grid.dart`（模型）+ `lib/widgets/jianpu_grid_view.dart`（视图）：

| 维度 | 做法 |
| --- | --- |
| 对齐 | 槽宽 = 可用宽 ÷ 全曲最大列数 → **同列必然同一 x**（组件测试断言） |
| 配色 | `AppColors` 语义色：`lyricsBg` 底、`textPrimary` 音符/歌词、`textTertiary` 节号、**`primary` 半透明小节线**（随换肤联动） |
| 音符 | 内置印刷记谱字体 `EchoJianpu` 的数字字形（`0x4e52`~`0x4e5d`）；变音记号走 UI 字体 |
| 记号 | **按数据语义自绘**：八度点（圆点）、减时线（横线，1~2 条）、延长记号（⌒+•，`CustomPainter`）；上方行贴音符下沿、下方行贴音符上沿 |
| 小节线 | 按 `rowspan` 在覆盖的每一行都绘制 → 竖线视觉连续（不跨歌词行） |
| 字号/缩放 | 随全局字号等级（`Transform.scale`）与窗口宽度联动；内容超出可纵向滚动 |
| 回退 | 无网格数据（老库/未收录）→ 回退该首「简谱」整页扫描图 |
| 按节显示 | `JianpuGridView(stanza: k)` 只保留第 k 节**歌词行**（谱行被该块各节共用，不随节变化 —— 全库无「一块一节」结构）；一页一节 + 底部「第 k / N 节」翻页条 + 右上「手动/自动」（自动 = 复用 `autoPageIndexFor` 跟随播放切节）；内容少时字号按高度放大铺满 |

### 10.3 验证（三级交叉）

| 层 | 工具 | 基线 |
| --- | --- | --- |
| L0 DB ↔ CSV 逐格 | `tools/jianpu_csv_selftest.py` | 全库 474 首 / 21819 行 / 321703 格 **零差异** |
| L1 列对齐不变式 | 同上（按块核对） | 仅 3 份源数据自身块内行宽差异（`163`/`197`/`297`） |
| L3 实机快照 | 同上 `--ui <uiautomator xml>` | 第 9 首 **30/30 行逐元素一致** |
| App 侧 | `flutter analyze` / `flutter test` | **0 issues / 38 passed** |

