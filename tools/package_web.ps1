<#
.SYNOPSIS
    将 EchoHymn 的 Flutter Web 构建产物打包成一个版本化的绿色迁移包目录。

.DESCRIPTION
    脚本自动：
      1. 检测并拷贝 build\web 目录（若不存在则提示先构建）
      2. 生成 start_web.cmd / 开始使用.bat / 使用说明.txt
      3. 压成 zip 并输出到 release\<版本名>\ 目录

    -Version 参数：
      手动指定版本标识（如 "1.0.1"）。
      缺省时自动生成：echo-hymn 时间戳-短commitHash，例如：
        e26cb8c-20260814-214507 （短hash-日期-时间）

    输出目录结构（release 目录）：
      release\<版本名>\
        <版本名>.zip          # 绿色迁移包
#>

param(
  [string]$Version = ''
)

$ErrorActionPreference = 'Stop'

# ---- 路径定义 ----
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$WebDir = Join-Path $Root 'hymn_app\build\web'
$ReleaseDir = Join-Path $Root 'release'

function Write-OK($msg) { Write-Host "[OK] $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "[!!] $msg" -ForegroundColor Yellow }

# ---- 1. 生成版本名 ----
if ([string]::IsNullOrWhiteSpace($Version)) {
  # 自动版本：短commitHash-UTC日期-UTC时间
  $commit = & git -C $Root rev-parse --short HEAD 2>$null
  if (-not $commit) { $commit = 'nogit' }
  $ts = Get-Date -Format 'yyyyMMdd-HHmmss'
  $Version = "$commit-$ts"
}
# 清理非法字符
$Version = $Version -replace '[^0-9A-Za-z._-]', '-'
$PkgName = "echohymn-web-$Version"
Write-OK "版本标识: $Version"

# ---- 2. 校验构建产物 ----
if (-not (Test-Path (Join-Path $WebDir 'index.html'))) {
  Write-Warn "未找到 $WebDir\index.html"
  Write-Host "请先在 hymn_app 目录执行: flutter build web --release"
  exit 1
}
Write-OK "检测到 Web 构建产物: $WebDir"

# ---- 3. 准备 staging 目录 ----
$StageDir = Join-Path $env:TEMP $PkgName
if (Test-Path $StageDir) { Remove-Item $StageDir -Recurse -Force }
New-Item -ItemType Directory -Path $StageDir -Force | Out-Null

# 拷贝 web 产物
Copy-Item -Path (Join-Path $WebDir '*') -Destination $StageDir -Recurse -Force
Write-OK "已拷贝 web 产物"

# ---- 4. 生成启动/说明文件 ----
$startWeb = @'
@echo off
chcp 65001 >nul
title EchoHymn Web
echo ============================================
echo   EchoHymn - 赞美诗与颂歌 (Web 本地版)
echo ============================================
echo.

REM 切换到脚本所在目录
cd /d "%~dp0"

REM 寻找可用的 python
set "PYCMD="
where python >nul 2>nul && set "PYCMD=python"
if not defined PYCMD (
    where py >nul 2>nul && set "PYCMD=py -3"
)

if not defined PYCMD (
    echo [错误] 未找到 Python。
    echo 请安装 Python（https://www.python.org/）并勾选 "Add to PATH"，
    echo 或将本目录部署到任意静态服务器后访问。
    echo.
    explorer "%~dp0"
    pause
    exit /b 1
)

echo 使用命令: %PYCMD% -m http.server 8000
echo 浏览器即将打开: http://localhost:8000
echo 按 Ctrl+C 停止服务。
echo.
start "" "http://localhost:8000"
%PYCMD% -m http.server 8000
'@
Set-Content -Path (Join-Path $StageDir 'start_web.cmd') -Value $startWeb -Encoding Default

$startBat = @'
@echo off
chcp 65001 >nul
call "%~dp0start_web.cmd"
'@
Set-Content -Path (Join-Path $StageDir '开始使用.bat') -Value $startBat -Encoding Default

$readme = @"
==========================================
  EchoHymn - 赞美诗与颂歌
  Web 绿色版
  版本: $Version
  构建时间: $(Get-Date)
==========================================

【运行方法】
  双击「开始使用.bat」即可启动本地服务器并自动打开浏览器。

【要求：目标电脑需要 Python】
  本程序通过 Python 内置 http.server 提供本地服务。
  - 若未安装 Python：https://www.python.org/ 下载并勾选 Add to PATH。
  - 或将本目录部署到任意静态服务器后访问 index.html。

【常见问题】
  1. 双击闪退：说明未找到 python。
  2. 浏览器缓存旧版本：Ctrl+F5 强制刷新。
  3. 本包内置 CanvasKit 与中文字体，可离线打开；
     音频文件仍需联网加载。
==========================================
"@
Set-Content -Path (Join-Path $StageDir '使用说明.txt') -Value $readme -Encoding Default
Write-OK "已生成启动脚本与说明"

# ---- 5. 输出到 release\<版本名>\ ----
$PkgOutDir = Join-Path $ReleaseDir $PkgName
if (-not (Test-Path $ReleaseDir)) { New-Item -ItemType Directory -Path $ReleaseDir -Force | Out-Null }
if (Test-Path $PkgOutDir) { Remove-Item $PkgOutDir -Recurse -Force }
New-Item -ItemType Directory -Path $PkgOutDir -Force | Out-Null

$zipPath = Join-Path $PkgOutDir "$PkgName.zip"
Push-Location $env:TEMP
try {
  Compress-Archive -Path $PkgName -DestinationPath $zipPath -Force
}
finally {
  Pop-Location
}

# 顺带把 web 产物根目录的启动说明也放一份到版本目录（便于直接浏览产物）
Copy-Item -Path (Join-Path $StageDir '使用说明.txt') -Destination $PkgOutDir -Force

Remove-Item $StageDir -Recurse -Force -ErrorAction SilentlyContinue

Write-OK "迁移包已生成: $zipPath"

# 输出版本名，供上层脚本使用
Write-Host "RELEASE_NAME=$PkgName"