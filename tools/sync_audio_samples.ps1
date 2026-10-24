<#
.SYNOPSIS
    同步内置音频样本到 hymn_app\assets\media\（按构建变体裁剪）。

.DESCRIPTION
    阶段 B 素材方案（ANDROID_PLAN §7.5 定稿）：**样本内置（10~20 首）+ 外部导入（SAF）**。
    本脚本从仓库单一数据源 `data\Hymn_Downloads\` 挑固定 12 首样本，扁平复制到
    `hymn_app\assets\media\`，并生成 `index.json`（asset 文件名 → DB 内相对路径）。

    变体口径（与 ANDROID_PLAN B3 验收一致）：

        full   钢琴 + 人声（样本全集）
        piano  仅 *_鋼琴版.m4a
        vocal  仅 *_人聲版.mp3
        lite   **不复制任何音频**（index.json 为空数组，包内无音频文件）

    用法：

        pwsh -NoProfile -ExecutionPolicy Bypass -File tools\sync_audio_samples.ps1 -Variant full
        pwsh -NoProfile -ExecutionPolicy Bypass -File tools\sync_audio_samples.ps1 -Variant lite

    `tools\publish_android.ps1` 已按变体自动调用；手动 `flutter build apk` 前请自己跑一次。

.NOTES
    产物在 `hymn_app\assets\media\` 下，**不入库**（`.gitignore` 忽略），可随时重建。
    移动端首启由 `lib/services/media_bootstrap.dart` 依据 index.json 还原为
    `files/Hymn_Downloads/<原名>/<原文件名>` —— 中文目录名与文件名全程保留（路径复测点）。
#>
param(
    [ValidateSet('full', 'piano', 'vocal', 'lite')]
    [string]$Variant = 'full'
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$srcRoot = Join-Path $Root 'data\Hymn_Downloads'
$dstDir = Join-Path $Root 'hymn_app\assets\media'

# 固定样本集（12 首）：覆盖首曲 / 编号跳跃 / `_b` 特殊命名 / 单版本曲目
$samples = @(
    '001_1頌讚獨一真神',
    '002_2讚美聖父',
    '009_9向主歡呼',
    '010_10榮耀歸耶穌',
    '026_26求主向我發言',
    '052_51_b萬古靈磐乙',
    '103_102為主而活',
    '114_113奉獻會堂',
    '121_120奉獻所有',
    '177_174真教會必興起',
    '391_386我得一友',
    '392_387求主對我述說'
)

if (-not (Test-Path $srcRoot)) { throw "缺少素材源目录 $srcRoot" }

# 清空输出目录（保留目录本身，避免 pubspec 声明失效）
if (Test-Path $dstDir) {
    Get-ChildItem -Path $dstDir -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
}
else {
    New-Item -ItemType Directory -Path $dstDir -Force | Out-Null
}

$index = New-Object System.Collections.ArrayList
$seq = 0
$totalBytes = 0

foreach ($s in $samples) {
    $dir = Join-Path $srcRoot $s
    if (-not (Test-Path $dir)) {
        Write-Warning "样本目录不存在，跳过: $s"
        continue
    }
    $files = Get-ChildItem -Path (Join-Path $dir '*') -File |
        Where-Object { $_.Extension -in '.m4a', '.mp3' }

    $picked = switch ($Variant) {
        'lite' { @() }
        'piano' { @($files | Where-Object { $_.Name -like '*鋼琴版*' }) }
        'vocal' { @($files | Where-Object { $_.Name -like '*人聲版*' }) }
        default { @($files) }
    }

    foreach ($f in $picked) {
        $seq++
        $kind = if ($f.Name -like '*鋼琴版*') { 'piano' } else { 'vocal' }
        $assetName = ('s{0:D3}_{1}{2}' -f $seq, $kind, $f.Extension)
        Copy-Item -Path $f.FullName -Destination (Join-Path $dstDir $assetName) -Force
        [void]$index.Add([pscustomobject]@{
                asset  = $assetName
                target = "Hymn_Downloads/$s/$($f.Name)"
                kind   = $kind
                bytes  = $f.Length
            })
        $totalBytes += $f.Length
    }
}

# index.json：必须为 UTF-8 **无 BOM**（Dart jsonDecode 遇 BOM 会失败）
$jsonText = if ($index.Count -eq 0) { '[]' } else { ConvertTo-Json -InputObject @($index) -Depth 4 }
[System.IO.File]::WriteAllText((Join-Path $dstDir 'index.json'), $jsonText, (New-Object System.Text.UTF8Encoding($false)))

$mb = [math]::Round($totalBytes / 1MB, 2)
Write-Host ("[OK] 样本同步完成：变体={0} 文件={1} 体积={2} MB → hymn_app\assets\media" -f $Variant, $index.Count, $mb) -ForegroundColor Green
if ($Variant -eq 'lite') {
    Write-Host '     lite 变体：index.json 为空数组，APK 内不含任何音频文件（B3 验收口径）' -ForegroundColor Yellow
}
