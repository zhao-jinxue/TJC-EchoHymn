<#
.SYNOPSIS
    Android release 构建（**唯一推荐入口**）：先按变体同步素材，再构建，最后校验体积与签名。

.DESCRIPTION
    **为什么需要它**：`flutter build apk` **不会**同步 `hymn_app/assets/media/` ——
    如果上一次构建的是别的变体，打出的包就会出现「变体与内容不匹配」
    （实测：full 变体打成 63.5 MB，应为 ~81 MB；装到机器上还会有几十条
    `PathNotFoundException` 素材安装失败）。

    本脚本按正确顺序做三件事：

        1. tools\sync_audio_samples.ps1 -Variant <v>     ← 素材与变体对齐
        2. flutter build apk --release --flavor <v>      ← 构建（正式签名）
        3. 体积下限校验 + apksigner verify                ← 抓错配包与签名问题

    用法：

        pwsh -NoProfile -File tools\build_android_release.ps1 -Variant full
        pwsh -NoProfile -File tools\build_android_release.ps1 -Variant lite -SkipVerify

    体积下限（arm64 release，对齐 ANDROID_PLAN §1.4 与 B-2/B-3 实测）：
        full 70 / piano 66 / vocal 58 / lite 55 MB —— 低于下限即判"素材错配"。

.NOTES
    `tools\publish_android.ps1`（commit 自动发布）内部已按变体 sync，
    手动出包请一律用本脚本，不要直接 `flutter build apk`。
#>
param(
    [ValidateSet('full', 'piano', 'vocal', 'lite')]
    [string]$Variant = 'full',

    [string]$TargetPlatform = 'android-arm64',

    [switch]$SkipVerify
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$AppDir = Join-Path $Root 'hymn_app'
$env:PUB_CACHE = if ($env:PUB_CACHE) { $env:PUB_CACHE } elseif (Test-Path 'E:\pub-cache') { 'E:\pub-cache' } else { $env:PUB_CACHE }

# 各变体的体积下限（MB）：低于下限说明 assets/media 不是该变体的状态
$MinMb = @{ full = 70; piano = 66; vocal = 58; lite = 55 }

Write-Host "===== 构建 $Variant（$TargetPlatform）=====" -ForegroundColor Cyan

# ---- 1. 同步素材（治本：杜绝"变体与内容错配"）----
$sync = Join-Path $Root 'tools\sync_audio_samples.ps1'
Write-Host '[*] 同步素材 ...' -ForegroundColor Cyan
# 2026-11-13 用户定稿：release 构建只打**主体**（程序 + 数据库）；素材走 installer 数据包。
$syncArgs = @('-Variant', $Variant, '-Empty')
& pwsh -NoProfile -ExecutionPolicy Bypass -File $sync @syncArgs
if ($LASTEXITCODE -ne 0) { throw '素材同步失败，中止构建' }

# ---- 2. 构建 ----
# **必须彻底清理**（2026-10-28 实测教训）：仅删 intermediates 不够 ——
# 连续构建 4 个变体时，piano 的 APK 里出现了 vocal 素材（交叉污染），
# 因为 Flutter 的 flutter_assets 清单有独立缓存。唯一可靠做法是 flutter clean。
Write-Host '[*] flutter clean（保证素材不跨变体污染）...' -ForegroundColor DarkGray
Push-Location $AppDir
flutter clean 2>&1 | Out-Null
# Gradle 的 mergeReleaseAssets 也有独立缓存（flutter clean 清不到）——
# 2026-10-28 实测：piano 与 vocal 产出了**同一个包**（都是 vocal 素材），
# 必须在 android/ 下再跑一次 gradlew clean。
Push-Location (Join-Path $AppDir 'android')
if (Test-Path '.\gradlew.bat') { .\gradlew.bat clean 2>&1 | Out-Null }
Pop-Location
Pop-Location

# 关键：`flutter build` 的 asset bundle 有**增量缓存**，只同步目录内容不会让它失效
# （实测：full 与 lite 打出同样 63.52 MB，因为沿用了上一次的 flutter_assets）。
# touch pubspec.yaml 更新时间戳即可让 Flutter 重新打包 assets。
$pubspec = Join-Path $AppDir 'pubspec.yaml'
if (Test-Path $pubspec) {
    (Get-Item $pubspec).LastWriteTime = Get-Date
    Write-Host '[*] 已 touch pubspec.yaml（触发资源重新打包）' -ForegroundColor DarkGray
}
Write-Host '[*] flutter build apk --release ...' -ForegroundColor Cyan
Push-Location $AppDir
try {
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    flutter build apk --release --flavor $Variant --target-platform $TargetPlatform "--dart-define=AUDIO_VARIANT=$Variant" 2>&1 | Out-Host
    $code = $LASTEXITCODE
    $ErrorActionPreference = $prevEAP
}
finally { Pop-Location }
if ($code -ne 0) { throw "构建失败 (exit=$code)" }

# ---- 3. 校验体积 ----
$apk = Join-Path $AppDir "build\app\outputs\apk\$Variant\release\app-$Variant-release.apk"
if (-not (Test-Path $apk)) { throw "未找到产物 $apk" }
$mb = [math]::Round((Get-Item $apk).Length / 1MB, 2)
$min = $MinMb[$Variant]
Write-Host ("[*] 产物体积: {0} MB（下限 {1} MB）" -f $mb, $min) -ForegroundColor Cyan
if ($mb -lt $min) {
    Write-Host "[FAIL] 体积低于下限 —— 极可能是素材错配（assets/media 不是 $Variant 状态）" -ForegroundColor Red
    exit 1
}
Write-Host '[OK] 体积符合预期' -ForegroundColor Green

# ---- 4. 签名校验 ----
if (-not $SkipVerify) {
    $bt = (Get-ChildItem 'D:\Android\Sdk\build-tools' -Directory -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending | Select-Object -First 1)
    if ($bt) {
        $cert = & "$($bt.FullName)\apksigner.bat" verify --print-certs $apk 2>&1 |
            Select-String -Pattern 'DN:' | Select-Object -First 1
        Write-Host ("[*] 签名: " + ($cert.Line.Trim() -replace 'Signer #1 certificate ', '')) -ForegroundColor Cyan
        if ($cert.Line -match 'CN=Android Debug') {
            Write-Host '[WARN] 当前是 debug 签名（缺少 key.properties？）' -ForegroundColor Yellow
        }
    }
}

# **构建后立刻归档**（2026-10-28 实测教训）：每个变体构建前的 flutter/gradle clean 会清空 build/，
# 让前面变体的 APK 一起消失 → 先复制到独立目录再继续。
$distDir = Join-Path $Root 'release\android\builds'
New-Item -ItemType Directory -Force -Path $distDir | Out-Null
Copy-Item -Path $apk -Destination (Join-Path $distDir ("EchoHymn-$Variant-release.apk")) -Force
Write-Host ("[OK] 已归档 → release\android\builds\EchoHymn-$Variant-release.apk") -ForegroundColor Green

Write-Host "[OK] $Variant 构建完成: $apk（$mb MB）" -ForegroundColor Green
exit 0
