# -*- coding: utf-8 -*-
"""
WorkBuddyAIPortable  一键构建脚本
================================

功能：
  1) 调 www.workbuddy.ai/v2/update 拿最新上游安装包 URL
  2) 下载安装包 → 解包外层 NSIS → 解包内层 app-64.7z
  3) 下载/定位 PortableApps.com Launcher 2.2.9 + NSIS makensis
  4) 用 PAL nsi 模板编译出 WorkBuddyAIPortable.exe
  5) 生成纯 zip 便携包

产物（落盘到 dist/）：
  WorkBuddyAIPortable_<version>_English.paf.exe    ← PAF 可执行安装器
  WorkBuddyAIPortable_<version>_portable.zip       ← 纯便携目录压缩包

环境变量（可选）：
  PORTABLEAPPS_REPO     仓库根（默认脚本所在目录）
  PORTABLEAPPS_7Z_PATH  7z.exe 绝对路径（不设则 PATH 里找）
  PORTABLEAPPS_MAKENSIS makensis.exe 绝对路径（不设则从 PAL 里出）
  SKIP_DOWNLOAD=1       跳过下载（已存在 App/WorkBuddyAI 时）
  DRY_RUN=1             演练，不落盘

用法：
  ./build.ps1                      # 完整构建
  ./build.ps1 -SkipDownload        # 用已填充好的 App/WorkBuddyAI 重编译
  ./build.ps1 -DryRun              # 只演练
"""

$ErrorActionPreference = "Stop"

$Root        = Split-Path -Parent $MyInvocation.MyCommand.Path
$PalCache    = Join-Path $env:TEMP "portable-build\pal-2.2.9"
$Dist        = Join-Path $Root "dist"
$WorkbuddyAI = Join-Path $Root "App\WorkBuddyAI"
$LauncherIni = Join-Path $Root "App\AppInfo\Launcher\WorkBuddyAIPortable.ini"
$AppInfoIni  = Join-Path $Root "App\AppInfo\appinfo.ini"
$TempDir     = Join-Path $env:TEMP "portable-build\workbuddyai-upstream"

# 解析命令行
param(
    [switch]$SkipDownload,
    [switch]$DryRun
)

function Step($msg) { Write-Host ""; Write-Host "==== $msg ====" -ForegroundColor Cyan }
function OK  ($msg) { Write-Host "  ✓ $msg" -ForegroundColor Green }
function Skip($msg) { Write-Host "  ↷ $msg" -ForegroundColor DarkGray }
function Fail($msg) { Write-Host "  ✗ $msg" -ForegroundColor Red; exit 1 }

# =====================================================================
# Step 1 — 读 appinfo.ini，拿 AppID / Version
# =====================================================================
Step "解析 appinfo.ini"
$ai = @{}
foreach($line in Get-Content $AppInfoIni -Encoding UTF8){
    $line = $line.Trim()
    if(-not $line -or $line.StartsWith(";")){ continue }
    if($line -match "^([^=]+)=(.*)$"){ $ai[$Matches[1].Trim()] = $Matches[2].Trim() }
}
$AppID   = $ai["ID"]
$Ver3    = $ai["PackageVersion"]
$Name    = $ai["Name"]
OK "AppID=$AppID  Version=$Ver3  Name=$Name"

# =====================================================================
# Step 2 — 探测 7z.exe
# =====================================================================
Step "探测 7z"
$candidates = @()
foreach($p in (Get-Command 7z -ErrorAction SilentlyContinue).Source,
             (Get-Command 7za -ErrorAction SilentlyContinue).Source,
             (Get-Command 7zz -ErrorAction SilentlyContinue).Source,
             $env:PORTABLEAPPS_7Z_PATH,
             "$env:SOFTAPP_DIR\7-Zip\7z.exe",
             "D:\SoftApp\7-Zip\7z.exe",
             "$env:ProgramFiles\7-Zip\7z.exe",
             "$env:ProgramW6432\7-Zip\7z.exe"){
    if($p -and (Test-Path $p) -and ($candidates -notcontains $p)){
        $candidates += $p
    }
}
$SevenZ = $null
foreach($c in $candidates){
    $ver = (& $c 2>&1 | Select-Object -First 1) -join ' '
    if($ver -match '7-Zip \((?<major>\w).*?(?<maj>\d+)\.(?<min>\d+)'){
        $maj = [int]$Matches.maj; $min = [int]$Matches.min
        if(($maj -gt 21) -or ($maj -eq 21 -and $min -ge 07 -and $c -notmatch '7za')){
            $SevenZ = $c; OK "选定: $c  ($ver)" ; break
        }
    }
}
if(-not $SevenZ){ Fail "没找到可用的 7z（需 7-Zip 22+）。装 D:\SoftApp\7-Zip\7z.exe 或设 PORTABLEAPPS_7Z_PATH" }

# =====================================================================
# Step 3 — 下载上游安装包
# =====================================================================
$UpstreamVer = $null
$InstallerUrl = $null

if(-not $SkipDownload -and -not (Test-Path "$WorkbuddyAI\WorkBuddyAI.exe")){
    Step "拉取上游版本信息（www.workbuddy.ai/v2/update）"
    $api = "https://www.workbuddy.ai/v2/update?platform=workbuddy-win32-x64-user&scene=saas"
    try {
        $resp = Invoke-RestMethod -Uri $api -Headers @{"User-Agent"="Mozilla/5.0"} -TimeoutSec 30
        $UpstreamVer = $resp.version    # 4 段 genieVersion，如 5.8.4.41366630
        $InstallerUrl = $resp.url
        OK "上游版本: $UpstreamVer"
        OK "安装包: $InstallerUrl"
    } catch { Fail "API 请求失败: $_" }

    Step "下载安装包"
    New-Item -ItemType Directory -Force -Path $TempDir | Out-Null
    $Installer = Join-Path $TempDir "WorkBuddy-upstream.exe"
    if(-not (Test-Path $Installer) -or ((Get-Item $Installer).Length -lt 100MB)){
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $InstallerUrl -OutFile $Installer -UseBasicParsing -TimeoutSec 1200
        OK "下载完成: $([math]::Round((Get-Item $Installer).Length/1MB,1)) MB"
    } else { Skip "已缓存安装包" }

    Step "解包"
    $Unpack1 = Join-Path $TempDir "_unpack1"
    $Unpack2 = Join-Path $TempDir "_unpack2"
    foreach($d in $Unpack1,$Unpack2,$WorkbuddyAI){ if(Test-Path $d){ Remove-Item $d -Recurse -Force -ErrorAction SilentlyContinue } }
    & $SevenZ x $Installer "-o$Unpack1" -y | Out-Null
    # 找内层 app-64.7z
    $Inner = Get-ChildItem $Unpack1 -Filter "app-64.7z" -Recurse | Select-Object -First 1
    if(-not $Inner){ Fail "没找到内层 app-64.7z" }
    & $SevenZ x $Inner.FullName "-o$Unpack2" -y | Out-Null
    if(-not (Test-Path "$Unpack2\WorkBuddyAI.exe")){ Fail "内层没解出 WorkBuddyAI.exe" }
    Move-Item $Unpack2 $WorkbuddyAI -Force
    OK "App/WorkBuddyAI 已填充 ($([math]::Round((Get-ChildItem $WorkbuddyAI -Recurse | Measure-Object Length -Sum).Sum/1MB,1)) MB)"

    # 回写 PackageVersion（截断到前 3 段）
    $NewVer = ($UpstreamVer -split '\.')[0..2] -join '.'
    Step "回写 appinfo.ini 的 PackageVersion -> $NewVer"
    $text = Get-Content $AppInfoIni -Raw -Encoding UTF8
    $text = [regex]::Replace($text, '(PackageVersion=)[^\r\n]+', "`$1$NewVer")
    Set-Content $AppInfoIni $text -Encoding UTF8 -NoNewline
    $Ver3 = $NewVer
    OK "PackageVersion 已更新为 $Ver3"
} elseif (Test-Path "$WorkbuddyAI\WorkBuddyAI.exe") {
    Skip "App/WorkBuddyAI 已存在，跳过下载"
} else {
    Fail "-SkipDownload 但 App/WorkBuddyAI 不存在"
}

# =====================================================================
# Step 4 — 下载 PortableApps.com Launcher 2.2.9 + NSIS
# =====================================================================
Step "下载 PortableApps.com Launcher 2.2.9"
$palUrl = "https://downloads.sourceforge.net/project/portableapps/PortableApps.comLauncher/2.2.9/PortableApps.comLauncher_2.2.9.paf.exe"
if(-not (Test-Path $PalCache)){
    New-Item -ItemType Directory -Force -Path $PalCache | Out-Null
    $PalExe = Join-Path $PalCache "pal.paf.exe"
    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest -Uri $palUrl -OutFile $PalExe -UseBasicParsing -TimeoutSec 120
    & $SevenZ x $PalExe "-o$PalCache" -y | Out-Null
    OK "PAL 已就位: $PalCache"
} else { Skip "PAL 已缓存" }

$Makensis = Join-Path $PalCache "App\NSIS\makensis.exe"
$NsiSrc   = Join-Path $PalCache "Other\Source\PortableApps.comLauncher.nsi"
if(-not (Test-Path $Makensis)){ Fail "makensis.exe 不存在: $Makensis" }

# =====================================================================
# Step 5 — 编译 PAF 安装器
# =====================================================================
Step "编译 $AppID.exe  (makensis)"
$pafExe = Join-Path $Root "$AppID.exe"
if(Test-Path $pafExe){ Remove-Item $pafExe -Force }
& $Makensis /V4 "/DPACKAGE=$Root" $NsiSrc 2>&1 | Select-Object -Last 15
if(-not (Test-Path $pafExe)){ Fail "编译失败，没生成 $pafExe" }
OK "PAF 安装器: $([math]::Round((Get-Item $pafExe).Length/1MB,1)) MB"

# =====================================================================
# Step 6 — 打包纯 zip
# =====================================================================
Step "打包纯 zip"
New-Item -ItemType Directory -Force -Path $Dist | Out-Null
$VerFile = $Ver3.Replace('.','')
$ZipName = "${AppID}_${VerFile}_portable.zip"
$ZipPath = Join-Path $Dist $ZipName
if(Test-Path $ZipPath){ Remove-Item $ZipPath -Force }
$ZipTemp = Join-Path $TempDir "_zip"
if(Test-Path $ZipTemp){ Remove-Item $ZipTemp -Recurse -Force }
New-Item -ItemType Directory -Path $ZipTemp | Out-Null
Copy-Item -Recurse -Force "$Root\App"   $ZipTemp\
Copy-Item -Force "$Root\$AppID.exe"     $ZipTemp\
# 纯 zip 也把 update.py 带上
if(Test-Path "$Root\update.py"){ Copy-Item -Force "$Root\update.py" $ZipTemp\ }
& $SevenZ a -tzip $ZipPath "$ZipTemp\*" -mx=1 | Out-Null
OK "纯 zip: $([math]::Round((Get-Item $ZipPath).Length/1MB,1)) MB -> dist\$ZipName"

# =====================================================================
# Step 7 — 复制 PAF 安装器到 dist
# =====================================================================
$PafDist = Join-Path $Dist "${AppID}_${VerFile}_English.paf.exe"
Copy-Item $pafExe $PafDist -Force
OK "PAF 安装器 -> dist\${AppID}_${VerFile}_English.paf.exe"

# =====================================================================
# 汇总
# =====================================================================
Write-Host ""
Write-Host "============================ BUILD SUCCESS ============================" -ForegroundColor Green
Write-Host "  版本:          $Ver3   (上游 genieVersion: $UpstreamVer)"
Write-Host "  PAF 安装器:    dist\${AppID}_${VerFile}_English.paf.exe"
Write-Host "  纯 zip:        dist\$ZipName"
Write-Host "========================================================================" -ForegroundColor Green
