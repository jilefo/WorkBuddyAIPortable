; ===========================================================================
; WorkBuddy AI Portable  Custom.nsh  （UTF-8 无 BOM）
; ===========================================================================
; 职责：
;   1. 创建/移除 %USERPROFILE%\.workbuddy 目录联接（junction）到便携 Data 目录
;      —— 解决子进程（daemon/prewarm/CLI）环境变量被过滤后回退到默认路径的问题
;   2. 清理开机自启项（HKCU\...\Run 中 WorkBuddy 相关值）
;   3. 清理 URL 协议注册残留（HKCU\Software\Classes\workbuddy / buddy-app）
;   4. 清理更新器计划任务（WorkBuddy 前缀）
;   5. 结束便携目录内残留进程
; ===========================================================================

; ---------------------------------------------------------------------------
; 辅助 PS1 脚本生成
; ---------------------------------------------------------------------------
!macro NP_WriteHelpers
  CreateDirectory "$DataDirectory\settings"
  FileOpen $9 "$DataDirectory\settings\.np-helpers.ps1" w
  FileWrite $9 'param($$mode,$$a1,$$a2,$$a3,$$a4)$\r$\n'
  FileWrite $9 '$$ErrorActionPreference="SilentlyContinue"$\r$\n'
  FileWrite $9 'if($$mode -eq "kill"){$\r$\n'
  FileWrite $9 '$$r=(Resolve-Path -LiteralPath $$a4).Path$\r$\n'
  FileWrite $9 'Get-Process -ErrorAction SilentlyContinue | Where-Object {$$_.Path -and $$_.Path.StartsWith($$r,[System.StringComparison]::OrdinalIgnoreCase)} | ForEach-Object {try{Stop-Process -Id $$_.Id -Force -ErrorAction SilentlyContinue}catch{}}$\r$\n'
  FileWrite $9 'exit 0}$\r$\n'
  FileWrite $9 'if($$mode -eq "runclean"){$\r$\n'
  FileWrite $9 '$$k="HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"$\r$\n'
  FileWrite $9 '$$item=Get-ItemProperty -Path $$k -ErrorAction SilentlyContinue$\r$\n'
  FileWrite $9 'if($$item){$$item.PSObject.Properties | Where-Object {$$_.Name -notlike "PS*" -and $$_.Name -like "*WorkBuddy*"} | ForEach-Object {Remove-ItemProperty -Path $$k -Name $$_.Name -Force -ErrorAction SilentlyContinue}}$\r$\n'
  FileWrite $9 'exit 0}$\r$\n'
  FileWrite $9 'if($$mode -eq "taskclean"){$\r$\n'
  FileWrite $9 'Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $$_.TaskName -like "*WorkBuddy*" -or $$_.TaskName -like "*workbuddy*" } | ForEach-Object { Unregister-ScheduledTask -TaskName $$_.TaskName -Confirm:$$false -ErrorAction SilentlyContinue }$\r$\n'
  FileWrite $9 'exit 0}$\r$\n'
  FileWrite $9 'if($$mode -eq "setup"){$\r$\n'
  FileWrite $9 '$$prof=$$a1;if(-not $$prof){$$prof=$$env:USERPROFILE}$\r$\n'
  FileWrite $9 '$$wb=Join-Path $$prof ".workbuddy"$\r$\n'
  FileWrite $9 '$$portable=$$a4$\r$\n'
  FileWrite $9 '$$backup=Join-Path $$prof ".workbuddy.portable-backup"$\r$\n'
  FileWrite $9 'if(Test-Path $$wb){$\r$\n'
  FileWrite $9 '  $$item=Get-Item -LiteralPath $$wb -Force$\r$\n'
  FileWrite $9 '  if($$item.Attributes -band [IO.FileAttributes]::ReparsePoint){$\r$\n'
  FileWrite $9 '    $$target=($$item.Target -join ";")$\r$\n'
  FileWrite $9 '    if($$target -ieq $$portable){exit 0}$\r$\n'
  FileWrite $9 '    [IO.Directory]::Delete($$wb,$$false)$\r$\n'
  FileWrite $9 '  } else {$\r$\n'
  FileWrite $9 '    if(Test-Path $$backup){Remove-Item $$backup -Recurse -Force -ErrorAction SilentlyContinue}$\r$\n'
  FileWrite $9 '    Move-Item -LiteralPath $$wb $$backup -Force -ErrorAction SilentlyContinue$\r$\n'
  FileWrite $9 '  }$\r$\n'
  FileWrite $9 '}$\r$\n'
  FileWrite $9 'New-Item -ItemType Junction -Path $$wb -Target $$portable -Force -ErrorAction SilentlyContinue | Out-Null$\r$\n'
  FileWrite $9 'exit 0}$\r$\n'
  FileWrite $9 'if($$mode -eq "teardown"){$\r$\n'
  FileWrite $9 '$$prof=$$a1;if(-not $$prof){$$prof=$$env:USERPROFILE}$\r$\n'
  FileWrite $9 '$$wb=Join-Path $$prof ".workbuddy"$\r$\n'
  FileWrite $9 '$$portable=$$a4$\r$\n'
  FileWrite $9 '$$backup=Join-Path $$prof ".workbuddy.portable-backup"$\r$\n'
  FileWrite $9 'if(Test-Path $$wb){$\r$\n'
  FileWrite $9 '  $$item=Get-Item -LiteralPath $$wb -Force$\r$\n'
  FileWrite $9 '  if($$item.Attributes -band [IO.FileAttributes]::ReparsePoint){$\r$\n'
  FileWrite $9 '    $$target=($$item.Target -join ";")$\r$\n'
  FileWrite $9 '    if($$target -ieq $$portable){[IO.Directory]::Delete($$wb,$$false)}$\r$\n'
  FileWrite $9 '  }$\r$\n'
  FileWrite $9 '}$\r$\n'
  FileWrite $9 'if(Test-Path $$backup){Move-Item -LiteralPath $$backup $$wb -Force -ErrorAction SilentlyContinue}$\r$\n'
  FileWrite $9 'exit 0}$\r$\n'
  FileWrite $9 'if($$mode -eq "regclean"){$\r$\n'
  FileWrite $9 '$$names="^workbuddy|^codebuddy|^WorkBuddy|^buddy-app"$\r$\n'
  FileWrite $9 '$$cls="HKCU:\Software\Classes"$\r$\n'
  FileWrite $9 'Get-ChildItem $$cls -ErrorAction SilentlyContinue | Where-Object {$$_.PSChildName -match $$names} | ForEach-Object {Remove-Item $$_.PSPath -Recurse -Force -ErrorAction SilentlyContinue}$\r$\n'
  FileWrite $9 '$$ra="HKCU:\Software\RegisteredApplications"$\r$\n'
  FileWrite $9 '$$ri=Get-ItemProperty -Path $$ra -ErrorAction SilentlyContinue$\r$\n'
  FileWrite $9 'if($$ri){$$ri.PSObject.Properties | Where-Object {$$_.Name -notlike "PS*" -and $$_.Name -match "(?i)workbuddy|codebuddy"} | ForEach-Object {Remove-ItemProperty -Path $$ra -Name $$_.Name -Force -ErrorAction SilentlyContinue}}$\r$\n'
  FileWrite $9 '$$fe="HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts"$\r$\n'
  FileWrite $9 'Get-ChildItem $$fe -ErrorAction SilentlyContinue | ForEach-Object {$\r$\n'
  FileWrite $9 '  $$ow=Join-Path $$_.PSPath "OpenWithProgids"$\r$\n'
  FileWrite $9 '  if(Test-Path $$ow){$\r$\n'
  FileWrite $9 '    $$oi=Get-ItemProperty -Path $$ow -ErrorAction SilentlyContinue$\r$\n'
  FileWrite $9 '    if($$oi){$$oi.PSObject.Properties | Where-Object {$$_.Name -notlike "PS*" -and $$_.Name -match "(?i)workbuddy|codebuddy"} | ForEach-Object {Remove-ItemProperty -Path $$ow -Name $$_.Name -Force -ErrorAction SilentlyContinue}}$\r$\n'
  FileWrite $9 '  }}$\r$\n'
  FileWrite $9 'exit 0}$\r$\n'
  FileWrite $9 'exit 99$\r$\n'
  FileClose $9
!macroend
!define NP_WriteHelpers `!insertmacro NP_WriteHelpers`

; ---------------------------------------------------------------------------
; 内部函数
; ---------------------------------------------------------------------------

; 结束便携目录内的后台残留进程
Function KillResidual
  nsExec::ExecToStack 'powershell -NoProfile -ExecutionPolicy Bypass -File "$DataDirectory\settings\.np-helpers.ps1" kill "" "" "" "$EXEDIR\App"'
  Pop $0
  Pop $1
FunctionEnd

; 清理开机自启项
Function DeleteRunKey
  nsExec::ExecToStack 'powershell -NoProfile -ExecutionPolicy Bypass -File "$DataDirectory\settings\.np-helpers.ps1" runclean "" "" "" ""'
  Pop $0
  Pop $1
FunctionEnd

; 清理更新器计划任务
Function DeleteUpdateTask
  nsExec::ExecToStack 'powershell -NoProfile -ExecutionPolicy Bypass -File "$DataDirectory\settings\.np-helpers.ps1" taskclean "" "" "" ""'
  Pop $0
  Pop $1
FunctionEnd

; 清理 URL 协议注册残留
Function DeleteProtoReg
  DeleteRegKey HKCU "Software\Classes\workbuddy"
  DeleteRegKey HKCU "Software\Classes\buddy-app"
FunctionEnd

; 清理文件关联注册残留（应用会写入 workbuddyai.* / workbuddy-ai /
; RegisteredApplications / FileExts OpenWithProgids）
Function DeleteFileAssoc
  nsExec::ExecToStack 'powershell -NoProfile -ExecutionPolicy Bypass -File "$DataDirectory\settings\.np-helpers.ps1" regclean "" "" "" ""'
  Pop $0
  Pop $1
FunctionEnd

; 创建 %USERPROFILE%\.workbuddy 到便携目录的 junction
; 注意：launcher 已把 USERPROFILE 重定向到便携 Data\home，故此处必须传入
;       系统真实 profile 路径（NSIS $PROFILE），否则会指向错误位置。
Function SetupJunction
  nsExec::ExecToStack 'powershell -NoProfile -ExecutionPolicy Bypass -File "$DataDirectory\settings\.np-helpers.ps1" setup "$PROFILE" "" "" "$DataDirectory\workbuddy"'
  Pop $0
  Pop $1
FunctionEnd

; 移除 junction 并恢复原始目录
Function TeardownJunction
  nsExec::ExecToStack 'powershell -NoProfile -ExecutionPolicy Bypass -File "$DataDirectory\settings\.np-helpers.ps1" teardown "$PROFILE" "" "" "$DataDirectory\workbuddy"'
  Pop $0
  Pop $1
FunctionEnd

; ===========================================================================
; PAL 钩子
; ===========================================================================

; 主程序启动前
!macro Custom.nsh_PreExecPrimary
  ${NP_WriteHelpers}
  Call KillResidual
  Call DeleteRunKey
  Call DeleteUpdateTask
  Call DeleteProtoReg
  Call DeleteFileAssoc
  Call SetupJunction
!macroend

; 主程序退出后
!macro Custom.nsh_PostPrimary
  ${NP_WriteHelpers}
  Call KillResidual
  Call DeleteRunKey
  Call DeleteUpdateTask
  Call DeleteProtoReg
  Call DeleteFileAssoc
  Call TeardownJunction
!macroend

; 卸载/收尾
!macro Custom.nsh_Unload
  ${NP_WriteHelpers}
  Call KillResidual
  Call DeleteRunKey
  Call DeleteUpdateTask
  Call DeleteProtoReg
  Call DeleteFileAssoc
  Call TeardownJunction
!macroend
