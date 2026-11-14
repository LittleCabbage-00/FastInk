# 内部构建实现：解析 SDK/工具链、检查启动器兼容性、编译并交给打包脚本。应由 build.ps1 调用，不能直接绕过资源保护。
[CmdletBinding()]
param(
  [ValidateSet('Auto', 'Native', 'FlutterOnly')]
  [string]$Mode = 'Auto',
  [ValidateSet('x64', 'arm64')][string]$Architecture = ($env:PROCESSOR_ARCHITECTURE -replace '^AMD64$', 'x64'),
  [string]$FlutterPath,
  [string]$LauncherDirectory,
  [string]$OutputDirectory,
  [switch]$Installer,
  [switch]$RunTests,
  [switch]$KeepStaging,
  [int]$CompilerHeapMB = 1024
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'workspace_paths.ps1')

# 执行指定命令并检查原生退出码，非零立即向上抛错，避免失败后继续打包。Command 是已解析程序路径，Arguments 为逐项参数。
function Invoke-Checked {
  param([string]$Command, [string[]]$Arguments)
  & $Command @Arguments
  if ($LASTEXITCODE -ne 0) { throw "Command failed ($LASTEXITCODE): $Command" }
}

# 优先使用显式 FlutterPath，再查询 PATH。
function Find-Flutter {
  if ($FlutterPath) { return (Resolve-Path -LiteralPath $FlutterPath).Path }
  $command = Get-Command flutter -ErrorAction SilentlyContinue
  if ($command) { return $command.Source }
  throw 'Flutter not found. Add it to PATH or pass -FlutterPath <flutter.bat>.'
}

# 只读查询 Visual Studio C++ 与 CMake 是否可用，返回布尔值供 Auto 选择构建模式，不安装工具链。
function Test-NativeToolchain {
  $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
  if (-not (Test-Path -LiteralPath $vswhere)) { return $false }
  $compilerComponent = if ($Architecture -eq 'arm64') {
    'Microsoft.VisualStudio.Component.VC.Tools.ARM64'
  } else {
    'Microsoft.VisualStudio.Component.VC.Tools.x86.x64'
  }
  $installation = & $vswhere -latest -products '*' -requires $compilerComponent `
    Microsoft.VisualStudio.Component.VC.CMake.Project -property installationPath
  return ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace(($installation -join '')))
}

# 对原生启动器相关源文件计算稳定指纹，防止源实现变化后误复用旧 EXE；代码注释变更也会影响当前原始文件指纹。
function Get-NativeFingerprint {
  $paths = @('windows\runner', 'windows\CMakeLists.txt',
    'windows\flutter\CMakeLists.txt', 'windows\flutter\generated_plugins.cmake',
    'windows\flutter\generated_plugin_registrant.cc', 'windows\flutter\generated_plugin_registrant.h')
  $lines = foreach ($path in $paths) {
    $item = Get-Item -LiteralPath (Join-Path $projectRoot $path)
    $files = if ($item.PSIsContainer) { Get-ChildItem -LiteralPath $item.FullName -File -Recurse } else { @($item) }
    foreach ($file in ($files | Sort-Object FullName)) {
      $relative = $file.FullName.Substring($projectRoot.Length).Replace('\', '/')
      "$relative $((Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash)"
    }
  }
  $sha = [Security.Cryptography.SHA256]::Create()
  try { return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes(($lines -join "`n"))))).Replace('-', '').ToLowerInvariant() }
  finally { $sha.Dispose() }
}

# 按显式位置、启动器缓存与既有包目录查找兼容原生启动器，校验 Flutter 引擎 DLL，不递归扫描个人资料库。
function Find-Launcher {
  param([string]$EngineDll)
  $candidates = [Collections.Generic.List[string]]::new()
  if ($LauncherDirectory) {
    $candidates.Add((Resolve-Path -LiteralPath $LauncherDirectory).Path)
  } else {
    $candidates.Add($cache)
    $candidates.Add($nativeRelease)
    # 只检查程序包目录，绝不递归扫描用户资料库。
    foreach ($parent in @('dist', 'build\packages')) {
      $directory = Join-Path $projectRoot $parent
      if (-not (Test-Path -LiteralPath $directory)) { continue }
      foreach ($child in (Get-ChildItem -LiteralPath $directory -Directory | Sort-Object LastWriteTime -Descending)) {
        $candidates.Add($child.FullName)
        foreach ($nested in (Get-ChildItem -LiteralPath $child.FullName -Directory)) {
          if ($nested.Name -like 'FastInk*') { $candidates.Add($nested.FullName) }
        }
      }
    }
  }
  $engineHash = (Get-FileHash -LiteralPath $EngineDll -Algorithm SHA256).Hash
  foreach ($candidate in $candidates) {
    $exe = Join-Path $candidate 'FastInk.exe'
    $dll = Join-Path $candidate 'flutter_windows.dll'
    if ((Test-Path -LiteralPath $exe) -and (Test-Path -LiteralPath $dll)) {
      if ((Get-FastInkPeArchitecture $exe) -eq $Architecture -and
          (Get-FileHash -LiteralPath $dll -Algorithm SHA256).Hash -eq $engineHash) { return $candidate }
    }
  }
  throw 'No compatible FastInk launcher found. Run -Mode Native once, or pass -LauncherDirectory <matching Windows bundle>.'
}

$flutter = Find-Flutter
$flutterBin = Split-Path -Parent $flutter
$dart = Join-Path $flutterBin 'dart.bat'
$sdk = Split-Path -Parent $flutterBin
$Architecture = $Architecture.ToLowerInvariant()
$target = "windows-$Architecture"
$hostDart = Get-FastInkPeArchitecture (Join-Path $flutterBin 'cache/dart-sdk/bin/dart.exe')
if ($hostDart -ne $Architecture) {
  throw "Flutter uses a $hostDart Dart SDK. Build $target with the $Architecture Windows Flutter SDK and toolchain."
}
$nativeRelease = Join-Path $projectRoot "build/windows/$Architecture/runner/Release"
$launcherCache = Join-Path $projectRoot 'build/windows-launcher'
$cache = if ($Architecture -eq 'arm64') { Join-Path $launcherCache 'arm64' } else { $launcherCache }
$env:FASTINK_COMPILER_HEAP_MB = [string]$CompilerHeapMB
$env:CMAKE_BUILD_PARALLEL_LEVEL = '1'
$env:MSBUILDDISABLENODEREUSE = '1'
$env:FLUTTER_SUPPRESS_ANALYTICS = 'true'
$env:DART_SUPPRESS_ANALYTICS = 'true'
$frontend = Join-Path $projectRoot 'scripts/low_memory_frontend.dart'
$genOptions = "--old_gen_heap_size=$CompilerHeapMB"
$env:FRONTEND_SERVER_STARTER_PATH = $frontend

Push-Location -LiteralPath $projectRoot
try {
  Invoke-Checked $dart @('scripts/sync_app_version.dart')
  Invoke-Checked $flutter @('pub', 'get')
  if ($RunTests) {
    Invoke-Checked $dart @('analyze', '--fatal-infos')
    # 仅清理可再生成的测试资源，不再逐次累积 previous 备份目录。
    Remove-FastInkGeneratedPath (Join-Path $projectRoot 'build/unit_test_assets') | Out-Null
    Invoke-Checked $flutter @('test', '--no-pub', '--concurrency=1', '--reporter=expanded', '--no-track-widget-creation', "--frontend-server-starter-path=$frontend")
  }
  if ($Mode -eq 'Auto') {
    if (Test-NativeToolchain) { $Mode = 'Native' } else { $Mode = 'FlutterOnly' }
  }
  Write-Host "Build mode: $Mode"
  $nativeFingerprint = Get-NativeFingerprint
  $cacheInfoPath = Join-Path $cache 'launcher-info.json'
  $temporaryRelease = $null
  if ($Mode -eq 'Native') {
    Invoke-Checked $flutter @('build', 'windows', '--release', '--no-pub', "--extra-gen-snapshot-options=$genOptions")
    $release = $nativeRelease
  } else {
    $plugins = Get-Content -LiteralPath 'windows/flutter/generated_plugins.cmake' -Raw
    foreach ($match in [regex]::Matches($plugins, 'list\(APPEND FLUTTER_(?:FFI_)?PLUGIN_LIST\s*([^)]*)\)')) {
      if ($match.Groups[1].Value.Trim()) { throw 'Native plugins require -Mode Native. FlutterOnly cannot rebuild plugin DLLs.' }
    }
    $engineDll = Join-Path $sdk "bin/cache/artifacts/engine/$target-release/flutter_windows.dll"
    $launcher = Find-Launcher $engineDll
    if (Test-Path -LiteralPath $cacheInfoPath) {
      $cacheInfo = Get-Content -LiteralPath $cacheInfoPath -Raw | ConvertFrom-Json
      if ($cacheInfo.nativeFingerprint -ne $nativeFingerprint) {
        throw 'Windows native sources changed since the launcher was cached. Rebuild with -Mode Native.'
      }
    }
    Write-Warning "Reusing native launcher: $launcher. Dart and assets are rebuilt; EXE file version metadata is retained."
    $assemblyRoot = Join-Path $projectRoot 'build/windows-script'
    $assembled = if ($Architecture -eq 'arm64') { Join-Path $assemblyRoot 'arm64' } else { $assemblyRoot }
    Invoke-Checked $flutter @('assemble', '--resource-pool-size=1', "--output=$assembled/", "-dTargetPlatform=$target",
      '-dBuildMode=release', '-dTargetFile=lib/main.dart', "-dExtraGenSnapshotOptions=$genOptions", "-dFrontendServerStarterPath=$frontend", "release_bundle_${target}_assets")
    $nativeAssetFiles = @(Get-ChildItem -LiteralPath (Join-Path $assembled 'native_assets') -File -Recurse -ErrorAction SilentlyContinue)
    $launcherManifest = Join-Path $launcher 'native_assets.json'
    $launcherAssets = if (Test-Path -LiteralPath $launcherManifest) {
      (Get-Content -LiteralPath $launcherManifest -Raw | ConvertFrom-Json).'native-assets'
    }
    if ($nativeAssetFiles.Count -gt 0 -or ($launcherAssets -and @($launcherAssets.PSObject.Properties).Count -gt 0)) {
      throw 'Dart native asset hooks require -Mode Native so their libraries are bundled correctly.'
    }
    # 每次打包创建全新目录，避免带入旧资源或个人文件。
    $release = Join-Path $projectRoot ("build\script-runs\" + [guid]::NewGuid().ToString('N'))
    $temporaryRelease = $release
    New-Item -ItemType Directory -Path (Join-Path $release 'data') -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $launcher 'FastInk.exe') -Destination $release
    Copy-Item -LiteralPath $engineDll -Destination $release
    Copy-Item -LiteralPath (Join-Path $sdk "bin/cache/artifacts/engine/$target/icudtl.dat") -Destination (Join-Path $release 'data')
    Copy-Item -LiteralPath (Join-Path $assembled 'windows\app.so') -Destination (Join-Path $release 'data')
    Copy-Item -LiteralPath (Join-Path $assembled 'flutter_assets') -Destination (Join-Path $release 'data') -Recurse
    if (Test-Path -LiteralPath $launcherManifest) {
      Copy-Item -LiteralPath $launcherManifest -Destination $release
    }
  }
  # Poppler 程序、DLL、数据与许可证一同分发。
  if (-not (Test-Path -LiteralPath (Join-Path $release 'tools\poppler\pdfinfo.exe'))) {
    Copy-Item -LiteralPath (Join-Path $projectRoot 'windows\tools') -Destination $release -Recurse
  }
  if (-not (Test-Path -LiteralPath (Join-Path $release 'tools\qpdf\qpdf.exe'))) {
    $qpdfTools = Join-Path $projectRoot 'windows\tools\qpdf'
    if (-not (Test-Path -LiteralPath (Join-Path $qpdfTools 'qpdf.exe'))) {
      throw 'Fast PDF export tools are missing: windows\tools\qpdf.'
    }
    New-Item -ItemType Directory -Path (Join-Path $release 'tools') -Force | Out-Null
    Copy-Item -LiteralPath $qpdfTools -Destination (Join-Path $release 'tools') -Recurse
  }
    $oneNoteTools = Join-Path $projectRoot 'windows\tools\onenote'
    New-Item -ItemType Directory -Path (Join-Path $release 'tools') -Force | Out-Null
    Copy-Item -LiteralPath $oneNoteTools -Destination (Join-Path $release 'tools') -Recurse -Force
    Copy-Item -LiteralPath (Join-Path $projectRoot 'windows\tools\markdown') -Destination (Join-Path $release 'tools') -Recurse -Force
    $info = [ordered]@{
    version = (Select-String -LiteralPath 'pubspec.yaml' -Pattern '^version:\s*(.+)$').Matches[0].Groups[1].Value.Trim()
    architecture = $Architecture
    mode = $Mode
    nativeLauncherReused = ($Mode -eq 'FlutterOnly')
    nativeFingerprint = $nativeFingerprint
    builtAtUtc = [DateTime]::UtcNow.ToString('o')
  }
  $info | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $release 'BUILD-INFO.json') -Encoding UTF8
  $packageArgs = @{
    SkipBuild = $true; SkipInstaller = (-not $Installer.IsPresent)
    KeepStaging = $KeepStaging; ReleaseDirectory = $release; FlutterPath = $flutter
    Architecture = $Architecture
  }
  if ($OutputDirectory) { $packageArgs.OutputDirectory = $OutputDirectory }
  & (Join-Path $projectRoot 'scripts\package_windows.ps1') @packageArgs
  # 只缓存启动器，不缓存应用数据；用指纹校验后续复用。
  New-Item -ItemType Directory -Path $cache -Force | Out-Null
  foreach ($name in @('FastInk.exe', 'flutter_windows.dll', 'native_assets.json')) {
    $source = Join-Path $release $name
    if ((Test-Path -LiteralPath $source) -and
        [IO.Path]::GetFullPath($source) -ne [IO.Path]::GetFullPath((Join-Path $cache $name))) {
      Copy-Item -LiteralPath $source -Destination $cache -Force
    }
  }
  if (-not (Test-Path -LiteralPath (Join-Path $release 'native_assets.json'))) {
    $cachedManifest = Join-Path $cache 'native_assets.json'
    if (Test-Path -LiteralPath $cachedManifest) { Remove-Item -LiteralPath $cachedManifest }
  }
  $info | ConvertTo-Json | Set-Content -LiteralPath $cacheInfoPath -Encoding UTF8
  if ($temporaryRelease -and -not $KeepStaging) {
    $resolvedRelease = (Resolve-Path -LiteralPath $temporaryRelease).Path
    $runRoot = [IO.Path]::GetFullPath((Join-Path $projectRoot 'build\script-runs')).TrimEnd('\') + '\'
    if (-not $resolvedRelease.StartsWith($runRoot, [StringComparison]::OrdinalIgnoreCase)) {
      throw "Refusing to clean outside the build run directory: $resolvedRelease"
    }
    Remove-FastInkGeneratedPath $resolvedRelease | Out-Null
  }
} finally {
  Pop-Location
}
