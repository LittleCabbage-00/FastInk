# 公开测试入口与内部 Worker：串行执行版本同步、依赖校验、静态分析和指定测试。TestPath 指定测试范围；Preview 保存截图；DenseInkPath/PdfSamplePath 为外部样本，不能复制进发行包。内存与 CPU 参数和构建使用同类约束。
[CmdletBinding()]
param(
  [string[]]$TestPath=@('test'), [switch]$Preview,
  [string]$DenseInkPath, [string]$PdfSamplePath,
  [ValidateRange(1536,16384)][int]$MaxMemoryMB=2560,
  [ValidateRange(1024,16384)][int]$ReserveMemoryMB=2560,
  [ValidateRange(10,75)][int]$CpuPercent=50,
  [switch]$Worker, [string]$RequestPath
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$projectRoot=Split-Path -Parent $PSScriptRoot
if ($Worker) {
  $request=Get-Content -LiteralPath $RequestPath -Raw | ConvertFrom-Json
  $taskTemp=Join-Path ([IO.Path]::GetTempPath()) ('FastInkTest-'+[guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $taskTemp | Out-Null
  $env:TEMP=$taskTemp; $env:TMP=$taskTemp
  $env:FASTINK_COMPILER_HEAP_MB='1024'
  $env:FLUTTER_SUPPRESS_ANALYTICS='true'
  $env:FASTINK_UI_PREVIEW=if($request.preview) {'1'} else {'0'}
  if($request.denseInkPath) {$env:FASTINK_DENSE_INK=$request.denseInkPath; $env:FASTINK_DENSE_EXPORT_INPUT=$request.denseInkPath}
  if($request.pdfSamplePath) {$env:FASTINK_OUTLINE_SAMPLE=$request.pdfSamplePath; $env:FASTINK_CAPITAL_DENSE='1'}
  $flutterCommand=Get-Command flutter -ErrorAction SilentlyContinue
  if (-not $flutterCommand) {throw 'Flutter not found. Add Flutter to PATH.'}
  $flutter=$flutterCommand.Source
  $dart=Join-Path (Split-Path -Parent $flutter) 'dart.bat'
  Set-Location -LiteralPath $projectRoot
  . (Join-Path $PSScriptRoot 'workspace_paths.ps1')
  Remove-FastInkGeneratedPath (Join-Path $projectRoot 'build/unit_test_assets') | Out-Null
  & $dart (Join-Path $PSScriptRoot 'sync_app_version.dart'); if($LASTEXITCODE -ne 0) {exit $LASTEXITCODE}
  & $flutter pub get; if($LASTEXITCODE -ne 0) {exit $LASTEXITCODE}
  & $dart analyze --fatal-infos; if($LASTEXITCODE -ne 0) {exit $LASTEXITCODE}
  $tests=@($request.testPath | ForEach-Object {[string]$_})
  & $flutter test --no-pub --concurrency=1 --reporter=expanded --no-track-widget-creation "--frontend-server-starter-path=$PSScriptRoot/low_memory_frontend.dart" @tests
  exit $LASTEXITCODE
}
. (Join-Path $PSScriptRoot 'build_resource_guard.ps1')
$mutex=New-Object Threading.Mutex($false,'Local\FastInk.WindowsBuild'); $locked=$false; $requestFile=$null
try {
  try {$locked=$mutex.WaitOne(0)} catch [Threading.AbandonedMutexException] {$locked=$true}
  if(-not $locked) {throw 'A build or test is already running.'}
  $reports=Join-Path $projectRoot 'build/reports'; New-Item -ItemType Directory -Path $reports -Force | Out-Null
  $run='test-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8)
  $requestFile=Join-Path $reports ($run+'.request.json')
  @{testPath=@($TestPath); preview=[bool]$Preview; denseInkPath=$DenseInkPath; pdfSamplePath=$PdfSamplePath} |
    ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $requestFile -Encoding UTF8
  $shell=(Get-Process -Id $PID).Path
  Invoke-ResourceControlledProcess -Executable $shell `
    -Arguments ('-NoProfile -ExecutionPolicy Bypass -File "{0}" -Worker -RequestPath "{1}"' -f $PSCommandPath,$requestFile) `
    -WorkingDirectory $projectRoot -LogPath (Join-Path $reports ($run+'.log')) `
    -ReportPath (Join-Path $reports ($run+'.json')) -MemoryLimitMB $MaxMemoryMB -ReserveMemoryMB $ReserveMemoryMB -CpuPercent $CpuPercent
} finally {
  if($requestFile -and (Test-Path -LiteralPath $requestFile)) {Remove-Item -LiteralPath $requestFile -Force}
  if($locked) {$mutex.ReleaseMutex()}; $mutex.Dispose()
}
