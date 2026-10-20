# -*- coding: utf-8 -*-
#
# WorkBuddyAIPortable  一键构建脚本
# ================================
#
# 功能：
#   1) 调 www.workbuddy.ai/v2/update 拿最新上游安装包 URL
#   2) 下载安装包 -> 解包外层 NSIS -> 解包内层 app-64.7z
#   3) 下载/定位 PortableApps.com Launcher 2.2.9 + NSIS makensis
#   4) 用 PAL nsi 模板编译出 WorkBuddyAIPortable.exe
#   5) 生成纯 zip 便携包
#
# 产物（落盘到 dist/）：
#   WorkBuddyAIPortable_<version>_English.paf.exe     <- PAF 可执行安装器
#   WorkBuddyAIPortable_<version>_portable.zip        <- 纯便携目录压缩包
#
# 环境变量（可选）：
#   PORTABLEAPPS_REPO      仓库根（默认脚本所在目录）
#   PORTABLEAPPS_7Z_PATH   7z/7za 绝对路径（不设则优先用 PATH 上的 7za.exe）
#   PORTABLEAPPS_MAKENSIS  makensis.exe 绝对路径（不设则从 PAL 里出）
#   SKIP_DOWNLOAD=1        跳过下载（已存在 App/WorkBuddyAI 时）
#   DRY_RUN=1              演练，不落盘
#
# 用法：
#   ./build.ps1                      # 完整构建
#   ./build.ps1 -SkipDownload        # 用已填充好的 App/WorkBuddyAI 重编译
#   ./build.ps1 -DryRun              # 只演练
#
# 注意：param 块必须是脚本中第一条可执行语句（注释除外），
#       因此它必须放在所有赋值语句之前，否则 PS 会报
#       "param : The term 'param' is not recognized"。

param(
    [switch]$SkipDownload,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

$Root        = Split-Path -Parent $MyInvocation.MyCommand.Path
$PalCache    = Join-Path $env:TEMP "portable-build\pal-2.2.9"
$Dist        = Join-Path $Root "dist"
$WorkbuddyAI = Join-Path $Root "App\WorkBuddyAI"
$LauncherIni = Join-Path $Root "App\AppInfo\Launcher\WorkBuddyAIPortable.ini"
$AppInfoIni  = Join-Path $Root "App\AppInfo\appinfo.ini"
$TempDir     = Join-Path $env:TEMP "portable-build\workbuddyai-upstream"

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
$Name    = $ai["Name"]
# appinfo.ini 的 PackageVersion 是 4 段（X.X.X.X，makensis 的 VIProductVersion 要求）；
# 产物文件名用 3 段，与 CI 里的 upstream3 保持一致。
$Ver3    = ($ai["PackageVersion"] -split '\.')[0..2] -join '.'
OK "AppID=$AppID  Version=$Ver3  Name=$Name"

# =====================================================================
# Step 2 — 探测 7-Zip（主工具优先用 PATH 上的 7za.exe）
# =====================================================================
Step "探测 7-Zip"

function Get-SevenZInfo($exe){
    # banner 可能以空行开头，先过滤空行再取首行
    $banner = (& $exe 2>&1 | Where-Object { "$_".Trim() } | Select-Object -First 1) -join ' '
    # 兼容两种 banner：7z -> "7-Zip 26.04 (x64)"，7za -> "7-Zip (a) 26.04 (x64)"
    if($banner -notmatch '7-Zip\s+(?:\([a-zA-Z]+\)\s*)?(?<maj>\d+)\.(?<min>\d+)'){ return $null }
    # 7za/7zr 是精简版，格式表里没有 Nsis/PE，解不了 .paf.exe 和上游 NSIS 安装包
    $formats = & $exe i 2>&1
    [pscustomobject]@{
        Path   = $exe
        Banner = $banner
        Maj    = [int]$Matches.maj
        Min    = [int]$Matches.min
        Nsis   = [bool](@($formats | Where-Object { "$_" -match '\bNsis\b' }).Count)
    }
}

$candidates = @()
foreach($n in @('7za','7z','7zz')){
    foreach($cmd in @(Get-Command $n -All -ErrorAction SilentlyContinue)){
        if($cmd.Source -and ($candidates -notcontains $cmd.Source)){ $candidates += $cmd.Source }
    }
}
foreach($p in @($env:PORTABLEAPPS_7Z_PATH,
                "$env:SOFTAPP_DIR\7-Zip\7z.exe",
                "D:\SoftApp\7-Zip\7z.exe",
                "$env:ProgramFiles\7-Zip\7z.exe",
                "$env:ProgramW6432\7-Zip\7z.exe")){
    if($p -and (Test-Path $p) -and ($candidates -notcontains $p)){ $candidates += $p }
}

$found = @()
foreach($c in $candidates){
    $info = Get-SevenZInfo $c
    if(-not $info){ continue }
    if(($info.Maj -gt 21) -or ($info.Maj -eq 21 -and $info.Min -ge 07)){ $found += $info }
}
if(-not $found){ Fail "没找到可用的 7-Zip（需 21.07+）。把 7za.exe 放进 PATH，或设 PORTABLEAPPS_7Z_PATH" }

# 主工具：优先 7za；同名多个时取版本最高的（避免被 C:\Windows\system32 里的旧版遮蔽）
$SevenZInfo = @($found |
    Sort-Object @{Expression={ if($_.Path -match '7za'){0}else{1} }},
                @{Expression='Maj';Descending=$true},
                @{Expression='Min';Descending=$true})[0]
$SevenZ = $SevenZInfo.Path
OK "主工具: $SevenZ  ($($SevenZInfo.Banner))"

# NSIS 解包专用：7za 不带 NSIS handler，必须用完整版 7z.exe
$NsisInfo   = @($found | Where-Object { $_.Nsis } |
    Sort-Object @{Expression='Maj';Descending=$true}, @{Expression='Min';Descending=$true})[0]
$SevenZNsis = if($NsisInfo){ $NsisInfo.Path } else { $null }
if($SevenZNsis){ OK "NSIS 解包: $SevenZNsis" }
else { Write-Host "  ! 未找到支持 NSIS 的 7z.exe（7za 不含该 handler），解包 .paf.exe / 上游安装包时会失败" -ForegroundColor Yellow }

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
    if(-not $SevenZNsis){ Fail "解包上游 NSIS 安装包需要完整版 7z.exe（7za 不含 NSIS handler）" }
    $Unpack1 = Join-Path $TempDir "_unpack1"
    $Unpack2 = Join-Path $TempDir "_unpack2"
    foreach($d in $Unpack1,$Unpack2,$WorkbuddyAI){ if(Test-Path $d){ Remove-Item $d -Recurse -Force -ErrorAction SilentlyContinue } }
    # 外层安装包是 NSIS -> 用 7z.exe；内层 app-64.7z -> 主工具即可
    & $SevenZNsis x $Installer "-o$Unpack1" -y | Out-Null
    # 找内层 app-64.7z
    $Inner = Get-ChildItem $Unpack1 -Filter "app-64.7z" -Recurse | Select-Object -First 1
    if(-not $Inner){ Fail "没找到内层 app-64.7z" }
    & $SevenZ x $Inner.FullName "-o$Unpack2" -y | Out-Null
    if(-not (Test-Path "$Unpack2\WorkBuddyAI.exe")){ Fail "内层没解出 WorkBuddyAI.exe" }
    Move-Item $Unpack2 $WorkbuddyAI -Force
    OK "App/WorkBuddyAI 已填充 ($([math]::Round((Get-ChildItem $WorkbuddyAI -Recurse | Measure-Object Length -Sum).Sum/1MB,1)) MB)"

    # 回写 PackageVersion（产物命名用 3 段，PackageVersion 必须 4 段）
    $Ver3   = ($UpstreamVer -split '\.')[0..2] -join '.'
    $NewVer = "$Ver3.0"
    Step "回写 appinfo.ini 的 PackageVersion -> $NewVer"
    $text = Get-Content $AppInfoIni -Raw -Encoding UTF8
    $text = [regex]::Replace($text, '(PackageVersion=)[^\r\n]+', "`$1$NewVer")
    Set-Content $AppInfoIni $text -Encoding UTF8 -NoNewline
    OK "PackageVersion 已更新为 $NewVer"
} elseif (Test-Path "$WorkbuddyAI\WorkBuddyAI.exe") {
    Skip "App/WorkBuddyAI 已存在，跳过下载"
} else {
    Fail "-SkipDownload 但 App/WorkBuddyAI 不存在"
}

# =====================================================================
# Step 4 — 准备 PortableApps.com Launcher 2.2.9 + NSIS
#   优先使用仓库内置的 vendor\PortableApps.comLauncher_2.2.9.paf.exe；
#   SourceForge 的旧下载地址已失效（404），仅作兜底。
# =====================================================================
Step "准备 PortableApps.com Launcher 2.2.9"
$PalNsi = Join-Path $PalCache "Other\Source\PortableApps.comLauncher.nsi"
if(-not (Test-Path $PalNsi)){
    New-Item -ItemType Directory -Force -Path $PalCache | Out-Null
    $PalPaf = Join-Path $Root "vendor\PortableApps.comLauncher_2.2.9.paf.exe"
    if(-not (Test-Path $PalPaf)){
        Write-Host "  ! vendor 内置 PAF 缺失，回退到网络下载" -ForegroundColor Yellow
        $PalPaf = Join-Path $PalCache "pal.paf.exe"
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri "https://downloads.sourceforge.net/portableapps/PortableApps.comLauncher/2.2.9/PortableApps.comLauncher_2.2.9.paf.exe" -OutFile $PalPaf -UseBasicParsing -TimeoutSec 120
    }
    # .paf.exe 是 NSIS 安装包 -> 必须用支持 NSIS 的完整版 7z.exe
    if(-not $SevenZNsis){ Fail "解包 PAL 需要完整版 7z.exe（7za 不含 NSIS handler）: $PalPaf" }
    & $SevenZNsis x $PalPaf "-o$PalCache" -y | Out-Null
    if(-not (Test-Path $PalNsi)){ Fail "PAL 解压失败: $PalPaf" }
    OK "PAL 已就位: $PalCache"
} else { Skip "PAL 已缓存" }

$Makensis = Join-Path $PalCache "App\NSIS\makensis.exe"
$NsiSrc   = Join-Path $PalCache "Other\Source\PortableApps.comLauncher.nsi"
if(-not (Test-Path $Makensis)){ Fail "makensis.exe 不存在: $Makensis" }

# =====================================================================
# Step 5 — 编译 PAF 安装器
# =====================================================================
$iniText  = Get-Content $AppInfoIni -Raw -Encoding UTF8
# PAL 的 OutFile 是 "${PACKAGE}\${AppID}.exe"，${AppID} 与 ${NamePortable} 必须显式传入，
# 否则会生成字面量 "${AppID}.exe"（PortableApps.comLauncherGenerator 也是这么传的）。
$PalAppID = ([regex]::Match($iniText, '(?m)^ID=([^\r\n]+)')).Groups[1].Value.Trim()
$PalName  = ([regex]::Match($iniText, '(?m)^Name=([^\r\n]+)')).Groups[1].Value.Trim()
# PAL 的 PortableApps.comLauncher.nsi 里是 VIProductVersion ${Version}，
# 必须由 /DVersion 提供 4 段版本号，否则 makensis 报
# "invalid VIProductVersion format, should be X.X.X.X" 并中止编译。
$PkgVersion = ([regex]::Match($iniText, '(?m)^PackageVersion=([^\r\n]+)')).Groups[1].Value.Trim()
if($PkgVersion -notmatch '^\d+\.\d+\.\d+\.\d+$'){ Fail "PackageVersion 必须是 4 段（X.X.X.X），当前: '$PkgVersion'" }
Step "编译 $PalAppID.exe  (makensis)"
$pafExe = Join-Path $Root "$PalAppID.exe"
if(Test-Path $pafExe){ Remove-Item $pafExe -Force }
& $Makensis /V4 "/DPACKAGE=$Root" "/DAppID=$PalAppID" "/DNamePortable=$PalName" "/DVersion=$PkgVersion" $NsiSrc 2>&1 | Select-Object -Last 15
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
