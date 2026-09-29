; Plasmai for Windows: the tray client (ROADMAP pillar 7) as an installer.
; Built by scripts/package-windows.sh (release.yml, job "windows"):
;   iscc /DAppVersion=<version> /DSourceDir=<deployed app> /DOutputDir=<dir> plasmai.iss
;
; Per user, no administrator rights: into %LOCALAPPDATA%\Programs\Plasmai, like the
; app's own data (tokens in the Credential Manager, settings in %LOCALAPPDATA%).
; "Start at login" writes the same Run value as the app's own menu entry
; (app/platform/autostart_win.cpp), so either can switch it off again.

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\..\dist\windows\Plasmai"
#endif
#ifndef OutputDir
  #define OutputDir "..\..\dist\windows"
#endif

[Setup]
AppId={{6C1F5E0B-4E0A-4C2B-9E55-5B0B7C1D2A71}
AppName=Plasmai
AppVersion={#AppVersion}
AppPublisher=shrippen
AppPublisherURL=https://github.com/shrippen/Plasmai
AppSupportURL=https://github.com/shrippen/Plasmai/issues
DefaultDirName={localappdata}\Programs\Plasmai
DefaultGroupName=Plasmai
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir={#OutputDir}
OutputBaseFilename=Plasmai-{#AppVersion}-setup
SetupIconFile=..\..\app\windows\plasmai.ico
UninstallDisplayIcon={app}\plasmai-app.exe
LicenseFile=..\..\LICENSE
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
; An update or uninstall closes the running tray client first (Restart Manager).
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "en"; MessagesFile: "compiler:Default.isl"
Name: "de"; MessagesFile: "compiler:Languages\German.isl"
Name: "fr"; MessagesFile: "compiler:Languages\French.isl"
Name: "es"; MessagesFile: "compiler:Languages\Spanish.isl"
Name: "it"; MessagesFile: "compiler:Languages\Italian.isl"
Name: "nl"; MessagesFile: "compiler:Languages\Dutch.isl"
Name: "pt_BR"; MessagesFile: "compiler:Languages\BrazilianPortuguese.isl"
Name: "pl"; MessagesFile: "compiler:Languages\Polish.isl"
Name: "uk"; MessagesFile: "compiler:Languages\Ukrainian.isl"
Name: "ru"; MessagesFile: "compiler:Languages\Russian.isl"
Name: "ja"; MessagesFile: "compiler:Languages\Japanese.isl"

[CustomMessages]
en.Autostart=Start Plasmai at login
de.Autostart=Plasmai bei der Anmeldung starten
fr.Autostart=Lancer Plasmai à l'ouverture de session
es.Autostart=Iniciar Plasmai al iniciar sesión
it.Autostart=Avvia Plasmai all'accesso
nl.Autostart=Plasmai starten bij aanmelden
pt_BR.Autostart=Iniciar o Plasmai ao entrar
pl.Autostart=Uruchamiaj Plasmai po zalogowaniu
uk.Autostart=Запускати Plasmai під час входу
ru.Autostart=Запускать Plasmai при входе в систему
ja.Autostart=ログイン時に Plasmai を起動

[Tasks]
Name: "autostart"; Description: "{cm:Autostart}"
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Plasmai"; Filename: "{app}\plasmai-app.exe"
Name: "{autodesktop}\Plasmai"; Filename: "{app}\plasmai-app.exe"; Tasks: desktopicon

[Registry]
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "Plasmai"; \
  ValueData: """{app}\plasmai-app.exe"" --hidden"; Tasks: autostart; Flags: uninsdeletevalue
; Switched on later in the app's menu: the uninstaller removes it as well.
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: none; ValueName: "Plasmai"; \
  Flags: uninsdeletevalue

[Run]
Filename: "{app}\plasmai-app.exe"; Description: "{cm:LaunchProgram,Plasmai}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
; Settings and the offline snapshot stay (a reinstall keeps them); the token is in the
; Credential Manager and stays too. Only what the app created next to itself goes.
Type: filesandordirs; Name: "{app}"
