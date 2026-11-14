# 构建资源监督公共函数。该文件只提供类型初始化和受限进程调用，默认预算不代表所有调用入口的最终预算。
Set-StrictMode -Version Latest

# 按需编译本项目的 Windows Job 资源约束桥，同一进程只加载一次类型；失败时不能绕过资源限制继续构建。
function Initialize-BuildResourceGuard {
  if (-not ('FastInk.Build.ResourceJob' -as [type])) {
    Add-Type -Path (Join-Path $PSScriptRoot 'BuildResourceGuard.cs')
  }
}

# 启动受限且不可见的自有工作进程树，监控作业提交内存、系统余量与退出码，最后写入 JSON 报告并释放句柄。Executable/Arguments 指定入口；WorkingDirectory 是绝对工作目录；LogPath/ReportPath 指向本次报告。MemoryLimitMB/ReserveMemoryMB 单位 MB，CpuPercent 为 CPU 百分比。只可停止所属 Job，不结束其他应用。
function Invoke-ResourceControlledProcess {
  param(
    [Parameter(Mandatory=$true)][string]$Executable,
    [Parameter(Mandatory=$true)][string]$Arguments,
    [Parameter(Mandatory=$true)][string]$WorkingDirectory,
    [Parameter(Mandatory=$true)][string]$LogPath,
    [Parameter(Mandatory=$true)][string]$ReportPath,
    [int]$MemoryLimitMB = 3072,
    [int]$ReserveMemoryMB = 2560,
    [int]$CpuPercent = 50
  )
  Initialize-BuildResourceGuard
  $job = $null
  $reader = $null
  $started = Get-Date
  $lowestFree = [FastInk.Build.ResourceJob]::AvailablePhysicalBytes()
  $peakCommit = [uint64]0
  $peakWorking = [int64]0
  $sampledPrivate = [int64]0
  $lastStatus = $started
  $lowSamples = 0
  $reason = $null
  $exitCode = 1
  try {
    if ($lowestFree -lt (($MemoryLimitMB + $ReserveMemoryMB) * 1MB)) {
      throw ('Not enough free RAM to start safely: {0:N0} MB available, {1} MB build budget + {2} MB system reserve. Close unused apps and retry.' -f ($lowestFree / 1MB),$MemoryLimitMB,$ReserveMemoryMB)
    }
    $job = New-Object FastInk.Build.ResourceJob -ArgumentList ([uint64]($MemoryLimitMB * 1MB)), $CpuPercent
    $job.Start($Executable,$Arguments,$WorkingDirectory,$LogPath)
    $stream = New-Object IO.FileStream -ArgumentList $LogPath,([IO.FileMode]::Open),([IO.FileAccess]::Read),([IO.FileShare]::ReadWrite)
    $reader = New-Object IO.StreamReader -ArgumentList $stream,([Text.Encoding]::UTF8),$true
    do {
      $text = $reader.ReadToEnd()
      if ($text) { Write-Host -NoNewline $text }
      $free = [FastInk.Build.ResourceJob]::AvailablePhysicalBytes()
      $lowestFree = [math]::Min($lowestFree,$free)
      $peakCommit = [math]::Max($peakCommit,$job.PeakCommitBytes)
      $working = [int64]0
      $private = [int64]0
      foreach ($processId in $job.ProcessIds()) {
        try {
          $child = [Diagnostics.Process]::GetProcessById($processId)
          try { $working += $child.WorkingSet64; $private += $child.PrivateMemorySize64 } finally { $child.Dispose() }
        } catch [ArgumentException] { } catch [InvalidOperationException] { }
      }
      $peakWorking = [math]::Max($peakWorking,$working)
      $sampledPrivate = [math]::Max($sampledPrivate,$private)
      $job.PollNotifications()
      if ($job.MemoryLimitReached) {
        $reason = 'Build memory budget reached; stopped this build tree to keep Windows responsive.'
      }
      if ($free -lt ($ReserveMemoryMB * 1MB)) { $lowSamples++ } else { $lowSamples=0 }
      if ($lowSamples -ge 2) {
        $reason = 'Available system RAM dropped below the reserve; stopped only this build tree.'
      }
      if ($reason) { $job.Stop(); break }
      if (((Get-Date)-$lastStatus).TotalSeconds -ge 15) {
        Write-Host ('[RAM guard] sampled build peak {0:N0}/{1} MB; system free {2:N0} MB; CPU cap {3}%' -f ($sampledPrivate / 1MB),$MemoryLimitMB,($free / 1MB),$CpuPercent)
        $lastStatus = Get-Date
      }
      # 退出作业时清理原生编译服务进程。
      if ($job.HasExited) { break }
      Start-Sleep -Milliseconds 250
    } while ($true)
    $text = $reader.ReadToEnd()
    if ($text) { Write-Host -NoNewline $text }
    if ($reason) { throw $reason }
    $exitCode = $job.ExitCode
    if ($exitCode -ne 0) { throw "Build failed (exit $exitCode). Full log: $LogPath" }
  } catch {
    if (-not $reason) { $reason = $_.Exception.Message }
    if ($job) { $job.Stop() }
    throw
  } finally {
    if ($job) {
      $peakCommit = [math]::Max($peakCommit,$job.PeakCommitBytes)
      $job.Dispose()
    }
    if ($reader) { $reader.Dispose() }
    $report = [ordered]@{
      startedAtUtc=$started.ToUniversalTime().ToString('o')
      durationSeconds=[math]::Round(((Get-Date)-$started).TotalSeconds,2)
      memoryLimitMB=$MemoryLimitMB; reserveMemoryMB=$ReserveMemoryMB; cpuPercent=$CpuPercent
      peakPrivateCommitMB=[math]::Round($sampledPrivate / 1MB,1)
      reportedJobPeakMB=[math]::Round($peakCommit / 1MB,1)
      peakWorkingSetMB=[math]::Round($peakWorking / 1MB,1)
      lowestSystemAvailableMB=[math]::Round($lowestFree / 1MB,1)
      succeeded=($exitCode -eq 0 -and -not $reason); reason=$reason; logPath=$LogPath
    }
    $report | ConvertTo-Json | Set-Content -LiteralPath $ReportPath -Encoding UTF8
    Write-Host ('Sampled build RAM peak: {0:N0} MB; lowest system free: {1:N0} MB. Report: {2}' -f ($sampledPrivate / 1MB),($lowestFree / 1MB),$ReportPath)
  }
}
