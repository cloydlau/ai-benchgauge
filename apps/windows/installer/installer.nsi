Unicode true
!include "MUI2.nsh"
!include "FileFunc.nsh"
!include "LogicLib.nsh"
!include "x64.nsh"
!include "WinVer.nsh"
!ifndef VERSION
!error "VERSION is required"
!endif
Name "AI BenchGauge"
OutFile "${OUTPUT}"
InstallDir "$LOCALAPPDATA\Programs\AI-BenchGauge"
RequestExecutionLevel user
SetCompressor /SOLID lzma
VIProductVersion "${VERSION}.0"
VIAddVersionKey "ProductName" "AI BenchGauge"
VIAddVersionKey "FileVersion" "${VERSION}"
VIAddVersionKey "LegalCopyright" "Copyright cloydlau"
!define MUI_ABORTWARNING
!define MUI_FINISHPAGE_RUN "$INSTDIR\AI-BenchGauge.exe"
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_LICENSE "${PAYLOAD}\Licenses\AI-BenchGauge.txt"
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "English"
!insertmacro MUI_LANGUAGE "SimpChinese"
!insertmacro MUI_LANGUAGE "TradChinese"
Var UpdateMode
Var WaitPID
Var Parameters
Function .onInit
    ${IfNot} ${RunningX64}
    ${OrIfNot} ${AtLeastWin10}
        MessageBox MB_ICONSTOP "AI BenchGauge requires 64-bit Windows 10 or newer."
        Abort
    ${EndIf}
    SetRegView 64
    ${GetParameters} $Parameters
    ClearErrors
    ${GetOptions} $Parameters "/UPDATE" $UpdateMode
    ${IfNot} ${Errors}
        StrCpy $UpdateMode "yes"
        SetSilent silent
        ${GetOptions} $Parameters "/WAITPID=" $WaitPID
        ${If} $WaitPID != ""
            System::Call 'kernel32::OpenProcess(i 0x00100000, i 0, i $WaitPID) p.r0'
            ${If} $0 != 0
                System::Call 'kernel32::WaitForSingleObject(p r0, i 60000) i.r1'
                System::Call 'kernel32::CloseHandle(p r0)'
                ${If} $1 != 0
                    SetErrorLevel 1
                    Abort
                ${EndIf}
            ${EndIf}
        ${EndIf}
    ${EndIf}
    ; Never overwrite a running installation. Use the same per-user mutex.
    checkRunning:
    System::Call 'kernel32::OpenMutexW(i 0x00100000, i 0, w "Local\AI-BenchGauge") p.r0'
    ${If} $0 != 0
        System::Call 'kernel32::CloseHandle(p r0)'
        ${If} $UpdateMode == "yes"
            SetErrorLevel 1
            Abort
        ${EndIf}
        MessageBox MB_RETRYCANCEL "Please quit AI BenchGauge before installing." IDRETRY checkRunning
        Abort
    ${EndIf}
FunctionEnd
Section "Install"
    SetShellVarContext current
    SetOutPath "$INSTDIR"
    File /r "${PAYLOAD}\*"
    ; Only install Evergreen WebView2 if missing. The core app works offline.
    ReadRegStr $0 HKCU "Software\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}" "pv"
    SetRegView 32
    ReadRegStr $1 HKLM "Software\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}" "pv"
    SetRegView 64
    ${If} $0 == ""
    ${OrIf} $0 == "0.0.0.0"
        ${If} $1 == ""
        ${OrIf} $1 == "0.0.0.0"
            DetailPrint "Installing Microsoft WebView2 Runtime..."
            ExecWait '$\"$INSTDIR\prerequisites\MicrosoftEdgeWebview2Setup.exe$\" /silent /install' $2
        ${EndIf}
    ${EndIf}
    WriteUninstaller "$INSTDIR\Uninstall.exe"
    CreateShortcut "$SMPROGRAMS\AI BenchGauge.lnk" "$INSTDIR\AI-BenchGauge.exe"
    WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\AI-BenchGauge" "DisplayName" "AI BenchGauge"
    WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\AI-BenchGauge" "DisplayVersion" "${VERSION}"
    WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\AI-BenchGauge" "Publisher" "cloydlau"
    WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\AI-BenchGauge" "UninstallString" '$\"$INSTDIR\Uninstall.exe$\"'
    WriteRegDWORD HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\AI-BenchGauge" "NoModify" 1
    WriteRegDWORD HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\AI-BenchGauge" "NoRepair" 1
SectionEnd
Function .onInstSuccess
    ${If} $UpdateMode == "yes"
        Exec '$\"$INSTDIR\AI-BenchGauge.exe$\"'
    ${EndIf}
FunctionEnd
Function un.onInit
    checkRunning:
    System::Call 'kernel32::OpenMutexW(i 0x00100000, i 0, w "Local\AI-BenchGauge") p.r0'
    ${If} $0 != 0
        System::Call 'kernel32::CloseHandle(p r0)'
        MessageBox MB_RETRYCANCEL "Please quit AI BenchGauge before uninstalling." IDRETRY checkRunning
        Abort
    ${EndIf}
FunctionEnd
Section "Uninstall"
    SetShellVarContext current
    SetRegView 64
    Delete "$SMPROGRAMS\AI BenchGauge.lnk"
    DeleteRegKey HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\AI-BenchGauge"
    RMDir /r "$INSTDIR"
    ; Preferences/cache/private account profiles are outside this directory.
SectionEnd
