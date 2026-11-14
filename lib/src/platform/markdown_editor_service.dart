/// Markdown 编辑器核心服务。
///
/// 负责文件读写、自动保存、图片资源和 TOC 提取。
///
/// 外部文件流程：
///   openExternalAsTemp → 只读预览 → 显式 saveToPath / importToLibrary。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'markdown_history.dart';
import 'markdown_encoding.dart';

/// 单个 Markdown 文件的运行时状态。
class MarkdownFileState {
  /// 创建当前 Markdown 文件状态，记录路径、显示标题、正文和是否已修改，和编辑器组件生命周期分开。
  MarkdownFileState({
    required this.path,
    this.content = '',
    this.isDirty = false,
    this.lastSavedContent = '',
    this.tocItems = const <TocItem>[],
  });

  /// 当前文件路径（可能是 temp 路径或资料库路径）。
  final String path;

  /// 当前编辑内容。
  String content;

  /// 是否有未保存的修改。
  bool isDirty;

  /// 上次保存时的内容快照。
  String lastSavedContent;

  /// 从内容中提取的目录条目。
  List<TocItem> tocItems;

  /// 文件名（不含路径）。
  String get fileName => File(path).uri.pathSegments.last;
}

/// 目录条目。
class TocItem {
  /// 创建不可变的 TocItem 参数对象；各参数保存在对应字段中，不在构造时执行外部读写。
  /// 保存和显示使用的完整标题。
  /// level：Markdown 标题层级，用于目录缩进和跳转组织。
  /// offset：标题在 Markdown 原文中的字符偏移，供选区和定位使用。
  const TocItem({
    required this.title,
    required this.level,
    required this.offset,
  });

  /// 保存和显示使用的完整标题。
  final String title;

  /// level：Markdown 标题层级，用于目录缩进和跳转组织。
  final int level;

  /// offset：标题在 Markdown 原文中的字符偏移，供选区和定位使用。
  final int offset;
}

/// Markdown 文件服务。
class MarkdownEditorService {
  /// _autoSaveTimer：Markdown 自动保存的延迟任务，连续输入重置，离开或关闭时取消/刷盘。
  Timer? _autoSaveTimer;

  /// _state：服务当前装载的 Markdown 文件状态，为空时还没有可读写文件。
  MarkdownFileState? _state;

  /// 返回当前已加载文件状态，尚未建立文稿时返回 null。
  MarkdownFileState? get state => _state;

  /// _autoSaveDelayMs：Markdown 自动保存防抖时长，单位毫秒。
  int _autoSaveDelayMs = 300;

  /// _autoSaveEnabled：Markdown 服务自动保存开关，关闭时不继续保留旧定时任务。
  bool _autoSaveEnabled = true;

  /// autoSaveDelayMs：修改后自动保存的等待时间，单位毫秒，连续输入会重新计时。
  int get autoSaveDelayMs => _autoSaveDelayMs;

  /// 更新autoSaveDelayMs：修改后自动保存的等待时间，单位毫秒，连续输入会重新计时。
  set autoSaveDelayMs(int value) {
    _autoSaveDelayMs = value.clamp(100, 5000);
    if (_state?.isDirty == true) _scheduleAutoSave();
  }

  /// autoSaveEnabled：手写笔迹自动保存开关；关闭不取消切页/退出刷盘。
  bool get autoSaveEnabled => _autoSaveEnabled;

  /// 更新autoSaveEnabled：手写笔迹自动保存开关；关闭不取消切页/退出刷盘。
  set autoSaveEnabled(bool value) {
    _autoSaveEnabled = value;
    _autoSaveTimer?.cancel();
    if (value && _state?.isDirty == true) _scheduleAutoSave();
  }

  /// onAutoSaved：自动保存完成回调，success 表示该次写入结果，宿主据此更新提示。
  void Function(bool success)? onAutoSaved;

  /// history：Markdown 修订历史服务，按配置保存已变化的版本，不等同于编辑器 Ctrl+Z 栈。
  MarkdownHistory? history;

  /// historyEnabled：是否为 Markdown 保存本地修订历史。
  bool historyEnabled = true;

  /// historyLimit：每篇 Markdown 保留的修订数量上限。
  int historyLimit = 50;

  /// detectedEncoding：最近载入文件识别到的编码名称，源文编辑与导出可据此提示。
  String detectedEncoding = 'UTF-8';

  /// _writes：Markdown 文件写入串行队列，避免较早的异步保存覆盖较新的正文。
  Future<void> _writes = Future<void>.value();

  // ============================================================
  //  打开方式
  // ============================================================

  /// 打开资料库中的文件或文档文件夹。
  ///
  /// 如果传入的是文件夹路径（文档文件夹），自动查找其中的 .md 文件。
  Future<MarkdownFileState> openFile(String path) async {
    String mdPath = path;
    if (Directory(path).existsSync()) {
      // 文档文件夹：找到其中的 .md 文件。
      _documentDir = path;
      final FileSystemEntity? mdFile = Directory(path)
          .listSync()
          .whereType<File>()
          .where((f) => f.path.toLowerCase().endsWith('.md'))
          .firstOrNull;
      mdPath = mdFile?.path ?? '$path${Platform.pathSeparator}untitled.md';
    }
    final File file = File(mdPath);
    _documentDir = file.parent.path;
    String content = '';
    if (file.existsSync()) {
      final decoded = await MarkdownEncoding.read(file);
      content = decoded.$1;
      detectedEncoding = decoded.$2;
    }
    _state = MarkdownFileState(
      path: mdPath,
      content: content,
      lastSavedContent: content,
      tocItems: extractToc(content),
    );
    return _state!;
  }

  /// 外部文件打开：复制到 %temp%/FastInk/ 后只读预览。
  ///
  /// 返回的 [MarkdownFileState.path] 指向临时副本。
  /// 原始路径保存在 [externalSourcePath] 中，供后续覆盖或导入时使用。
  Future<MarkdownFileState> openExternalAsTemp(String sourcePath) async {
    final File source = File(sourcePath);
    _documentDir = source.parent.path;
    final tempRoot = await Directory(_tempDir()).create(recursive: true);
    final Directory dir = await tempRoot.createTemp('markdown-');
    final String fileName = File(sourcePath).uri.pathSegments.last;
    final String tempPath = '${dir.path}${Platform.pathSeparator}$fileName';
    final File tempFile = File(tempPath);
    await source.copy(tempPath);
    final decoded = await MarkdownEncoding.read(tempFile);
    final String content = decoded.$1;
    detectedEncoding = decoded.$2;
    _state = MarkdownFileState(
      path: tempPath,
      content: content,
      lastSavedContent: content,
      tocItems: extractToc(content),
    );
    externalSourcePath = sourcePath;
    return _state!;
  }

  /// 当前文档的文件夹路径（包含 .md 文件和 assets/ 子目录）。
  String? _documentDir;

  /// 当前文档的资源文件夹路径。
  String get assetsDir => '${_documentDir!}${Platform.pathSeparator}assets';

  /// 创建新文档（在资料库目录中创建独立文件夹）。
  ///
  /// 结构：`directory/未命名-时间戳/未命名-时间戳.md` + `assets/` 子目录。
  MarkdownFileState createNew(String directory) {
    final String timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .substring(0, 19);
    String baseName = '未命名-$timestamp';
    int suffix = 2;
    while (Directory(
      '$directory${Platform.pathSeparator}$baseName',
    ).existsSync()) {
      baseName = '未命名-$timestamp-${suffix++}';
    }
    _documentDir = '$directory${Platform.pathSeparator}$baseName';
    Directory(_documentDir!).createSync(recursive: true);
    Directory(assetsDir).createSync(recursive: true);
    // 写入元数据，标记为 Markdown 文档文件夹。
    _writeMetadata(baseName);
    final String path = '$_documentDir${Platform.pathSeparator}$baseName.md';
    _state = MarkdownFileState(path: path, content: '');
    return _state!;
  }

  /// 写入 .fastink-md.json 元数据。
  void _writeMetadata(String name) {
    if (_documentDir == null) return;
    final File meta = File(
      '$_documentDir${Platform.pathSeparator}.fastink-md.json',
    );
    meta.writeAsStringSync(
      jsonEncode(<String, Object?>{
        'name': name,
        'createdAt': DateTime.now().toIso8601String(),
      }),
    );
  }

  /// 把图片文件插入到当前文档的 assets/ 目录，返回相对路径。
  ///
  /// 在编辑器中插入 `![](assets/filename.png)`。
  Future<String?> insertImage(File sourceFile) async {
    if (_documentDir == null) return null;
    final Directory assets = Directory(assetsDir);
    if (!assets.existsSync()) assets.createSync(recursive: true);
    final String originalName = sourceFile.uri.pathSegments.last;
    // 避免文件名冲突。
    String destName = originalName;
    int i = 1;
    while (File(
      '${assets.path}${Platform.pathSeparator}$destName',
    ).existsSync()) {
      final String ext = originalName.contains('.')
          ? '.${originalName.split('.').last}'
          : '';
      final String base = originalName.contains('.')
          ? originalName.substring(0, originalName.lastIndexOf('.'))
          : originalName;
      destName = '$base-$i$ext';
      i++;
    }
    await sourceFile.copy('${assets.path}${Platform.pathSeparator}$destName');
    return 'assets/$destName';
  }

  /// 把剪贴板图像字节保存为当前文稿的独立资源，返回可写入 Markdown 的相对引用路径。
  Future<String> insertImageBytes(Uint8List bytes) async {
    if (_documentDir == null ||
        bytes.length < 8 ||
        bytes.length > 64000000 ||
        !List.generate(
          8,
          (i) => bytes[i],
        ).join(',').startsWith('137,80,78,71,13,10,26,10')) {
      throw const FormatException('Invalid clipboard PNG');
    }
    final assets = await Directory(assetsDir).create(recursive: true);
    final name = 'paste-${DateTime.now().microsecondsSinceEpoch}.png';
    await File(
      '${assets.path}${Platform.pathSeparator}$name',
    ).writeAsBytes(bytes, flush: true);
    return 'assets/$name';
  }

  // ============================================================
  //  外部文件状态
  // ============================================================

  /// 外部文件的原始路径（非 null 表示来自外部文件）。
  String? externalSourcePath;

  /// FastInk 临时文件目录。
  static String _tempDir() {
    final String base =
        Platform.environment['TEMP'] ??
        Platform.environment['TMP'] ??
        Platform.environment['LOCALAPPDATA'] ??
        Directory.systemTemp.path;
    return '$base${Platform.pathSeparator}FastInk';
  }

  // ============================================================
  //  重命名
  // ============================================================

  /// 重命名当前文件。返回新路径，失败返回 null。
  ///
  /// 同时更新磁盘文件名和文件夹内的元数据。
  Future<String?> rename(String newName) async {
    final MarkdownFileState? s = _state;
    if (s == null ||
        newName.trim().isEmpty ||
        RegExp(r'[<>:"/\\|?*\x00-\x1f]').hasMatch(newName) ||
        newName.endsWith('.') ||
        newName.endsWith(' ')) {
      return null;
    }
    await _writes;
    try {
      final File oldFile = File(s.path);
      final String dir = oldFile.parent.path;
      final String ext = '.md';
      final String safeName = newName.endsWith(ext) ? newName : '$newName$ext';
      final String newPath = '$dir${Platform.pathSeparator}$safeName';
      if (newPath != s.path) {
        if (File(newPath).existsSync()) return null;
        if (oldFile.existsSync()) {
          await oldFile.rename(newPath);
        }
        // 文件尚未落盘时（新建后未保存），只更新路径，后续 save() 会创建。
      }
      // 更新元数据（如果有）。
      final File meta = File('$dir${Platform.pathSeparator}.fastink-md.json');
      if (meta.existsSync()) {
        try {
          final Map<String, Object?> json =
              jsonDecode(meta.readAsStringSync()) as Map<String, Object?>;
          json['name'] = newName;
          meta.writeAsStringSync(
            const JsonEncoder.withIndent('  ').convert(json),
          );
        } catch (_) {}
      }
      // 更新内部状态。
      _state = MarkdownFileState(
        path: newPath,
        content: s.content,
        isDirty: s.isDirty,
        lastSavedContent: s.lastSavedContent,
        tocItems: s.tocItems,
      );
      await history?.renamed(s.path, newPath);
      return newPath;
    } catch (_) {
      return null;
    }
  }

  // ============================================================
  //  编辑与保存
  // ============================================================

  /// 更新内容（触发自动保存）。
  void updateContent(String newContent) {
    if (_state == null) return;
    _state!.content = newContent;
    _state!.isDirty = newContent != _state!.lastSavedContent;
    _state!.tocItems = extractToc(newContent);
    _scheduleAutoSave();
  }

  /// 保存到当前路径（temp 或资料库）。
  ///
  /// 文件不存在时无条件写入（新建文档首次保存）。
  Future<bool> save() async {
    final MarkdownFileState? s = _state;
    if (s == null) return true;
    if (!s.isDirty && File(s.path).existsSync()) return true;
    final String content = s.content;
    final bool ok = await _writeToFile(s.path, content);
    if (ok) {
      s.lastSavedContent = content;
      s.isDirty = s.content != content;
    }
    return ok;
  }

  /// 保存到指定路径（用于"编辑原文件"直接覆盖原始文件）。
  Future<bool> saveToPath(String targetPath) async {
    final MarkdownFileState? s = _state;
    if (s == null) return false;
    final String content = s.content;
    final bool ok = await _writeToFile(targetPath, content);
    if (ok) {
      // 同时更新 temp 副本，保持一致。
      if (s.path != targetPath) {
        await _writeToFile(s.path, content);
      }
      s.lastSavedContent = content;
      s.isDirty = s.content != content;
    }
    return ok;
  }

  /// 导入到资料库：复制 temp 文件到 library 目录，更新路径。
  ///
  /// 导入后外部模式解除，后续保存直接写资料库文件。
  Future<String?> importToLibrary(String libraryRoot) async {
    final MarkdownFileState? s = _state;
    if (s == null) return null;
    try {
      final String fileName = File(
        externalSourcePath ?? s.path,
      ).uri.pathSegments.last;
      final String base = fileName.replaceFirst(
        RegExp(r'\.md$', caseSensitive: false),
        '',
      );
      String destPath = '$libraryRoot${Platform.pathSeparator}$base.md';
      int suffix = 2;
      while (File(destPath).existsSync()) {
        destPath = '$libraryRoot${Platform.pathSeparator}$base-${suffix++}.md';
      }
      // 确保资料库目录存在。
      final Directory libDir = Directory(libraryRoot);
      if (!libDir.existsSync()) libDir.createSync(recursive: true);
      // 把当前内容写到资料库路径。
      final content = await copyLocalImages(
        content: s.content,
        sourcePath: externalSourcePath ?? s.path,
        targetPath: destPath,
      );
      if (!await _writeToFile(destPath, content)) return null;
      // 更新状态，切换为资料库模式。
      _state = MarkdownFileState(
        path: destPath,
        content: content,
        lastSavedContent: content,
        tocItems: extractToc(content),
      );
      externalSourcePath = null;
      _documentDir = File(destPath).parent.path;
      return destPath;
    } catch (_) {
      return null;
    }
  }

  /// 另存为新路径。
  Future<bool> saveAs(String newPath) async {
    final MarkdownFileState? s = _state;
    if (s == null) return false;
    final bool ok = await _writeToFile(newPath, s.content);
    if (ok) {
      _state = MarkdownFileState(
        path: newPath,
        content: s.content,
        lastSavedContent: s.content,
        tocItems: s.tocItems,
      );
      externalSourcePath = null;
    }
    return ok;
  }

  // ============================================================
  //  TOC 提取
  // ============================================================

  /// 只复制本地图片引用，远程链接原样保留；目标附件
  /// 使用独立目录，避免覆盖无关文件。
  static Future<String> copyLocalImages({
    required String content,
    required String sourcePath,
    required String targetPath,
  }) async {
    final base = File(sourcePath).absolute.uri;
    Directory? assets;
    final replacements = <String, String>{};
    final pattern = RegExp(
      r'!\[([^\]]*)\]\(\s*(?:<([^>]+)>|([^\s)]+))(?:\s+"[^"]*")?\s*\)',
    );
    for (final match in pattern.allMatches(content)) {
      final raw = match.group(2) ?? match.group(3)!;
      if (replacements.containsKey(raw)) continue;
      final uri = base.resolve(raw);
      if (uri.scheme != 'file') continue;
      final file = File.fromUri(uri);
      if (!await file.exists()) continue;
      if (assets == null) {
        final target = File(targetPath);
        await target.parent.create(recursive: true);
        final name = target.uri.pathSegments.last.replaceFirst(
          RegExp(r'\.md$', caseSensitive: false),
          '',
        );
        assets = await target.parent.createTemp('$name.assets-');
      }
      final original = file.uri.pathSegments.last;
      var name = original;
      int suffix = 2;
      while (await File(
        '${assets.path}${Platform.pathSeparator}$name',
      ).exists()) {
        name = '${suffix++}-$original';
      }
      await file.copy('${assets.path}${Platform.pathSeparator}$name');
      replacements[raw] =
          '${assets.uri.pathSegments.where((s) => s.isNotEmpty).last}/$name';
    }
    return content.replaceAllMapped(pattern, (match) {
      final replacement = replacements[match.group(2) ?? match.group(3)!];
      return replacement == null
          ? match.group(0)!
          : '![${match.group(1)}](<$replacement>)';
    });
  }

  /// 解析真实标题建立目录，跳过代码围栏中的伪标题并保留全文字符偏移。
  static List<TocItem> extractToc(String content) {
    if (content.isEmpty) return const <TocItem>[];
    final List<TocItem> items = <TocItem>[];
    int offset = 0;
    String? fence;
    int fenceLength = 0;
    final lines = content.split('\n');
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final marker = RegExp(r'^ {0,3}(`{3,}|~{3,})').firstMatch(line);
      if (marker != null) {
        final value = marker.group(1)!;
        if (fence == null) {
          fence = value[0];
          fenceLength = value.length;
        } else if (value[0] == fence &&
            value.length >= fenceLength &&
            line.substring(marker.end).trim().isEmpty) {
          fence = null;
        }
      } else if (fence == null) {
        final match = RegExp(
          r'^ {0,3}(#{1,6})\s+(.+)$',
        ).firstMatch(line.trimRight());
        final setext =
            i + 1 < lines.length &&
            line.trim().isNotEmpty &&
            RegExp(r'^ {0,3}(=+|-+)\s*$').hasMatch(lines[i + 1]);
        if (match != null || setext) {
          items.add(
            TocItem(
              title: match != null
                  ? match
                        .group(2)!
                        .replaceFirst(RegExp(r'\s+#+\s*$'), '')
                        .trim()
                  : line.trim(),
              level: match != null
                  ? match.group(1)!.length
                  : (lines[i + 1].trimLeft().startsWith('=') ? 1 : 2),
              offset: offset,
            ),
          );
        }
      }
      offset += line.length + 1;
    }
    return items;
  }

  /// 返回实际待办标记的源文偏移，供勾选操作原位替换，代码示例不参与。
  static List<int> taskOffsets(String content) {
    final offsets = <int>[];
    int position = 0;
    String? fence;
    int fenceLength = 0;
    for (final line in content.split('\n')) {
      final marker = RegExp(r'^ {0,3}(`{3,}|~{3,})').firstMatch(line);
      if (marker != null) {
        final value = marker.group(1)!;
        if (fence == null) {
          fence = value[0];
          fenceLength = value.length;
        } else if (value[0] == fence &&
            value.length >= fenceLength &&
            line.substring(marker.end).trim().isEmpty) {
          fence = null;
        }
      } else if (fence == null) {
        final match = RegExp(
          r'^\s*(?:[-+*]|\d+[.)])\s+\[([ xX])\]',
        ).firstMatch(line);
        if (match != null) offsets.add(position + match.end - 2);
      }
      position += line.length + 1;
    }
    return offsets;
  }

  /// 将正文写入给定路径并返回成功状态，写入任务仍经过串行队列，失败不能冒充已保存。
  Future<bool> _writeToFile(String path, String content) {
    final result = _writes.then((_) async {
      try {
        final file = File(path);
        await file.parent.create(recursive: true);
        if (historyEnabled &&
            history != null &&
            (externalSourcePath == null
                ? path == _state?.path
                : path == externalSourcePath) &&
            await file.exists()) {
          final previous = (await MarkdownEncoding.read(file)).$1;
          if (previous != content) {
            await history!.capture(path, previous, limit: historyLimit);
          }
        }
        final temporary = File(
          '$path.fastink-${DateTime.now().microsecondsSinceEpoch}.tmp',
        );
        try {
          await temporary.writeAsString(content, flush: true);
          await temporary.rename(path);
        } finally {
          if (await temporary.exists()) await temporary.delete();
        }
        return true;
      } catch (_) {
        return false;
      }
    });
    _writes = result.then((_) {});
    return result;
  }

  /// 取消旧保存计时，根据开关和防抖时长为当前脏文件安排自动保存。
  void _scheduleAutoSave() {
    _autoSaveTimer?.cancel();
    if (!autoSaveEnabled) return;
    _autoSaveTimer = Timer(Duration(milliseconds: autoSaveDelayMs), () async {
      final ok = await save();
      onAutoSaved?.call(ok);
    });
  }

  /// 取消尚未触发的自动保存，解除保存完成回调。
  void dispose() {
    _autoSaveTimer?.cancel();
    onAutoSaved = null;
  }
}
