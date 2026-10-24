<#
.SYNOPSIS
    全平台发布流水线：一次 commit 同时产出 Windows 与 Android release 产物。

.DESCRIPTION
    由 git post-commit 钩子调用（tools\git-hooks\post-commit），也可手动执行：

        pwsh -NoProfile -ExecutionPolicy Bypass -File tools\publish_all.ps1
        pwsh -NoProfile -ExecutionPolicy Bypass -File tools\publish_all.ps1 -SkipWindows
        pwsh -NoProfile -ExecutionPolicy Bypass -File tools\publish_all.ps1 -SkipAndroid

    目的：**同一 commit 的 Windows / Android 产物始终对齐**，避免两个平台的
    功能与修复不同步（历史问题：Windows 自动发布、Android 全靠手动）。

    产物布局（互不覆盖）：
      release\windows\echohymn_win_<时间戳>_<sha>\        桌面包（exe + data/）
      release\android\echohymn_android_<时间戳>_<sha>\    4 变体 APK + SHA256SUMS + BUILD-INFO
      release\ohos\                                       OpenHarmony 预留（暂不产出）

    **installer（Inno Setup 安装包）不在此流程内**：仅在定版本打 tag 后由
    tools\build_installer.ps1 产出（体积 3 GB 级，不宜每次 commit 重打）。

    各平台脚本为独立 pwsh 子进程，一个失败不影响另一个继续。
    汇总写 release\auto-release-summary.log（UTF-8 with BOM）。

.NOTES
    此脚本【绝不能】执行 git add/commit 等写操作（post-commit 死循环）。
#>
param(
    [int]$KeepCount = 5,
    [switch]$SkipWindows,
    [switch]$SkipAndroid
)

$ErrorActionPreference = 'Stop'

$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$ReleaseRoot = Join-Path $Root 'release'
$SummaryLog = Join-Path $ReleaseRoot 'auto-release-summary.log'

if (-not (Test-Path $ReleaseRoot)) { New-Item -ItemType Directory -Path $ReleaseRoot -Force | Out-Null }

function Write-Sum {
    param([string]$Text, [ConsoleColor]$Color = [ConsoleColor]::Gray)
    Write-Host $Text -ForegroundColor $Color
    try { Add-Content -Path $SummaryLog -Value $Text -Encoding utf8BOM -ErrorAction Stop } catch { }
}

# ---- 分支检查（与各平台脚本一致：仅 master/main）----
try { $branch = & git -C $Root rev-parse --abbrev-ref HEAD 2>$null } catch { $branch = '' }
if ($branch -ne 'master' -and $branch -ne 'main') {
    Write-Sum "[*] 分支 $branch 非 master/main，跳过多平台发布" -Color DarkGray
    exit 0
}
$commitShort = (& git -C $Root rev-parse --short HEAD 2>$null)
if (-not $commitShort) { $commitShort = 'nogit' }

$ts = Get-Date -Format 'yyyyMMdd-HHmmss'
try { Set-Content -Path $SummaryLog -Value '' -Encoding utf8BOM -ErrorAction Stop } catch { }

Write-Sum ''
Write-Sum '==============================================' -Color Cyan
Write-Sum "  多平台发布开始  commit=$commitShort  分支=$branch  $ts" -Color Cyan
Write-Sum '==============================================' -Color Cyan

# 子任务表：名称 / 脚本 / 开关
$jobs = @(
    @{ Name = 'Windows'; Script = 'publish_windows.ps1'; Skip = $SkipWindows },
    @{ Name = 'Android'; Script = 'publish_android.ps1'; Skip = $SkipAndroid }
)

$results = @()
foreach ($j in $jobs) {
    if ($j.Skip) {
        Write-Sum "[--] $($j.Name) 已按参数跳过" -Color DarkGray
        $results += [pscustomobject]@{ Platform = $j.Name; Exit = 'skipped' }
        continue
    }
    $script = Join-Path $Root ("tools\$($j.Script)")
    if (-not (Test-Path $script)) {
        Write-Sum "[ERR] 缺少脚本 $script" -Color Red
        $results += [pscustomobject]@{ Platform = $j.Name; Exit = 'missing' }
        continue
    }
    Write-Sum "[*] 开始 $($j.Name) 发布..." -Color Cyan
    # 用独立进程，避免子脚本的 exit / $LASTEXITCODE 污染本进程
    & pwsh -NoProfile -ExecutionPolicy Bypass -File $script -KeepCount $KeepCount
    $code = $LASTEXITCODE
    if ($code -eq 0) {
        Write-Sum "[OK] $($j.Name) 发布完成" -Color Green
    }
    else {
        Write-Sum "[ERR] $($j.Name) 发布失败 (exit=$code)" -Color Red
    }
    $results += [pscustomobject]@{ Platform = $j.Name; Exit = $code }
}

# ---- 汇总 ----
Write-Sum ''
Write-Sum '----------------------------------------------' -Color Cyan
foreach ($r in $results) {
    $tag = if ($r.Exit -eq 0) { 'OK  ' } elseif ($r.Exit -eq 'skipped') { 'SKIP' } else { 'FAIL' }
    Write-Sum "  [$tag] $($r.Platform)" -Color $(if ($r.Exit -eq 0) { 'Green' } elseif ($r.Exit -eq 'skipped') { 'DarkGray' } else { 'Red' })
}
foreach ($p in @(@{ n = 'windows'; d = 'release\windows' }, @{ n = 'android'; d = 'release\android' }, @{ n = 'ohos'; d = 'release\ohos' })) {
    $dir = Join-Path $Root $p.d
    $latest = Get-ChildItem -Path $dir -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like 'echohymn_*' } | Sort-Object Name -Descending | Select-Object -First 1
    $latestName = if ($latest) { $latest.Name } else { '（暂无）' }
    Write-Sum ("  {0,-8}: {1}" -f $p.n, $latestName) -Color Gray
}
Write-Sum '----------------------------------------------' -Color Cyan
Write-Sum '  installer 不在此流程内：定版本打 tag 后跑 tools\build_installer.ps1' -Color Yellow
Write-Sum '==============================================' -Color Cyan

$failed = @($results | Where-Object { $_.Exit -ne 0 -and $_.Exit -ne 'skipped' })
exit $(if ($failed.Count -gt 0) { 1 } else { 0 })
