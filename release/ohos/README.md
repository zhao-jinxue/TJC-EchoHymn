# release/ohos — OpenHarmony（鸿蒙）发布产物预留目录

> 本目录为**鸿蒙平台发布产物**的预留位置，当前**不产出任何文件**。

## 现状

| 平台 | 产物位置 | 状态 |
| --- | --- | --- |
| Windows | `release/windows/echohymn_win_<ts>_<sha>/` | ✅ 每次 commit 自动产出 |
| Android | `release/android/echohymn_android_<ts>_<sha>/` | ✅ 每次 commit 自动产出（4 变体 APK） |
| OpenHarmony | `release/ohos/` | 📁 预留，工程尚未生成（见 `hymn_app/ohos/README.md`） |

## 接入后预期产物

鸿蒙应用以 `.hap`（Harmony Ability Package）交付，接入时预期：

```
release/ohos/echohymn_ohos_<yyyyMMdd-HHmmss>_<短sha>/
├── EchoHymn-full-v<ver>-<sha>.hap
├── EchoHymn-<variant>-v<ver>-<sha>.hap
└── SHA256SUMS.txt
```

对应脚本届时新建 `tools/publish_ohos.ps1`，并在 `tools/publish_all.ps1` 的 `$jobs`
表中追加一项（`Name='OpenHarmony'; Script='publish_ohos.ps1'`），即可纳入
每次 commit 的多平台产物对齐流程。
