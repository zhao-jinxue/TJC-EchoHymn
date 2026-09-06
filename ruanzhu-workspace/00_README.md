# EchoHymn 软著材料工作区（ruanzhu-workspace）

> **定位**：计算机软件著作权申请材料的编辑工作区，与开发主线（`docs/SESSION_SUMMARY.md`）**解耦**——本目录维护自己的进度与决策，`SESSION_SUMMARY.md` 只保留一行指针。会话过程记录仍遵循项目 `.clinerules` 强制流程写入 `docs/sessions/`。

## 文档地图与使用顺序

| 顺序 | 文件 | 作用 | 状态 |
| --- | --- | --- | --- |
| 0 | `00_README.md`（本文件） | 索引、待确认决策、整体进度 | 持续更新 |
| 1 | `01_cline_master_prompt.md` | Cline 主提示词（Step 1~4 内容规范） | 已修订（2026-09-06） |
| 2 | `02_session_handoff_guide.md` | 跨会话"存档-读档"SOP + `progress_state.json` 模板 | 已补全（2026-09-06） |
| 3 | `03_application_process.md` | CPCC 申报全流程（人工，线上操作） | 就绪 |
| 4 | `04_manual_operations_guide.md` | Word 排版/截图/一致性终审（人工） | 就绪 |
| — | `output/` | 产物目录：~~空~~ → **`source_code.txt` + `source_code.docx`（60页×50行）+ `material_plan.md`（已确认 rev1）** | ✅ Step 2 已出 |
| — | `tools_clean/clean.py` | Step 2 确定性清洗脚本（report + build 双模式，Dart 状态机 + 全断言 + docx 排版） | ✅ 已建并使用 |

## 决策记录（2026-09-06 逐步落定）

| 决策项 | 结论 | 状态 |
| --- | --- | --- |
| **软件全称** | **EchoHymn 赞美诗播放软件** | ✅ 已确认（用户选定） |
| **版本号** | **V1.5**（对应 tag `v1.5.2`，开发完成日期取 2026-09-05，与 git 历史自洽） | ✅ 采纳建议值 |
| **代码统计口径** | 只计手写 Dart：全量 8683 行，排除 `lib/data/chinese_convert_map.dart`（2086 行纯数据映射表）≈ **6600 行**；排除 Flutter 模板 C++（`windows/` 1.35 万行中的生成物），自研 runner 定制部分是否计入待 Step 1 计划细化 | ✅ 采纳建议值（Step 1 列明细供审阅） |
| **发表状态 + 首次发表日期** | **已发表**。事实链：GitHub 仓库可见最早提交为 **2026-08-30**（= 仓库公开日，当时公开至 v1.4.0；本地历史中 author date 2026-08-05 的早期提交亦随该日推送而公开）。申报口径（按登记版本 V1.5）：开发完成日期 = 首次发表日期 = **2026-09-05**（tag `v1.5.2` 落地并进入公开仓库之日；满足"完成日期 ≤ 发表日期"红线；08-30 公开的是 V1.4.0 等历史版本，与本版本填报不构成矛盾） | ✅ 已定（2026-09-06 修正：原"初始提交 08-05"推断更新为"公开日 08-30"，口径不受影响） |
| **著作权人姓名一致性** | `LICENSE` 书面声明 "Copyright (c) 2026 赵金雪 All Rights Reserved"（专有许可，非开源）；用户已确认申请人即**赵金雪**本人且与 CPCC 实名同一名下——三者一致，无矛盾 | ✅ 已确认（2026-09-06） |
| **申请表语言/代码量填报** | Dart；约 6600 行（按上述口径） | ✅ 随口径自动得出 |

## 当前进度

- [x] 2026-09-06：工作区建立（01~04 文档）；01 严谨性修订（import 保留、脱敏方式、统计口径、Step 2 脚本化）；02 补全存档/读档 SOP
- [x] 决策落定：全称=EchoHymn 赞美诗播放软件 / 版本=V1.5 / 统计口径=排除数据表与模板 C++ / 发表状态=已发表（2026-09-05）
- [x] 创建 `progress_state.json`（按 02 模板，2026-09-06 已建，current_step=Step 1）
- [x] Step 1：资产盘点与《材料准备计划》（2026-09-06 完成：清洗后 5780 行→前30+后30页方案，`output/material_plan.md` **待用户确认**）
- [x] Step 2：~~`clean.py` build 模式 + `output/source_code.txt`（3000 行 + 断言）~~ ✅ 2026-09-06 完成：txt+docx 双产物 3000 物理行，全断言 + 结构校验通过；**遗留：本机无 Word，页数=60 为几何推导，需在装有 Word 的电脑复核并导出 PDF**
- [x] Step 3：`output/user_manual_draft.md` + `user_manual.docx`（2026-09-06 完成：五大章 26 标题 / 18 截图占位 / 4 表格 / 封面+目录域+页眉页脚，素材源 `user_manual_dialog.dart` + INSTALLER/SESSION_SUMMARY 交叉印证；**遗留：截图待实机补入，Word 复核页数≥15**）
- [x] Step 4：《自检报告》（2026-09-06 完成：`output/consistency_check.md`，A名称版本/B功能↔代码18项对照/C可回溯6样全中/D脱敏0命中/E七项人工复核风险；结论：无退回级硬伤）
- [x] **AI 四步全部完成**，余人工环节：18 截图补入 → Word 复核导 PDF → CPCC 填报（见报告的 E 表与 03/04 文档）
- [ ] 人工：Word 排版（04）、截图（需软件实机运行）、CPCC 申报（03）

## 新会话续接方式

读本文件 + `progress_state.json`（若存在）+ 最近一篇 `docs/sessions/*.md`，然后按 02 的"读档 SOP"向用户复述断点后继续。
