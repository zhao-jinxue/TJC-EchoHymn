@echo off
chcp 65001 >nul
title EchoHymn - 安装 git post-commit 自动发布钩子
echo ============================================
echo   EchoHymn - git 钩子安装
echo   [功能] 每次 git commit 后自动构建+打包，
echo          发布到 release\ 并按版本保留最近 5 份
echo ============================================
echo.

cd /d "%~dp0"

if not exist "..\.git\hooks" (
    echo [错误] 未找到 .git\hooks 目录。
    echo 请确认在当前 Git 仓库内运行本脚本。
    pause
    exit /b 1
)

copy /Y "git-hooks\post-commit" "..\.git\hooks\post-commit" >nul
rem 确保 Git Bash 可执行（无扩展名 sh 脚本）
if exist "..\.git\hooks\post-commit.sample" del "..\.git\hooks\post-commit.sample" >nul 2>nul
if errorlevel 1 (
    echo [错误] 复制钩子失败。
    pause
    exit /b 1
)

echo [OK] post-commit 钩子已安装到 .git\hooks\
echo.
echo 说明:
echo   - 以后每次 git commit 成功后，会自动在后台执行
echo     tools\publish_release.ps1（构建 Web + 打包 + 保留5版）
echo   - 发布结果见 release\ 目录
echo   - 若想修改保留份数，编辑 tools\publish_release.ps1 顶部 KeepCount
echo.
echo 安装完成。
pause