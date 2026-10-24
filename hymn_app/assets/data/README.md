# assets/data — 打包进应用的静态数据

| 文件 | 入库 | 来源 |
| --- | --- | --- |
| `hymns.json` | ✅ | 早期结构化数据（历史遗留，仍被部分界面读取） |
| `tjc_hymn.db` | ❌（`.gitignore`） | 由 `tools/sync_db_asset.ps1` 从仓库 `data/tjc_hymn.db` 同步 |

## 为什么 `tjc_hymn.db` 不入库

`data/tjc_hymn.db` 是**唯一数据源**（474 首 + 曲谱网格三表）。移动端需要把它打包进
APK（首启由 `lib/services/db_bootstrap.dart` 拷到应用私有目录）。若把副本也入库，
仓库里会出现两份 25 MB 的二进制库，且极易不同步。

## 构建前必做

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File tools\sync_db_asset.ps1
```

`tools/publish_android.ps1` 已自动调用；**手动 `flutter build apk` 前请自己跑一次**。

## 改库后的两步

1. `tools/sync_db_asset.ps1 -Force`
2. `lib/services/db_bootstrap.dart` 的 `assetVersion` +1（否则已安装用户不会换库）
