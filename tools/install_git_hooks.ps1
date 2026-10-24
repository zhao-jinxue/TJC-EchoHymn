<#
.SYNOPSIS
    安装 / 卸载仓库级 git 钩子（core.hooksPath = tools/git-hooks）。

.DESCRIPTION
    钩子随仓库入库（tools\git-hooks\post-commit），换机后执行本脚本即可生效：

        pwsh -NoProfile -ExecutionPolicy Bypass -File tools\install_git_hooks.ps1
        pwsh -NoProfile -ExecutionPolicy Bypass -File tools\install_git_hooks.ps1 -Uninstall

    同时把 post-commit 规范化为 LF 换行（sh 不接受 CRLF）与 UTF-8 无 BOM。

.NOTES
    2026-10-18 起：钩子从 .git\hooks（不入库）迁到 tools\git-hooks（入库），
    并改为调用 tools\publish_all.ps1（Windows + Android 双平台产物）。
#>
param([switch]$Uninstall)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)

if ($Uninstall) {
    & git -C $Root config --unset core.hooksPath 2>$null
    Write-Host '[OK] 已移除 core.hooksPath（回落到 .git/hooks）' -ForegroundColor Green
    exit 0
}

$hooksDir = Join-Path $Root 'tools\git-hooks'
if (-not (Test-Path $hooksDir)) { throw "缺少钩子目录 $hooksDir" }

& git -C $Root config core.hooksPath 'tools/git-hooks'
Write-Host '[OK] core.hooksPath = tools/git-hooks' -ForegroundColor Green

# post-commit 必须 LF + UTF-8(no BOM)，否则 Git Bash 的 sh 报错
$pc = Join-Path $hooksDir 'post-commit'
if (Test-Path $pc) {
    $text = [System.IO.File]::ReadAllText($pc).Replace("`r`n", "`n")
    [System.IO.File]::WriteAllText($pc, $text, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host '[OK] post-commit 已规范化为 LF / UTF-8(no BOM)' -ForegroundColor Green
}

$cur = & git -C $Root config --get core.hooksPath
Write-Host "当前 core.hooksPath = $cur" -ForegroundColor Cyan
Write-Host '钩子行为：commit 后后台产出 release\windows\ + release\android\ 双平台产物' -ForegroundColor Gray
