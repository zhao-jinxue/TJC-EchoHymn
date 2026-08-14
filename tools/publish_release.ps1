<#
.SYNOPSIS
    发布流水线：构建最新代码 → 打包版本化迁移包 → 只保留最近 N 个发布版本。

.DESCRIPTION
    供 git post-commit 钩子自动调用，也可手动执行：

      手动执行（推荐）：
        pwsh -NoProfile -ExecutionPolicy Bypass -File tools\publish_release.ps1

    行为：
      1. 仅当当前分支为 master/main 时才自动发布（避免特性分支误触发）
      2. 使用官方 pub 源构建 hugm_app Web release
      3. 调用 package_web.ps1 打包为 release\<版本名>\<版本名>.zip
      4. 删除 release\ 下多余的旧版本目录，只保留最近 [KeepCount] 个

    版本名自动生成：短commitHash-时间戳，如 e26cb8c-20260814-214507

.NOTES
    注意：此脚本【绝不能】执行 git add/commit 等写操作，
    否则会在 post-commit 钩子中造成无限循环。
#>

param(
    # 保留的发布版本数量
    [int]$KeepCount = 5
)

$ErrorActionPreference = 'Stop'

# ---- 仓库根目录 ----
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$ToolsDir = Join-Path $Root 'tools'
$ReleaseDir = Join-Path $Root 'release'
$WebDir = Join-Path $Root 'hymn_app\build\web'

function Write-Step { Write-Host "[*] $args" -ForegroundColor Cyan }
function Write-OK { Write-Host "[OK] $args" -ForegroundColor Green }
function Write-ErrorL { Write-Host "[ERR] $args" -ForegroundColor Red }

# ---- 1. 分支检查（master/main 才自动发布）----
try {
    $branch = & git -C $Root rev-parse --abbrev-ref HEAD 2>$null
}
catch { $branch = '' }
if ($branch -ne 'master' -and $branch -ne 'main') {
    Write-Step "分支 $branch 非 master/main，跳过自动发布"
    exit 0
}
$commitShort = (& git -C $Root rev-parse --short HEAD 2>$null)
if (-not $commitShort) { $commitShort = 'nogit' }
Write-Step "提交 $branch@$commitShort 触发自动发布"

# ---- 2. 使用官方源构建（镜像源 TLS 有问题）----
$env:PUB_HOSTED_URL = 'https://pub.dev'
$env:FLUTTER_STORAGE_BASE_URL = 'https://storage.googleapis.com'

Write-Step '构建 Web release 版本...'
Push-Location (Join-Path $Root 'hymn_app')
try {
    flutter build web --release 2>&1 | Out-Host
    if ($LASTEXITCODE -ne 0) {
        Write-ErrorL "flutter build web --release 失败 (exit=$LASTEXITCODE)，已中止发布"
        exit 1
    }
}
finally {
    Pop-Location
}
Write-OK '构建完成'

# ---- 3. 打包版本化迁移包 ----
Write-Step '打包迁移包...'
$packageScript = Join-Path $ToolsDir 'package_web.ps1'
& $packageScript 2>&1 | Out-Host
if ($LASTEXITCODE -ne 0) {
    Write-ErrorL "打包失败 (exit=$LASTEXITCODE)，已中止发布"
    exit 1
}
Write-OK '打包完成'

# ---- 4. 只保留最近 KeepCount 个版本目录 ----
Write-Step "清理旧版本（保留最近 $KeepCount 个）..."
if (Test-Path $ReleaseDir) {
    # 按创建时间倒序排序的版本子目录（形如 echohymn-web-*）
    $versionDirs = Get-ChildItem -Path $ReleaseDir -Directory |
    Where-Object { $_.Name -like 'echohymn-web-*' } |
    Sort-Object CreationTime -Descending

    $toDelete = $versionDirs | Select-Object -Skip $KeepCount
    foreach ($d in $toDelete) {
        Remove-Item $d.FullName -Recurse -Force -ErrorAction SilentlyContinue
        Write-Step "已删除旧版本: $($d.Name)"
    }

    if ($toDelete.Count -eq 0) {
        Write-OK "无需清理（当前 $($versionDirs.Count) 个版本 ≤ $KeepCount）"
    }
}

# ---- 5. 汇总 ----
$newest = Get-ChildItem -Path $ReleaseDir -Directory -ErrorAction SilentlyContinue |
Where-Object { $_.Name -like 'echohymn-web-*' } |
Sort-Object CreationTime -Descending |
Select-Object -First 1

Write-Host ""
Write-Host "==============================================" -ForegroundColor Green
Write-Host "  自动发布完成 (commit $commitShort)"           -ForegroundColor Green
if ($newest) {
    Write-Host "  最新版本: $($newest.Name)"                  -ForegroundColor Green
    Write-Host "  位置:     $($newest.FullName)"               -ForegroundColor Green
}
$kept = Get-ChildItem -Path $ReleaseDir -Directory -ErrorAction SilentlyContinue |
Where-Object { $_.Name -like 'echohymn-web-*' }
Write-Host "  当前保留: $($kept.Count) 个版本（上限 $KeepCount）" -ForegroundColor Green
Write-Host "==============================================" -ForegroundColor Green