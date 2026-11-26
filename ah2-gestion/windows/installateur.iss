; Installateur Windows d'AH2 Gestion (Inno Setup 6).
; Compilé par GitHub Actions : iscc /DVersion=x.y.z windows\installateur.iss

#ifndef Version
  #define Version "0.0.0"
#endif

[Setup]
AppId=AH2Gestion-AHandToHumanity
AppName=AH2 Gestion
AppVersion={#Version}
AppPublisher=A Hand to Humanity
DefaultDirName={autopf}\AH2 Gestion
DefaultGroupName=AH2 Gestion
OutputDir=..\build\installateur
OutputBaseFilename=AH2-Gestion-Setup-{#Version}
Compression=lzma2
SolidCompression=yes
ArchitecturesInstallIn64BitMode=x64compatible
ArchitecturesAllowed=x64compatible
WizardStyle=modern
SetupIconFile=runner\resources\app_icon.ico
UninstallDisplayIcon={app}\ah2_gestion.exe
; Une mise à jour s'installe par-dessus : les données (dans le profil
; utilisateur, %APPDATA%) ne sont jamais touchées par l'installateur.

[Languages]
Name: "french"; MessagesFile: "compiler:Languages\French.isl"

[Tasks]
Name: "bureau"; Description: "Créer un raccourci sur le Bureau"; GroupDescription: "Raccourcis :"

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\AH2 Gestion"; Filename: "{app}\ah2_gestion.exe"
Name: "{autodesktop}\AH2 Gestion"; Filename: "{app}\ah2_gestion.exe"; Tasks: bureau

[Run]
Filename: "{app}\ah2_gestion.exe"; Description: "Lancer AH2 Gestion"; Flags: nowait postinstall skipifsilent
