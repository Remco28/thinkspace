; Builds Thinkspace-Setup.exe from the folder tool\package_windows.ps1 prepares.
; Per-user install (no administrator needed), Start-menu entry, optional
; desktop shortcut, double-click for .thinkspace files, and an uninstaller.
#define MyAppName "Thinkspace"
#ifndef MyAppVersion
  #define MyAppVersion "0.0.0"
#endif

[Setup]
AppId={{B7C0E4A2-5D3F-4C8E-9B61-3F7A2D1E8C55}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher=Remco28
AppPublisherURL=https://github.com/Remco28/thinkspace
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
OutputDir=..\..\dist
OutputBaseFilename=Thinkspace-Setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
SetupIconFile=..\..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\thinkspace.exe
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
ChangesAssociations=yes

[Tasks]
Name: "desktopicon"; Description: "Put a Thinkspace shortcut on the desktop"; Flags: unchecked

[Files]
Source: "..\..\dist\thinkspace-windows-x64\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\thinkspace.exe"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\thinkspace.exe"; Tasks: desktopicon

[Registry]
Root: HKA; Subkey: "Software\Classes\.thinkspace"; ValueType: string; ValueName: ""; ValueData: "Thinkspace.Project"; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\Thinkspace.Project"; ValueType: string; ValueName: ""; ValueData: "Thinkspace project"; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Classes\Thinkspace.Project\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\thinkspace.exe,0"
Root: HKA; Subkey: "Software\Classes\Thinkspace.Project\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\thinkspace.exe"" ""%1"""

[Run]
Filename: "{app}\thinkspace.exe"; Description: "Start Thinkspace"; Flags: nowait postinstall skipifsilent
