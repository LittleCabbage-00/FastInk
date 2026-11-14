# 内部工作进程：RequestPath 是公开入口创建的本次参数 JSON；读取后转交实现层，异常转换为非零退出码。
param([Parameter(Mandatory=$true)][string]$RequestPath)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$OutputEncoding = [Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)
# 避免 PowerShell 7 调用方传入不兼容的模块搜索路径。
$env:PSModulePath = (Join-Path $PSHOME 'Modules') + ';' + $env:PSModulePath
Import-Module (Join-Path $PSHOME 'Modules/Microsoft.PowerShell.Utility') -Force
Import-Module (Join-Path $PSHOME 'Modules/Microsoft.PowerShell.Management') -Force
$request = Get-Content -LiteralPath $RequestPath -Raw | ConvertFrom-Json
$arguments = @{}
foreach ($property in $request.PSObject.Properties) { $arguments[$property.Name] = $property.Value }
try {
  & (Join-Path $PSScriptRoot 'build_windows_impl.ps1') @arguments
  exit 0
} catch {
  Write-Error $_ -ErrorAction Continue
  exit 1
}
