# 公开构建入口：共用互斥锁、计算内存预算并启动受限工作进程。Mode 为构建模式；MaxBuildMemoryMB 是作业内存上限，ReserveMemoryMB 是系统余量，CpuPercent 是 CPU 上限，CompilerHeapMB 是编译器堆预算。预算不足立即失败，不结束其他应用。
[CmdletBinding()]
param(
  [ValidateSet('Auto', 'Native', 'FlutterOnly')][string]$Mode = 'Auto',
  [ValidateSet('x64', 'arm64')][string]$Architecture = ($env:PROCESSOR_ARCHITECTURE -replace '^AMD64$', 'x64'),
  [string]$FlutterPath,
  [string]$LauncherDirectory,
  [string]$OutputDirectory,
  [switch]$Installer,
  [switch]$RunTests,
  [switch]$KeepStaging,
  [switch]$ExternalTools,
  [ValidateRange(1536,16384)][int]$MaxBuildMemoryMB = 2560,
  [ValidateRange(1024,16384)][int]$ReserveMemoryMB = 2560,
  [ValidateRange(10,75)][int]$CpuPercent = 50,
  [ValidateRange(512,2048)][int]$CompilerHeapMB = 1024
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'build_resource_guard.ps1')

# 重复点击不能启动第二个编译器，即使另一个项目副本也受同一个互斥锁保护。
$mutex = New-Object Threading.Mutex($false, 'Local\FastInk.WindowsBuild')
$locked = $false
$requestPath = $null
try {
  try { $locked = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $locked = $true }
  if (-not $locked) { throw 'A FastInk build is already running. This second build was not started.' }
  if (-not [Environment]::Is64BitProcess) { throw 'Use 64-bit PowerShell for the guarded Windows build.' }
  Initialize-BuildResourceGuard
  $availableMB = [math]::Floor([FastInk.Build.ResourceJob]::AvailablePhysicalBytes() / 1MB)
  # 为作业之外的启动和监控逻辑预留系统内存。
  $budget = [math]::Min($MaxBuildMemoryMB, [math]::Floor(($availableMB-$ReserveMemoryMB-256)/64)*64)
  if ($budget -lt 1536) { throw "Not enough free RAM to build safely ($availableMB MB available). Close unused apps and retry; system reserve is $ReserveMemoryMB MB." }
  $heap = [int][math]::Min($CompilerHeapMB,[math]::Floor(($budget-512)/2))
  $worker = @{}
  foreach ($name in @('Mode','Architecture','FlutterPath','LauncherDirectory','OutputDirectory','Installer','RunTests','KeepStaging','ExternalTools')) {
    if ($PSBoundParameters.ContainsKey($name)) {
      $value = $PSBoundParameters[$name]
      if ($value -is [Management.Automation.SwitchParameter]) { $value = $value.IsPresent }
      $worker[$name] = $value
    }
  }
  $worker.CompilerHeapMB = $heap
  $reports = Join-Path $projectRoot 'build/reports'
  New-Item -ItemType Directory -Path $reports -Force | Out-Null
  $run = 'build-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0,8)
  $requestPath = Join-Path $reports "$run.request.json"
  $worker | ConvertTo-Json | Set-Content -LiteralPath $requestPath -Encoding UTF8
  $shell = Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
  $entry = Join-Path $PSScriptRoot 'build_windows_worker.ps1'
  Write-Host "Safe build: tree RAM <= $budget MB; system reserve $ReserveMemoryMB MB; compiler heap $heap MB; CPU <= $CpuPercent%; serial compilation/tests."
  Invoke-ResourceControlledProcess -Executable $shell `
    -Arguments ('-NoProfile -ExecutionPolicy Bypass -File "{0}" -RequestPath "{1}"' -f $entry,$requestPath) `
    -WorkingDirectory $projectRoot -LogPath (Join-Path $reports "$run.log") `
    -ReportPath (Join-Path $reports "$run.json") -MemoryLimitMB $budget `
    -ReserveMemoryMB $ReserveMemoryMB -CpuPercent $CpuPercent
} finally {
  if ($requestPath -and (Test-Path -LiteralPath $requestPath)) { Remove-Item -LiteralPath $requestPath -Force }
  if ($locked) { $mutex.ReleaseMutex() }
  $mutex.Dispose()
}
