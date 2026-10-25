<#
.SYNOPSIS
    设计令牌一致性抽查（ANDROID_PLAN §3.0.1 令牌表 vs 代码常量）。

.DESCRIPTION
    五态 / 令牌 / 间距这类"规范"最容易在实现中悄悄漂移。本脚本做**静态抽查**：
    把令牌表里的关键值（顶栏 56/48、合并行 44、播放条 72/64、断点 600、chip 26 …）
    与代码中的实际常量逐条比对，输出 OK / WARN / FAIL。

    用法：

        pwsh -NoProfile -File tools\check_design_tokens.ps1

    退出码：0 = 无 FAIL（WARN 允许，通常是"为触控优先而放宽"的有意偏差）；1 = 有 FAIL。

.NOTES
    这是**抽查**不是全量校验：令牌表里还有颜色/圆角/动效曲线等无法静态比对，
    需靠实机走查（M3 出口的确认单逐条）。
#>
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$lib = Join-Path $Root 'hymn_app\lib'

$fail = 0
$warn = 0

function Get-Code($file) {
    $p = Join-Path $lib $file
    if (-not (Test-Path $p)) { return $null }
    return Get-Content $p -Raw -Encoding utf8
}

# ---- 强一致项：缺失即 FAIL（令牌值必须出现在代码里）----
function Check-Contains($label, $file, $needle, $tokenDesc) {
    $code = Get-Code $file
    if ($null -eq $code) {
        Write-Host "[SKIP] $label —— 文件缺失（$file）" -ForegroundColor DarkGray
        return
    }
    if ($code.Contains($needle)) {
        Write-Host ("[OK]   {0,-22} = {1}" -f $label, $tokenDesc) -ForegroundColor Green
    }
    else {
        Write-Host ("[FAIL] {0,-22} 未找到 `"{1}`"（令牌 {2}；文件 {3}）" -f $label, $needle, $tokenDesc, $file) -ForegroundColor Red
        $script:fail++
    }
}

# ---- 数值项：与令牌逐个比对（不等则 WARN，需人工判定是否有意偏差）----
function Check-Number($label, $file, $pattern, $expect, $reason) {
    $code = Get-Code $file
    if ($null -eq $code) {
        Write-Host "[SKIP] $label —— 文件缺失（$file）" -ForegroundColor DarkGray
        return
    }
    $m = [regex]::Match($code, $pattern)
    if (-not $m.Success) {
        Write-Host "[FAIL] $label —— 未匹配 /$pattern/（$file）" -ForegroundColor Red
        $script:fail++
        return
    }
    $actual = $m.Groups[1].Value
    if ("$actual" -eq "$expect") {
        Write-Host ("[OK]   {0,-22} = {1}" -f $label, $actual) -ForegroundColor Green
    }
    else {
        Write-Host ("[WARN] {0,-22} = {1}（令牌 {2}）→ {3}" -f $label, $actual, $expect, $reason) -ForegroundColor Yellow
        $script:warn++
    }
}

Write-Host ''
Write-Host '===== 设计令牌一致性抽查（§3.0.1）=====' -ForegroundColor Cyan
Write-Host ''

# 断点（§3.0.6：<600 手机 / 600~839 横屏双栏 / ≥840 平板）
Check-Number '断点 kMobileBreakpoint' 'screens\home_screen.dart' 'kMobileBreakpoint = (\d+)' '600' '手机阈值'
Check-Number '横屏左栏 kLandscapeLeftWidth' 'screens\home_screen.dart' 'kLandscapeLeftWidth = (\d+)' '260' '§3.0.6 左栏常驻'

# bar.top：竖屏 56 / 横屏 48
Check-Contains 'bar.top 竖屏/横屏' 'screens\home_screen.dart' 'isLandscape ? 48 : 56' '56 / 48'

# bar.combined 44
Check-Contains 'bar.combined' 'widgets\hymn_display.dart' 'height: 44,' '44'

# bar.play 横屏 64（竖屏目标 72 由 padding 组合，非固定 height）
Check-Contains 'bar.play 横屏' 'widgets\hymn_display.dart' 'height: 64,' '64'

# chip.height 26（§3.0.1）—— 实现为 32：触控更友好，属有意偏差
Check-Number 'chip.height' 'screens\settings_page.dart' 'height: (\d+),\s*\r?\n\s*padding: const EdgeInsets.symmetric\(horizontal: 14\)' '26' '实现 32（触控优先，属有意偏差）'

# page.padding 16 —— 搜索页 / 设置页等新页面严格用 16
Check-Contains 'page.padding（新页面）' 'screens\search_page.dart' 'symmetric(horizontal: 16)' '16'

# 简谱网格 padX 18：**Windows 排版基线**（jianpu_golden_test 快照依赖），
# 与令牌 16 差 2dp 属有意偏差 —— 只在无快照依赖的新页面上用 16。
Check-Number '简谱网格 padX' 'widgets\jianpu_grid_view.dart' 'static const double padX = (\d+)' '16' '实现 18：Windows 排版基线（golden 快照依赖），有意偏差'

# 深色谱面遮罩 20%（§3.10 令牌 image.dim）
Check-Number 'image.dim（深色遮罩）' 'theme\score_display_prefs.dart' 'dimAlpha = ([0-9.]+)' '0.20' '§3.10 定稿 20%'

# 缩放包络 maxScale 3.0（§3.11）
Check-Number 'maxScale（§3.11）' 'widgets\hymn_display.dart' '_maxScale = ([0-9.]+)' '3.0' '缩放上限 3.0×'

# 字号四档（§3.3）
Check-Contains '字号四档' 'theme\app_fonts.dart' "xlarge('xlarge'" 'normal/medium/large/xlarge'

Write-Host ''
Write-Host '----------------------------------------------' -ForegroundColor Cyan
Write-Host "  FAIL: $fail    WARN: $warn" -ForegroundColor $(if ($fail -gt 0) { 'Red' } elseif ($warn -gt 0) { 'Yellow' } else { 'Green' })
Write-Host '  WARN 通常是"为触控/可读性有意放宽"，需人工确认后保留或修正' -ForegroundColor Gray
Write-Host '----------------------------------------------' -ForegroundColor Cyan

if ($fail -gt 0) { exit 1 }
exit 0
