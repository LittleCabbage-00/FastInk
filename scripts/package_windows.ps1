# Windows 发行包生成与逐项校验。输出为独立暂存目录、便携 ZIP、校验和及可选安装包；只清理本次拥有的生成位置，不收集用户资料库。
[CmdletBinding()]
param(
  [ValidateSet('x64', 'arm64')][string]$Architecture = ($env:PROCESSOR_ARCHITECTURE -replace '^AMD64$', 'x64'),
  [switch]$SkipBuild,
  [switch]$SkipInstaller,
  [switch]$KeepStaging,
  [switch]$ExternalTools,
  [string]$OutputDirectory,
  [string]$ReleaseDirectory,
  [string]$FlutterPath,
  [string]$InnoCompiler,
  [string]$ToolRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'workspace_paths.ps1')
$config = Import-PowerShellDataFile -LiteralPath (
  Join-Path $projectRoot 'packaging\windows\release_config.psd1'
)
$Architecture = $Architecture.ToLowerInvariant()
$target = "windows-$Architecture"

# 运行打包所需原生命令，失败保留退出码和调用上下文，不把未完成目录当发行包。
function Invoke-CheckedCommand {
  param([string]$Command, [string[]]$Arguments)

  & $Command @Arguments
  if ($LASTEXITCODE -ne 0) {
    throw "Command failed ($LASTEXITCODE): $Command $($Arguments -join ' ')"
  }
}

# 从 pubspec.yaml 读取语义版本与构建号，非法版本直接失败，发行包命名与应用关于页共用同一来源。
function Get-PackageVersion {
  $pubspec = Get-Content -LiteralPath (Join-Path $projectRoot 'pubspec.yaml')
  $versionLine = $pubspec | Where-Object { $_ -match '^version:\s*' } |
    Select-Object -First 1
  if ($versionLine -notmatch '^version:\s*([0-9]+\.[0-9]+\.[0-9]+)(?:\+\d+)?\s*$') {
    throw 'Could not read a three-part version from pubspec.yaml.'
  }
  return $Matches[1]
}

# 解析显式 Flutter 参数、PATH 或本地 SDK 的 flutter.bat，返回可调用路径，不在打包中自动更新 SDK。
function Resolve-FlutterCommand {
  $command = Get-Command flutter -ErrorAction SilentlyContinue
  if ($command) { return $command.Source }

  throw 'Flutter not found. Add Flutter to PATH.'
}

# 查找指定或已安装的 Inno Setup 编译器；按入口约定需要安装时委托安装脚本，不能把路径缺失当安装包已生成。
function Resolve-InnoCompiler {
  if (-not [string]::IsNullOrWhiteSpace($InnoCompiler)) {
    if (-not (Test-Path -LiteralPath $InnoCompiler)) {
      throw "The specified Inno Setup compiler does not exist: $InnoCompiler"
    }
    return (Resolve-Path -LiteralPath $InnoCompiler).Path
  }

  $candidates = @(
    $env:FASTINK_ISCC,
    "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe",
    "$env:ProgramFiles\Inno Setup 6\ISCC.exe",
    "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe"
  ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
  foreach ($candidate in $candidates) {
    if (Test-Path -LiteralPath $candidate) { return $candidate }
  }

  # 首次使用时准备打包工具，其根目录仍可配置。
  $bootstrap = Join-Path $PSScriptRoot 'install_inno_setup.ps1'
  $resolvedToolRoot = if (-not [string]::IsNullOrWhiteSpace($ToolRoot)) {
    $ToolRoot
  } elseif (-not [string]::IsNullOrWhiteSpace($env:FASTINK_TOOL_ROOT)) {
    $env:FASTINK_TOOL_ROOT
  } else {
    ''
  }
  $output = if ($resolvedToolRoot) {
    & $bootstrap -ToolRoot $resolvedToolRoot
  } else {
    & $bootstrap
  }
  return ($output | Select-Object -Last 1)
}

# 定位安装器可使用的中文消息文件；找不到适配文件时明确处理，不把系统代码页猜成源文件编码。
function Resolve-ChineseMessagesFile {
  $language = $config.InnoSetup.ChineseLanguage
  $dependencyRoot = Join-Path $projectRoot 'build\packaging'
  $destination = Join-Path $dependencyRoot $language.FileName
  New-Item -ItemType Directory -Path $dependencyRoot -Force | Out-Null

  $isValid = $false
  if (Test-Path -LiteralPath $destination) {
    $currentHash = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash
    $isValid = $currentHash -eq $language.Sha256
  }
  if (-not $isValid) {
    Write-Host 'Preparing the Simplified Chinese installer messages...'
    Invoke-WebRequest -Uri $language.Url -OutFile $destination
    $downloadedHash = (
      Get-FileHash -LiteralPath $destination -Algorithm SHA256
    ).Hash
    if ($downloadedHash -ne $language.Sha256) {
      Remove-Item -LiteralPath $destination -Force
      throw 'Installer language file checksum verification failed.'
    }
  }
  return $destination
}

# 校验打包暂存目录为项目允许范围内的独立路径，防止清理目标意外指向根目录或个人数据。
function Assert-SafeStagingPath {
  param([string]$Path, [string]$StagingRoot)

  $fullPath = [IO.Path]::GetFullPath($Path)
  $fullRoot = [IO.Path]::GetFullPath($StagingRoot).TrimEnd('\') + '\'
  if (-not $fullPath.StartsWith($fullRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to clean a path outside the staging directory: $fullPath"
  }
}

# 把受支持的 Release 内容复制到本次暂存目录，检查隐私数据和开发产物排除规则，源程序目录不改写。
function Copy-ReleaseBundle {
  param([string]$Source, [string]$Destination)

  New-Item -ItemType Directory -Path $Destination -Force | Out-Null

  # 只复制运行所需文件；即使本地启动过发布目录中的程序，
  # 也不能把本地设置或文稿资料库带进公开安装包。
  Get-ChildItem -LiteralPath $Source -File |
    Where-Object {
      $_.Name -eq $config.ExecutableName -or $_.Extension -eq '.dll' -or
      $_.Name -in @('native_assets.json', 'BUILD-INFO.json')
    } |
    ForEach-Object {
      Assert-NoBundleLinks $_.FullName
      Copy-Item -LiteralPath $_.FullName -Destination $Destination -Force
    }

  $dataDestination = Join-Path $Destination 'data'
  New-Item -ItemType Directory -Path $dataDestination -Force | Out-Null
  foreach ($entry in @('app.so', 'icudtl.dat', 'flutter_assets')) {
    $sourceEntry = Join-Path (Join-Path $Source 'data') $entry
    if (-not (Test-Path -LiteralPath $sourceEntry)) {
      throw "Release runtime file is missing: $sourceEntry"
    }
    Assert-NoBundleLinks $sourceEntry
    Copy-Item -LiteralPath $sourceEntry -Destination $dataDestination `
      -Recurse -Force
  }

  $toolsSource = Join-Path $Source 'tools'
  if (Test-Path -LiteralPath $toolsSource) {
    Assert-NoBundleLinks $toolsSource
    if ($ExternalTools) {
      $destinationTools = Join-Path $Destination 'tools'
      New-Item -ItemType Directory -Path $destinationTools -Force | Out-Null
      Copy-Item -LiteralPath (Join-Path $toolsSource 'onenote') -Destination $destinationTools -Recurse
      $markdownTools = Join-Path $destinationTools 'markdown'
      New-Item -ItemType Directory -Path $markdownTools -Force | Out-Null
      Get-ChildItem -LiteralPath (Join-Path $toolsSource 'markdown') -File |
        Where-Object { $_.Name -ne 'mermaid.min.js' } |
        Copy-Item -Destination $markdownTools
    } else {
      Copy-Item -LiteralPath $toolsSource -Destination $Destination -Recurse -Force
    }
  }
}

# 检查包目录不含可逃离打包根范围的符号链接/目录联接；OneDrive 云重解析点不等同于文件系统跳转链接。
function Assert-NoBundleLinks {
  param([string]$Path)
  $rootItem = Get-Item -LiteralPath $Path -Force
  $items = @($rootItem)
  if ($rootItem.PSIsContainer) { $items += @(Get-ChildItem -LiteralPath $Path -Recurse -Force) }
  foreach ($item in $items) {
    # 云占位符并非目录重定向，仍拒绝真实符号链接和目录联接。
    if ($item.LinkType -in @('SymbolicLink','Junction')) {
      throw "Runtime resources contain a link; use regular local files: $($item.FullName)"
    }
  }
}

$version = Get-PackageVersion
$releaseDirectory = if ($ReleaseDirectory) {
  (Resolve-Path -LiteralPath $ReleaseDirectory).Path
} else {
  Join-Path $projectRoot "build/windows/$Architecture/runner/Release"
}
$stagingRoot = Join-Path $projectRoot ('build\packages\package-' + [guid]::NewGuid().ToString('N'))
$outputRoot = if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
  Join-Path $projectRoot 'dist'
} else {
  $hostDart = Get-FastInkPeArchitecture (Join-Path (Split-Path -Parent $flutter) 'cache/dart-sdk/bin/dart.exe')
  if ($hostDart -ne $Architecture) { throw "Building $target requires the $Architecture Flutter SDK." }
  [IO.Path]::GetFullPath($OutputDirectory)
}

$flutter = if ($FlutterPath) { (Resolve-Path -LiteralPath $FlutterPath).Path } else { Resolve-FlutterCommand }
$dart = Join-Path (Split-Path -Parent $flutter) 'dart.bat'
$versionGenerator = Join-Path $projectRoot 'scripts\sync_app_version.dart'
if ($SkipBuild) {
  Invoke-CheckedCommand $dart @($versionGenerator, '--check')
} else {
  Invoke-CheckedCommand $dart @($versionGenerator)
  Push-Location -LiteralPath $projectRoot
  try { Invoke-CheckedCommand $flutter @('build', 'windows', '--release', '--no-pub') }
  finally { Pop-Location }
}

$requiredFiles = @(
  (Join-Path $releaseDirectory $config.ExecutableName),
  (Join-Path $releaseDirectory 'flutter_windows.dll'),
  (Join-Path $releaseDirectory 'data\app.so'),
  (Join-Path $releaseDirectory 'data\icudtl.dat'),
  (Join-Path $releaseDirectory 'data\flutter_assets\AssetManifest.bin')
)
foreach ($required in $requiredFiles) {
  if (-not (Test-Path -LiteralPath $required)) {
    throw "Release directory is incomplete; missing: $required"
  }
}
foreach ($binary in @($config.ExecutableName, 'flutter_windows.dll')) {
  $machine = Get-FastInkPeArchitecture (Join-Path $releaseDirectory $binary)
  if ($machine -ne $Architecture) { throw "$binary targets $machine. Expected $Architecture." }
}

New-Item -ItemType Directory -Path $stagingRoot -Force | Out-Null
New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null

$portableBaseName = '{0}-{1}-{2}-portable' -f `
  $config.ProductName, $version, $target
$runtimeBaseName = '{0}-{1}-{2}-runtime' -f `
  $config.ProductName, $version, $target
$runtimeDirectory = Join-Path $stagingRoot $runtimeBaseName
$portableDirectory = Join-Path $stagingRoot $portableBaseName
Assert-SafeStagingPath $runtimeDirectory $stagingRoot
Assert-SafeStagingPath $portableDirectory $stagingRoot
if (Test-Path -LiteralPath $runtimeDirectory) {
  Remove-FastInkGeneratedPath $runtimeDirectory | Out-Null
}
if (Test-Path -LiteralPath $portableDirectory) {
  Remove-FastInkGeneratedPath $portableDirectory | Out-Null
}
Copy-ReleaseBundle $releaseDirectory $runtimeDirectory
if ($ExternalTools) {
  foreach ($name in @('LICENSE','FLUTTER-LICENSE','THIRD_PARTY_NOTICES.md')) {
    Copy-Item -LiteralPath (Join-Path $projectRoot $name) -Destination $runtimeDirectory
  }
  Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'setup_windows_tools.ps1') -Destination $runtimeDirectory
}
New-Item -ItemType Directory -Path $portableDirectory | Out-Null
Copy-Item -Path (Join-Path $runtimeDirectory '*') `
  -Destination $portableDirectory -Recurse -Force
Set-Content -LiteralPath (
  Join-Path $portableDirectory $config.PortableMarkerName
) -Value 'FastInk portable mode' -Encoding ascii

$portableArchive = Join-Path $outputRoot "$portableBaseName.zip"
$temporaryArchive = Join-Path $outputRoot (".$portableBaseName-" + [guid]::NewGuid().ToString('N') + '.zip.tmp')
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
try {
  # .NET Framework (Windows PowerShell 5.1) can emit backslash ZIP names.
  # 在两种 PowerShell 运行时中均显式使用正斜杠 ZIP 成员名。
  $zipWriter = [IO.Compression.ZipFile]::Open($temporaryArchive, [IO.Compression.ZipArchiveMode]::Create)
  try {
    foreach ($file in (Get-ChildItem -LiteralPath $portableDirectory -File -Recurse -Force)) {
      $relative = $file.FullName.Substring($portableDirectory.Length).TrimStart('\', '/').Replace('\', '/')
      [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zipWriter, $file.FullName,
        "$portableBaseName/$relative", [IO.Compression.CompressionLevel]::Optimal) | Out-Null
    }
  } finally { $zipWriter.Dispose() }
  $archive = [IO.Compression.ZipFile]::OpenRead($temporaryArchive)
  try {
    $expectedFiles = @(Get-ChildItem -LiteralPath $portableDirectory -File -Recurse -Force)
    $fileEntries = @($archive.Entries | Where-Object { -not $_.FullName.EndsWith('/') })
    if ($fileEntries.Count -ne $expectedFiles.Count) { throw 'ZIP file count mismatch.' }
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
      foreach ($entry in $fileEntries) {
        $entryName = $entry.FullName.Replace('\', '/')
        if ($entryName -match '(^|/)(FastInkData|\.fastink|\.fastink-config-root)(/|$)') {
          throw "ZIP contains personal data: $($entry.FullName)"
        }
        $stream = $entry.Open()
        try { $actual = ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-', '') }
        finally { $stream.Dispose() }
        $expectedPath = Join-Path $stagingRoot $entryName.Replace('/', '\')
        if ($actual -ne (Get-FileHash -LiteralPath $expectedPath -Algorithm SHA256).Hash) {
          throw "ZIP content mismatch: $($entry.FullName)"
        }
      }
    } finally { $sha.Dispose() }
    if ($null -eq $archive.GetEntry("$portableBaseName/$($config.PortableMarkerName)")) {
      throw 'Portable marker is missing from ZIP.'
    }
  } finally { $archive.Dispose() }
  Move-Item -LiteralPath $temporaryArchive -Destination $portableArchive -Force
} finally {
  if (Test-Path -LiteralPath $temporaryArchive) { Remove-Item -LiteralPath $temporaryArchive -Force }
}

$artifacts = [Collections.Generic.List[string]]::new()
$artifacts.Add($portableArchive)

if (-not $SkipInstaller) {
  $compiler = Resolve-InnoCompiler
  $chineseMessages = Resolve-ChineseMessagesFile
  $setupBaseName = '{0}-{1}-{2}-setup' -f `
    $config.ProductName, $version, $target
  $iss = Join-Path $projectRoot 'packaging\windows\FastInk.iss'
  Invoke-CheckedCommand $compiler @(
    "/DAppVersion=$version",
    "/DAppArchitecture=$Architecture",
    "/DSourceDir=$runtimeDirectory",
    "/DOutputDir=$outputRoot",
    "/DOutputBaseName=$setupBaseName",
    "/DChineseMessagesFile=$chineseMessages",
    $iss
  )
  $setup = Join-Path $outputRoot "$setupBaseName.exe"
  if (-not (Test-Path -LiteralPath $setup)) {
    throw "Installer was not generated: $setup"
  }
  $artifacts.Add($setup)
}

$checksumPath = Join-Path $outputRoot (
  '{0}-{1}-{2}-SHA256SUMS.txt' -f $config.ProductName, $version, $target
)
$checksumLines = foreach ($artifact in $artifacts) {
  $hash = Get-FileHash -LiteralPath $artifact -Algorithm SHA256
  '{0}  {1}' -f $hash.Hash.ToLowerInvariant(), (Split-Path $artifact -Leaf)
}
Set-Content -LiteralPath $checksumPath -Value $checksumLines -Encoding ascii
$artifacts.Add($checksumPath)

if (-not $KeepStaging) {
  Assert-SafeStagingPath $portableDirectory $stagingRoot
  Remove-FastInkGeneratedPath $portableDirectory | Out-Null
  Assert-SafeStagingPath $runtimeDirectory $stagingRoot
  Remove-FastInkGeneratedPath $runtimeDirectory | Out-Null
  Remove-FastInkGeneratedPath $stagingRoot | Out-Null
}

Write-Host ''
Write-Host 'Windows release packages generated:'
$artifacts | ForEach-Object { Write-Host "  $_" }
