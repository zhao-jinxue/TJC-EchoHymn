<#
.SYNOPSIS
    Android 设备布局走查：多尺寸（dp）× 字号档位（标准/大/特大）批量验证。

.DESCRIPTION
    对应发布前清单（ANDROID_PLAN §7.4）中「多尺寸 × 四档字号走查」条目。
    纯 adb 驱动，不改代码、不重装应用（安装由调用方先用 adb install 完成）。

    每个组合执行：
      1. `wm size` / `wm density` 切换视口（dp = 像素 / density * 160）
      2. force-stop → 写 state.json（预设字号 + 关闭首启手册）→ 启动
      3. 截图 + 采集 `RenderFlex overflowed`（logcat）与「布局模式切换」（应用日志）

    前置：设备已 root（`adb root`），因为要直接写 `/data/data/<pkg>/files/state.json`。

    用法：

        adb root
        pwsh -NoProfile -File tools\verify_android_device.ps1
        pwsh -NoProfile -File tools\verify_android_device.ps1 -Package com.echohymn.app.lite -Name lite

    结束后自动 `wm size reset` / `wm density reset` 还原设备。

.NOTES
    退出码：0 = 全部组合无 overflow；1 = 至少一个组合出现溢出。
    截图与汇总写入 `release/android/device-verify/<Name>-<时间戳>/`。
#>
param(
    [string]$Package = 'com.echohymn.app',
    [string]$Activity = '.MainActivity',
    [string]$Name = 'full',
    [int]$WaitSeconds = 9,
    [string[]]$Only = @(),
    [switch]$SkipScreenshots
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)

# ---- 视口矩阵：宽×高（dp）← 像素 / density 换算 ----
$Viewports = @(
    @{ Label = '360x800';  Size = '720x1600';  Density = 320 },  # 小屏手机
    @{ Label = '411x914';  Size = '1080x2400'; Density = 420 },  # Pixel 7 基准
    @{ Label = '480x1067'; Size = '1440x3200'; Density = 480 },  # 大屏手机
    @{ Label = '320x640';  Size = '640x1280';  Density = 320 },  # §7.4 要求的最小断点
    @{ Label = '914x411';  Size = '2400x1080'; Density = 420 }   # 横屏双栏
)

# 移动端三档字号（FontSizeLevel.id；xlarge 手机不显示）
$FontLevels = @('normal', 'medium', 'large')

if (-not (Get-Command adb -ErrorAction SilentlyContinue)) { throw 'adb 不在 PATH 中' }
$devices = @(adb devices | Select-String 'device$')
if ($devices.Count -eq 0) { throw '没有可用设备（先启动模拟器或连接真机）' }

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$outDir = Join-Path $Root "release\android\device-verify\$Name-$stamp"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

function Get-AppUid {
    $uid = (adb shell stat -c %u "/data/data/$Package" 2>$null | Out-String).Trim()
    if ($uid -notmatch '^\d+$') { throw "无法获取 $Package 的 uid（是否已安装？是否 adb root？）" }
    return $uid
}

function Set-DeviceState([string]$fontLevel) {
    $json = @{
        leftTab = ''; subcategory = ''; playlistName = ''
        hymnNumber = '1'; audioVersion = ''; displayMode = 'lyrics'
        playlistIndex = 0; showLeft = $false; showRight = $false
        appTheme = 'morningBlue'; fontSizeLevel = $fontLevel
        scoreDarkMode = 'dim'; manualOnStart = $false
        lyricAutoMode = $false; closeAction = 'exit'
    } | ConvertTo-Json -Compress
    $local = Join-Path $outDir 'state.json'
    [System.IO.File]::WriteAllText($local, $json, (New-Object System.Text.UTF8Encoding($false)))
    adb push $local /data/local/tmp/state.json 2>&1 | Out-Null
    adb shell cp /data/local/tmp/state.json "/data/data/$Package/files/state.json" 2>&1 | Out-Null
    adb shell chown "${script:uid}:${script:uid}" "/data/data/$Package/files/state.json" 2>&1 | Out-Null
}

function Get-LayoutLine {
    $log = Join-Path $outDir 'app.log'
    $today = Get-Date -Format 'yyyy-MM-dd'
    adb pull "/data/data/$Package/files/logs/app_$today.log" $log 2>&1 | Out-Null
    if (-not (Test-Path $log)) { return '' }
    $lines = Get-Content $log -Encoding UTF8
    for ($i = $lines.Count - 1; $i -ge 0; $i--) {
        if ($lines[$i] -match '布局模式切换') {
            $detail = if ($i + 1 -lt $lines.Count) { $lines[$i + 1].Trim() } else { '' }
            return "$($lines[$i].Trim()) $detail"
        }
    }
    return ''
}

$script:uid = Get-AppUid
Write-Host "===== 布局走查：$Package（uid=$script:uid）=====" -ForegroundColor Cyan
Write-Host "输出目录：$outDir" -ForegroundColor Gray
Write-Host '不要在中途改动设备窗口；结束后自动还原。' -ForegroundColor DarkGray

$results = New-Object System.Collections.ArrayList
try {
    # -Only 可只跑指定视口（如 `-Only 914x411`），便于针对性复测
    $selected = if ($Only.Count -gt 0) {
        $Viewports | Where-Object { $Only -contains $_.Label }
    }
    else { $Viewports }
    foreach ($vp in $selected) {
        foreach ($font in $FontLevels) {
            adb shell wm size $vp.Size | Out-Null
            adb shell wm density $vp.Density | Out-Null
            adb shell am force-stop $Package | Out-Null
            Set-DeviceState -fontLevel $font
            adb logcat -c | Out-Null
            adb shell am start -n "$Package/$Activity" | Out-Null
            Start-Sleep -Seconds $WaitSeconds

            $alive = (adb shell pidof $Package | Out-String).Trim()
            $overflow = @(adb logcat -d 2>&1 | Select-String 'A RenderFlex overflowed')
            $layout = Get-LayoutLine

            $shot = ''
            if (-not $SkipScreenshots) {
                $shot = Join-Path $outDir ("{0}_{1}.png" -f $vp.Label, $font)
                adb shell screencap -p /sdcard/_verify.png | Out-Null
                adb pull /sdcard/_verify.png $shot 2>&1 | Out-Null
            }

            [void]$results.Add([pscustomobject]@{
                    Viewport = $vp.Label
                    Font     = $font
                    Alive    = [bool]$alive
                    Overflow = $overflow.Count
                    Layout   = $layout
                    Shot     = if ($shot) { Split-Path -Leaf $shot } else { '' }
                })

            $color = if ($alive -and $overflow.Count -eq 0) { 'Green' } else { 'Red' }
            $tail = if ($layout.Length -gt 40) { $layout.Substring($layout.Length - 40) } else { $layout }
            Write-Host ("[{0,-9}] {1,-7} pid={2,-6} overflow={3}  {4}" -f $vp.Label, $font, ($alive -replace '\s', ''), $overflow.Count, $tail) -ForegroundColor $color
        }
    }
}
finally {
    adb shell wm size reset | Out-Null
    adb shell wm density reset | Out-Null
    Write-Host '[*] 已还原 wm size / wm density' -ForegroundColor DarkGray

    $csv = Join-Path $outDir 'summary.csv'
    $results | Export-Csv -Path $csv -Encoding UTF8
    Write-Host "[OK] 汇总：$csv" -ForegroundColor Cyan
}

$failed = @($results | Where-Object { -not $_.Alive -or $_.Overflow -gt 0 })
Write-Host ''
if ($failed.Count -eq 0) {
    Write-Host ("===== 走查通过：{0} 个组合全部无溢出 =====" -f $results.Count) -ForegroundColor Green
    exit 0
}
Write-Host ("===== 走查失败：{0}/{1} 个组合异常 =====" -f $failed.Count, $results.Count) -ForegroundColor Red
$failed | Format-Table Viewport, Font, Alive, Overflow -AutoSize | Out-String | Write-Host
exit 1
