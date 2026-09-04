# 📐 EchoHymn 发布规则（18 条 · 定稿 2026-09）

> 本文件是 EchoHymn Windows 安装包的**发布规范基线**：第 1~8 条源自产品需求，第 9~18 条为专业发布者视角审核补全。
> 每次制作/修订安装包时逐条核对；修订本文件须经与安装包工程（`installer/`）同步验证。
> 配套文档：`docs/INSTALLER.md`（操作手册）；构建入口：`tools/build_installer.ps1`。

---

## 一、基础需求（1~8）

| # | 规则 | 实现载体 / 说明 |
| --- | --- | --- |
| 1 | **仅限 Windows 平台分发** | `installer/echohymn.iss`（Inno Setup 6，x64 安装模式）；Android/鸿蒙另行规划，不使用本安装包工程 |
| 2 | **必须获取管理员权限** | `[Setup] PrivilegesRequired=admin`，双击安装自动弹 UAC 提权，用于写 Program Files、注册表与目录授权 |
| 3 | **向导首页为系统兼容性检查** | 自定义页"第一步 · 系统兼容性检查"（欢迎页已禁用，检查页即首屏）；存在 ✘ 项时禁用"下一步"，修复后可点「重新检测」 |
| 4 | **第二页选择安装位置** | 内置目录选择页，默认 `D:\Program Files\EchoHymn`；**D 盘不存在或剩余 <8GB 自动回退 `C:\Program Files\EchoHymn`**，允许用户改路径；程序全部内容复制至该目录 |
| 5 | **第三页誓言宣誓（宗教仪式关卡）** | 自定义页展示**祷告版**宣誓词（`OATH_TEXT` 常量）；展示框为**静态文本**（无右键菜单，杜绝复制源头）；输入框拦截 复制/粘贴/全选/撤消（Ctrl+C/V/X/Z/A、Shift+Insert），并对**一切非键盘引发的内容变化**（右键菜单粘贴/删除/撤消、拖放）经 OnChange 守卫即时回滚+红字告警（中文输入法走键事件通道不受影响）；校验=去空白+半角标点归一全角后全文比对；**失败红字提示且不开始安装**。定位：敬畏感仪式，非安全机制（拍照抄写不可防） |
| 6 | **压缩使安装包尽量小** | 载荷 7z LZMA2 solid（preset 1，媒体不可再压取物理下限）+ 打包清单过滤无引用素材（`payload_manifest.txt`，由 `tools/scan_db_refs.py` 生成）；外壳 ISCC `Comp=none`（加密数据不再压） |
| 7 | **加密使安装包不可被轻易破解** | 单一载荷 **AES-256 + 加密头**（文件清单不可见），密钥 XOR 混淆内嵌于向导代码（`DecodeKey`），拦截右键解压/解包工具。**能力边界**：安装包必须可被任何用户免密安装，故不宣称"不可破解"，定位为抬高门槛级防护 |
| 8 | **提供可独立执行的卸载程序** | `unins000.exe` + 开始菜单"卸载 EchoHymn"+ 控制面板入口；卸载弹窗询问是否保留个人数据（歌单库 `tjc_hymn.db`/`state.json`/日志），**默认保留**，静默卸载=保留 |

## 二、发布者补全规则（9~18）

| # | 规则 | 实现载体 / 说明 |
| --- | --- | --- |
| 9 | **代码签名策略明示** | 首期不签名（无证书预算），SmartScreen「未知发布者」的处理指引写入 `docs/INSTALLER.md`；后续购 OV 证书则在构建脚本追加 SignTool。**已知代价**：3GB 未签名单文件双击后到 UAC 弹窗有 5~15 秒系统安全扫描空档（Defender 全文件扫描+SmartScreen 哈希信誉查询），签名后可降至 1~3 秒，向导代码层无法消除 |
| 10 | **兼容性检查项完整定义** | ① 64 位 Windows；② Windows 10 及以上；③ Media Foundation 可用（`{sys}\mfplat.dll`，N/KN 版须装媒体功能包，音频命脉）；④ 磁盘空间（系统盘 ≥ 载荷+5GB，安装盘 ≥ 载荷×2+5GB，载荷体积编译期注入真实值）；⑤ VC++ 运行库随包内置说明；⑥ 旧版本检测提示（升级路径） |
| 11 | **升级安装保留用户数据** | 安装前备份 `{app}\data\tjc_hymn.db` → 解包 → 还原（个人歌单不丢）；`state.json`/`logs/` 不在载荷内天然保留；AppId 固定 GUID 保证同产品覆盖升级 |
| 12 | **安装目录授权普通用户可写** | `[Run] icacls {app} /grant *S-1-5-32-545:(OI)(CI)M /T`——应用便携设计将 `state.json`/`logs/` 写在 exe 同级，Program Files 下不授权则状态保存 100% 失败（分发后致命项） |
| 13 | **快捷方式体系完备** | 开始菜单组（启动 + 卸载）+ 桌面快捷方式（可选勾选）+ 图标与应用 exe 同源（`app_icon.ico` 构建时自动复制） |
| 14 | **支持静默安装与安装日志** | `/SILENT` `/VERYSILENT` `/NORESTART` `/DIR=` `/TASKS=` `/LOG=`；静默属发布者/批量部署通道：**跳过誓言交互校验，环境检查仍生效**（规则 5 的唯一豁免通道，须知情使用） |
| 15 | **版本号单源注入** | `hymn_app/pubspec.yaml` `version` → 构建脚本解析 → ISCC `/DAppVersion` → 安装包文件名/产品版本/注册表 DisplayVersion；禁止手工散落维护版本号（2026-09 曾发生 pubspec 落后两个大版本） |
| 16 | **发布附 SHA256 校验值** | 构建自动产出 `EchoHymn_Setup_v<版本>.exe.sha256`；对外分发时必须连同校验值一并提供（用户可验证下载完整性，防篡改/防损坏） |
| 17 | **失败处理与回滚** | 解包异常捕获 → 明确报错并中止安装（提示核对 SHA256）；`CloseApplications=yes` 安装前处理占用文件的运行实例；卸载检测到运行程序给出中文提示（`UninstallAppRunningError`）；磁盘满等 IO 错误由向导原生报错弹窗承载 |
| 18 | **构建全程脚本化、可重复** | `tools/build_installer.ps1` 一键完成（版本→release 定位→语言文件→staging→加密载荷→编译→SHA256），支持 `-SkipStaging/-SkipPayload` 增量；安装包**不并入** post-commit 自动发布（3GB 压缩耗时长，保持手动触发）；构建产物（payload.7z/staging/output/）一律 .gitignore 排除 |

---

## 三、验证基线（发布前必过清单）

1. 静默装到非默认目录 → 文件数/目录结构与 staging 一致（含 `tjc_hymn.db`、`flutter_assets`、`icudtl.dat`、`Hymn_Downloads`）；
2. **普通（非提权）权限启动程序**，确认 `state.json` 与 `logs/` 成功写入（规则 12 终极证明）；
3. 静默卸载 → 程序文件全清、个人数据保留、注册表项自清；
4. 三页向导人工走查：环境 ✘ 阻断 / 誓言错字拦截与不可复制 / 无 D 盘回退；
5. `release/auto-release.log` 核对（提交触发）+ 安装包 `.sha256` 留档。

## 四、维护提示

- 素材（歌曲/音频/谱图）更新后：先 `python tools/scan_db_refs.py` 再生成 `installer/payload_manifest.txt`，后构建（规则 6 的数据侧保障）。
- 更换载荷密码：改 `installer/make_payload.py` 的 `PASSWORD`，并将新口令逐字符 XOR `0x5A` 的结果同步填入 `echohymn.iss` 的 `DecodeKey`（两处必须一致）。
- 修订宣誓词：仅改 `echohymn.iss` 的 `OATH_TEXT` 常量（校验归一化逻辑随之生效），修改属规则 5 变更，需重新走查誓言页。
