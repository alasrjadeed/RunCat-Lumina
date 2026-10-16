; ---------------------------------------------------------------------------
; RunCat Lumina - Inno Setup script (per-user install, no administrator rights)
;
; Local build:
;   ISCC.exe /DAppVersion=1.0.1 packaging\windows\installer\RunCatLumina.iss
;   (or simply: scripts\windows\build-installer.bat)
;
; Requires the windowed executable built from RunCat-Lumina.store.spec at
; dist\gui\RunCat-Lumina.exe (override with /DExePath="C:\path\to\exe").
;
; Output:      dist\installer\RunCatLumina-<version>-Setup.exe
; Installs to: %LOCALAPPDATA%\Programs\RunCat Lumina
; Uninstall:   Settings > Apps, or unins000.exe in the install folder
; User settings in %USERPROFILE%\.config\runcat-lumina are preserved on
; uninstall on purpose (delete the folder manually to reset everything).
; ---------------------------------------------------------------------------

#ifndef AppVersion
  #define AppVersion "1.0.1"
#endif
#ifndef ExePath
  #define ExePath "..\..\..\dist\gui\RunCat-Lumina.exe"
#endif
#ifndef SetupIcon
  #define SetupIcon "setup.ico"
#endif

[Setup]
AppId={{03C8ACD2-73DC-40E2-B450-EB86FFC58107}
AppName=RunCat Lumina
AppVersion={#AppVersion}
AppVerName=RunCat Lumina {#AppVersion}
AppPublisher=AL ASAR JADEED
AppPublisherURL=https://alasarjadeed.com
AppSupportURL=https://alasarjadeed.com
AppUpdatesURL=https://github.com/alasrjadeed/RunCat-Lumina/releases
DefaultDirName={localappdata}\Programs\RunCat Lumina
DefaultGroupName=RunCat Lumina
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir=..\..\..\dist\installer
OutputBaseFilename=RunCatLumina-{#AppVersion}-Setup
SetupIconFile={#SetupIcon}
UninstallDisplayIcon={app}\RunCat-Lumina.exe
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
LicenseFile=..\..\..\LICENSE

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "startup"; Description: "Start RunCat Lumina when I sign in"; GroupDescription: "Startup:"
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional shortcuts:"; Flags: unchecked

[Files]
Source: "{#ExePath}"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\RunCat Lumina"; Filename: "{app}\RunCat-Lumina.exe"
Name: "{group}\{cm:UninstallProgram,RunCat Lumina}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\RunCat Lumina"; Filename: "{app}\RunCat-Lumina.exe"; Tasks: desktopicon

[Registry]
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; \
    ValueName: "RunCat Lumina"; ValueData: """{app}\RunCat-Lumina.exe"""; \
    Flags: uninsdeletevalue; Tasks: startup

[Run]
Filename: "{app}\RunCat-Lumina.exe"; Description: "{cm:LaunchProgram,RunCat Lumina}"; \
    Flags: nowait postinstall skipifsilent

[UninstallRun]
; Stop the tray app before its files are removed.
Filename: "{cmd}"; Parameters: "/C taskkill /IM RunCat-Lumina.exe /F"; \
    Flags: runhidden; RunOnceId: "KillRunCatLumina"

[Code]
{ Kill a running instance before installing/upgrading: a single-file PyInstaller
  executable holds a lock on itself, which would make the copy fail. }
function InitializeSetup(): Boolean;
var
  ResultCode: Integer;
begin
  Exec(ExpandConstant('{cmd}'), '/C taskkill /IM RunCat-Lumina.exe /F',
       '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Result := True;
end;
