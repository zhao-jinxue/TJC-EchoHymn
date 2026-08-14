@echo off
chcp 65001 >nul
title EchoHymn - 一键打包 Web 迁移包
echo ============================================
echo   EchoHymn - 一键打包 Web 绿色迁移包
echo ============================================
echo.

cd /d "%~dp0"

REM 优先使用 PowerShell 7（pwsh），其次是 Windows PowerShell
set "PS=pwsh"
where pwsh >nul 2>nul || set "PS=powershell"

echo 正在打包（可能需要十几秒，压缩 Web 产物）...
echo.

%PS% -NoProfile -ExecutionPolicy Bypass -File "%~dp0package_web.ps1"

echo.
echo 打包脚本执行完毕。
echo 迁移包位置：E:\EchoHymn\release\echohymn-web-1.0.0.zip
echo.
pause