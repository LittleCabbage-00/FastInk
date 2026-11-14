; FastInk Windows 安装规则。构建参数由 package_windows.ps1 传入。
#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef AppArchitecture
  #define AppArchitecture "x64"
#endif
#ifndef SourceDir
  #error SourceDir is required
#endif
#ifndef OutputDir
  #error OutputDir is required
#endif
#ifndef OutputBaseName
  #define OutputBaseName "FastInk-Setup"
#endif
#ifndef ChineseMessagesFile
  #error ChineseMessagesFile is required
#endif

[Setup]
AppId={{8B24933E-55FC-4E4B-B8AE-3C58F18A4F93}
AppName=FastInk
AppVersion={#AppVersion}
AppVerName=FastInk {#AppVersion}
AppPublisher=FastInk
DefaultDirName={localappdata}\Programs\FastInk
DefaultGroupName=FastInk
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
#if AppArchitecture == "arm64"
ArchitecturesAllowed=arm64
ArchitecturesInstallIn64BitMode=arm64
#else
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
#endif
MinVersion=10.0.17763
Uninstallable=yes
CreateUninstallRegKey=yes
UninstallDisplayName=FastInk
UninstallDisplayIcon={app}\FastInk.exe
SetupIconFile=..\..\windows\runner\resources\app_icon.ico
OutputDir={#OutputDir}
OutputBaseFilename={#OutputBaseName}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
SetupLogging=yes
CloseApplications=yes
RestartApplications=no
VersionInfoVersion={#AppVersion}
VersionInfoProductName=FastInk
VersionInfoDescription=FastInk 安装程序

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "chinesesimplified"; MessagesFile: "{#ChineseMessagesFile}"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\FastInk"; Filename: "{app}\FastInk.exe"
Name: "{autodesktop}\FastInk"; Filename: "{app}\FastInk.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\FastInk.exe"; Description: "{cm:LaunchProgram,FastInk}"; Flags: nowait postinstall skipifsilent

; 用户资料和设置不属于安装文件，卸载时故意不删除。
