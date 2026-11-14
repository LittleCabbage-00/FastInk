# 资源保护回归：自有探针验证提交内存、CPU/优先级与子进程约束，不将结束任意应用当作测试手段。
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$projectScripts = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'scripts'
. (Join-Path $projectScripts 'build_resource_guard.ps1')
Initialize-BuildResourceGuard
$project = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$testRoot = Join-Path $project ('build/resource-guard-tests/' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
$shell = Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
$plain = Join-Path $testRoot 'plain.ps1'
[IO.File]::WriteAllText($plain, 'Write-Output "fixture output"; Start-Sleep -Milliseconds 400; exit 0')
$sleep = Join-Path $testRoot 'sleep.ps1'
[IO.File]::WriteAllText($sleep, 'Start-Sleep -Seconds 60')
$innocent = Start-Process -FilePath $shell -ArgumentList ('-NoProfile -File "{0}"' -f $sleep) -WindowStyle Hidden -PassThru
try {
  Invoke-ResourceControlledProcess -Executable $shell -Arguments ('-NoProfile -File "{0}"' -f $plain) `
    -WorkingDirectory $project -LogPath "$testRoot/plain.log" -ReportPath "$testRoot/plain.json" `
    -MemoryLimitMB 256 -ReserveMemoryMB 2560 -CpuPercent 50
  $report = Get-Content "$testRoot/plain.json" -Raw | ConvertFrom-Json
  if (-not $report.succeeded -or $report.peakPrivateCommitMB -le 0 -or $report.peakPrivateCommitMB -gt 256) { throw 'Bad successful-run accounting' }
  if (-not ((Get-Content "$testRoot/plain.log" -Raw).Contains('fixture output'))) { throw 'Worker output missing' }

  $childPid = Join-Path $testRoot 'child.pid'
  $child = Join-Path $testRoot 'child.ps1'
  [IO.File]::WriteAllText($child, ('[IO.File]::WriteAllText(''{0}'',[string]$PID); Start-Sleep -Seconds 60' -f $childPid))
  $oom = Join-Path $testRoot 'oom.ps1'
  $oomSource = @'
$OutputEncoding = [Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)
$child = Start-Process -FilePath '__SHELL__' -ArgumentList '-NoProfile -File "__CHILD__"' -WindowStyle Hidden -PassThru
for ($attempt = 0; $attempt -lt 100 -and -not (Test-Path -LiteralPath '__PID__'); $attempt++) { Start-Sleep -Milliseconds 25 }
Add-Type 'using System; using System.Runtime.InteropServices; public class Probe { [DllImport("kernel32.dll",SetLastError=true)] public static extern IntPtr VirtualAlloc(IntPtr a, UIntPtr s, uint t, uint p); }'
$allocation = [Probe]::VirtualAlloc([IntPtr]::Zero,[UIntPtr]([uint64](512MB)),0x3000,4)
if ($allocation -ne [IntPtr]::Zero) { [IO.File]::WriteAllText('__PID__.unsafe','Over-budget allocation succeeded'); exit 20 }
[IO.File]::WriteAllText('__PID__.blocked','Over-budget native allocation rejected')
Start-Sleep -Seconds 10
'@
  [IO.File]::WriteAllText($oom,$oomSource.Replace('__SHELL__',$shell).Replace('__CHILD__',$child).Replace('__PID__',$childPid))
  $rejected = $false
  try {
    Invoke-ResourceControlledProcess -Executable $shell -Arguments ('-NoProfile -File "{0}"' -f $oom) `
      -WorkingDirectory $project -LogPath "$testRoot/oom.log" -ReportPath "$testRoot/oom.json" `
      -MemoryLimitMB 256 -ReserveMemoryMB 2560 -CpuPercent 50
  } catch { $rejected = $true }
  $report = Get-Content "$testRoot/oom.json" -Raw | ConvertFrom-Json
  if (-not $rejected -or $report.succeeded -or $report.reason -notmatch 'memory budget') { throw 'An over-budget child tree was not rejected' }
  if ($report.peakPrivateCommitMB -gt 257) { throw 'Hard memory budget exceeded' }
  if (Test-Path -LiteralPath "$childPid.unsafe") { throw 'Windows allowed an over-budget native allocation' }
  if (-not (Test-Path -LiteralPath $childPid)) { throw 'Descendant test was not exercised' }
  $ownedChildId = [int](Get-Content -LiteralPath $childPid -Raw)
  for ($attempt=0; $attempt -lt 30 -and (Get-Process -Id $ownedChildId -ErrorAction SilentlyContinue); $attempt++) { Start-Sleep -Milliseconds 100 }
  if (Get-Process -Id $ownedChildId -ErrorAction SilentlyContinue) { throw 'A descendant survived the cancelled build' }
  $innocent.Refresh()
  if ($innocent.HasExited) { throw 'An unrelated process was stopped' }

  $rejected = $false
  try {
    Invoke-ResourceControlledProcess -Executable $shell -Arguments ('-NoProfile -File "{0}"' -f $plain) `
      -WorkingDirectory $project -LogPath "$testRoot/refused.log" -ReportPath "$testRoot/refused.json" `
      -MemoryLimitMB 256 -ReserveMemoryMB 999999 -CpuPercent 50
  } catch { $rejected = $true }
  if (-not $rejected -or (Test-Path "$testRoot/refused.log")) { throw 'Insufficient-memory preflight started a worker' }
  Write-Host "PASS: successful build accounting, hard tree cap, descendant cleanup, unrelated process preservation and low-RAM preflight. Reports: $testRoot"
} finally {
  if (-not $innocent.HasExited) { $innocent.Kill(); $null=$innocent.WaitForExit(5000) }
  $innocent.Dispose()
}
