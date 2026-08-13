; Installer for Rich Man Fitness.
;
; Produces a single setup .exe the gym owner can double-click. Installs
; per-user, so there is no admin password prompt on the gym's computer.
;
; Built by .github/workflows/windows-build.yml. To build by hand:
;   iscc /DAppVersion=1.0.0 /DSourceDir=..\rmf_desktop\build\windows\x64\runner\Release installer\rich_man_fitness.iss

#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif

#ifndef SourceDir
  #define SourceDir "..\rmf_desktop\build\windows\x64\runner\Release"
#endif

#define AppName "Rich Man Fitness"
#define AppPublisher "Rich Man Fitness"
#define AppExeName "Rich Man Fitness.exe"

[Setup]
; This GUID must never change. Windows uses it to recognise an existing
; installation, so a new version replaces the old one in place instead of
; installing a second copy alongside it.
AppId={{8E2B6F41-4C3D-4A7E-9B15-2D6F8A3C1E90}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
OutputDir=..\dist
OutputBaseFilename=RichManFitness-Setup-{#AppVersion}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern

; Per-user install: no administrator password needed, which matters on a gym
; computer where nobody knows the admin credentials.
PrivilegesRequired=lowest

; 64-bit only, matching the Flutter build.
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

; Refuse to install over a running copy rather than leaving a half-updated app.
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a shortcut on the desktop"; GroupDescription: "Shortcuts:"

[Files]
; The whole Release folder: the executable will not start without the Flutter
; runtime, the SQLite DLL and pdfium beside it.
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExeName}"
Name: "{group}\Uninstall {#AppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExeName}"; Description: "Open {#AppName}"; Flags: nowait postinstall skipifsilent

; Nothing is listed under [UninstallDelete].
;
; The gym's database, receipts and backups live in the user's application data
; folder, not in the install directory, so uninstalling removes the program and
; leaves the data untouched. That is deliberate: an uninstall must never destroy
; a year of payment history, and reinstalling picks the data straight back up.
