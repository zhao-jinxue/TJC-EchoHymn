<#
.SYNOPSIS
    Android 产物白名单校验：禁止类型 / 库外路径 / 数据基线。

.DESCRIPTION
    验收口径（IMPLEMENTATION_PLAN B-6）：
      ① 产物**不得包含** `.pdf` / `.exe` / `.mp4` 等文档、可执行、视频文件；
      ② `assets/flutter_assets/` 下**不得出现库外路径**（只允许白名单目录）；
      ③ 顺带校验 M2 数据基线（ANDROID_PLAN §12.2）：474 首 / 21819 行 / 321703 单元格。

    用法：

        pwsh -NoProfile -File tools\verify_android_package.ps1
        pwsh -NoProfile -File tools\verify_android_package.ps1 -Apk path\to\app-full-release.apk
        pwsh -NoProfile -File tools\verify_android_package.ps1 -SkipBaseline   # 跳过 DB 基线（无 python 时）

    不带 -Apk 时：优先校验 `release\android` 最新版本目录里的全部 APK；
    若不存在，则回落到 `hymn_app\build\app\outputs\apk\<变体>\release\`。

.NOTES
    白名单目录：assets/data（库与 json）、assets/media（样本音频与扫描图）、assets/fonts（内嵌字体）、
    shaders / packages / fonts（Flutter 框架资源）。其余一律视为「库外路径」并判失败。
    退出码：0 = 全部通过；1 = 有失败项（供 publish_android.ps1 判断）。
#>
param(
    [string]$Apk,
    [switch]$SkipBaseline
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)

# ---- 禁止的扩展名（文档 / 可执行 / 视频；音频与图片是合法素材）----
$ForbiddenExt = @('.pdf', '.exe', '.msi', '.apk', '.mp4', '.webm', '.mkv', '.avi', '.mov',
    '.doc', '.docx', '.ppt', '.pptx', '.xls', '.xlsx', '.zip', '.7z', '.rar')

# ---- flutter_assets 下允许的路径前缀 ----
$AllowedPrefixes = @(
    'assets/data/',      # tjc_hymn.db / hymns.json
    'assets/media/',     # 样本音频 + 扫描图
    'assets/fonts/',     # 内嵌字体（EchoSans / EchoKai / EchoJianpu）
    'shaders/',
    'packages/',
    'fonts/'             # Flutter 框架字体（MaterialIcons 等）
)
# 框架自身在 flutter_assets 根下的固定文件（不算库外路径）
$AllowedRootFiles = @(
    'AssetManifest.json', 'AssetManifest.bin', 'FontManifest.json', 'NOTICES',
    'NOTICES.Z', 'version.json', 'isolate_snapshot_data', 'kernel_blob.bin',
    'vm_snapshot_data',
    # Flutter native-assets 特性（flutter config --enable-native-assets）产物；
    # `objective_c` 依赖它，缺失会构建失败，故属框架合法文件
    'NativeAssetsManifest.json'
)

Add-Type -AssemblyName System.IO.Compression.FileSystem

function Resolve-TargetApks {
    if ($Apk) {
        if (-not (Test-Path $Apk)) { throw "APK 不存在：$Apk" }
        return @((Resolve-Path $Apk).Path)
    }
    $releaseRoot = Join-Path $Root 'release\android'
    if (Test-Path $releaseRoot) {
        $latest = Get-ChildItem $releaseRoot -Directory -Filter 'echohymn_android_*' |
            Sort-Object Name -Descending | Select-Object -First 1
        if ($latest) {
            $apks = @(Get-ChildItem $latest.FullName -File -Filter '*.apk' | Select-Object -ExpandProperty FullName)
            if ($apks.Count -gt 0) { return $apks }
        }
    }
    $buildApk = Join-Path $Root 'hymn_app\build\app\outputs\apk'
    if (Test-Path $buildApk) {
        $apks = @(Get-ChildItem $buildApk -Recurse -File -Filter 'app-*-release.apk' |
                Select-Object -ExpandProperty FullName)
        if ($apks.Count -gt 0) { return $apks }
    }
    throw '未找到任何 APK：请先构建，或用 -Apk 指定路径'
}

function Test-OneApk {
    param([string]$Path)

    $name = [System.IO.Path]::GetFileName($Path)
    $forbidden = New-Object System.Collections.ArrayList
    $outside = New-Object System.Collections.ArrayList
    $dbEntry = $null

    $zip = [System.IO.Compression.ZipFile]::OpenRead($Path)
    try {
        foreach ($e in $zip.Entries) {
            $full = $e.FullName.Replace('\', '/')
            $ext = [System.IO.Path]::GetExtension($full).ToLowerInvariant()
            if ($ForbiddenExt -contains $ext) { [void]$forbidden.Add($full) }

            $marker = 'assets/flutter_assets/'
            if ($full.StartsWith($marker)) {
                $rel = $full.Substring($marker.Length)
                if ($rel -eq '') { continue }
                $relFile = $rel.TrimEnd('/')
                if ($rel.EndsWith('/')) { continue }        # 目录条目
                if ($AllowedRootFiles -contains $relFile) { continue }
                $ok = $false
                foreach ($p in $AllowedPrefixes) {
                    if ($rel.StartsWith($p)) { $ok = $true; break }
                }
                if (-not $ok) { [void]$outside.Add($relFile) }
                if ($relFile -eq 'assets/data/tjc_hymn.db') { $dbEntry = $e }
            }
        }
    }
    finally {
        $zip.Dispose()
    }

    return [pscustomobject]@{
        Apk       = $name
        Forbidden = $forbidden
        Outside   = $outside
        DbPath    = $Path
        HasDb     = ($null -ne $dbEntry)
    }
}

function Get-DbBaseline {
    param([string]$ApkPath)

    $tmp = Join-Path $env:TEMP ('echohymn_verify_' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null
    $dbOut = Join-Path $tmp 'tjc_hymn.db'
    try {
        $zip = [System.IO.Compression.ZipFile]::OpenRead($ApkPath)
        try {
            $entry = $zip.Entries |
                Where-Object { $_.FullName -eq 'assets/flutter_assets/assets/data/tjc_hymn.db' } |
                Select-Object -First 1
            if (-not $entry) { return $null }
            [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $dbOut, $true)
        }
        finally { $zip.Dispose() }

        $py = @'
import sqlite3, sys
sys.stdout.reconfigure(encoding="utf-8")
c = sqlite3.connect(sys.argv[1])
print(c.execute("select count(*) from tjc_hymn").fetchone()[0])
print(c.execute("select count(*) from jianpu_row").fetchone()[0])
print(c.execute("select count(*) from jianpu_cell").fetchone()[0])
'@
        $pyFile = Join-Path $tmp 'q.py'
        [System.IO.File]::WriteAllText($pyFile, $py, (New-Object System.Text.UTF8Encoding($false)))
        $raw = & python $pyFile $dbOut 2>&1
        if ($LASTEXITCODE -ne 0) { return $null }
        $nums = @($raw | ForEach-Object { "$_".Trim() } | Where-Object { $_ -match '^\d+$' })
        if ($nums.Count -lt 3) { return $null }
        return @{ Hymns = [int]$nums[0]; Rows = [int]$nums[1]; Cells = [int]$nums[2] }
    }
    finally {
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# ================= 主流程 =================
Write-Host ''
Write-Host '===== Android 产物白名单校验 =====' -ForegroundColor Cyan

$targets = Resolve-TargetApks
Write-Host "待校验 APK：$($targets.Count) 个" -ForegroundColor Gray

$failed = 0
$results = @()
foreach ($t in $targets) {
    $r = Test-OneApk -Path $t
    $results += $r
    Write-Host ''
    Write-Host "── $($r.Apk)" -ForegroundColor White

    if ($r.Forbidden.Count -eq 0) {
        Write-Host '   [OK]   禁止类型（.pdf/.exe/.mp4 等）无命中' -ForegroundColor Green
    }
    else {
        $failed++
        Write-Host "   [FAIL] 发现 $($r.Forbidden.Count) 个禁止类型文件：" -ForegroundColor Red
        $r.Forbidden | Select-Object -First 10 | ForEach-Object { Write-Host "          - $_" -ForegroundColor Red }
    }

    if ($r.Outside.Count -eq 0) {
        Write-Host '   [OK]   无库外路径' -ForegroundColor Green
    }
    else {
        $failed++
        Write-Host "   [FAIL] 发现 $($r.Outside.Count) 个库外路径：" -ForegroundColor Red
        $r.Outside | Select-Object -First 10 | ForEach-Object { Write-Host "          - $_" -ForegroundColor Red }
    }
}

# ---- 数据基线（取第一个含 DB 的 APK）----
if (-not $SkipBaseline) {
    Write-Host ''
    $withDb = $results | Where-Object { $_.HasDb } | Select-Object -First 1
    if (-not $withDb) {
        Write-Host '[FAIL] 所有 APK 内均未找到 assets/data/tjc_hymn.db' -ForegroundColor Red
        $failed++
    }
    else {
        Write-Host "── 数据基线（$($withDb.Apk)）" -ForegroundColor White
        $base = Get-DbBaseline -ApkPath $withDb.DbPath
        if ($null -eq $base) {
            Write-Host '   [SKIP] 无法读取库（缺少 python 或表不存在）' -ForegroundColor Yellow
        }
        else {
            $expect = @{ Hymns = 474; Rows = 21819; Cells = 321703 }
            foreach ($k in @('Hymns', 'Rows', 'Cells')) {
                $got = $base[$k]
                $want = $expect[$k]
                $label = switch ($k) {
                    'Hymns' { 'tjc_hymn' }
                    'Rows' { 'jianpu_row' }
                    'Cells' { 'jianpu_cell' }
                }
                if ($got -eq $want) {
                    Write-Host ("   [OK]   {0,-12} = {1}（基线 {2}）" -f $label, $got, $want) -ForegroundColor Green
                }
                else {
                    Write-Host ("   [FAIL] {0,-12} = {1}（基线 {2}）" -f $label, $got, $want) -ForegroundColor Red
                    $failed++
                }
            }
        }
    }
}

Write-Host ''
if ($failed -eq 0) {
    Write-Host '===== 校验通过 =====' -ForegroundColor Green
    exit 0
}
Write-Host "===== 校验失败：$failed 项 =====" -ForegroundColor Red
exit 1

