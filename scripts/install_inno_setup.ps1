# 按当前安装流程取得并校验 Inno Setup 编译器，安装路径和下载文件均需明确；不修改个人笔记内容。
[CmdletBinding()]
param(
  [string]$ToolRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$config = Import-PowerShellDataFile -LiteralPath (
  Join-Path $projectRoot 'packaging\windows\release_config.psd1'
)

if ([string]::IsNullOrWhiteSpace($ToolRoot)) {
  $ToolRoot = Join-Path $projectRoot '.tooling'
}

$destination = Join-Path $ToolRoot 'InnoSetup'
$compiler = Join-Path $destination 'ISCC.exe'
if (Test-Path -LiteralPath $compiler) {
  Write-Output $compiler
  exit 0
}

$downloadRoot = Join-Path $ToolRoot 'downloads'
$installer = Join-Path $downloadRoot (
  'innosetup-{0}.exe' -f $config.InnoSetup.Version
)
New-Item -ItemType Directory -Path $downloadRoot -Force | Out-Null
New-Item -ItemType Directory -Path $destination -Force | Out-Null

Write-Host "正在下载 Inno Setup $($config.InnoSetup.Version)..."
Invoke-WebRequest -Uri $config.InnoSetup.DownloadUrl -OutFile $installer

# 下载后先核验 Windows 数字签名，避免运行来源不明的打包器。
$signature = Get-AuthenticodeSignature -LiteralPath $installer
if ($signature.Status -ne 'Valid' -or
    $signature.SignerCertificate.Subject -notmatch $config.InnoSetup.PublisherPattern) {
  throw "Inno Setup 数字签名校验失败：$($signature.Status)"
}

$arguments = @(
  '/CURRENTUSER',
  '/VERYSILENT',
  '/SUPPRESSMSGBOXES',
  '/NORESTART',
  '/NOICONS',
  "/DIR=$destination"
)
$process = Start-Process -FilePath $installer -ArgumentList $arguments `
  -Wait -PassThru -WindowStyle Hidden
if ($process.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $compiler)) {
  throw "Inno Setup 安装失败，退出码：$($process.ExitCode)"
}

Remove-Item -LiteralPath $installer -Force
Write-Output $compiler
