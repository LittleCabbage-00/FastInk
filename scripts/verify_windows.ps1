# 校验当前 pubspec 版本的发行包：核对路径、私有数据排除、工具和 AOT 哈希，再用自有隐藏进程验证启动。SkipLaunch 仅跳过启动，不能写成已实测启动成功。只结束本脚本启动的进程。
[CmdletBinding()]
param(
  [ValidateSet('x64', 'arm64')][string]$Architecture = ($env:PROCESSOR_ARCHITECTURE -replace '^AMD64$', 'x64'),
  [switch]$Installer,
  [switch]$SkipLaunch
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
. (Join-Path $PSScriptRoot 'workspace_paths.ps1')
$projectRoot=$script:FastInkWorkspace
$match=[regex]::Match((Get-Content -LiteralPath (Join-Path $projectRoot 'pubspec.yaml') -Raw), '(?m)^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$')
if(-not $match.Success) {throw 'Cannot read the application version'}
$version=$match.Groups[1].Value; $fullVersion=$version+'+'+$match.Groups[2].Value
$Architecture=$Architecture.ToLowerInvariant()
$target="windows-$Architecture"
$bundle="FastInk-$version-$target-portable"
$package=Join-Path $projectRoot "dist/$bundle.zip"
$checksums=Get-Content -LiteralPath (Join-Path $projectRoot "dist/FastInk-$version-$target-SHA256SUMS.txt")
$reports=Join-Path $projectRoot 'build/reports'
New-Item -ItemType Directory -Path $reports -Force | Out-Null
# 计算 ZIP 指定条目内容的 SHA-256，读取完成后释放条目流与哈希对象；不为校验而覆盖本地文件。
function Get-ArchiveHash($Entry) {
  $stream=$Entry.Open(); $hash=[Security.Cryptography.SHA256]::Create()
  try {return [BitConverter]::ToString($hash.ComputeHash($stream)).Replace('-','')}
  finally {$stream.Dispose(); $hash.Dispose()}
}

# 同时匹配摘要与文件名，防止把同一清单的另一项当作当前文件。
function Get-VerifiedHash([string]$Path) {
  $hash=(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
  if ($checksums -notcontains "$hash  $(Split-Path -Leaf $Path)") {
    throw "SHA256 mismatch: $Path"
  }
  return $hash
}

# 在 CI 的临时目录试装和卸载。用便携包校验过的文件对照安装内容。
function Test-Installer([string]$Setup, [string]$Destination, [string]$Portable) {
  $uninstallKey='Software\Microsoft\Windows\CurrentVersion\Uninstall\{8B24933E-55FC-4E4B-B8AE-3C58F18A4F93}_is1'
  if ((Test-Path -LiteralPath "HKCU:\$uninstallKey") -or (Test-Path -LiteralPath "HKLM:\$uninstallKey")) {
    throw 'FastInk is already installed. Run the install test on a clean Windows runner.'
  }
  $installLog=Join-Path $reports "install-$version-$target.log"
  $uninstallLog=Join-Path $reports "uninstall-$version-$target.log"
  try {
    $process=Start-Process -FilePath $Setup -ArgumentList @(
      '/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART','/NOICONS','/NOCLOSEAPPLICATIONS',
      "/DIR=`"$Destination`"","/LOG=`"$installLog`""
    ) -WindowStyle Hidden -Wait -PassThru
    if ($process.ExitCode -ne 0) {throw "Installer exited with $($process.ExitCode). See $installLog"}
    foreach ($file in Get-ChildItem -LiteralPath $Portable -File -Recurse -Force) {
      $relative=$file.FullName.Substring($Portable.Length+1)
      if ($relative -eq '.fastink-portable') {continue}
      $installed=Join-Path $Destination $relative
      if ((Get-FileHash -LiteralPath $installed).Hash -ne (Get-FileHash -LiteralPath $file.FullName).Hash) {
        throw "Installed content differs: $relative"
      }
    }
    if (Test-Path -LiteralPath (Join-Path $Destination '.fastink-portable')) {
      throw 'The installer contains the portable marker'
    }
  } finally {
    $uninstaller=Join-Path $Destination 'unins000.exe'
    if (Test-Path -LiteralPath $uninstaller) {
      $process=Start-Process -FilePath $uninstaller -ArgumentList @(
        '/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART',"/LOG=`"$uninstallLog`""
      ) -WindowStyle Hidden -Wait -PassThru
      if ($process.ExitCode -ne 0 -or (Test-Path -LiteralPath (Join-Path $Destination 'FastInk.exe'))) {
        throw "Installer cleanup failed. See $uninstallLog"
      }
    }
  }
}

$setupHash=$null
if ($Installer) {
  $setup=Join-Path $projectRoot "dist/FastInk-$version-$target-setup.exe"
  $setupHash=Get-VerifiedHash $setup
}
$archive=[IO.Compression.ZipFile]::OpenRead($package)
try {
  $names=@($archive.Entries | ForEach-Object {$_.FullName})
  if($names -match 'FastInkData|settings.json|\.reference|msyh\.ttc|segoeui\.ttf|/scripts/|/test/|\.dart_tool') {
    throw 'Unexpected private data or development artifact in the package'
  }
  if(-not ($names -match '/\.fastink-portable$')) {throw 'Portable marker missing'}
  if($names | Where-Object {$_.Contains('\') -or $_.StartsWith('/') -or $_.Split('/') -contains '..'}) {throw 'Invalid ZIP path'}
  $infoReader=[IO.StreamReader]::new($archive.GetEntry("$bundle/BUILD-INFO.json").Open())
  try {$info=$infoReader.ReadToEnd() | ConvertFrom-Json} finally {$infoReader.Dispose()}
  if($info.version -ne $fullVersion -or $info.architecture -ne $Architecture) {throw 'Build version or architecture mismatch'}
  $aot=@($archive.Entries | Where-Object {$_.FullName.EndsWith('/data/app.so')})
  if($aot.Count -ne 1) {throw 'Wrong AOT entry count'}
  $compiledPath=if($info.mode -eq 'Native') {
    "build/windows/$Architecture/runner/Release/data/app.so"
  } elseif($Architecture -eq 'arm64') {
    'build/windows-script/arm64/windows/app.so'
  } else {
    'build/windows-script/windows/app.so'
  }
  $compiled=(Get-FileHash -LiteralPath (Join-Path $projectRoot $compiledPath) -Algorithm SHA256).Hash
  if((Get-ArchiveHash $aot[0]) -ne $compiled) {throw 'Packaged AOT differs from the current compiled application'}
  $components=@('onenote/import.ps1','markdown/MERMAID-LICENSE.txt',
      'markdown/render_diagram.ps1','markdown/ResourceJob.cs','markdown/README.txt',
      'markdown/mermaid.min.js','poppler/pdfinfo.exe','qpdf/qpdf.exe','qpdf/qpdf30.dll')
  $requiredFiles=@('LICENSE','FLUTTER-LICENSE','THIRD_PARTY_NOTICES.md','msvcp140.dll','vcruntime140.dll')
  if($Architecture -eq 'x64') {$requiredFiles+='vcruntime140_1.dll'}
  foreach($file in $requiredFiles) {
    if(-not $archive.GetEntry("$bundle/$file")) {throw "Missing license or app-local runtime: $file"}
  }
  foreach($component in $components) {
    $entry=@($archive.Entries | Where-Object {$_.FullName.EndsWith('/tools/'+$component)})
    if($entry.Count -ne 1) {throw "Runtime component missing: $component"}
    $source=Join-Path $projectRoot ('windows/tools/'+$component)
    if((Get-ArchiveHash $entry[0]) -ne (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash) {
      throw "Stale runtime component: $component"
    }
  }
  $sum=Get-VerifiedHash $package
} finally {$archive.Dispose()}
$verify=Join-Path $projectRoot ('build/verify-'+[guid]::NewGuid().ToString('N'))
$smoke=$null
try {
  [IO.Compression.ZipFile]::ExtractToDirectory($package,$verify)
  $runtime=Join-Path $verify $bundle
  if ($Installer -and -not $SkipLaunch) {
    Test-Installer $setup (Join-Path $verify 'installed') $runtime
  }
  foreach($binary in @('FastInk.exe','flutter_windows.dll')) {
    if((Get-FastInkPeArchitecture (Join-Path $runtime $binary)) -ne $Architecture) {throw "Architecture mismatch: $binary"}
  }
  $aotReader=[IO.BinaryReader]::new([IO.File]::OpenRead((Join-Path $runtime 'data/app.so')))
  try {
    if ($aotReader.ReadUInt32() -ne 0x464c457f -or $aotReader.ReadUInt16() -ne 0x0102) {throw 'Invalid 64-bit Dart AOT header'}
    $aotReader.BaseStream.Position=18
    $machine=if($Architecture -eq 'arm64') {183} else {62}
    if($aotReader.ReadUInt16() -ne $machine) {throw 'Dart AOT architecture mismatch'}
  } finally {$aotReader.Dispose()}
  if(-not $SkipLaunch) {
    $qpdf=& (Join-Path $runtime 'tools/qpdf/qpdf.exe') --version
    if($LASTEXITCODE -ne 0 -or ($qpdf -join '') -notmatch '12.4.2') {throw 'Packaged qpdf cannot start'}
    # pdfinfo -v 将版本打印到 stderr，使用进程退出码核对能否加载。
    $pdfInfo=Start-Process -FilePath (Join-Path $runtime 'tools/poppler/pdfinfo.exe') -ArgumentList '-v' -WindowStyle Hidden -Wait -PassThru
    if($pdfInfo.ExitCode -ne 0) {throw 'Packaged pdfinfo cannot start'}
    $stdout=Join-Path $reports "smoke-$version-$target-stdout.log"
    $stderr=Join-Path $reports "smoke-$version-$target-stderr.log"
    # 只启动并关闭本脚本创建的隐藏进程，不枚举或结束用户的窗口。
    $smoke=Start-Process -FilePath (Join-Path $runtime 'FastInk.exe') -WorkingDirectory $runtime `
      -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
    Start-Sleep -Seconds 6
    $smoke.Refresh()
    if($smoke.HasExited) {throw "Packaged app exited: $($smoke.ExitCode)"}
    if((Get-Item -LiteralPath $stderr).Length -gt 0) {throw 'The app reported startup errors'}
  }
  @{version=$fullVersion; architecture=$Architecture; zip=$package; sha256=$sum; startupVerified=(-not $SkipLaunch.IsPresent)
    installerSha256=$setupHash; installationVerified=($Installer.IsPresent -and -not $SkipLaunch.IsPresent)} |
    ConvertTo-Json | Set-Content -LiteralPath (Join-Path $reports "verify-$version-$target.json") -Encoding UTF8
  Write-Output "PASS: $fullVersion $target ZIP, runtime components, compiled AOT, SHA256 and requested startup checks."
} finally {
  if($smoke -and -not $smoke.HasExited) {
    $smoke.Kill()
    if(-not $smoke.WaitForExit(5000)) {throw 'The owned smoke process is still exiting; kept its directory.'}
  }
  # 校验目录是本脚本新建的临时副本，结束后删除，避免每次积累完整发行包。
  Remove-FastInkGeneratedPath $verify | Out-Null
}
