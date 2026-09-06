# 《一致性自检报告》——EchoHymn 赞美诗播放软件 V1.5（Step 4）

> 自检方法：全部结论基于命令级取证（sqlite3 实测、python 正则回源、git 校验、docx/txt 结构核验），非目测。
> 基线：源代码材料锚定 commit `73b0d20`；经 `git log 73b0d20..HEAD -- hymn_app/` 验证**代码零漂移**（后续 3 个提交全部为材料工作区与文档）。

## A. 软件名称与版本号一致性 ✅

| 检查项 | 结果 |
| --- | --- |
| 全称「EchoHymn 赞美诗播放软件」在 `progress_state.json` / `material_plan.md` / 手册标题+封面 / 源码材料页眉（docx 域内）四处 | 逐字一致，无缺漏空格 |
| 版本号 | 全部 **V1.5** 大写形态（手册 3 处、页眉 1 处、计划/状态各若干），**小写 v1.5 / v1.5.2 零出现** |
| 手册内品牌说明 | 附录注明"界面品牌名 EchoHymn ↔ 登记全称"对应关系，为截图环节预留解释口径 |

## B. 手册功能点 ↔ 代码实现对照（禁止虚构核查）

| 手册陈述 | 代码/数据证据 | 是否入 60 页材料 |
| --- | --- | --- |
| 收录 474 首、45 分类 | `tjc_hymn.db` 实测 count=474/45 | 表读写在 sqlite_repository ✓（后30页） |
| 诗歌列表每页 35 首 | `hymn_list_panel.dart:37` `_pageSize = 35` | 该文件中段排除（见风险 R5） |
| 编号定位/回车播放/清空 | home_screen + hymn_list_panel | home_screen 前30页 ✓ |
| 歌名+歌词模糊搜索·三列弹窗·繁简双向 | `hymn_search_service.dart` | ✓（后30页） |
| 谱面宽度驱动缩放、Ctrl+滚轮缩放/滚轮滚动分流 | `hymn_display.dart:662` `PointerSignalResolver`、`:668` `_ScoreImageView` | 类定义在中段（见 R5），调用侧在前30页 hymn_display 前 285 行内 |
| 全局快捷键（空格/Ctrl+P/切歌/音量/静音/F1） | `app.dart` 根 Focus 处理器 | ✓（前30页） |
| 快捷键说明表 11 行 | `user_manual_dialog.dart:40` `kShortcutList` | 中段排除（R5） |
| 五套配色全称、27 色槽、暗夜墨深色标题栏 | `app_palette.dart`（`晨光蓝 · 经典` 等，材料流 2668 行命中） | ✓（后30页） |
| 四级字号×1.0/1.3/1.6/1.9、含弹窗等比 | `app_fonts.dart` + home_screen 菜单 + `app_state_service` 持久化 | ✓（`fontSizeLevel` 材料内 4 处命中） |
| 音量滑条=系统音量镜像 | `audio_service.dart:307` 系统音量通道 | ✓（后30页） |
| 人声版多版本 👥 选择 | audio_service + hymn_display 版本栏 | ✓ |
| 个人歌单新建/重名检查/删除/整单播放、单表 JSON | `playlist.dart` + `sqlite_repository` `playlist_hymn` | ✓（`playlist_hymn` 材料内命中） |
| 恢复不自动播放、进度从 0 | app_state_service + audio_service loadHymn | ✓ |
| state.json 原子写+唯一串行队列 / logs 保留 7 份 | app_state_service ✓ / log_service `maxFiles = 7`（材料流 2304 行命中）✓ | ✓ |
| 内置用户手册打开关闭三方式、防叠加 `_isOpen` | user_manual_dialog（中段排除）+ ManualPrefs（home_screen 材料内引用 ✓） | 部分（R5） |
| 单实例保护（第二实例聚焦已有窗口退出） | `hymn_app/windows/runner/main.cpp:15` `CreateMutexW` | ❌ C++ 按已确认计划不纳入（R6） |
| 安装双文件/三页向导/两段解包/卸载保留数据 | `installer/echohymn.iss` + `docs/INSTALLER.md` | 安装器不在材料（属另一独立软件/构件，申报对象为 hymn_app 运行时，见 R6 注） |
| 内置字体 EchoSans | app.dart:202（材料内命中） | ✓ |

**结论**：手册所有功能性陈述均可回源到实际代码/文档，无虚构；未实现功能零提及。

## C. 源代码材料 ↔ 仓库可回溯性 ✅

- 抽样反查：材料第 1/500/1500/1501/2500/3000 物理行，6/6 在 `hymn_app/lib` 源码中逐字命中；
- 断言记录（build 运行日志）：3000 物理行、0 空行、0 注释残留、import 行 80、敏感 0 命中、txt↔docx 逐段一致；
- 显式断行仅为排版投影（不增删字符），与 `source_code.txt` 一致留档可复核。

## D. 脱敏与合规 ✅

- 六类正则（IP/手机号/邮箱/密钥字样/sk- 前缀/外链）对全清洗流扫描 **0 命中**，未触发 `****` 替换（Step 4 应登记的替换位置：**空**）；
- 已知敏感位点均在统计口径之外：`.clinerules`（千问 API Key）、`README/LICENSE`（联系邮箱）——**不得**混入提交材料，`code_scope.exclude` 已隔离；
- `installer/make_payload.py` 含载荷口令——不在 lib 范围，天然排除。

## E. 需人工复核的风险点（提交前逐项打勾）

| # | 风险 | 处置建议 |
| --- | --- | --- |
| R1 | 截图窗口区显示的品牌文案（如"EchoHymn · 聆听赞美诗"）与登记全称不完全同形 | 按 04 指南：截图保留"EchoHymn"主干即可；标题栏若含其他中文品牌词，裁切或修图处理，宁缺勿矛盾 |
| R2 | 若任何界面/关于处显示 v1.5.x 全量版本号 | 截图前确认界面不显示与"V1.5"冲突的版本串（当前 UI 未显示版本号，风险低，复核即可） |
| R3 | 源码材料 60 页为几何推导（本机无 Word） | Word 打开逐页核对 50 行/页 + 页码 1~60 连续，导出 `源代码.pdf` |
| R4 | 手册 18 处占位待补真实截图；补图后总页数需 ≥15 | 实机截图（假数据/测试歌单），Word 更新目录域后核页数，导出 `用户手册.pdf` |
| R5 | 个别功能的实现代码位于"中部排除段"（每页 35、谱面查看器类体、快捷键表数据等） | 合规（前30+后30 本为节选制式）；备完整源码留档应对质询，说明材料为节选、全量在仓库 `73b0d20` |
| R6 | 单实例/窗口通道由 Windows C++ 实现、安装向导为独立工程，均不在申报材料 | 申报表"编程语言"填 Dart 与材料自洽；功能描述保留在手册（行为陈述不依赖材料含码），无需调整 |
| R7 | 申请表填报口径联动 | 开发完成 2026-09-05 / 首次发表 2026-09-05 / 已发表 / 原始取得 / 独立开发 / Dart / 约 6600 行——填报时与本表逐项对照 |

## 总体结论

**无退回级硬伤**：名称版本闭环、功能描述全溯源零虚构、敏感零命中、基线零漂移。待办集中于人工环节（R3/R4 复核与截图、R1 截图一致性），完成后可按 `03_application_process.md` 提交。

—— AI 四步（Step 1~4）至此全部完成。