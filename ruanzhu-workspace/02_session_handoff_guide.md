# Cline 跨会话断点续传指南 (Session Handoff Guide)

在使用 Cline + 千问/DeepSeek 处理软著材料时，单个会话很难一次性完成数千行代码的清洗和长文档的生成。以下是标准化的“存档-读档”SOP。

## 一、 准备工作：建立状态追踪文件

在项目根目录（或 `ruanzhu-workspace` 下）创建一个名为 `progress_state.json` 的文件，用于记录进度：

```json
{
  "project_name": "您的软件全称",
  "version": "V1.0",
  "current_step": "Step 2", 
  "step2_status": {
    "total_target_pages": 60,
    "completed_pages": 20,
    "last_processed_file": "src/controllers/userController.js",
    "last_line_number": 1050,
    "output_file": "./output/source_code.txt"
  },
  "step3_status": {
    "completed_sections": ["引言", "运行环境"],
    "pending_sections": ["核心功能操作说明", "异常处理"]
  },
  "step4_status": {
    "done": false,
    "risk_points_found": []
  },
  "step2_file_plan": [
    {"file": "lib/main.dart", "cleaned_lines": 42, "done": true},
    {"file": "lib/app.dart", "cleaned_lines": 210, "done": false}
  ],
  "pending_tasks": ["Step 2 剩余文件按 step2_file_plan 顺序继续", "截图占位符待人工补图"],
  "notes_for_ai": "上次因为上下文溢出中断，代码清洗到了 userController.js 的第1050行。"
}
```

> 说明：`step2_file_plan` 是**有序**的输入文件清单（Step 1 确认后填入），`cleaned_lines` 为脚本清洗后行数——续传时用"已完成文件的行数累加"即可精确推算断点页码，不依赖记忆。

## 二、存档 SOP（每轮会话结束 / 预感到上下文将溢出时）

1. 更新 `progress_state.json`：
   - `current_step`、对应 `stepN_status` 的完成计数与断点位置（`last_processed_file` / `last_line_number`）；
   - `pending_tasks` 写入**下一会话要执行的第一条具体指令**（如"运行 tools_clean/clean.py 处理第 8~14 号文件并追加到 source_code.txt"）。
2. 按项目 `.clinerules` 强制流程，在 `docs/sessions/<会话时间>.md` 中记录本轮的提问、思路与结果（JSON 只存机器状态，人类可读的决策与教训进会话日志——两者互补，缺一不可）。
3. `git add ruanzhu-workspace/ docs/sessions/` 随代码一起提交，状态即永久留档。

## 三、读档 SOP（新会话开始）

1. 读取 `ruanzhu-workspace/progress_state.json`，确认 `current_step` 与断点位置。
2. 读取最近一篇 `docs/sessions/*.md` 的"最终结果/遗留问题"，恢复人类语境。
3. 向用户复述："当前处于 Step X，已完成 …，下一步将 …，是否继续？"——得到确认后再动手，禁止从 Step 1 重跑。
4. 幂等性检查：Step 2 续写 `source_code.txt` 前，先核对文件现有行数与 `completed_pages × 50` 是否一致，不一致以文件实际内容为准修正状态。

## 四、与软著主流程文档的挂钩

- 本指南只解决"跨会话不断线"；材料的内容规范以 `01_cline_master_prompt.md` 为准，人工排版以 `04_manual_operations_guide.md` 为准，申报操作以 `03_application_process.md` 为准，待确认决策与整体进度见 `00_README.md`。
