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
  Expand-CheckedArchive 'https://conda.anaconda.org/conda-forge/win-64/poppler-26.09.0-h924501e_0.conda' 'poppler-conda.zip' 'bb319f6881d91e175f90a9d33a25313e4cfddc15dd234521519985baf92fefcd'

  $popplerTarget = Join-Path $ToolsDirectory 'poppler'
  $qpdfTarget = Join-Path $ToolsDirectory 'qpdf'
  $shareTarget = Join-Path $ToolsDirectory 'share'
  New-Item -ItemType Directory -Path $popplerTarget,$qpdfTarget,$shareTarget -Force | Out-Null
  # 只取实际调用的程序及其 PE 导入依赖。Windows 自带的 UCRT 由系统加载。
  $popplerFiles = @(
    'pdfinfo.exe', 'pdftohtml.exe', 'pdftoppm.exe', 'pdftotext.exe', 'pdfunite.exe',
    'poppler.dll', 'deflate.dll', 'freetype.dll', 'icudt78.dll', 'icuuc78.dll',
    'jpeg8.dll', 'lcms2.dll', 'lerc.dll', 'libcrypto-3-x64.dll', 'libcurl.dll',
    'liblzma.dll', 'libpng16.dll', 'libssh2.dll', 'msvcp140.dll', 'openjp2.dll',
    'psl-5.dll', 'tiff.dll', 'vcruntime140.dll', 'vcruntime140_1.dll', 'zlib.dll', 'zstd.dll'
  )
  foreach ($name in $popplerFiles) {
    Copy-Item -LiteralPath (Join-Path $temp "poppler-26.09.0/Library/bin/$name") -Destination $popplerTarget -Force
  }
  Copy-Item -LiteralPath (Join-Path $temp 'poppler-26.09.0/share/poppler') -Destination $shareTarget -Recurse -Force
  # conda 包的 info 归档保存生成这份 Poppler 二进制使用的补丁和构建配方。
  $sources = Join-Path $shareTarget 'source'
  New-Item -ItemType Directory -Path $sources -Force | Out-Null
  Expand-CheckedArchive 'https://poppler.freedesktop.org/poppler-26.09.0.tar.xz' 'poppler-26.09.0.tar.xz' '8059eadb6805340768f138c465b57f8164c92b4a0773c37ef031ea6c0d987b2e'
  Expand-CheckedArchive 'https://poppler.freedesktop.org/poppler-data-0.4.12.tar.gz' 'poppler-data-0.4.12.tar.gz' 'c835b640a40ce357e1b83666aabd95edffa24ddddd49b8daff63adb851cdab74'
  foreach ($name in @('poppler-26.09.0.tar.xz','poppler-data-0.4.12.tar.gz','info-poppler-26.09.0-h924501e_0.tar.zst')) {
    Copy-Item -LiteralPath (Join-Path $temp $name) -Destination $sources -Force
  }
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
