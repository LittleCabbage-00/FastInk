# 打包回归检查：使用隔离样本验证便携标记、ZIP 路径和内容校验，完成后只清理自身临时目录。
# 仅检查打包集成，不编译或执行测试夹具。
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$projectScripts = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'scripts'
$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$fixture = Join-Path $tempRoot ('fastink-package-check-' + [guid]::NewGuid().ToString('N'))
$release = Join-Path $fixture 'release'
$output = Join-Path $fixture 'output'
try {
  foreach ($directory in @('data\flutter_assets', 'tools\poppler', 'tools\qpdf', 'tools\markdown', 'FastInkData')) {
    New-Item -ItemType Directory -Path (Join-Path $release $directory) -Force | Out-Null
  }
  foreach ($name in @('FastInk.exe', 'flutter_windows.dll', 'native_assets.json', 'BUILD-INFO.json',
      'data\app.so', 'data\icudtl.dat', 'data\flutter_assets\AssetManifest.bin', 'tools\poppler\pdfinfo.exe',
      'tools\qpdf\qpdf.exe', 'tools\qpdf\qpdf30.dll', 'tools\qpdf\LICENSE.txt', 'tools\markdown\mermaid.min.js')) {
    [IO.File]::WriteAllText((Join-Path $release $name), "fixture:$name")
  }
  # 写入最小 PE 头供打包器校验架构。测试只读文件头，不启动这些夹具。
  $header = [byte[]]::new(70)
  $header[0] = 0x4d
  $header[1] = 0x5a
  $header[60] = 64
  $header[64] = 0x50
  $header[65] = 0x45
  $header[68] = 0x64
  $header[69] = 0x86
  foreach ($binary in @('FastInk.exe', 'flutter_windows.dll')) {
    [IO.File]::WriteAllBytes((Join-Path $release $binary), $header)
  }
  foreach ($name in @('settings.json', '.fastink-config-root', 'FastInkData\private.json', 'unrelated.exe')) {
    [IO.File]::WriteAllText((Join-Path $release $name), 'private fixture - must not ship')
  }
  & (Join-Path $projectScripts 'package_windows.ps1') -Architecture x64 -SkipBuild -SkipInstaller -ReleaseDirectory $release -OutputDirectory $output
  $zip = @(Get-ChildItem -LiteralPath $output -Filter '*.zip')
  if ($zip.Count -ne 1) { throw 'Expected one portable ZIP.' }
  $archive = [IO.Compression.ZipFile]::OpenRead($zip[0].FullName)
  try {
    $names = @($archive.Entries | ForEach-Object { $_.FullName })
    if ($names | Where-Object { $_.Contains('\') }) { throw 'ZIP names must use forward slashes on every PowerShell runtime.' }
    if (-not ($names -match '/\.fastink-portable$')) { throw 'Portable marker was omitted.' }
    if (-not ($names -match '/BUILD-INFO.json$')) { throw 'Build info was omitted.' }
    foreach ($tool in @('qpdf.exe', 'qpdf30.dll', 'LICENSE.txt')) {
      if (-not ($names -match "/tools/qpdf/$([regex]::Escape($tool))$")) { throw "Fast PDF tool was omitted: $tool" }
    }
    if ($names -match 'FastInkData|settings.json|\.fastink-config-root|unrelated.exe') { throw 'Private fixture files leaked.' }
  } finally { $archive.Dispose() }
  $before = (Get-FileHash -LiteralPath $zip[0].FullName -Algorithm SHA256).Hash
  Remove-Item -LiteralPath (Join-Path $release 'data\app.so')
  $rejected = $false
  try {
    & (Join-Path $projectScripts 'package_windows.ps1') -Architecture x64 -SkipBuild -SkipInstaller -ReleaseDirectory $release -OutputDirectory $output
  } catch { $rejected = $true }
  if (-not $rejected) { throw 'An incomplete bundle was accepted.' }
  if ((Get-FileHash -LiteralPath $zip[0].FullName -Algorithm SHA256).Hash -ne $before) {
    throw 'A failed run replaced the previous ZIP.'
  }
  Write-Host 'PASS: ZIP contents, portable marker, personal-data exclusion, incomplete-bundle rejection and previous ZIP preservation.'
} finally {
  $resolved = [IO.Path]::GetFullPath($fixture)
  if (-not $resolved.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe fixture cleanup path.' }
  if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
