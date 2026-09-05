# ============================================================
# EchoHymn 安装包构建脚本
# 流程: 取版本(pubspec) -> 定位 release -> 下载中文语言(缺则) ->
#       staging 组装 -> AES 加密 7z 载荷 -> ISCC 编译 -> SHA256
# 用法: pwsh -File tools/build_installer.ps1 [-ReleaseDir <目录名>] [-SkipPayload]
# ============================================================
param(
    [string]$ReleaseDir = "",
    [switch]$SkipStaging = $false,
    [switch]$SkipPayload = $false
)
$ErrorActionPreference = "Stop"
. "C:\Users\小蔡爱金雪\.cline\scripts\Fix-Path.ps1"

$Root    = "E:\EchoHymn"
$InstDir = Join-Path $Root "installer"
$OutDir  = Join-Path $InstDir "output"
$Stage   = Join-Path $InstDir "staging"
$StageData = Join-Path $InstDir "staging_data"
$Payload = Join-Path $InstDir "payload.7z"
$IslFile = Join-Path $InstDir "ChineseSimplified.isl"
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

# 1) 应用版本号：读 hymn_app/pubspec.yaml 的 version（去掉 +build 后缀）
$Pubspec = Get-Content (Join-Path $Root "hymn_app\pubspec.yaml") -Encoding UTF8
$AppVersion = ($Pubspec | Select-String -Pattern '^version:\s*([\d\.]+)' | Select-Object -First 1).Matches[0].Groups[1].Value
if (-not $AppVersion) { throw "无法从 pubspec.yaml 解析版本号" }
Write-Host "应用版本: $AppVersion"

# 2) 定位 release 包（默认取最新一个）
if (-not $ReleaseDir) {
    $ReleaseDir = (Get-ChildItem (Join-Path $Root "release") -Directory -Filter "echohymn_win_*" |
        Sort-Object Name -Descending | Select-Object -First 1).Name
}
$RelPath = Join-Path $Root "release\$ReleaseDir"
if (-not (Test-Path $RelPath)) { throw "release 目录不存在: $RelPath" }
Write-Host "载荷来源: $RelPath"

# 3) 简体中文语言文件（仓库内已固化官方 6.5.0+ 简体中文 isl，维护者 Zhenghan Yang/Kira；
#    正常构建不会走到下载分支。旧离线生成器 make_chinese_isl.py 因产生半翻译混合体已删除）
if (-not (Test-Path $IslFile)) {
    Write-Host "下载 ChineseSimplified.isl ..."
    $rawUrl = "https://raw.githubusercontent.com/jrsoftware/issrc/refs/heads/main/Files/Languages/ChineseSimplified.isl"
    $urls = @("https://gh-proxy.com/$rawUrl", $rawUrl)
    $ok = $false
    foreach ($u in $urls) {
        try { curl.exe -sSL --connect-timeout 15 -o $IslFile $u; if ((Test-Path $IslFile) -and ((Get-Item $IslFile).Length -gt 20KB)) { $ok = $true; break } } catch {}
    }
    if (-not $ok) { throw "中文语言文件获取失败——请手动放置 $IslFile（官方源: https://jrsoftware.org/files/istrans/）后重试" }
    # 官方源无 BOM，ISCC 要求非 ASCII 语言文件带 UTF-8 BOM
    $islBytes = [System.IO.File]::ReadAllBytes($IslFile)
    if ($islBytes[0] -ne 0xEF) { [System.IO.File]::WriteAllBytes($IslFile, ([byte[]](0xEF,0xBB,0xBF) + $islBytes)) }
}

# 3.5) 安装程序图标（取应用 exe 同源图标）
$AppIco = Join-Path $Root "hymn_app\windows\runner\resources\app_icon.ico"
if (-not (Test-Path $AppIco)) { throw "应用图标不存在: $AppIco" }
Copy-Item $AppIco (Join-Path $InstDir "app_icon.ico") -Force

# 数据文件名带版本号，与安装包同级分发（安装向导按此名在 {src} 目录检测）
$DataName = "EchoHymn_Data_v$AppVersion.7z"
$DataArc  = Join-Path $InstDir $DataName

# 4) staging 组装（主程序区 + 素材区双拆分；-SkipStaging 复用现有暂存区）
if (-not $SkipStaging) {
    python (Join-Path $InstDir "prepare_staging.py") $RelPath $Stage $StageData
    if ($LASTEXITCODE -ne 0) { throw "staging 组装失败" }
} elseif (-not (Test-Path $Stage) -or -not (Test-Path $StageData)) {
    throw "-SkipStaging 但 staging/staging_data 不存在"
}

# 5) AES-256 加密 7z 双载荷（-SkipPayload 可跳过重打包）
#    主载荷内嵌安装包（数十 MB）；素材载荷外置单独分发（约 3 GB，不入包）
if (-not $SkipPayload) {
    python (Join-Path $InstDir "make_payload.py") $Stage $Payload
    if ($LASTEXITCODE -ne 0) { throw "主载荷打包失败" }
    python (Join-Path $InstDir "make_payload.py") $StageData $DataArc
    if ($LASTEXITCODE -ne 0) { throw "素材载荷打包失败" }
    Remove-Item $Stage,$StageData -Recurse -Force   # 载荷已生成，暂存区即删防污染
}

# 6) 编译安装程序（ISCC；iss 需 UTF-8 BOM 以正确显示中文）
$Iscc = @(
    "C:\Program Files (x86)\Inno Setup 6\ISCC.exe",
    "C:\Program Files\Inno Setup 6\ISCC.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $Iscc) { throw "未找到 ISCC.exe——请先安装 Inno Setup 6" }

$IssFile = Join-Path $InstDir "echohymn.iss"
$issText = Get-Content $IssFile -Raw -Encoding UTF8
[System.IO.File]::WriteAllText($IssFile, $issText, (New-Object System.Text.UTF8Encoding($true)))

# 载荷为已加密的高压缩数据，Inno 再压缩无收益且巨慢——用 store（none）
$PayloadInfo = Get-Item $Payload
$DataInfo = Get-Item $DataArc
& $Iscc "/DAppVersion=$AppVersion" "/DComp=none" `
    "/DPayloadBytes=$($PayloadInfo.Length)" "/DPayloadMBStr=$([math]::Round($PayloadInfo.Length/1MB))" `
    "/DDataBytes=$($DataInfo.Length)" "/DDataGBStr=$([math]::Round($DataInfo.Length/1GB,1))" `
    "/DDataFileName=$DataName" $IssFile
if ($LASTEXITCODE -ne 0) { throw "ISCC 编译失败" }

# 素材载荷移入输出目录与安装包并置（分发时成对交付）
Move-Item $DataArc (Join-Path $OutDir $DataName) -Force

# 7) 产出 SHA256 校验文件（安装包与素材数据文件都要）
$SetupExe = Join-Path $OutDir "EchoHymn_Setup_v$AppVersion.exe"
if (-not (Test-Path $SetupExe)) { throw "编译成功但未找到产物: $SetupExe" }
foreach ($f in @($SetupExe, (Join-Path $OutDir $DataName))) {
    $h = (Get-FileHash $f -Algorithm SHA256).Hash
    "$h  $(Split-Path $f -Leaf)" | Set-Content "$f.sha256" -Encoding ASCII
    Write-Host "SHA256 $(Split-Path $f -Leaf): $h"
}

$sizeMB = [math]::Round((Get-Item $SetupExe).Length / 1MB, 1)
$sizeGB = [math]::Round((Get-Item (Join-Path $OutDir $DataName)).Length / 1GB, 2)
Write-Host ""
Write-Host "══════════════════════════════════════════"
Write-Host " 安装包构建完成（主体/素材拆分双产物）"
Write-Host "  安装包: $SetupExe（$sizeMB MB）"
Write-Host "  素材包: $(Join-Path $OutDir $DataName)（$sizeGB GB）"
Write-Host "  分发时两文件须置于同一目录"
Write-Host "══════════════════════════════════════════"
