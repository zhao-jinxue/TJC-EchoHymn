# 项目目录职责与平台边界（EchoHymn）

> 建立于 2026-10-18（阶段 M1 完成后）。目的：三处易混乱的目录（`installer/`、`release/`、`hymn_app/`）
> 职责单一化，并为 OpenHarmony 预留位置。**改动目录结构前先读本文档。**

## 一、顶层目录职责

| 目录 | 职责 | 入库 | 备注 |
| --- | --- | --- | --- |
| `hymn_app/` | **唯一的应用工程**（Flutter 多平台：Windows / Android / 未来 OHOS） | ✅ 源码 | 构建产物 `hymn_app/build/` 不入库 |
| `data/` | **共享数据源**：`tjc_hymn.db`（474 首）+ `Hymn_Downloads/`（音频与素材） | DB ✅ / 大素材 ❌ | 两平台共用同一份数据 |
| `tools/` | 构建、发布、生成器脚本 | ✅ | 见下方「发布脚本」 |
| `installer/` | **Windows 专用**安装包工程（Inno Setup 6：`.iss` + 载荷打包） | 脚本 ✅ / 产物 ❌ | 仅 Windows，仅 tag 时产出 |
| `release/` | **多平台发布产物**（按平台分层，见 `release/README.md`） | ❌（仅 README） | 自动重建，可随时删除 |
| `docs/` | 文档，按平台归档（`Windows/` `Android/` `OpenHarmony/` `iOS/` `knowledge/` `sessions/` `ruanzhu/`） | ✅ | 软著材料唯一归档 `docs/ruanzhu/` |
| `_shots/` | 本地验收截图（临时取证） | ❌ | |

## 二、产物流向（一张图看懂）

```
                       ┌── tools/publish_windows.ps1 ──→ release/windows/echohymn_win_<ts>_<sha>/
git commit (master) ─→ tools/publish_all.ps1 ┤
                       └── tools/publish_android.ps1 ──→ release/android/echohymn_android_<ts>_<sha>/ (4 变体)

git tag vX.Y.Z       ─→ tools/build_installer.ps1 ──→ installer/output/EchoHymn_Setup_v*.exe (+ Data.7z)
git push             ─→ （无自动发布）
```

- **每次 commit**：Windows + Android 双平台产物**同时产出**，保证功能对齐。
- **installer**：只在定版本打 tag 后产出（3 GB 级载荷，不宜每次重打）。
- **OpenHarmony**：`release/ohos/` 已预留，接入时新建 `tools/publish_ohos.ps1` 并加入 `publish_all.ps1` 的 `$jobs`。

## 三、`hymn_app/` 平台边界（关键）

Flutter 单工程多平台，目录按「平台宿主」与「Dart 代码」分开：

| 路径 | 平台归属 | Windows 构建是否使用 |
| --- | --- | --- |
| `hymn_app/windows/` | 仅 Windows（C++ runner、资源、快捷方式） | ✅ 唯一使用 |
| `hymn_app/android/` | 仅 Android（Gradle、Manifest、MainActivity、flavor） | ❌ **完全不参与** |
| `hymn_app/ohos/` | 仅鸿蒙（当前只有 README 占位） | ❌ |
| `hymn_app/assets/` | 全平台共享资源（字体、DB、谱面 JSON） | ✅ |
| `hymn_app/lib/` | Dart 代码（多平台共享） | ✅ |

**`lib/` 内部的平台边界**——凡涉及宿主系统的能力，一律走「接口 + 条件导入」：

```
lib/platform/                          ← 平台相关能力的唯一落点
├── README.md                          ← 边界规则（新增平台能力前必读）
├── window_controls.dart               ← 接口 + 工厂（条件导入分派，平台无关）
├── window_controls_windows.dart       ← 仅 Windows 实现（MethodChannel → runner）
└── window_controls_stub.dart          ← 其他平台（Android/鸿蒙/测试）Noop
```

规则：

1. **共享代码（`lib/screens/`、`lib/services/`、`lib/models/`…）不得直接 `import` 任何 `*_windows.dart` / `*_android.dart` / `*_ohos.dart`**，只能 import 接口文件（如 `platform/window_controls.dart`）。
2. **运行时分派**——同一 SDK 内仅「能力有无」不同的差异（窗口/托盘/系统音量/快捷键），
   在接口文件里按平台选实现：
   ```dart
   static final WindowControls instance = _create();
   static WindowControls _create() =>
       Platform.isWindows ? WindowsWindowControls() : const NoopWindowControls();
   ```
   原因：Dart 条件导入只能按 **library 可用性** 区分（`dart.library.io` 在 Windows 与 Android
   **都为真**），无法区分二者；这类差异只能用 `Platform.isWindows` 在运行时分派。
3. **编译期裁剪**——依赖只存在于某平台的库（如 FFI 原生实现）必须用条件导入，
   否则另一平台编译期就会因缺少依赖而失败：
   ```dart
   import 'chinese_convert_stub.dart'
       if (dart.library.ffi) 'chinese_convert_native.dart' as impl;
   ```
   这也是「Windows 构建不引入 Android 专属代码」的**硬界限**：含平台专属依赖的文件
   只能通过条件导入被引用，Windows 编译时该分支整体不参与编译。
4. **未引用即不打包**：Dart AOT 只编译可达代码，因此「平台实现文件只被接口文件引用」
   即可保证另一平台的产物里不含其逻辑（当前 `window_controls_stub.dart` 为全平台共用的
   Noop，本身无平台依赖）。
4. 新增能力同理：`xxx.dart`（接口）+ `xxx_windows.dart` / `xxx_android.dart` / `xxx_ohos.dart` / `xxx_stub.dart`。

> 已有先例（可作为模板）：`lib/services/chinese_convert_{service,stub,native}.dart`、
> `lib/platform/window_controls*.dart`。

## 四、`installer/` 边界

- 仅 Windows，**只有** `echohymn.iss`、`ChineseSimplified.isl`、`app_icon.ico`、`make_payload.py`、
  `prepare_staging.py`、`payload_manifest.txt` 入库。
- `installer/output/`、`installer/payload.7z`、`installer/staging*/` 均在 `.gitignore`（可再生产物）。
- 未来如需 Android 的「应用商店包」或鸿蒙 `.hap` 签名产物，不要塞进 `installer/`，
  而是：Android → `release/android/` 内的 APK（必要时加 `tools/build_aab.ps1`）；
  鸿蒙 → `release/ohos/`。

## 五、相关文档

- `release/README.md` —— 产物布局与保留策略
- `docs/Android/STATE.md` —— Android 阶段与工单进度
- `docs/Android/ANDROID_PLAN.md` §1.4 —— 体积构成（APK 46.5 MB 实测）
- `docs/sessions/` —— 会话记录（按 `## 任务 N` 分段）
