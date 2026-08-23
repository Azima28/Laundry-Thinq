; Inno Setup Script for Smart Laundry POS Desktop
; Standard Windows Installer Generator

#define MyAppName "Smart Laundry POS"
#define MyAppVersion "2.4.0"
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

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; Flutter Desktop Release Files
Source: "LaundryApps(Upgrade)\build\windows\x64\runner\Release\*"; DestDir: "{app}\app"; Flags: ignoreversion recursesubdirs createallsubdirs
; Python Backend Executable
Source: "main.exe"; DestDir: "{app}"; Flags: ignoreversion
; WhatsApp Web Node.js Service
Source: "wa_service\*"; DestDir: "{app}\wa_service"; Flags: ignoreversion recursesubdirs createallsubdirs; Excludes: "node_modules\.cache\*,*.log,.wwebjs_auth\*,*.bak"
; Configuration
Source: "config.json"; DestDir: "{app}"; Flags: ignoreversion onlyifdoesntexist

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\app\{#MyAppExeName}"; IconFilename: "{app}\app\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\app\{#MyAppExeName}"; IconFilename: "{app}\app\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\app\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
Type: filesandordirs; Name: "{app}\*.log"
Type: filesandordirs; Name: "{app}\__pycache__"
