; Inno Setup Script for Smart Laundry POS Desktop
; Standard Windows Installer Generator

#define MyAppName "Smart Laundry POS"
#define MyAppVersion "2.4.2"
#define MyAppPublisher "Smart Laundry Team"
#define MyAppURL "https://smartlaundry.local"
#define MyAppExeName "flutter_application_1.exe"
#define MyPythonExeName "main.exe"

[Setup]
; Unique App ID (GUID)
AppId={{C481A67B-6F5D-4F71-B88E-632D15792F01}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={autopf}\SmartLaundryPOS
DisableProgramGroupPage=yes
; Require administrative privileges for secure installation in Program Files
PrivilegesRequired=admin
PrivilegesRequiredOverridesAllowed=dialog
OutputDir=installer_output
OutputBaseFilename=SmartLaundry_POS_Setup_v{#MyAppVersion}
SetupIconFile=LaundryApps(Upgrade)\windows\runner\resources\app_icon.ico
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern

; Automatic application closing to prevent locked file conflicts during updates
CloseApplications=yes
CloseApplicationsFilter=*.exe,*.dll
RestartApplications=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; Flutter Desktop Release Files (installed directly in {app})
Source: "LaundryApps(Upgrade)\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
; Python Backend Executable
Source: "main.exe"; DestDir: "{app}"; Flags: ignoreversion
; WhatsApp Web Node.js Service (Clean code only: excludes non-runtime definitions & docs to maximize install speed)
Source: "wa_service\*"; DestDir: "{app}\wa_service"; Flags: ignoreversion recursesubdirs createallsubdirs; Excludes: "node_modules\.cache\*,*.log,.wwebjs_auth\*,*.bak,*.d.ts,*.md,*.map,*.tsbuildinfo,*.tgz"
; Configuration & Tuya Smartplug Defaults
Source: "config.json"; DestDir: "{app}"; Flags: ignoreversion onlyifdoesntexist
Source: "smartplug_controller\*"; DestDir: "{app}\smartplug_controller"; Flags: ignoreversion recursesubdirs createallsubdirs onlyifdoesntexist

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; IconFilename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; IconFilename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
Type: filesandordirs; Name: "{app}\*.log"
Type: filesandordirs; Name: "{app}\__pycache__"

[Code]
procedure KillRunningProcesses();
var
  ResultCode: Integer;
begin
  // Forcefully terminate any running instances of Flutter UI, Python Backend, or Node.js WhatsApp microservice
  Exec('taskkill.exe', '/F /IM flutter_application_1.exe /T', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Exec('taskkill.exe', '/F /IM main.exe /T', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Exec('taskkill.exe', '/F /IM node.exe /T', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Exec('taskkill.exe', '/F /IM wa_service.exe /T', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Exec('taskkill.exe', '/F /IM "Smart Laundry POS.exe" /T', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Sleep(500);
end;

function InitializeSetup(): Boolean;
begin
  KillRunningProcesses();
  Result := True;
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  KillRunningProcesses();
  Result := '';
end;
