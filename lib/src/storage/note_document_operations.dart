part of 'note_repository.dart';

extension NoteDocumentOperations on NoteRepository {
  /// 只删除确认归当前资料库拥有的指定文稿存储，拒绝把外部原文件或资料库根目录当删除目标。
  Future<void> deleteDocumentStorage(
    String documentId,
    String sourcePath,
  ) async {
    final String normalizedRoot = _normalizedAbsolute(dataRoot);

    // Markdown 文件：删除 .md 文件及其父文件夹（如果是文档文件夹）。
    if (sourcePath.toLowerCase().endsWith('.md')) {
      final File mdFile = File(sourcePath);
      if (await mdFile.exists() &&
          _isStrictChild(mdFile.path, normalizedRoot)) {
        final Directory parent = mdFile.parent;
        final File meta = File('${parent.path}/.fastink-md.json');
        if (await meta.exists() &&
            _isStrictChild(parent.path, normalizedRoot)) {
          await _forceDeleteDirectory(parent);
        } else {
          await _forceDeleteFile(mdFile);
        }
      }
      return;
    }

    // 笔记文稿：删除墨迹存储目录。
    final Directory inkDirectory = Directory('$dataRoot/documents/$documentId');
    if (_isStrictChild(inkDirectory.path, normalizedRoot) &&
        await inkDirectory.exists()) {
      await _forceDeleteDirectory(inkDirectory);
    }

    // 导入的图片/PDF：删除导入目录。
    final Directory sourceDirectory = File(sourcePath).parent;
    final String importsRoot = _normalizedAbsolute('$dataRoot/imports');
    if (_isStrictChild(sourceDirectory.path, importsRoot) &&
        await sourceDirectory.exists()) {
      await _forceDeleteDirectory(sourceDirectory);
    }
  }

  /// 强制删除文件：清除只读标志 → 重试 → 重命名后标记待删。
  Future<void> _forceDeleteFile(File file) async {
    if (!await file.exists()) return;
    // 第 1 步：清除只读 / 隐藏属性（OneDrive 占位文件常带此标志）。
    try {
      final ProcessResult result = await Process.run('cmd', [
        '/c',
        'attrib',
        '-R',
        '-H',
        '-S',
        file.path,
      ], runInShell: true);
      if (result.exitCode != 0) {
        // attrib 可能因文件不存在而失败，忽略。
      }
    } catch (_) {}
    // 第 2 步：尝试删除，最多重试 3 次（OneDrive 同步锁可能短暂释放）。
    for (int attempt = 0; attempt < 3; attempt++) {
      try {
        await file.delete();
        return;
      } catch (_) {
        if (attempt < 2) {
          await Future<void>.delayed(
            Duration(milliseconds: 200 * (attempt + 1)),
          );
        }
      }
    }
    // 第 3 步：重命名为 .pending-delete 临时文件，下次启动时清理。
    try {
      final String tombstone = '${file.path}.pending-delete';
      await file.rename(tombstone);
    } catch (_) {}
  }

  /// 强制删除目录：递归清除属性后删除。
  Future<void> _forceDeleteDirectory(Directory dir) async {
    if (!await dir.exists()) return;
    // 递归清除所有文件的只读属性。
    try {
      await Process.run('cmd', [
        '/c',
        'attrib',
        '-R',
        '-H',
        '-S',
        '${dir.path}/*.*',
        '/S',
      ], runInShell: true);
    } catch (_) {}
    // 尝试删除，最多重试 3 次。
    for (int attempt = 0; attempt < 3; attempt++) {
      try {
        await dir.delete(recursive: true);
        return;
      } catch (_) {
        if (attempt < 2) {
          await Future<void>.delayed(
            Duration(milliseconds: 300 * (attempt + 1)),
          );
        }
      }
    }
    // 最后手段：逐文件重命名为 .pending-delete。
    try {
      await for (final FileSystemEntity entity in dir.list(recursive: true)) {
        if (entity is File) {
          try {
            await entity.rename('${entity.path}.pending-delete');
          } catch (_) {}
        }
      }
      // 尝试删除已清空的目录骨架。
      try {
        await dir.delete();
      } catch (_) {}
    } catch (_) {}
  }

  /// 打开导入文件选择器，返回用户所选路径集合，取消返回空列表。
  Future<List<File>> pickImportFiles({String? initialDirectory}) async {
    final OpenFilePicker picker = OpenFilePicker()
      ..filterSpecification = <String, String>{
        tr('所有支持的文稿', 'All supported documents'):
            '*.pdf;*.png;*.jpg;*.jpeg;*.webp;*.one;*.onex;*.onepkg',
        tr(
          'PDF 和图片 (*.pdf; *.png; *.jpg; *.webp)',
          'PDF and images (*.pdf; *.png; *.jpg; *.webp)',
        ): '*.pdf;*.png;*.jpg;*.jpeg;*.webp',
        tr('PDF 文档 (*.pdf)', 'PDF document (*.pdf)'): '*.pdf',
        'OneNote (*.one; *.onex; *.onepkg)': '*.one;*.onex;*.onepkg',
        tr('图片 (*.png; *.jpg; *.webp)', 'Images (*.png; *.jpg; *.webp)'):
            '*.png;*.jpg;*.jpeg;*.webp',
      }
      ..defaultFilterIndex = 0
      ..title = tr(
        '导入 PDF、图片或 OneNote（可多选）',
        'Import PDF, images or OneNote (multiple selection allowed)',
      );
    if (initialDirectory != null) picker.initialDirectory = initialDirectory;
    return picker.getFiles();
  }

  /// 打开只接受可用图像类型的选择器，返回原文件引用，导入时再复制。
  Future<List<File>> pickImageFiles({String? initialDirectory}) async {
    final OpenFilePicker picker = OpenFilePicker()
      ..filterSpecification = <String, String>{
        tr('图片 (*.png; *.jpg; *.webp)', 'Images (*.png; *.jpg; *.webp)'):
            '*.png;*.jpg;*.jpeg;*.webp',
      }
      ..defaultFilterIndex = 0
      ..title = tr('选择要插入的图片页', 'Choose image pages to insert');
    if (initialDirectory != null) picker.initialDirectory = initialDirectory;
    return picker.getFiles();
  }

  /// 选择要放到当前页面中的图片。这里与“插入图片页”使用不同的标题，
  /// 避免用户误以为图片会占用一整页。
  Future<List<File>> pickEmbeddedImageFiles({String? initialDirectory}) async {
    final OpenFilePicker picker = OpenFilePicker()
      ..filterSpecification = <String, String>{
        tr('图片 (*.png; *.jpg; *.webp)', 'Images (*.png; *.jpg; *.webp)'):
            '*.png;*.jpg;*.jpeg;*.webp',
      }
      ..defaultFilterIndex = 0
      ..title = tr('将图片放入当前页面', 'Place images on the current page');
    if (initialDirectory != null) picker.initialDirectory = initialDirectory;
    return picker.getFiles();
  }

  /// 选择兼容页面文件并建立文稿，用户取消返回 null。
  Future<NoteDocument?> pickImageNote({String? initialDirectory}) async {
    final OpenFilePicker picker = OpenFilePicker()
      ..filterSpecification = <String, String>{
        tr(
          '图片笔记页 (*.png; *.jpg; *.webp)',
          'Image note pages (*.png; *.jpg; *.webp)',
        ): '*.png;*.jpg;*.jpeg;*.webp',
        tr('所有文件', 'All files'): '*.*',
      }
      ..defaultFilterIndex = 0
      ..defaultExtension = 'png'
      ..title = tr('选择一页，自动打开同本笔记', 'Choose one page to open the entire note');
    if (initialDirectory != null) picker.initialDirectory = initialDirectory;
    final File? file = picker.getFile();
    if (file == null) return null;
    return indexFromSelectedPath(file.path);
  }

  /// 根据元数据、PDF 或图像路径选择索引流程，复用已有稳定文稿身份并恢复页面清单。
  Future<NoteDocument> indexFromSelectedPath(
    String selectedPath, {
    String? documentId,
  }) async {
    final File selected = File(selectedPath);
    if (!await selected.exists()) {
      throw FileSystemException(
        tr('页面不存在', 'Page does not exist'),
        selectedPath,
      );
    }

    final String directoryPath = selected.parent.path;
    final String selectedName = _fileName(selectedPath);
    final RegExpMatch? selectedMatch = _scrblePattern.firstMatch(selectedName);
    final List<_IndexedFile> indexed = <_IndexedFile>[];

    await for (final FileSystemEntity entity in selected.parent.list(
      followLinks: false,
    )) {
      if (entity is! File) continue;
      final String name = _fileName(entity.path);
      if (!_imagePattern.hasMatch(name)) continue;

      if (selectedMatch != null) {
        final RegExpMatch? match = _scrblePattern.firstMatch(name);
        if (match == null || match.group(1) != selectedMatch.group(1)) continue;
        indexed.add(
          _IndexedFile(
            path: entity.path,
            name: name,
            pageNumber: int.parse(match.group(2)!),
          ),
        );
      } else {
        indexed.add(_IndexedFile(path: entity.path, name: name, pageNumber: 0));
      }
    }

    if (selectedMatch != null) {
      indexed.sort((a, b) => a.pageNumber.compareTo(b.pageNumber));
    } else {
      indexed.sort((a, b) => _naturalCompare(a.name, b.name));
      for (int i = 0; i < indexed.length; i++) {
        indexed[i] = indexed[i].withPageNumber(i + 1);
      }
    }
    if (indexed.isEmpty) {
      throw StateError(
        tr('没有找到同一本笔记的页面。', 'No pages from the same note were found.'),
      );
    }

    final String title = selectedMatch?.group(1) ?? _fileName(directoryPath);
    final List<NotePage> pages = <NotePage>[
      for (int i = 0; i < indexed.length; i++)
        NotePage(
          index: i,
          originalPage: indexed[i].pageNumber,
          path: indexed[i].path,
          name: indexed[i].name,
        ),
    ];
    final int selectedIndex = pages.indexWhere(
      (page) => _samePath(page.path, selectedPath),
    );

    final NoteDocument indexedDocument = NoteDocument(
      id: documentId ?? _stableId('$directoryPath\u0000$title'),
      title: title,
      directory: directoryPath,
      pages: pages,
      initialIndex: selectedIndex < 0 ? 0 : selectedIndex,
    );
    return _loadDocumentManifest(indexedDocument);
  }
}
