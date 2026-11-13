<#
.SYNOPSIS
    同步内置音频样本到 hymn_app\assets\media\（按构建变体裁剪）。

.DESCRIPTION
    素材方案（2026-11-13 用户定稿）：**按变体把对应音频全量打进 APK**，
    应用首启由 `MediaBootstrap` 同步迁移到私有目录（不再依赖外部导入）。

      - `-IncludeAll`：遍历 `data\Hymn_Downloads` 全部 474 首（全量）；
        不带则仍只复制 12 首样本（旧行为，调试用）。
      - 变体白名单：full = 鋼琴版 + 人聲版（**不含合唱类**）；
        piano = 鋼琴版 + `249` 人聲版（替代）；vocal = 人聲版 + `3`/`389` 四部合唱版
        + 9 首鋼琴版（替代）；lite = 无音频。四者均内置全部扫描图（`-SkipImages` 可关）。

    实测体积（全量）：full ≈2.52 GB / piano ≈1.68 GB / vocal ≈1.45 GB / lite ≈0.55 GB。

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
    [string]$Variant = 'full',

    # 全量内置（2026-11-13 用户定稿）：遍历 data\Hymn_Downloads 全部 474 首，
    # 按变体白名单把音频 + 扫描图全部打进 APK（安装后由 MediaBootstrap 迁移）。
    # 不带此开关时仍只复制 12 首样本（旧行为，保留给快速调试）。
    [switch]$IncludeAll,

    # 不内置扫描图（full 体积回退方案用；默认内置）
    [switch]$SkipImages
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

# 全量模式：遍历全部诗歌目录；否则只用 12 首样本
if ($IncludeAll) {
    $samples = @(Get-ChildItem -Path $srcRoot -Directory | Sort-Object Name | ForEach-Object { $_.Name })
    Write-Host "[*] 全量模式：$($samples.Count) 首诗歌目录" -ForegroundColor Cyan
}

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
    $files = Get-ChildItem -Path (Join-Path $dir '*') -File
    $audio = @($files | Where-Object { $_.Extension -in '.m4a', '.mp3' })
    $images = @($files | Where-Object { $_.Extension -in '.png', '.jpg' })

    # 音频白名单（2026-11-13 定稿：全量版 = **鋼琴版 + 人聲版**，不含合唱类；
    # 合唱仅保留 3/389 的四部合唱版，作为人声版的替代音源）
    $picked = @(switch ($Variant) {
        'lite' { @() }
        'piano' {
            @($audio | Where-Object { $_.Name -like '*鋼琴版*' -or $_.Name -like '249_人聲版*' })
        }
        'vocal' {
            $alts = @('103_', '107_', '178_', '255_', '268_', '274_b_', '308_', '386_', '387_')
            @($audio | Where-Object {
                    $n = $_.Name
                    if ($n -like '*人聲版*') { return $true }
                    if ($n -like '3_四部合唱版*' -or $n -like '389_四部合唱版*') { return $true }
                    if ($n -like '*鋼琴版*') {
                        foreach ($a in $alts) { if ($n.StartsWith($a)) { return $true } }
                    }
                    return $false
                })
        }
        default {
            @($audio | Where-Object { $_.Name -like '*鋼琴版*' -or $_.Name -like '*人聲版*' })
        }
    })
    # 扫描图（简谱 / 五线谱 PNG）：所有变体都内置（-SkipImages 可关闭）
    if (-not $SkipImages) { $picked += $images }

    foreach ($f in $picked) {
        $seq++
        $kind = if ($f.Name -like '*鋼琴版*') { 'piano' }
        elseif ($f.Name -like '*人聲版*') { 'vocal' }
        elseif ($f.Name -like '*合唱*') { 'choir' }
        elseif ($f.Name -like '*简谱*') { 'numbered' }
        else { 'staff' }
        $assetName = ('s{0:D4}_{1}{2}' -f $seq, $kind, $f.Extension)
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
    Write-Host '     lite 变体：**不含任何音频文件**，仅内置扫描图（无音频版 = 扫描图 + 数据库）' -ForegroundColor Yellow
}
