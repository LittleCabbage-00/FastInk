# 从上游下载 PDF 和 Mermaid 组件。先核对压缩包，再把文件放到当前项目或便携包的 tools 目录。
[CmdletBinding()]
param(
  [ValidateSet('x64', 'arm64')][string]$Architecture = ($env:PROCESSOR_ARCHITECTURE -replace '^AMD64$', 'x64'),
  [string]$ToolsDirectory
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not $ToolsDirectory) {
  $ToolsDirectory = if (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'FastInk.exe')) {
    Join-Path $PSScriptRoot 'tools'
  } else {
    Join-Path (Split-Path -Parent $PSScriptRoot) 'windows/tools'
  }
}
if (-not (Test-Path -LiteralPath (Join-Path $ToolsDirectory 'onenote/import.ps1'))) {
  throw 'Specify FastInk tools directory with -ToolsDirectory.'
}

# Poppler 目前使用 x64 外部进程。Windows 11 ARM64 的 x64 仿真负责运行它。
$qpdf = if ($Architecture -eq 'arm64') {
  @{ Name='qpdf-12.4.2-msvc-arm64'; Hash='2b5d7740a2513d8a841116692dc2cf7efe83f35262386ebab18bed35fbf15ab1' }
} else {
  @{ Name='qpdf-12.4.2-msvc64'; Hash='db87077e683630c1217e0e8f9a20a9749d952ab676e881c3689187763a5de25d' }
}
$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$temp = Join-Path $tempRoot ('FastInkTools-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp | Out-Null

# 每个归档以固定 SHA-256 校验。校验通过后才允许解包。
function Expand-CheckedArchive([string]$Url, [string]$Name, [string]$Hash) {
  $archive = Join-Path $temp $Name
  & curl.exe --fail --silent --show-error --location --retry 2 --output $archive $Url
  if ($LASTEXITCODE -ne 0) { throw "Download failed for $Name." }
  if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ne $Hash) {
    throw "Checksum mismatch for $Name."
  }
  & tar.exe -xf $archive -C $temp
  if ($LASTEXITCODE -ne 0) { throw "Could not extract $Name." }
}

try {
  Expand-CheckedArchive 'https://github.com/oschwartz10612/poppler-windows/releases/download/v26.09.0-0/Release-26.09.0-0.zip' 'poppler.zip' '7a6f256a0ddf7536182246a5733331bf4677cbcc34f4663774947ad34556c8d0'
  Expand-CheckedArchive "https://github.com/qpdf/qpdf/releases/download/v12.4.2/$($qpdf.Name).zip" 'qpdf.zip' $qpdf.Hash
  Expand-CheckedArchive 'https://registry.npmjs.org/mermaid/-/mermaid-12.2.0.tgz' 'mermaid.tgz' '071914164d0f6d53e5c26a10a220230d4ae8d37ed0f2263fbf072266f0af3a0a'

  $popplerTarget = Join-Path $ToolsDirectory 'poppler'
  $qpdfTarget = Join-Path $ToolsDirectory 'qpdf'
  $shareTarget = Join-Path $ToolsDirectory 'share'
  New-Item -ItemType Directory -Path $popplerTarget,$qpdfTarget,$shareTarget -Force | Out-Null
  Copy-Item -Path (Join-Path $temp 'poppler-26.09.0/Library/bin/*') -Destination $popplerTarget -Force
  Copy-Item -LiteralPath (Join-Path $temp 'poppler-26.09.0/share/poppler') -Destination $shareTarget -Recurse -Force
  Copy-Item -Path (Join-Path $temp "$($qpdf.Name)/bin/*") -Destination $qpdfTarget -Force
  $qpdfLicense = Join-Path $temp "$($qpdf.Name)/share/doc/qpdf/manual-html/license.html"
  Copy-Item -LiteralPath $qpdfLicense -Destination $qpdfTarget -Force
  Copy-Item -LiteralPath (Join-Path $temp 'package/dist/mermaid.min.js') -Destination (Join-Path $ToolsDirectory 'markdown') -Force
  Write-Output "Installed PDF and Mermaid tools: $ToolsDirectory"
} finally {
  $resolved = (Resolve-Path -LiteralPath $temp).Path
  $tempPrefix = $tempRoot.TrimEnd('\') + '\FastInkTools-'
  if ($resolved.StartsWith($tempPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    Remove-Item -LiteralPath $resolved -Recurse -Force
  }
}
