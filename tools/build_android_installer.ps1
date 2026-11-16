<#
.SYNOPSIS
    Android installer 产物（主体 APK + 三类数据包 × 两半）→ installer\output\android\

.DESCRIPTION
    2026-11-13 用户定稿：
      - **主体 APK**：只含程序 + 数据库（无素材），运行时按前十首检测切换 UI
      - **数据包**：扫描图 / 人声 / 钢琴，各拆成 0-237 与 238-474 两半（每个 <2GB）

    用法：
        pwsh -NoProfile -File tools\build_android_installer.ps1
        pwsh -NoProfile -File tools\build_android_installer.ps1 -SkipPacks   # 只打包 APK
        pwsh -NoProfile -File tools\build_android_installer.ps1 -Apk path\to\app-full-release.apk
#>
param(
    [string]$Apk = '',
    [switch]$SkipPacks
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$OutDir = Join-Path $Root 'installer\output\android'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

# ---- 1. 主体 APK ----
if (-not $Apk) {
    $Apk = Join-Path $Root 'hymn_app\build\app\outputs\flutter-apk\app-full-release.apk'
}
if (-not (Test-Path $Apk)) {
    throw "APK 不存在：$Apk（请先跑 tools\build_android_release.ps1 -Variant full）"
}
$pubspec = Get-Content (Join-Path $Root 'hymn_app\pubspec.yaml') -Encoding UTF8 |
    Select-String -Pattern '^version:\s*([0-9.]+)\+' | Select-Object -First 1
$ver = if ($pubspec) { $pubspec.Matches[0].Groups[1].Value } else { '0.0.0' }
$dstApk = Join-Path $OutDir "EchoHymn-v$ver.apk"
Copy-Item $Apk $dstApk -Force
Write-Host ("[OK] 主体 APK → {0}（{1} MB）" -f $dstApk, [math]::Round((Get-Item $dstApk).Length / 1MB, 1)) -ForegroundColor Green

# ---- 2. 数据包（三类 × 两半）----
if (-not $SkipPacks) {
    Write-Host '[*] 生成数据包（扫描图 / 人声 / 钢琴 × 前后两半）...' -ForegroundColor Cyan
    Push-Location $Root
    try {
        $env:PYTHONIOENCODING = 'utf-8'
        python (Join-Path $Root 'tools\build_android_media_packs.py') --out $OutDir
        if ($LASTEXITCODE -ne 0) { throw '数据包生成失败' }
    }
    finally { Pop-Location }
}

# ---- 3. SHA256SUMS（APK + 所有 zip）----
$sums = New-Object System.Collections.ArrayList
foreach ($f in (Get-ChildItem $OutDir -File | Where-Object { $_.Extension -in '.apk', '.zip' } | Sort-Object Name)) {
    [void]$sums.Add(('{0}  {1}' -f (Get-FileHash $f.FullName -Algorithm SHA256).Hash.ToLower(), $f.Name))
}
[System.IO.File]::WriteAllText(
    (Join-Path $OutDir 'SHA256SUMS.txt'),
    ("`r`n" -join $sums) + "`r`n",
    (New-Object System.Text.UTF8Encoding($true))
)

# ---- 4. BUILD-INFO ----
$info = @(
    'EchoHymn Android Installer 产物',
    '',
    "版本:    v$ver",
    "时间:    $(Get-Date -Format 'yyyyMMdd-HHmmss')",
    '结构:',
    '  EchoHymn-v<ver>.apk    主体（程序 + 数据库，无素材）',
    '  scores-0-237.zip       扫描图（简谱/五线谱 PNG）前半',
    '  scores-238-474.zip     扫描图 后半',
    '  vocal-0-237.zip        人声（含 3/389 四部合唱、9 首鋼琴替代）前半',
    '  vocal-238-474.zip      人声 后半',
    '  piano-0-237.zip        钢琴（含 249 人聲替代）前半',
    '  piano-238-474.zip      钢琴 后半',
    '',
    '安装顺序: 先装 APK → 打开应用 → 首启引导或「设置 → 数据导入」逐包导入。',
    '导入规则: 只接受符合 Hymn_Downloads/<目录>/<编号>_<类型>.<ext> 的文件，',
    '          规则外一律丢弃、不写入存储；同名文件直接覆盖。'
)
[System.IO.File]::WriteAllText((Join-Path $OutDir 'BUILD-INFO.txt'),
    ("`r`n" -join $info) + "`r`n", (New-Object System.Text.UTF8Encoding($true)))

Write-Host '==============================================' -ForegroundColor Green
Write-Host ("  Android installer 产物已生成：{0}" -f $OutDir) -ForegroundColor Green
Get-ChildItem $OutDir -File | Select-Object Name, @{n = 'MB'; e = { [math]::Round($_.Length / 1MB, 1) } } |
    Format-Table -AutoSize | Out-String | Write-Host
