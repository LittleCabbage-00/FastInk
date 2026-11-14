param([Parameter(Mandatory=$true)][string]$Source,[Parameter(Mandatory=$true)][string]$Destination)
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
$OutputEncoding=[Console]::OutputEncoding
function Emit($value) { [Console]::WriteLine(($value | ConvertTo-Json -Depth 100 -Compress)) }
function Local-Child([string]$path,[string]$root) {
  return [IO.Path]::GetFullPath($path).StartsWith([IO.Path]::GetFullPath($root).TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)
}
$app=$null
$book=''
try {
  $sourcePath=[IO.Path]::GetFullPath($Source)
  $work=[IO.Path]::GetFullPath($Destination)
  if(-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {throw 'Source file does not exist.'}
  $ext=[IO.Path]::GetExtension($sourcePath).ToLowerInvariant()
  if($ext -notin @('.one','.onex','.onepkg')) {throw 'Unsupported OneNote extension.'}
  if(-not (Test-Path -LiteralPath $work -PathType Container)) {throw 'Import workspace does not exist.'}
  if(@(Get-ChildItem -LiteralPath $work -Force).Count -gt 0) {throw 'Import workspace must be empty.'}
  if((Get-Item -LiteralPath $work).Attributes -band [IO.FileAttributes]::ReparsePoint) {throw 'Import workspace must not be a link.'}
  Emit @{type='progress';message='Reading OneNote content';completed=0;total=0}
  try {$app=New-Object -ComObject OneNote.Application} catch {throw 'Desktop OneNote is required. Install or repair the desktop version of OneNote.'}
  $notebook=Join-Path $work 'notebook'
  [void][IO.Directory]::CreateDirectory($notebook)
  if($ext -eq '.onepkg') {
    $package=Join-Path $work 'source.onepkg'
    Copy-Item -LiteralPath $sourcePath -Destination $package
    # 使用 Windows 内置 SetupAPI 解包 CAB，无需打开 OneNote 的
    # 交互式导包向导；创建文件前检查每个输出路径。
    Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Collections.Generic;
public static class FastInkCab {
 [StructLayout(LayoutKind.Sequential,CharSet=CharSet.Unicode)]
 struct Entry { public IntPtr Name; public uint Size,Error; public ushort Date,Time,Attributes; [MarshalAs(UnmanagedType.ByValTStr,SizeConst=260)] public string Target; }
 delegate uint Callback(IntPtr context,uint notification,IntPtr p1,IntPtr p2);
 [DllImport("setupapi.dll",CharSet=CharSet.Unicode,SetLastError=true)]
 static extern bool SetupIterateCabinetW(string cabinet,uint reserved,Callback callback,IntPtr context);
 public static void Extract(string cabinet,string directory) {
  string root=Path.GetFullPath(directory).TrimEnd('\\')+"\\";
  Exception failure=null;
  ulong total=0; int count=0;
  var names=new HashSet<string>(StringComparer.OrdinalIgnoreCase);
  Callback callback=(context,notification,p1,p2)=>{
   try {
    if(notification==17) {
     var entry=(Entry)Marshal.PtrToStructure(p1,typeof(Entry));
     string name=Marshal.PtrToStringUni(entry.Name).Replace('/','\\');
     if(Path.IsPathRooted(name) || name.Contains(":")) throw new InvalidDataException("Unsafe package member.");
     foreach(string part in name.Split('\\')) {
      string stem=part.Split('.')[0].ToUpperInvariant();
      if(part.Length==0 || part=="." || part==".." || part.EndsWith(".") || part.EndsWith(" ") || stem=="CON" || stem=="PRN" || stem=="AUX" || stem=="NUL" || System.Text.RegularExpressions.Regex.IsMatch(stem,@"^(COM|LPT)[1-9]$")) throw new InvalidDataException("Unsafe package member.");
     }
     string target=Path.GetFullPath(Path.Combine(root,name));
     if(!target.StartsWith(root,StringComparison.OrdinalIgnoreCase) || target.Length>=260 || !names.Add(target)) throw new InvalidDataException("Invalid or duplicate package path.");
     total+=entry.Size; count++;
     if(total>4294967296UL || count>10000) throw new InvalidDataException("Package exceeds import limits.");
     string ext=Path.GetExtension(target).ToLowerInvariant();
     if(ext!=".one" && ext!=".onex" && ext!=".onetoc2") return 2;
     Directory.CreateDirectory(Path.GetDirectoryName(target));
     entry.Target=target;
     Marshal.StructureToPtr(entry,p1,false);
     return 1;
    }
    if(notification==19) {
     int error=Marshal.ReadInt32(p1,IntPtr.Size*2);
     if(error!=0) throw new Win32Exception(error);
    }
    if(notification==18) throw new InvalidDataException("Multi-volume packages are not supported.");
    return 0;
   } catch(Exception error) {failure=error;return 0;}
  };
  bool success=SetupIterateCabinetW(cabinet,0,callback,IntPtr.Zero);
  GC.KeepAlive(callback);
  if(failure!=null) throw failure;
  if(!success) throw new Win32Exception(Marshal.GetLastWin32Error());
 }
}
'@
    [FastInkCab]::Extract($package,$notebook)
    $children=@(Get-ChildItem -LiteralPath $notebook -Directory)
    if($children.Count -eq 1 -and @(Get-ChildItem -LiteralPath $notebook -File -Filter '*.one').Count -eq 0) {$notebook=$children[0].FullName}
  } else {
    Copy-Item -LiteralPath $sourcePath -Destination (Join-Path $notebook ([IO.Path]::GetFileNameWithoutExtension($sourcePath)+'.one'))
  }
  $app.OpenHierarchy($notebook,'',[ref]$book,0)
  foreach($file in @(Get-ChildItem -LiteralPath $notebook -Recurse -File -Filter '*.onex')) {
    $target=[IO.Path]::ChangeExtension($file.FullName,'.one')
    if(-not (Local-Child $target $work) -or (Test-Path -LiteralPath $target)) {throw 'Conflicting section names in package.'}
    Move-Item -LiteralPath $file.FullName -Destination $target
  }
  $sectionTrees=New-Object Xml.XmlDocument
  $sectionGroups=@{}
  $sectionTrees.LoadXml('<Sections/>')
  foreach($file in @(Get-ChildItem -LiteralPath $notebook -Recurse -File -Filter '*.one')) {
    if(-not (Local-Child $file.FullName $work) -or ($file.Attributes -band [IO.FileAttributes]::ReparsePoint)) {throw 'Invalid section path.'}
    $sectionId=''
    $relative=$file.FullName.Substring($notebook.TrimEnd('\').Length).TrimStart('\')
    $app.OpenHierarchy($relative,$book,[ref]$sectionId,0)
    $sectionXml=''
    for($attempt=0;$attempt -lt 80;$attempt++) {
      try {
        $app.GetHierarchy($sectionId,4,[ref]$sectionXml,2)
        break
      } catch {
        if($attempt -eq 79 -or $_.Exception.InnerException.HResult -ne -2147213283) {throw}
        Start-Sleep -Milliseconds 250
      }
    }
    if($sectionXml) {
      [xml]$sectionTree=$sectionXml
      [void]$sectionTrees.DocumentElement.AppendChild($sectionTrees.ImportNode($sectionTree.DocumentElement,$true))
      $relativeDirectory=[IO.Path]::GetDirectoryName($relative)
      $sectionGroups[$sectionId]=@($relativeDirectory.Split('\') | Where-Object {$_})
    }
  }
  $hierarchy=''
  $app.GetHierarchy($book,4,[ref]$hierarchy,2)
  [IO.File]::WriteAllText((Join-Path $work 'hierarchy.xml'),$hierarchy,[Text.UTF8Encoding]::new($false))
  [xml]$tree=$sectionTrees
  $sections=@($tree.SelectNodes('//*[local-name()="Section"]'))
  $pages=@($tree.SelectNodes('//*[local-name()="Page"]'))
  if($pages.Count -eq 0) {throw 'No readable pages found. The notebook may be empty or password protected.'}
  [void][IO.Directory]::CreateDirectory((Join-Path $work 'pages'))
  Add-Type -AssemblyName PresentationCore,WindowsBase
  $done=0
  foreach($section in $sections) {
    $groups=New-Object Collections.Generic.List[string]
    foreach($group in @($sectionGroups[$section.GetAttribute('ID')])) {if($group){$groups.Add($group)}}
    $parent=$section.ParentNode
    $recycle=$false
    while($parent -and $parent.NodeType -eq [Xml.XmlNodeType]::Element) {
      if($parent.GetAttribute('isRecycleBin') -eq 'true') {$recycle=$true}
      if($parent.LocalName -eq 'SectionGroup') {$groups.Insert(0,$parent.GetAttribute('name'))}
      $parent=$parent.ParentNode
    }
    if($recycle) {continue}
    if($section.GetAttribute('isLocked') -eq 'true') {
      Emit @{type='warning';message=('Locked section: '+$section.GetAttribute('name'))}
      continue
    }
    foreach($page in @($section.SelectNodes('./*[local-name()="Page"]'))) {
      $pageXml=''
      $app.GetPageContent($page.GetAttribute('ID'),[ref]$pageXml,7,2)
      $stem=Join-Path $work ('pages\page-'+$done)
      [IO.File]::WriteAllText(($stem+'.xml'),$pageXml,[Text.UTF8Encoding]::new($false))
      [xml]$pageTree=$pageXml
      $inkObjects=New-Object Collections.Generic.List[object]
      $inkNodes=@($pageTree.SelectNodes('//*[local-name()="InkDrawing" or local-name()="InkWord"]'))
      for($i=0;$i -lt $inkNodes.Count;$i++) {
        $data=$inkNodes[$i].SelectSingleNode('./*[local-name()="Data"]')
        if(-not $data) {continue}
        try {
          $bytes=[Convert]::FromBase64String($data.InnerText)
          $stream=[IO.MemoryStream]::new($bytes,$false)
          try {$ink=[Windows.Ink.StrokeCollection]::new($stream)} finally {$stream.Dispose()}
          $bounds=$ink.GetBounds()
          $strokes=New-Object Collections.Generic.List[object]
          foreach($stroke in $ink) {
            $attr=$stroke.DrawingAttributes
            $color=$attr.Color
            $argb=([long]$color.A -shl 24) -bor ([long]$color.R -shl 16) -bor ([long]$color.G -shl 8) -bor [long]$color.B
            $points=New-Object Collections.Generic.List[object]
            foreach($point in $stroke.StylusPoints) {$points.Add(@([double]$point.X,[double]$point.Y,[double]$point.PressureFactor))}
            $strokes.Add(@{color=$argb;width=[double]$attr.Width;height=[double]$attr.Height;highlighter=$attr.IsHighlighter;ignorePressure=$attr.IgnorePressure;points=$points.ToArray()})
          }
          $inkObjects.Add(@{index=$i;bounds=@($bounds.X,$bounds.Y,$bounds.Width,$bounds.Height);strokes=$strokes.ToArray()})
        } catch {
          Emit @{type='warning';message=('Ink could not be decoded on '+$page.GetAttribute('name')+': '+$_.Exception.Message)}
        }
      }
      [IO.File]::WriteAllText(($stem+'.ink.json'),(ConvertTo-Json -InputObject $inkObjects.ToArray() -Depth 100 -Compress),[Text.UTF8Encoding]::new($false))
      Emit @{type='page';title=$page.GetAttribute('name');section=$section.GetAttribute('name');groups=$groups.ToArray();level=$page.GetAttribute('pageLevel');xml=($stem+'.xml');ink=($stem+'.ink.json')}
      $done++
      Emit @{type='progress';message=('Read '+$done+' / '+$pages.Count+' pages');completed=$done;total=$pages.Count}
    }
  }
  Emit @{type='complete';pages=$done}
} catch {
  Emit @{type='error';message=$_.Exception.Message}
  exit 1
} finally {
  # 此 ID 始终属于私有副本；不退出 OneNote，不关闭已打开的
  # 笔记本，不改变用户选区，也不回写原始文件。
  if($app) {
    if($book) {try {$app.CloseNotebook($book,$false)} catch {Emit @{type='warning';message='The private import notebook could not be closed automatically.'}}}
    [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($app)
  }
}
