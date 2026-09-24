# 📜 EchoHymn 软著（计算机软件著作权）材料总入口

> **唯一归档规则（2026-09-24 定稿）**：软著申请材料的**唯一归档位置 = `docs/ruanzhu/`**。
> 严禁再在仓库根或其他位置另建软著工作区 / 进度文件——同一条支线曾同时存在两份进度与决策记录
> （仓库根 `ruanzhu-workspace/` 与 `docs/ruanzhu/v<版本>/`），信息容易不一致；
> 2026-09-24 已把工作区整体迁入 `docs/ruanzhu/workspace/`，本目录即此后的唯一入口。
> 会话过程记录仍按 `.clinerules` 强制流程写入 `docs/sessions/`。

## 一、目录结构

```text
docs/ruanzhu/
├── README.md                 # 📍 本文件：总入口（索引 + 规则 + 常用命令 + 迁移记录）
├── v<版本>/                  # 逐版本递交材料（现行 + 历史留档）
│   ├── 源程序鉴别材料_V<版本>.docx / .txt   # 前后各 30 页 × 50 行（不足 60 页则全量）
│   ├── 软件说明书_V<版本>.docx              # 操作手册体例，页眉 = 名称 + 版本 + 页码域
│   ├── 受理中申请的处理建议.md / 署名与版本一致性核对.md
│   ├── 材料清单与待补项.md / 版本变更说明_*.md
│   └── img/                                 # 说明书插图（fig*.png，可选）
└── workspace/                # 软著编辑工作区（V1.5 期留档）
    ├── 00_README.md ~ 05_form_fill_content.md
    ├── progress_state.json   # 断点状态
    ├── output/               # V1.5 期产物（source_code.*、user_manual.*、自检报告等）
    └── tools_clean/          # V1.5 期清洗/导出脚本（clean.py、export_manual_docx.py）
```

## 二、现行版本与材料

| 版本 | 状态 | 说明 |
| --- | --- | --- |
| **v1.8.0** | ✅ **现行提交版本** | 源程序 **11002 行 / 221 页**（提交前后各 30 页 × 50 行）；说明书 **11 章**（含「关闭行为与系统托盘」） |
| v1.7.4 | 🗂 历史留档 | 上一版材料（v1.7.4 期），保留以便对照 |

入口文档（v1.8.0）：[材料清单与待补项](v1.8.0/材料清单与待补项.md) · [署名与版本一致性核对](v1.8.0/署名与版本一致性核对.md) ·
[受理中申请的处理建议](v1.8.0/受理中申请的处理建议.md) · [版本变更说明_1.6.x至1.8.0](v1.8.0/版本变更说明_1.6.x至1.8.0.md)

## 三、工具（`tools/`，版本随 `hymn_app/pubspec.yaml` 单源）

| 工具 | 作用 |
| --- | --- |
| `tools/make_ruanzhu_source.py` | 生成《源程序鉴别材料》（docx + txt；前 30 页 + 后 30 页 × 50 行，页眉含版本与页码域） |
| `tools/make_ruanzhu_manual.py` | 生成《软件说明书》（Word；11 章体例；插图取 `docs/ruanzhu/v<版本>/img/`） |
| `tools/migrate_ruanzhu_docs.py` | 辅助文档跨版本迁移（材料版本引用替换 + 变更说明改名；`--dry-run` 预演；含「历史留档」行保护） |

```bash
python tools/make_ruanzhu_source.py                          # 生成鉴别材料
python tools/make_ruanzhu_manual.py                          # 生成说明书
python tools/migrate_ruanzhu_docs.py --from 1.7.4 --to 1.8.0 --dry-run   # 预演辅助文档迁移
```

## 四、流程文档（`workspace/`，V1.5 期）

| 文档 | 作用 |
| --- | --- |
| [00_README.md](workspace/00_README.md) | V1.5 期工作区索引 / 决策记录 / 进度（历史留档） |
| [01_cline_master_prompt.md](workspace/01_cline_master_prompt.md) | 材料内容规范（Step 1~4 提示词） |
| [02_session_handoff_guide.md](workspace/02_session_handoff_guide.md) | 跨会话存档 / 读档 SOP + `progress_state.json` 模板 |
| [03_application_process.md](workspace/03_application_process.md) | CPCC 申报全流程（线上人工操作） |
| [04_manual_operations_guide.md](workspace/04_manual_operations_guide.md) | Word 排版 / 截图 / 一致性终审（人工） |
| [05_form_fill_content.md](workspace/05_form_fill_content.md) | 申请表填写内容 |
| `progress_state.json` / `output/` / `tools_clean/` | 断点状态 / V1.5 期产物 / 当期脚本（注：`tools_clean/clean.py report` 会**按当前代码重算并覆盖 `stats.json`**——V1.5 期留档数值请看 git 历史） |

## 五、历史与迁移记录

- **2026-09-06**：仓库根建立 `ruanzhu-workspace/`（软著支线工作区，与开发主线解耦）；当日完成 Step 1~4（材料计划 / 源程序 60 页 / 说明书 / 自检报告），余 Word 排版、实机截图、CPCC 填报为人工环节。
- **2026-09-06 之后**：材料改为**脚本生成**，逐版本产物入 `docs/ruanzhu/v<版本>/`（v1.7.4 → v1.8.0）；仓库外的一次性脚本 `ruanzhu_migrate.py` 负责辅助文档迁移。
- **2026-09-24**：
  1. 工作区由仓库根 `git mv` 至 `docs/ruanzhu/workspace/`（`git` 历史保留），内部路径引用同步更新为「相对本文件固定层级」，不再随目录层级漂移；
  2. 上述一次性脚本固化入库为 `tools/migrate_ruanzhu_docs.py`（含历史引用保护与 `--dry-run`，重复执行幂等）；
  3. 本文件（总入口）建立，并同步登记进 `docs/README.md` 与 `docs/Windows/SESSION_SUMMARY.md` 的指针——**防止再出现重复创建工作区**。
