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
      3. 将产物拷贝到 release\echohymn_win_<时间戳>_<短commitHash>\ 版本化目录
      4. 删除 release\ 下多余的旧版本目录，只保留最近 [KeepCount] 个

    版本名自动生成：时间戳_短commitHash，如 20260814-214507_e26cb8c
    （时间戳前置、下划线分隔，目录名可直接按名称排序定位最新版本）

    日志：
      输出同时写控制台与 release\auto-release.log。
      日志文件使用 UTF-8 with BOM 编码，PowerShell 5.1（Get-Content 默认 ANSI）
      与 PowerShell 7 均能正确识别中文，避免乱码。
      每次运行会覆盖旧日志（仅保留本次发布过程）。

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
$LogFile = Join-Path $ReleaseDir 'auto-release.log'

# ---- 日志函数：同时写控制台与日志文件（UTF-8 with BOM） ----
# utf8BOM：Windows PowerShell 5.1 / PowerShell 7 均支持该编码名
function Write-Log {
    param(
        [string]$Text,
        [ConsoleColor]$Color = [ConsoleColor]::Gray
    )
    Write-Host $Text -ForegroundColor $Color
    try {
        Add-Content -Path $LogFile -Value $Text -Encoding utf8BOM -ErrorAction Stop
    }
    catch {
        # 日志写入失败不影响发布流程
    }
}

function Write-Step   { Write-Log "[*] $args" -Color Cyan }
function Write-OK     { Write-Log "[OK] $args" -Color Green }
function Write-ErrorL { Write-Log "[ERR] $args" -Color Red }

# ---- 初始化 release 与日志文件（覆盖旧日志，写入 BOM） ----
if (-not (Test-Path $ReleaseDir)) { New-Item -ItemType Directory -Path $ReleaseDir -Force | Out-Null }
try {
    Set-Content -Path $LogFile -Value '' -Encoding utf8BOM -ErrorAction Stop
}
catch {
    # 若写日志失败，后续 Write-Log 会静默忽略
}

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
    # 临时放宽 ErrorActionPreference：flutter 正常提示（如 assets 下载）会写入
    # stderr，在 PowerShell 5.1 + $ErrorActionPreference=Stop 下会被误判为
    # 终止性错误（NativeCommandError），导致发布中断。构建后恢复原有设置。
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    # flutter 输出直接透传控制台（其 ANSI 特殊字符/进度动画不写入日志，
    #      保证日志文件为纯净 UTF-8 中文文本，PowerShell 5.1/7 均正常显示）。
    flutter build windows --release 2>&1 | Out-Host
    $ErrorActionPreference = $prevEAP
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

# 剔除 build 输出目录中「应用运行时产物」（logs/state.json）。
# 注意：**绝不能删除 $BuildOut/data/** —— 它是 Flutter 引擎运行资产
# （flutter_assets/、app.so、icudtl.dat），删除后 exe 会在引擎初始化阶段
# 以退出码 1 闪退，且 Dart 日志根本不会生成。
Get-ChildItem -Path $BuildOut -Directory -Filter 'logs' -ErrorAction SilentlyContinue |
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
Get-ChildItem -Path $BuildOut -File -Filter 'state.json' -ErrorAction SilentlyContinue |
    Remove-Item -Force -ErrorAction SilentlyContinue

$ts = Get-Date -Format 'yyyyMMdd-HHmmss'
$PkgName = "echohymn_win_${ts}_${commitShort}"
$PkgOutDir = Join-Path $ReleaseDir $PkgName

Write-Step "打包版本目录 $PkgName ..."
if (-not (Test-Path $ReleaseDir)) { New-Item -ItemType Directory -Path $ReleaseDir -Force | Out-Null }
if (Test-Path $PkgOutDir) { Remove-Item $PkgOutDir -Recurse -Force }
New-Item -ItemType Directory -Path $PkgOutDir -Force | Out-Null
Copy-Item -Path (Join-Path $BuildOut '*') -Destination $PkgOutDir -Recurse -Force | Out-Null

# 同时拷贝 data/（数据库 + 音频）到版本目录，保证目标机有数据。
# 注意：目标 $PkgOutDir/data 已存在（Flutter 引擎资产 flutter_assets/app.so/icudtl.dat），
# 因此必须拷贝「源的内容」（${DataDir}\*）而非源目录本身，否则会产生嵌套 data/data/
# 结构，导致 tjc_hymn.db 不在 exe 同级 data/ 顶层、AppPaths 向上查找失败。
$DataDir = Join-Path $Root 'data'
$PkgDataDir = Join-Path $PkgOutDir 'data'
if (Test-Path $DataDir) {
    if (-not (Test-Path $PkgDataDir)) {
        New-Item -ItemType Directory -Path $PkgDataDir -Force | Out-Null
    }
    Copy-Item -Path (Join-Path $DataDir '*') -Destination $PkgDataDir -Recurse -Force | Out-Null
}
Write-OK "产物已整理到 $PkgOutDir"

# ---- 4. 只保留最近 KeepCount 个版本目录 ----
Write-Step "清理旧版本（保留最近 $KeepCount 个）..."
if (Test-Path $ReleaseDir) {
    # 新命名 echohymn_win_<时间戳>_<短哈希> 保证名称排序=时间排序（最新在最前）
    $versionDirs = Get-ChildItem -Path $ReleaseDir -Directory |
        Where-Object { $_.Name -like 'echohymn_win_*' } |
        Sort-Object Name -Descending

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
Write-Log ''
Write-Log '==============================================' -Color Green
Write-Log "  Windows 自动发布完成 (commit $commitShort)" -Color Green
Write-Log "  最新版本: $PkgName" -Color Green
Write-Log "  位置:     $PkgOutDir" -Color Green
$kept = Get-ChildItem -Path $ReleaseDir -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -like 'echohymn_win_*' }
Write-Log "  当前保留: $($kept.Count) 个版本（上限 $KeepCount）" -Color Green
Write-Log '==============================================' -Color Green