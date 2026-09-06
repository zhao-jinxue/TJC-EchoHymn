# 《材料准备计划》——EchoHymn 赞美诗播放软件 V1.5（Step 1 输出，待确认）

> 生成：2026-09-06 · 依据：`01_cline_master_prompt.md` Step 1 + `progress_state.json` code_scope
> 数据源：commit `73b0d20`（v1.5.2 后纯文档提交，代码态等同 tag `v1.5.2`）；清洗器 `tools_clean/clean.py` 已实经三项校验（注释零残留 / 空行零残留 / 字符串内 `http` 前缀判定 3 处完整保留）。

## 1. 申报基础信息（全材料唯一口径）

| 项 | 值 |
| --- | --- |
| 软件全称 | **EchoHymn 赞美诗播放软件** |
| 版本号 | **V1.5** |
| 页眉文字（每页左上，人工在 Word 添加） | `EchoHymn 赞美诗播放软件 V1.5` |
| 编程语言 | Dart（纯 Dart 单一口径，理由见 §3） |
| 代码量（申报值） | 约 6600 行（含注释空行的手写源码）；材料内清洗后 5780 行取 3000 行 |
| 开发完成 / 首次发表 | 2026-09-05 / 2026-09-05（已发表；仓库公开日 2026-08-30 系历史版本发表，不构成矛盾） |

## 2. 资产盘点结果（实测，非估算）

- 统计范围：`hymn_app/lib/**/*.dart` 25 个文件（`data/chinese_convert_map.dart` 2086 行纯简繁映射数据表按 01 规则 6 排除）。
- **清洗后总行数 5780 行 ≡ 115.6 页 > 60 页 → 采用「前 30 页 + 后 30 页」策略**（每页 50 行，共 3000 行）。
- 敏感信息预扫描：**0 命中**（IP / 手机号 / 邮箱 / 密钥字样 / 外链）。仓库根部 `README.md`/`LICENSE` 中的联系邮箱与 `.clinerules` 中的 API Key 均不在统计范围，天然隔离。

## 3. 关键拍板（供确认，异议请指出）

1. **不纳入 `windows/` C++**：1.35 万行中绝大多数为 Flutter 模板生成物，自研定制（标题栏通道 / 单实例互斥）仅数百行且夹在模板中难以自证独创；5780 行 Dart 已足支撑 60 页。申报语言因此可写纯"Dart"，交叉一致性风险最小。
2. **提取顺序按业务流**：入口 → 主界面 → 核心显示组件 → 弹窗/面板 → 服务层 → 主题 → 数据模型。前 30 页恰含"入口 + 主界面 + 谱面/歌词显示"最能体现独创性的开头；后 30 页收在"音频服务 + 状态持久化 + SQLite + 换肤 + 数据模型"，两端均为核心业务代码。
3. **代码流冻结基准**：Step 2 产物绑定 commit `73b0d20`；此后若 lib/ 有任何代码改动，`source_code.txt` 必须重跑（01 绝对一致性原则）。

## 4. 前后 30 页切分映射（有序文件清单 + 清洗后行数 + 累计定位）

| # | 文件 | 清洗后行 | 累计 | 归属 |
| --- | --- | --- | --- | --- |
| 1 | lib/main.dart | 33 | 33 | 前30页 |
| 2 | lib/app.dart | 228 | 261 | 前30页 |
| 3 | lib/screens/home_screen.dart | 954 | 1215 | 前30页 |
| 4 | lib/widgets/hymn_display.dart | 676 | 1891 | 前30页(取至流内第1500行)/其余居中排除 |
| 5 | lib/widgets/hymn_search_dialog.dart | 203 | 2094 | 中部排除 |
| 6 | lib/widgets/playlist_dialog.dart | 455 | 2549 | 中部排除 |
| 7 | lib/widgets/user_manual_dialog.dart | 521 | 3070 | 中部排除 |
| 8 | lib/widgets/panels/left_panel_base.dart | 143 | 3213 | 中部排除 |
| 9 | lib/widgets/panels/hymn_list_panel.dart | 408 | 3621 | 中部排除 |
| 10 | lib/widgets/panels/default_playlists_panel.dart | 320 | 3941 | 中部排除 |
| 11 | lib/widgets/panels/my_playlists_panel.dart | 385 | 4326 | 中段排除 / 尾部起 4281 行起入后30页 |
| 12 | lib/services/app_paths.dart | 65 | 4391 | 后30页 |
| 13 | lib/services/app_state_service.dart | 148 | 4539 | 后30页 |
| 14 | lib/services/audio_service.dart | 332 | 4871 | 后30页 |
| 15 | lib/services/chinese_convert_native.dart | 20 | 4891 | 后30页 |
| 16 | lib/services/chinese_convert_service.dart | 18 | 4909 | 后30页 |
| 17 | lib/services/chinese_convert_stub.dart | 3 | 4912 | 后30页 |
| 18 | lib/services/hymn_search_service.dart | 73 | 4985 | 后30页 |
| 19 | lib/services/log_service.dart | 123 | 5108 | 后30页 |
| 20 | lib/services/sqlite_repository.dart | 238 | 5346 | 后30页 |
| 21 | lib/theme/app_fonts.dart | 36 | 5382 | 后30页 |
| 22 | lib/theme/app_palette.dart | 234 | 5616 | 后30页 |
| 23 | lib/models/hymn.dart | 90 | 5706 | 后30页 |
| 24 | lib/models/hymn_category.dart | 33 | 5739 | 后30页 |
| 25 | lib/models/playlist.dart | 41 | 5780 | 后30页(末行收束) |

- 前 30 页 = 流内第 1~1500 行；后 30 页 = 流内第 4281~5780 行（两段不重叠，1891 < 4281 ✓）。

## 5. Step 2 执行方案（确认后实施）

1. `clean.py` 增设 build 模式：按 §4 顺序清洗拼接 → 截取前 1500 / 后 1500 行 → 直接串接为 3000 行写入 `output/source_code.txt`。
2. 脚本内置断言（01 铁律的程序化保障）：总行数恰 3000；每 50 行一一无空行；无 `//`、`/*` 起始残留；`import` 行数 > 0；敏感正则 0 命中；任一断言失败即退出非零不产出。
3. 完成后更新 `progress_state.json`（step2_status.completed_pages=60）。

## 6. 风险与人工复核点

- **版本锚定**：若 Step 2 前 `hymn_app/lib` 有任何提交（当前无），本表全部行数作废需重跑 Step 1。
- **手册联动**：Step 3 素材源 `user_manual_dialog.dart` 本体位于中部排除段（5~7 项）——这是有意为之：手册对应功能描述照常写，但源码材料两端已含其调用的显示/服务实现，审阅自洽。
- **Word 排版**（04 任务一）：3000 行 ÷ 50 = 恰好 60 页；小五号 + 固定行距 13 磅起步逐页校验；页眉人工添加全称+版本号一字不差。
- 若审核方要求"去掉注释后代码过于紧凑"等补正，按 03 阶段四补正流程处理，无需变更本计划结构。

—— 以上请确认（或指定调整项），确认后进入 **Step 2：源代码格式化**。