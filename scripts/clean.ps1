# 清理可重新生成的产物，支持 -WhatIf。保留启动器缓存、非空资料库、Notebook.url 和正在运行的程序包；Legacy 也不能绕过路径白名单，不结束用户应用。
[CmdletBinding(SupportsShouldProcess=$true)]
param([switch]$Legacy)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'workspace_paths.ps1')
$projectRoot = $script:FastInkWorkspace
$buildRoot = Join-Path $projectRoot 'build'
$mutex = New-Object Threading.Mutex($false, 'Local\FastInk.WindowsBuild')
$locked=$false
try {
  try { $locked=$mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $locked=$true }
  if (-not $locked) { throw 'A build or test is running. Cleanup was not started.' }
  $protected = New-Object 'Collections.Generic.List[string]'
  $protected.Add([IO.Path]::GetFullPath((Join-Path $buildRoot 'windows-launcher')))
  # OneDrive 可能将 OneNote 笔记目录呈现为 Notebook.url；保留其入口，避免误删笔记相关数据。
  $oldReferences=Join-Path $projectRoot '.reference'
  if(Test-Path -LiteralPath $oldReferences) {
    foreach($notebook in (Get-FastInkGeneratedFiles $oldReferences | Where-Object {$_.Name -eq 'Notebook.url'})) {
      $protected.Add([IO.Path]::GetFullPath($notebook.DirectoryName))
    }
  }
  # 旧验证包也可能留有文稿；只要资料库非空，就保留整个数据目录及原路径。
  if (Test-Path -LiteralPath $buildRoot) {
    if((Get-Item -LiteralPath $buildRoot -Force).LinkType -in @('SymbolicLink','Junction')) {
      throw 'The build directory is a link. Cleanup stopped.'
    }
    foreach ($library in (Get-FastInkGeneratedFiles $buildRoot | Where-Object {$_.Name -eq 'library.json'})) {
      try {
        $state=Get-Content -LiteralPath $library.FullName -Raw | ConvertFrom-Json
        if ($state.PSObject.Properties['documents'] -and @($state.documents).Count -gt 0) {
          $protected.Add([IO.Path]::GetFullPath($library.DirectoryName))
        }
      } catch { throw "Cannot inspect a library; kept all files: $($library.FullName)" }
    }
  }
  # 不结束应用；若用户正在运行项目里的旧包，连同该包的目录一起保留。
  foreach ($process in (Get-CimInstance Win32_Process -Filter "Name='FastInk.exe'")) {
    if (-not $process.ExecutablePath) { throw 'Cannot resolve a running FastInk path. Cleanup stopped.' }
    $running=[IO.Path]::GetFullPath($process.ExecutablePath)
    if ($running.StartsWith($buildRoot+'\',[StringComparison]::OrdinalIgnoreCase)) {
      $protected.Add((Split-Path -Parent $running))
    }
  }
  $script:cleanFiles=0; [long]$script:cleanBytes=0; $script:cleanPaths=0
  $cleanupCmdlet=$PSCmdlet
  function Clear-GeneratedEntry([string]$Path) {
    $absolute=[IO.Path]::GetFullPath($Path)
    if (@($protected | Where-Object { $absolute.Equals($_,[StringComparison]::OrdinalIgnoreCase) -or
          $absolute.StartsWith($_+'\',[StringComparison]::OrdinalIgnoreCase) }).Count -gt 0) { return }
    if (@($protected | Where-Object { $_.StartsWith($absolute+'\',[StringComparison]::OrdinalIgnoreCase) }).Count -gt 0) {
      foreach ($child in (Get-ChildItem -LiteralPath $absolute -Force)) { Clear-GeneratedEntry $child.FullName }
      return
    }
    if ($cleanupCmdlet.ShouldProcess($absolute, 'Remove generated or obsolete project artifact')) {
      $removed=Remove-FastInkGeneratedPath -Path $absolute -Legacy:$Legacy
      $script:cleanFiles += $removed.Files; $script:cleanBytes += $removed.Bytes; $script:cleanPaths++
    }
  }
  if (Test-Path -LiteralPath $buildRoot) {
    foreach ($child in (Get-ChildItem -LiteralPath $buildRoot -Force)) { Clear-GeneratedEntry $child.FullName }
  }
  if ($Legacy) {
    foreach ($name in @('.reference','backups','build_paperfix','build_v2026','.idea','tools','fastink_flutter.iml','_UL')) {
      $legacyPath=Join-Path $projectRoot $name
      if (Test-Path -LiteralPath $legacyPath) { Clear-GeneratedEntry $legacyPath }
    }
  }
  $report=[ordered]@{ removedFiles=$script:cleanFiles; removedPaths=$script:cleanPaths;
    removedBytes=$script:cleanBytes; removedGiB=[math]::Round($script:cleanBytes/1GB,2);
    preservedPaths=@($protected | Where-Object {Test-Path -LiteralPath $_}); whatIf=[bool]$WhatIfPreference }
  if (-not $WhatIfPreference) {
    $reports=Join-Path $buildRoot 'reports'; New-Item -ItemType Directory -Path $reports -Force | Out-Null
    $report | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath (Join-Path $reports 'cleanup.json') -Encoding UTF8
  }
  $report | ConvertTo-Json -Depth 3
} finally {
  if($locked) {$mutex.ReleaseMutex()}; $mutex.Dispose()
}
