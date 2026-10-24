<#
.SYNOPSIS
    把仓库单一数据源 data\tjc_hymn.db 同步为移动端内置资产 hymn_app\assets\data\tjc_hymn.db。

.DESCRIPTION
    移动端（Android / 鸿蒙）没有「安装目录 + data/」形态，诗歌库必须打包进
    APK 后由 `DbBootstrap` 在首启拷到应用私有目录。

    为**避免仓库里存两份 25 MB 数据库**，`hymn_app/assets/data/tjc_hymn.db` 不入库，
    构建前由本脚本从 `data/tjc_hymn.db` 同步：

        pwsh -NoProfile -ExecutionPolicy Bypass -File tools\sync_db_asset.ps1

    `tools\publish_android.ps1` 已内置调用（每次自动发布前同步）。
    手动 `flutter build apk` 前也请先跑一次，否则 APK 内可能是旧库或没有库。

    **改库后必须**：
      1. 跑本脚本同步资产；
      2. 把 `lib/services/db_bootstrap.dart` 的 `assetVersion` +1（否则老用户不会换库）。
#>
param([switch]$Force)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$src = Join-Path $Root 'data\tjc_hymn.db'
$dstDir = Join-Path $Root 'hymn_app\assets\data'
$dst = Join-Path $dstDir 'tjc_hymn.db'

if (-not (Test-Path $src)) { throw "缺少源数据库 $src" }
if (-not (Test-Path $dstDir)) { New-Item -ItemType Directory -Path $dstDir -Force | Out-Null }

$srcInfo = Get-Item $src
$needCopy = $true
if (-not $Force -and (Test-Path $dst)) {
    $dstInfo = Get-Item $dst
    if ($dstInfo.Length -eq $srcInfo.Length -and
        $dstInfo.LastWriteTimeUtc -ge $srcInfo.LastWriteTimeUtc) {
        $needCopy = $false
    }
}

if (-not $needCopy) {
    Write-Host ('[OK] 资产库已是最新（{0:N2} MB，无需复制）' -f ($srcInfo.Length / 1MB)) -ForegroundColor Green
    exit 0
}

Copy-Item -Path $src -Destination $dst -Force
$mb = [math]::Round((Get-Item $dst).Length / 1MB, 2)
Write-Host "[OK] 已同步 data\tjc_hymn.db → hymn_app\assets\data\tjc_hymn.db（$mb MB）" -ForegroundColor Green
Write-Host '    提醒：若数据库内容有变化，记得把 db_bootstrap.dart 的 assetVersion +1' -ForegroundColor Yellow
