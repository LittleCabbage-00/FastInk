# 生成目录安全边界与遍历工具；workspace 根由脚本位置解析，不信任调用方当前工作目录。
Set-StrictMode -Version Latest
$script:FastInkWorkspace = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\')

# 读取 Windows PE 文件头里的处理器类型，用于验证启动器和引擎。
function Get-FastInkPeArchitecture {
  param([Parameter(Mandatory=$true)][string]$Path)
  $reader = [IO.BinaryReader]::new([IO.File]::OpenRead($Path))
  try {
    if ($reader.ReadUInt16() -ne 0x5a4d) { throw "Invalid DOS header: $Path" }
    $reader.BaseStream.Position = 0x3c
    $reader.BaseStream.Position = $reader.ReadUInt32()
    if ($reader.ReadUInt32() -ne 0x4550) { throw "Invalid PE signature: $Path" }
    switch ($reader.ReadUInt16()) {
      0x8664 { return 'x64' }
      0xaa64 { return 'arm64' }
      0x014c { return 'x86' }
      default { throw "Unknown Windows machine type: $Path" }
    }
  } finally { $reader.Dispose() }
}

# 验证绝对目标严格落在允许的生成目录内，跳转链接只删除链接本身，不进入目标；返回删除的文件数与字节数。Legacy 仅放行列出的旧产物名称，不能用于任意路径删除。
function Remove-FastInkGeneratedPath {
  param([Parameter(Mandatory=$true)][string]$Path, [switch]$Legacy)
  $absolute = [IO.Path]::GetFullPath($Path)
  $prefix = $script:FastInkWorkspace + '\'
  if (-not $absolute.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to remove a path outside the project: $absolute"
  }
  $relative = $absolute.Substring($prefix.Length)
  # 逐层检查父目录，不能通过 build 下的联接绕到项目外部。
  $ancestor = Split-Path -Parent $absolute
  while ($ancestor -and -not $ancestor.Equals($script:FastInkWorkspace,[StringComparison]::OrdinalIgnoreCase)) {
    if (Test-Path -LiteralPath $ancestor) {
      $parentItem=Get-Item -LiteralPath $ancestor -Force
      if ($parentItem.LinkType -in @('SymbolicLink','Junction')) {
        throw "Refusing to traverse a linked parent: $ancestor"
      }
    }
    $ancestor=Split-Path -Parent $ancestor
  }
  $legacyNames = @('.reference', 'backups', 'build_paperfix', 'build_v2026', '.idea', 'tools', 'fastink_flutter.iml', '_UL')
  if (-not $relative.StartsWith('build\', [StringComparison]::OrdinalIgnoreCase) -and
      -not ($Legacy -and $legacyNames -contains $relative)) {
    throw "Only generated paths or named legacy artifacts may be removed: $relative"
  }
  if (-not (Test-Path -LiteralPath $absolute)) { return [pscustomobject]@{ Files=0; Bytes=0 } }
  $item = Get-Item -LiteralPath $absolute -Force
  $files = 0; [long]$bytes = 0
  # 只枚举真实目录；符号链接/目录联接只解除链接，绝不递归到其目标。
  # OneDrive 云占位符也有 ReparsePoint 属性，不能把它误判为目录联接。
  $pending = New-Object 'Collections.Generic.Stack[string]'
  $pending.Push($absolute)
  while ($pending.Count -gt 0) {
    $current = Get-Item -LiteralPath $pending.Pop() -Force
    if ($current.LinkType -in @('SymbolicLink','Junction')) {
      if ($current.PSIsContainer) { [IO.Directory]::Delete($current.FullName) }
      else { [IO.File]::Delete($current.FullName) }
    } elseif ($current.PSIsContainer) {
      foreach ($child in (Get-ChildItem -LiteralPath $current.FullName -Force)) { $pending.Push($child.FullName) }
    } else { $files++; $bytes += $current.Length }
  }
  if (Test-Path -LiteralPath $absolute) {
    if ($item.PSIsContainer) { Remove-Item -LiteralPath $absolute -Recurse -Force }
    else { Remove-Item -LiteralPath $absolute -Force }
  }
  return [pscustomobject]@{ Files=$files; Bytes=$bytes }
}

# 遍历当前项目生成目录的实际文件，拒绝进入符号链接/联接目标，供清理预览与容量统计使用。
function Get-FastInkGeneratedFiles {
  param([string]$Path)
  $pending=New-Object 'Collections.Generic.Stack[string]'
  $pending.Push([IO.Path]::GetFullPath($Path))
  while($pending.Count -gt 0) {
    $item=Get-Item -LiteralPath $pending.Pop() -Force
    if($item.LinkType -in @('SymbolicLink','Junction')) {continue}
    if($item.PSIsContainer) {
      foreach($child in (Get-ChildItem -LiteralPath $item.FullName -Force)) {$pending.Push($child.FullName)}
    } else {Write-Output $item}
  }
}
