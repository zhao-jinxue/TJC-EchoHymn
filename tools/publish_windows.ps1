<#
.SYNOPSIS
    Windows 发布流水线：git commit 后自动构建 Windows release 并整理产物。

.DESCRIPTION
    供 git post-commit 钩子自动调用，也可手动执行：

      手动执行：
        pwsh -NoProfile -ExecutionPolicy Bypass -File tools\publish_windows.ps1

    行为：
      1. 仅当当前分支为 master/main 时才自动发布（避免特性分支误触发）
      2. flutter build windows --release 构建桌面版
      3. 将产物拷贝到 release\echohymn-win-<短commitHash>-<时间戳>\ 版本化目录
      4. 删除 release\ 下多余的旧版本目录，只保留最近 [KeepCount] 个

    版本名自动生成：短commitHash-时间戳，如 e26cb8c-20260814-214507

.NOTES
    注意：此脚本【绝不能】执行 git add/commit 等写操作，
    否则会在 post-commit 钩子中造成无限循环。
    仅针对 Windows 桌面版（目标平台主推）。
#>
param(
    # 保留的发布版本数量
    [int]$KeepCount = 5
)

$ErrorActionPreference = 'Stop'

# ---- 仓库根目录 ----
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$ReleaseDir = Join-Path $Root 'release'
$AppDir = Join-Path $Root 'hymn_app'
$BuildOut = Join-Path $AppDir 'build\windows\x64\runner\Release'

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
Write-Step "提交 $branch@$commitShort 触发 Windows 自动发布"

# ---- 2. 构建 Windows release ---- 
Write-Step '构建 Windows release 版本...'
Push-Location $AppDir
try {
    flutter build windows --release 2>&1 | Out-Host
    if ($LASTEXITCODE -ne 0) {
        Write-ErrorL "flutter build windows --release 失败 (exit=$LASTEXITCODE)，已中止发布"
        exit 1
    }
}
finally {
    Pop-Location
}
Write-OK '构建完成'

# ---- 3. 校验产物并打包版本化目录 ----
if (-not (Test-Path (Join-Path $BuildOut 'echo_hymn.exe'))) {
    Write-ErrorL "未找到构建产物 $BuildOut\echo_hymn.exe"
    exit 1
}

$ts = Get-Date -Format 'yyyyMMdd-HHmmss'
$PkgName = "echohymn-win-$commitShort-$ts"
$PkgOutDir = Join-Path $ReleaseDir $PkgName

Write-Step "打包版本目录 $PkgName ..."
if (-not (Test-Path $ReleaseDir)) { New-Item -ItemType Directory -Path $ReleaseDir -Force | Out-Null }
if (Test-Path $PkgOutDir) { Remove-Item $PkgOutDir -Recurse -Force }
Copy-Item -Path (Join-Path $BuildOut '*')        -Destination $PkgOutDir -Recurse -Force | Out-Null

# 同时拷贝 data/（数据库 + 音频）到版本目录，保证目标机有数据
$DataDir = Join-Path $Root 'data'
if (Test-Path $DataDir) {
    Copy-Item -Path $DataDir -Destination (Join-Path $PkgOutDir 'data') -Recurse -Force | Out-Null
}
Write-OK "产物已整理到 $PkgOutDir"

# ---- 4. 只保留最近 KeepCount 个版本目录 ----
Write-Step "清理旧版本（保留最近 $KeepCount 个）..."
if (Test-Path $ReleaseDir) {
    $versionDirs = Get-ChildItem -Path $ReleaseDir -Directory |
        Where-Object { $_.Name -like 'echohymn-win-*' } |
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
Write-Host ""
Write-Host "==============================================" -ForegroundColor Green
Write-Host "  Windows 自动发布完成 (commit $commitShort)"    -ForegroundColor Green
Write-Host "  最新版本: $PkgName"                            -ForegroundColor Green
Write-Host "  位置:     $PkgOutDir"                          -ForegroundColor Green
$kept = Get-ChildItem -Path $ReleaseDir -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -like 'echohymn-win-*' }
Write-Host "  当前保留: $($kept.Count) 个版本（上限 $KeepCount）" -ForegroundColor Green
Write-Host "==============================================" -ForegroundColor Green