<#
.SYNOPSIS
    将 EchoHymn 的 Flutter Web 构建产物打包成可直接拷贝到其他设备的绿色迁移包。

.DESCRIPTION
    脚本会自动：
      1. 检测并拷贝 build\web 目录（若不存在则提示先构建）
      2. 生成 start_web.cmd 启动脚本（自动寻找可用的 python / py，启动本地服务器）
      3. 生成 开始使用.bat（双击即启动）
      4. 压缩为 echo_hymn_web_<版本>.zip

    目标机无需安装 Flutter / Python / Node，只需：
      - 方式 A：拥有任意 python（推荐，python 或 py 命令）
      - 方式 B：将 build\web 目录部署到任意静态服务器（如 nginx）后访问
#>

$ErrorActionPreference = 'Stop'

# ---- 路径定义 ----
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$WebDir = Join-Path $Root 'hymn_app\build\web'
$OutDir = Join-Path $Root 'release'
$Version = '1.0.0'
$PkgName = "echohymn-web-${Version}"

function Write-Step($msg) { Write-Host "[*] $msg" -ForegroundColor Cyan }
function Write-OK($msg) { Write-Host "[✔] $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "[!] $msg" -ForegroundColor Yellow }

# ---- 1. 校验构建产物 ----
if (-not (Test-Path (Join-Path $WebDir 'index.html'))) {
    Write-Warn "未找到 $WebDir\index.html"
    Write-Host "请先在 hymn_app 目录执行: flutter build web --release" -ForegroundColor Yellow
    exit 1
}
Write-OK "检测到 Web 构建产物: $WebDir"

# ---- 2. 准备打包目录 ----
$StageDir = Join-Path $env:TEMP $PkgName
if (Test-Path $StageDir) { Remove-Item $StageDir -Recurse -Force }
New-Item -ItemType Directory -Path $StageDir -Force | Out-Null

# ---- 3. 拷贝 web 产物到打包目录 ----
Copy-Item -Path (Join-Path $WebDir '*') -Destination $StageDir -Recurse -Force
Write-OK "已拷贝 web 产物"

# ---- 4. 生成 start_web.cmd ----
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
    echo 正在打开本目录（可手动部署到服务器）...
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
Write-OK "已生成 start_web.cmd"

# ---- 5. 生成 开始使用.bat ----
$startBat = @'
@echo off
chcp 65001 >nul
call "%~dp0start_web.cmd"
'@
Set-Content -Path (Join-Path $StageDir '开始使用.bat') -Value $startBat -Encoding Default
Write-OK "已生成 开始使用.bat"

# ---- 6. 生成使用说明 ----
$readme = @"
==========================================
  EchoHymn - 赞美诗与颂歌
  Web 绿色版 v$Version
==========================================

【运行方法】
  双击「开始使用.bat」即可启动本地服务器并自动打开浏览器。

【要求：目标电脑需要 Python】
  本程序通过 Python 内置 http.server 提供本地服务。
  - 若电脑尚未安装 Python：
    请到 https://www.python.org/ 下载安装，
    安装时务必勾选 "Add python.exe to PATH"。
  - 或者，你可以将本目录（web）部署到任意静态服务器
    （如 nginx、IIS、宝塔等）后访问 index.html。

【常见问题】
  1. 双击后闪退：说明未找到 python，请先安装 Python。
  2. 某些浏览器缓存旧版本：按 Ctrl+F5 强制刷新。
  3. 支持离线使用：本包已内置 CanvasKit 与中文字体，
     无需联网即可打开（歌谱音频仍需联网加载）。
==========================================
"@
Set-Content -Path (Join-Path $StageDir '使用说明.txt') -Value $readme -Encoding Default
Write-OK "已生成 使用说明.txt"

# ---- 7. 压成 zip ----
if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir -Force | Out-Null }
$zipPath = Join-Path $OutDir "$PkgName.zip"
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }

Push-Location $env:TEMP
try {
    Compress-Archive -Path $PkgName -DestinationPath $zipPath -Force
}
finally {
    Pop-Location
}
Write-OK "已生成迁移包: $zipPath"

# 清理临时目录
Remove-Item $StageDir -Recurse -Force

Write-Host ""
Write-Host "打包完成！迁移方法：" -ForegroundColor Green
Write-Host "  1. 将 $zipPath 拷贝到目标 Windows 电脑" -ForegroundColor Green
Write-Host "  2. 解压后双击「开始使用.bat」即可使用（需装 Python）" -ForegroundColor Green
Write-Host ""