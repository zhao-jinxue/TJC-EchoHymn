<#
.SYNOPSIS
    Android 发布流水线：git commit 后自动构建 4 个变体 release APK 并整理产物。

.DESCRIPTION
    由 tools\publish_all.ps1 调用（post-commit 钩子 → publish_all → 本脚本），
    也可手动执行：

        pwsh -NoProfile -ExecutionPolicy Bypass -File tools\publish_android.ps1

    行为：
      1. 仅当当前分支为 master/main 时才自动发布（避免特性分支误触发）
      2. 逐变体构建：flutter build apk --release --flavor <v> --target-platform android-arm64
         （变体 full / piano / vocal / lite，applicationId 后缀 .piano/.vocal/.lite）
      3. 产物拷贝到 release\android\echohymn_android_<时间戳>_<短commitHash>\
      4. 生成 SHA256SUMS.txt 与 BUILD-INFO.txt
      5. 删除 release\android\ 下多余旧版本目录，只保留最近 [KeepCount] 个

    日志：release\android\auto-release.log（UTF-8 with BOM）。

.NOTES
    此脚本【绝不能】执行 git add/commit 等写操作，否则 post-commit 钩子会无限循环。
    **平台产物互不覆盖**：
      release\windows\  ← Windows 桌面版（publish_windows.ps1）
      release\android\  ← Android 手机版（本脚本，4 变体）
      release\ohos\     ← OpenHarmony 预留（当前不产出）
    安装包（installer）**不在 commit 流程内**，仅在定版本打 tag 后用
    tools\build_installer.ps1 产出（见 release\README.md）。
#>
param(
    # 保留的发布版本数量
    [int]$KeepCount = 5,
    # 需要构建的变体（2026-11-13 起 release **只打主体**：单一 APK，运行时按素材检测切换 UI）
    [string[]]$Variants = @('full'),
    # 目标 ABI（arm64 覆盖绝大多数真机）
    [string]$TargetPlatform = 'android-arm64'
)

$ErrorActionPreference = 'Stop'

$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$ReleaseRoot = Join-Path $Root 'release'
$ReleaseDir = Join-Path $ReleaseRoot 'android'
$AppDir = Join-Path $Root 'hymn_app'
$ApkOutBase = Join-Path $AppDir 'build\app\outputs\apk'
$LogFile = Join-Path $ReleaseDir 'auto-release.log'

if (-not (Test-Path $ReleaseDir)) { New-Item -ItemType Directory -Path $ReleaseDir -Force | Out-Null }

function Write-Log {
    param([string]$Text, [ConsoleColor]$Color = [ConsoleColor]::Gray)
    Write-Host $Text -ForegroundColor $Color
    try { Add-Content -Path $LogFile -Value $Text -Encoding utf8BOM -ErrorAction Stop } catch { }
}
function Write-Step   { Write-Log "[*] $args" -Color Cyan }
function Write-OK     { Write-Log "[OK] $args" -Color Green }
function Write-ErrorL { Write-Log "[ERR] $args" -Color Red }

try { Set-Content -Path $LogFile -Value '' -Encoding utf8BOM -ErrorAction Stop } catch { }

# ---- 1. 分支检查（master/main 才自动发布）----
try { $branch = & git -C $Root rev-parse --abbrev-ref HEAD 2>$null } catch { $branch = '' }
if ($branch -ne 'master' -and $branch -ne 'main') {
    Write-Step "分支 $branch 非 master/main，跳过 Android 自动发布"
    exit 0
}
$commitShort = (& git -C $Root rev-parse --short HEAD 2>$null)
if (-not $commitShort) { $commitShort = 'nogit' }
Write-Step "提交 $branch@$commitShort 触发 Android 自动发布（变体: $($Variants -join '/')）"

# ---- 2. 环境自愈：PUB_CACHE 必须在中文路径之外 ----
if (-not $env:PUB_CACHE -and (Test-Path 'E:\pub-cache')) {
    $env:PUB_CACHE = 'E:\pub-cache'
    Write-Step '未设置 PUB_CACHE，已回落到 E:\pub-cache'
}
Write-Step "PUB_CACHE=$env:PUB_CACHE"

# ---- 3. 版本号（单一源 pubspec.yaml）----
$verLine = Select-String -Path (Join-Path $AppDir 'pubspec.yaml') -Pattern '^version:\s*(\S+)' | Select-Object -First 1
$ver = if ($verLine) { $verLine.Matches[0].Groups[1].Value.Split('+')[0] } else { '0.0.0' }
Write-Step "版本号 v$ver"

$ts = Get-Date -Format 'yyyyMMdd-HHmmss'
$PkgName = "echohymn_android_${ts}_${commitShort}"
$PkgOutDir = Join-Path $ReleaseDir $PkgName
if (Test-Path $PkgOutDir) { Remove-Item $PkgOutDir -Recurse -Force }
New-Item -ItemType Directory -Path $PkgOutDir -Force | Out-Null

# ---- 3.5. 同步内置数据库资产（单一数据源 data/tjc_hymn.db → assets）----
$sync = Join-Path $Root 'tools\sync_db_asset.ps1'
if (Test-Path $sync) {
    Write-Step '同步内置数据库资产（assets/data/tjc_hymn.db）...'
    & pwsh -NoProfile -ExecutionPolicy Bypass -File $sync
    if ($LASTEXITCODE -ne 0) {
        Write-ErrorL '数据库资产同步失败（APK 内可能是旧库），继续构建'
    }
    else {
        Write-OK '数据库资产已同步'
    }
}
else {
    Write-ErrorL "缺少 $sync，APK 内将不含最新数据库"
}

# ---- 4. 逐变体构建 ----
$built = New-Object System.Collections.ArrayList
foreach ($v in $Variants) {
    Write-Step "构建变体 $v ..."
    # 按变体裁剪内置音频样本：full 双版本 / piano 仅钢琴 / vocal 仅人声 / lite 无音频
    $syncSamples = Join-Path $Root 'tools\sync_audio_samples.ps1'
    if (Test-Path $syncSamples) {
        # 2026-11-13 用户定稿：release 只打**主体**（程序 + 数据库），素材由 installer 数据包导入。
        $syncArgs = @('-Variant', $v, '-Empty')
        & pwsh -NoProfile -ExecutionPolicy Bypass -File $syncSamples @syncArgs | Out-Null
        if ($LASTEXITCODE -ne 0) { Write-ErrorL "样本同步失败（变体 $v），继续构建" }
    }
    Push-Location $AppDir
    try {
        # 强制资源重新打包（2026-10-28 教训：flutter build 的 asset bundle 有增量缓存，
        # 只改素材目录内容不会失效 → 大包切换时更易串素材）
        $pubspec = Join-Path $AppDir 'pubspec.yaml'
        if (Test-Path $pubspec) { (Get-Item $pubspec).LastWriteTime = Get-Date }
        # flutter 的正常提示会写 stderr，Stop 模式下会被误判为终止性错误
        $prevEAP = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        flutter build apk --release --flavor $v --target-platform $TargetPlatform "--dart-define=AUDIO_VARIANT=$v" 2>&1 | Out-Host
        $code = $LASTEXITCODE
        $ErrorActionPreference = $prevEAP
    }
    finally {
        Pop-Location
    }
    if ($code -ne 0) {
        Write-ErrorL "变体 $v 构建失败 (exit=$code)，跳过该变体"
        continue
    }

    $apk = Join-Path $ApkOutBase "$v\release\app-$v-release.apk"
    if (-not (Test-Path $apk)) {
        Write-ErrorL "未找到产物 $apk，跳过该变体"
        continue
    }
    $dst = Join-Path $PkgOutDir ("EchoHymn-{0}-v{1}-{2}.apk" -f $v, $ver, $commitShort)
    Copy-Item -Path $apk -Destination $dst -Force
    $mb = [math]::Round((Get-Item $dst).Length / 1MB, 1)
    Write-OK "  $v -> $([System.IO.Path]::GetFileName($dst))（$mb MB）"
    [void]$built.Add($v)
}

if ($built.Count -eq 0) {
    Write-ErrorL '所有变体均构建失败，清理空目录后退出'
    Remove-Item $PkgOutDir -Recurse -Force -ErrorAction SilentlyContinue
    exit 1
}

# ---- 5. 校验和清单与构建说明 ----
$sums = foreach ($f in (Get-ChildItem -Path $PkgOutDir -File -Filter '*.apk' | Sort-Object Name)) {
    "{0}  {1}" -f (Get-FileHash -Path $f.FullName -Algorithm SHA256).Hash.ToLower(), $f.Name
}
Set-Content -Path (Join-Path $PkgOutDir 'SHA256SUMS.txt') -Value $sums -Encoding utf8BOM
Write-OK '已生成 SHA256SUMS.txt'

$manifest = @(
    'EchoHymn Android 构建产物',
    '',
    "提交:    $branch@$commitShort",
    "版本:    v$ver",
    "时间:    $ts",
    "ABI:     $TargetPlatform",
    "已构建:  $($built -join ', ')",
    '',
    '变体说明（applicationId / 音频内容）:',
    '  full   com.echohymn.app        474 首全音频',
    '  piano  com.echohymn.app.piano  仅鋼琴音频',
    '  vocal  com.echohymn.app.vocal  仅人声音频',
    '  lite   com.echohymn.app.lite   无内置音频（占位替代规则）',
    '',
    '校验: 文件 SHA256 见 SHA256SUMS.txt'
)
Set-Content -Path (Join-Path $PkgOutDir 'BUILD-INFO.txt') -Value $manifest -Encoding utf8BOM

# ---- 5.6 版本级发布记录（F-3 验收项：SHA256 留档 + 版本日志）----
# 2026-11-11 修复：此前本脚本只写 auto-release.log（每次清空重写），
# `release/android/android-release.log` 自 2026-10-25 起停更 → F-3 该项实际失效。
# 现在每次发布**追加**一条版本记录（含签名指纹与各变体体积），保留历史。
$versionLog = Join-Path $ReleaseDir 'android-release.log'
if (-not (Test-Path $versionLog)) {
    Set-Content -Path $versionLog -Value 'EchoHymn Android 发布记录' -Encoding utf8BOM
}
$sigLine = '（未校验）'
try {
    $bt = Get-ChildItem 'D:\Android\Sdk\build-tools' -Directory -ErrorAction Stop |
        Sort-Object Name -Descending | Select-Object -First 1
    $firstApk = Get-ChildItem -Path $PkgOutDir -File -Filter '*.apk' |
        Sort-Object Name | Select-Object -First 1
    if ($bt -and $firstApk) {
        $cert = & "$($bt.FullName)\apksigner.bat" verify --print-certs $firstApk.FullName 2>&1 |
            Select-String -Pattern 'SHA-256 digest' | Select-Object -First 1
        if ($cert) { $sigLine = ($cert.Line -replace '.*SHA-256 digest:\s*', '').Trim() }
    }
}
catch { }
$record = @(
    '',
    '----------------------------------------------',
    "时间: $(Get-Date -Format 'yyyyMMdd-HHmmss')",
    "提交: $branch@$commitShort",
    "版本: v$ver",
    "ABI:  $TargetPlatform",
    "目录: $PkgName",
    "签名: SHA-256 $sigLine",
    '',
    '产物:'
) + @($built | ForEach-Object {
        $f = Get-ChildItem -Path $PkgOutDir -File -Filter "EchoHymn-$_-*.apk" |
            Select-Object -First 1
        if ($f) { "  $($f.Name)  ($([math]::Round($f.Length / 1MB, 1)) MB)" }
        else { "  $_（缺失）" }
    })
Add-Content -Path $versionLog -Value $record -Encoding utf8BOM
Write-OK "已追加版本记录 → release\android\android-release.log（签名 $sigLine）"

# ---- 5.5 产物白名单校验（B-6）：禁止类型 / 库外路径 / 数据基线 ----
$verify = Join-Path $Root 'tools\verify_android_package.ps1'
if (Test-Path $verify) {
    Write-Step '校验产物白名单与数据基线...'
    $verifyFailed = $false
    $isFirst = $true
    foreach ($apkFile in (Get-ChildItem -Path $PkgOutDir -File -Filter '*.apk' | Sort-Object Name)) {
        $vArgs = @{ Apk = $apkFile.FullName }
        if (-not $isFirst) { $vArgs['SkipBaseline'] = $true } # 基线只校验一次（各变体同库）
        & pwsh -NoProfile -ExecutionPolicy Bypass -File $verify @vArgs 2>&1 | ForEach-Object { Write-Log $_ }
        if ($LASTEXITCODE -ne 0) { $verifyFailed = $true }
        $isFirst = $false
    }
    if ($verifyFailed) {
        Write-ErrorL '白名单/基线校验未通过（详见上方 FAIL 项）'
    }
    else {
        Write-OK '白名单与数据基线校验通过（全部变体）'
    }
}


# ---- 6. 只保留最近 KeepCount 个版本目录 ----
Write-Step "清理旧版本（保留最近 $KeepCount 个）..."
$versionDirs = Get-ChildItem -Path $ReleaseDir -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -like 'echohymn_android_*' } |
    Sort-Object Name -Descending
$toDelete = $versionDirs | Select-Object -Skip $KeepCount
foreach ($d in $toDelete) {
    Remove-Item $d.FullName -Recurse -Force -ErrorAction SilentlyContinue
    Write-Step "已删除旧版本: $($d.Name)"
}
if (-not $toDelete) { Write-OK "无需清理（当前 $($versionDirs.Count) 个版本 ≤ $KeepCount）" }

# ---- 7. 汇总 ----
Write-Log ''
Write-Log '==============================================' -Color Green
Write-Log "  Android 自动发布完成 (commit $commitShort)" -Color Green
Write-Log "  最新版本: $PkgName" -Color Green
Write-Log "  变体:     $($built -join ', ')" -Color Green
Write-Log "  位置:     $PkgOutDir" -Color Green
$kept = Get-ChildItem -Path $ReleaseDir -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -like 'echohymn_android_*' }
Write-Log "  当前保留: $($kept.Count) 个版本（上限 $KeepCount）" -Color Green
Write-Log '==============================================' -Color Green
exit 0


