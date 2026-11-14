param([Parameter(Mandatory=$true)][string]$Request)
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=New-Object System.Text.UTF8Encoding($false)
$OutputEncoding=[Console]::OutputEncoding
$payload=Get-Content -LiteralPath $Request -Raw -Encoding UTF8 | ConvertFrom-Json
$work=[IO.Path]::GetFullPath((Split-Path -Parent $Request))
$html=[IO.Path]::GetFullPath([string]$payload.html)
$png=[IO.Path]::GetFullPath([string]$payload.output)
foreach($path in @($html,$png)) {
  if(-not $path.StartsWith($work.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Render output must stay in its private working directory'}
}
$candidates=@(
  (Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application\msedge.exe'),
  (Join-Path $env:ProgramFiles 'Microsoft\Edge\Application\msedge.exe'),
  (Join-Path $env:ProgramFiles 'Google\Chrome\Application\chrome.exe'),
  (Join-Path $env:LOCALAPPDATA 'Google\Chrome\Application\chrome.exe')
)
$browser=@($candidates | Where-Object {Test-Path -LiteralPath $_} | Select-Object -First 1)
if($browser.Count -eq 0){throw 'Mermaid rendering needs the existing Microsoft Edge or Google Chrome browser.'}
Add-Type -Path (Join-Path $PSScriptRoot 'ResourceJob.cs')
$job=[FastInk.MarkdownRuntime.ResourceJob]::new([UInt64](640MB),25)
try {
  $profile=Join-Path $work 'browser-profile'
  $log=Join-Path $work 'browser.log'
  $url=([uri]$html).AbsoluteUri
  $args='--headless=new --disable-gpu --no-first-run --disable-extensions --disable-sync --disable-background-networking --disable-component-update --disable-default-apps --hide-scrollbars --allow-file-access-from-files --force-device-scale-factor=1 --window-size=1200,4000 --virtual-time-budget=5000 --timeout=18000 --dump-dom --screenshot="'+$png+'" --user-data-dir="'+$profile+'" "'+$url+'"'
  $job.Start($browser[0],$args,$work,$log)
  $deadline=[DateTime]::UtcNow.AddSeconds(24)
  while(-not $job.HasExited) {
    $job.PollNotifications()
    if($job.MemoryLimitReached){throw 'Diagram renderer exceeded its memory limit.'}
    if([DateTime]::UtcNow -gt $deadline){throw 'Diagram rendering timed out.'}
    Start-Sleep -Milliseconds 100
  }
  if($job.ExitCode -ne 0){throw "Diagram renderer exited with code $($job.ExitCode)."}
  $text=Get-Content -LiteralPath $log -Raw -Encoding UTF8
  $match=[regex]::Match($text,'data-result="([^"]*)"')
  if(-not $match.Success){throw 'Diagram renderer did not return a result.'}
  $result=[Net.WebUtility]::HtmlDecode($match.Groups[1].Value) | ConvertFrom-Json
  if($result.error){throw [string]$result.error}
  if(-not (Test-Path -LiteralPath $png)){throw 'Diagram image is missing.'}
  @{width=[int]$result.width;height=[int]$result.height;peakMemoryMB=[math]::Round($job.PeakCommitBytes/1MB)} | ConvertTo-Json -Compress
} finally {
  # 本作业只拥有新建的无头浏览器及其私有配置目录。
  # 关闭作业不会操作已有浏览器或前台窗口。
  $job.Dispose()
}
