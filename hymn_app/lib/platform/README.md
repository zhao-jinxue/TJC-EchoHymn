# lib/platform — 平台专属能力的唯一落点

> 规矩见 `docs/knowledge/PROJECT_LAYOUT.md` §三。**新增任何「只有某个系统才有」的能力，都放这里。**

## 命名约定

| 文件 | 作用 | 被谁引用 |
| --- | --- | --- |
| `<能力>.dart` | 接口 + 工厂（`instance`），**平台无关** | 业务代码（`lib/screens/`、`lib/services/`） |
| `<能力>_windows.dart` | Windows 实现（MethodChannel → `windows/runner/*.cpp`） | 仅接口文件 |
| `<能力>_android.dart` | Android 实现（MethodChannel → `MainActivity` / 插件） | 仅接口文件 |
| `<能力>_ohos.dart` | 鸿蒙实现（预留） | 仅接口文件 |
| `<能力>_stub.dart` | 其它平台空实现（Noop / 返回 null） | 仅接口文件 |

## 两种分派机制（别混用）

1. **运行时**：能力「有/无」不同 → `Platform.isWindows ? Win : Noop`
   —— 条件导入无法区分 Windows 与 Android（`dart.library.io` 两者都为真）。
2. **编译期**：依赖库只在某平台存在 → 条件导入 `if (dart.library.ffi)`
   —— 参考 `lib/services/chinese_convert_service.dart`。

## 现有能力

| 能力 | 文件 | Windows | Android | 鸿蒙 |
| --- | --- | --- | --- | --- |
| 窗口/托盘/系统音量 | `window_controls*.dart` | ✅ MethodChannel `echo_hymn/window` | ⬜ Noop（`isSupported=false`） | ⬜ Noop |

## 硬规则

- 业务代码**只 import 接口文件**，绝不 import `*_windows.dart` / `*_android.dart`。
- Noop 实现**不得抛异常**（调用方无需 try/catch 兜底）。
- 能力不可用时返回 `null` / `false`，由上层降级（例：`getSystemVolume()→null` → 音量走应用增益）。
