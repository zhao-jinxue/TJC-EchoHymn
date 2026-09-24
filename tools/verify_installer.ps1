# ============================================================
# EchoHymn 安装包冒烟验证：静默装 → 启动程序 → 静默卸载 → 残留检查
#
# 目的：以确定性证据复现/验证「程序在运行时卸载 → 安装目录残留」类问题。
#   · 期望修复后行为：卸载器先结束运行中的实例，卸载后安装目录**完全消失**；
#   · -Baseline 传入「修复前」安装包时，脚本按 **EXPECT_RESIDUE** 判定（复现 bug）。
#
# 需管理员权限（安装包 PrivilegesRequired=admin；且要写 Program Files）。
# 用法（管理员 PowerShell）：
#   pwsh -NoProfile -ExecutionPolicy Bypass -File tools\verify_installer.ps1
#   pwsh ... -File tools\verify_installer.ps1 -Baseline .tmp_verify\EchoHymn_Setup_v1.8.0_prefix.exe
# 结果：控制台摘要 + installer\verify_<时间戳>.log（*.log 已被 .gitignore 排除）
# ============================================================
param(
    [string]$SetupDir = "E:\EchoHymn\installer\output",
    [string]$TargetDir = "D:\EchoHymn_SmokeTest\EchoHymn",
    [string]$Baseline = "",
    [int]$WaitAfterLaunchSec = 12
)
$ErrorActionPreference = "Stop"
. "C:\Users\小蔡爱金雪\.cline\scripts\Fix-Path.ps1"

$Root = "E:\EchoHymn"
$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $IsAdmin) { throw "本脚本需管理员权限：请从管理员 PowerShell 运行（或 Start-Process pwsh -Verb RunAs）" }

$Version = ((Get-Content (Join-Path $Root "hymn_app\pubspec.yaml") -Encoding UTF8 |
        Select-String -Pattern '^version:\s*([\d\.]+)').Matches[0].Groups[1].Value)
$SetupExe = Join-Path $SetupDir "EchoHymn_Setup_v$Version.exe"
$DataFile = Join-Path $SetupDir "EchoHymn_Data_v$Version.7z"
$Stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$LogFile = Join-Path $Root "installer\verify_$Stamp.log"

function Say([string]$msg) {
    Write-Host $msg
    Add-Content -Path $LogFile -Value $msg -Encoding UTF8
}

function Residue([string]$dir) {
    if (-not (Test-Path $dir)) { return @() }
    return @(Get-ChildItem $dir -Recurse -Force -ErrorAction SilentlyContinue |
        Select-Object -First 40 | ForEach-Object { $_.FullName.Substring($dir.Length) })
}

function Run-Phase([string]$name, [string]$setup, [string]$expect) {
    Say ""
    Say "================ $name（期望：$expect）================"
    $sw = [Diagnostics.Stopwatch]::StartNew()
    if (-not (Test-Path $setup)) { Say "[FAIL] 安装包不存在：$setup"; return $false }
    if (-not (Test-Path $DataFile)) { Say "[FAIL] 素材包不存在：$DataFile"; return $false }

    # 1) 静默安装（目标目录先清干净）
    if (Test-Path $TargetDir) { Remove-Item $TargetDir -Recurse -Force }
    $p = Start-Process -FilePath $setup -ArgumentList @(
        "/VERYSILENT", "/SUPPRESSMSGBOXES", "/NORESTART", "/DIR=`"$TargetDir`"",
        "/LOG=`"$env:TEMP\eh_setup_$Stamp.log`"") -Wait -PassThru
    Start-Sleep -Seconds 2
    $exe = Join-Path $TargetDir "echo_hymn.exe"
    $ins = (Test-Path $exe)
    Say "  安装退出码 = $($p.ExitCode)；echo_hymn.exe 存在 = $ins"
    if (-not $ins) { Say "[FAIL] 安装未完成"; return $false }

    # 2) 启动程序并保持运行（模拟用户正在使用 / 已最小化到托盘）
    $app = Start-Process -FilePath $exe -WorkingDirectory $TargetDir -PassThru
    Start-Sleep -Seconds $WaitAfterLaunchSec
    $running = @(Get-Process -Name echo_hymn -ErrorAction SilentlyContinue).Count
    Say "  启动后实例数 = $running（PID $($app.Id)）"
    if ($running -lt 1) { Say "[WARN] 程序未保持运行，本阶段对占用场景的验证力下降" }

    # 3) 程序运行中执行静默卸载
    $unins = Join-Path $TargetDir "unins000.exe"
    if (-not (Test-Path $unins)) { Say "[FAIL] 未找到卸载程序 $unins"; return $false }
    $up = Start-Process -FilePath $unins -ArgumentList @(
        "/VERYSILENT", "/SUPPRESSMSGBOXES", "/NORESTART",
        "/LOG=`"$env:TEMP\eh_unins_$Stamp.log`"") -Wait -PassThru
    Say "  卸载退出码 = $($up.ExitCode)"

    # 4) 复核：进程是否结束、程序文件是否清干净
    #    注意：静默卸载按设计**保留个人数据**（data\tjc_hymn.db / state.json / logs），
    #    因此「干净」的判据 = 无程序文件残留（而非目录整体消失）。
    $progFiles = @('echo_hymn.exe', 'unins000.exe', 'data\app.so', 'flutter_windows.dll', 'flutter_assets')
    $leftProcess = 0
    $still = @()
    $res = @()
    for ($i = 0; $i -lt 30; $i++) {
        $leftProcess = @(Get-Process -Name echo_hymn -ErrorAction SilentlyContinue).Count
        $still = @($progFiles | Where-Object { Test-Path (Join-Path $TargetDir $_) })
        if ($leftProcess -eq 0 -and $still.Count -eq 0) { break }
        Start-Sleep -Seconds 2
    }
    $sw.Stop()
    $res = @(Residue $TargetDir)
    Say "  卸载后实例数 = $leftProcess；安装目录存在 = $(Test-Path $TargetDir)"
    Say "  程序文件残留 = $(if ($still.Count -eq 0) { '无' } else { $still -join ', ' })"
    Say "  目录残留条目 = $($res.Count)（含按设计保留的个人数据 db/state.json/logs）"
    foreach ($r in $res) { Say "    残留: $r" }
    Say "  本阶段耗时 $([math]::Round($sw.Elapsed.TotalSeconds)) 秒"

    $clean = ($leftProcess -eq 0) -and ($still.Count -eq 0)
    $ok = if ($expect -eq 'CLEAN') { $clean } else { -not $clean }

    # 5) 收尾：结束残留进程 / 清理残留目录 / 删除测试产生的快捷方式
    if ($leftProcess -gt 0) { Stop-Process -Name echo_hymn -Force -ErrorAction SilentlyContinue; Start-Sleep -Seconds 2 }
    if (Test-Path $TargetDir) { Remove-Item $TargetDir -Recurse -Force }
    $grp = Join-Path $env:ProgramData "Microsoft\Windows\Start Menu\Programs\EchoHymn · 聆听赞美诗"
    if (Test-Path $grp) { Remove-Item $grp -Recurse -Force -ErrorAction SilentlyContinue }
    $lnk = Join-Path ([Environment]::GetFolderPath('CommonDesktopDirectory')) "EchoHymn · 聆听赞美诗.lnk"
    if (Test-Path $lnk) { Remove-Item $lnk -Force -ErrorAction SilentlyContinue }
    Say "  => $(if ($ok) { 'PASS' } else { 'FAIL' })（$name）"
    return $ok
}

Say "EchoHymn 安装包冒烟验证  $Stamp"
Say "  安装包: $SetupExe"
Say "  素材包: $DataFile（$([math]::Round((Get-Item $DataFile).Length / 1GB, 2)) GB）"
Say "  目标目录: $TargetDir"

$results = @()
if ($Baseline -and (Test-Path $Baseline)) {
    $baseCopy = Join-Path $SetupDir "EchoHymn_Setup_v${Version}_prefix.exe"
    Copy-Item $Baseline $baseCopy -Force
    Say "  基线（修复前）安装包已置于素材同目录: $baseCopy"
    $results += [pscustomobject]@{ Phase = 'A 修复前（复现 bug）'; Expect = 'RESIDUE'; Pass = (Run-Phase 'A 修复前' $baseCopy 'RESIDUE') }
}
elseif ($Baseline) {
    Say "  [WARN] 基线安装包不存在，跳过 A 阶段（仅验证修复后）：$Baseline"
}
$results += [pscustomobject]@{ Phase = 'B 修复后'; Expect = 'CLEAN'; Pass = (Run-Phase 'B 修复后' $SetupExe 'CLEAN') }

Say ""
Say "================ 验证摘要 ================"
$results | ForEach-Object { Say ("  {0,-22} 期望 {1,-8} {2}" -f $_.Phase, $_.Expect, $(if ($_.Pass) { 'PASS' } else { 'FAIL' })) }
Say "  日志: $LogFile"
if (($results | Where-Object { -not $_.Pass }).Count -gt 0) { exit 1 } else { exit 0 }
