part of '../../app/fastink_app.dart';

extension _FastInkLibraryCore on _FastInkHomeState {
  /// 查询变化后刷新列表，非空全域搜索关闭原展开目录；不更换整棵资料库组件身份。
  void _librarySearchChanged() {
    if (mounted) {
      _updateState(() {
        if (_searchInput.text.trim().isNotEmpty) _activeFolderId = null;
      });
    }
  }

  /// 读取索引、清理失效 Markdown 记录并扫描未登记源文，最后更新轻量资料库状态。
  Future<void> _loadLibrary() async {
    _cleanupPendingDeletes(_dataRoot);
    LibraryState library = await _libraryRepository.load();
    if (!mounted) return;
    // 清理磁盘上已不存在的 Markdown 索引条目（重命名、手动删除等场景）。
    library = _cleanStaleMarkdown(library);
    // 扫描资料库目录，自动注册磁盘上存在但 library.json 中缺失的 Markdown 文件。
    library = await _scanUnregisteredMarkdown(library);
    if (!mounted) return;
    _updateState(() {
      _library = library;
      _libraryLoaded = true;
    });
  }

  /// 清理上次删除失败遗留的 .pending-delete 文件。
  void _cleanupPendingDeletes(String root) {
    try {
      final Directory dir = Directory(root);
      if (!dir.existsSync()) return;
      for (final FileSystemEntity entity in dir.listSync(recursive: true)) {
        if (entity is File && entity.path.endsWith('.pending-delete')) {
          try {
            entity.deleteSync();
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  /// 移除索引中指向磁盘上已不存在的 Markdown 文件的条目。
  LibraryState _cleanStaleMarkdown(LibraryState library) {
    final List<LibraryDocument> kept = <LibraryDocument>[];
    bool changed = false;
    final seen = <String>{};
    for (final LibraryDocument doc in library.documents) {
      if (doc.scope == LibraryScope.markdown &&
          (!File(doc.sourcePath).existsSync() ||
              !seen.add(_markdownPath(doc.sourcePath)))) {
        changed = true;
        continue;
      }
      kept.add(doc);
    }
    if (!changed) return library;
    final LibraryState cleaned = LibraryState(
      documents: kept,
      folders: library.folders,
    );
    _libraryRepository.save(cleaned);
    return cleaned;
  }

  /// 扫描 dataRoot 下的 Markdown 文件，注册未被 library.json 追踪的文件。
  ///
  /// 两种结构都会扫描：
  ///   1. 子文件夹 + `.fastink-md.json` 元数据（新建 Markdown 产生的）。
  ///   2. dataRoot 根目录的 `.md` 文件（"导入到资料库" 产生的）。
  Future<LibraryState> _scanUnregisteredMarkdown(LibraryState library) async {
    try {
      final Directory root = Directory(_dataRoot);
      if (!root.existsSync()) return library;
      bool changed = false;
      final List<LibraryDocument> docs = List<LibraryDocument>.of(
        library.documents,
      );
      for (final FileSystemEntity entity in root.listSync()) {
        if (entity is Directory) {
          // 子文件夹：检查是否有 .fastink-md.json 元数据。
          final File meta = File(
            '${entity.path}${Platform.pathSeparator}.fastink-md.json',
          );
          if (!meta.existsSync()) continue;
          final FileSystemEntity? mdFile = entity
              .listSync()
              .whereType<File>()
              .where((f) => f.path.toLowerCase().endsWith('.md'))
              .firstOrNull;
          if (mdFile == null) continue;
          final String id = _markdownStableId(mdFile.path);
          if (docs.any(
            (LibraryDocument d) =>
                d.id == id ||
                _markdownPath(d.sourcePath) == _markdownPath(mdFile.path),
          )) {
            continue;
          }
          String title = mdFile.path
              .split(Platform.pathSeparator)
              .last
              .replaceAll(RegExp(r'\.md$', caseSensitive: false), '');
          try {
            final Map<String, Object?> metaJson =
                jsonDecode(meta.readAsStringSync()) as Map<String, Object?>;
            if (metaJson['name'] is String) {
              title = metaJson['name']! as String;
            }
          } catch (_) {}
          docs.add(
            LibraryDocument(
              id: id,
              title: title,
              sourcePath: mdFile.path,
              coverPath: '',
              pageCount: 1,
              importedAt: DateTime.now(),
              lastOpenedAt: DateTime.now(),
            ),
          );
          changed = true;
        } else if (entity is File &&
            entity.path.toLowerCase().endsWith('.md')) {
          // 根目录的 .md 文件（"导入到资料库" 产生的平铺文件）。
          final String id = _markdownStableId(entity.path);
          if (docs.any(
            (LibraryDocument d) =>
                d.id == id ||
                _markdownPath(d.sourcePath) == _markdownPath(entity.path),
          )) {
            continue;
          }
          final String title = entity.path
              .split(Platform.pathSeparator)
              .last
              .replaceAll(RegExp(r'\.md$', caseSensitive: false), '');
          docs.add(
            LibraryDocument(
              id: id,
              title: title,
              sourcePath: entity.path,
              coverPath: '',
              pageCount: 1,
              importedAt: DateTime.now(),
              lastOpenedAt: DateTime.now(),
            ),
          );
          changed = true;
        }
      }
      if (!changed) return library;
      final LibraryState updated = LibraryState(
        documents: docs,
        folders: library.folders,
      );
      await _libraryRepository.save(updated);
      return updated;
    } catch (_) {
      return library;
    }
  }

  /// 规范化 Markdown 路径，资料库登记和去重使用同一比较规则。
  static String _markdownPath(String path) =>
      File(path).absolute.uri.normalizePath().toString().toLowerCase();

  /// 由 Markdown 规范路径形成稳定编号，重开同一文件不重复创建索引。
  static String _markdownStableId(String mdPath) {
    int hash = 0xcbf29ce484222325;
    for (final int byte in utf8.encode(mdPath.toLowerCase())) {
      hash ^= byte;
      hash = (hash * 0x100000001b3) & 0x7fffffffffffffff;
    }
    return 'md-$hash';
  }

  /// 标记实际装载页为脏，按配置重置自动保存定时任务，并更新保存状态提示。
  void _inkCommitted() {
    _doc.dirty = true;
    _doc.saveTimer?.cancel();
    if (_settings.autoSaveEnabled) {
      _doc.saveTimer = Timer(
        Duration(milliseconds: _settings.autoSaveDelayMs),
        _saveWhenIdle,
      );
    }
    if (mounted) {
      _updateState(
        () => _doc.status = _settings.autoSaveEnabled
            ? tr('正在后台保存当前页…', 'Saving current page in the background…')
            : tr(
                '已修改 · 自动保存已关闭（切页或退出时仍会补存）',
                'Modified · auto save is off (changes are still saved on page switch or exit)',
              ),
      );
    }
  }

  /// 接收内容/选择层需要工具栏同步的低频通知，刷新首页依赖状态；活动采样另用局部重绘信号。
  void _inkChanged() {
    if (mounted) _updateState(() {});
  }

  /// 交互仍在进行时短暂延后保存，空闲后走强制刷盘入口，避免手势中复制半份变换内容。
  void _saveWhenIdle() {
    if (_ink.isInteracting) {
      _doc.saveTimer = Timer(const Duration(milliseconds: 150), _saveWhenIdle);
    } else {
      unawaited(_saveNow());
    }
  }

  /// 刷写实际所属页的笔迹。在途写入失败或出现未保存的新修改时返回 false。
  Future<bool> _saveNow() async {
    // 保存目标永远是 _ink.strokes 实际所属的那一页（inkPage），不是
    // currentPage——翻页的异步窗口里两者会分家，用 currentPage 会把旧页
    // 的笔迹写进新页的 JSON。
    final NoteDocument? document = _doc.inkDocument;
    final NotePage? page = _doc.inkPage;
    if (!_doc.dirty || document == null || page == null) {
      // "保存"的契约是刷盘：没有新内容也要等在途写入落地。调用方（切页、
      // 旋转、复制页、导出）接下来就会从磁盘读这份笔迹，不等就会读到旧内容。
      _doc.saveTimer?.cancel();
      try {
        await _doc.saveChain;
        return !_doc.dirty;
      } catch (_) {
        return false;
      }
    }
    _doc.saveTimer?.cancel();
    _doc.dirty = false;
    // 入队前截取笔迹快照，后续修改不会写入这次保存。
    final PageInk snapshot = PageInk(strokes: _ink.snapshot());

    // 保存失败后清理队列状态，下一次保存仍可入队。
    final write = _doc.saveChain
        .catchError((Object _) {})
        .then(
          (_) => _repository.savePageInk(
            document,
            page,
            snapshot,
            takeSnapshotOwnership: true,
          ),
        );
    _doc.saveChain = write;
    try {
      await write;
      // 状态只在仍是这一页的笔迹时更新，否则用户已经翻走，"当前页"会误导。
      if (mounted && identical(page, _doc.inkPage)) {
        _updateState(() {
          _doc.status = _doc.dirty
              ? tr('有新的修改等待保存…', 'New changes are waiting to be saved…')
              : tr(
                  '已保存 · 仅写入当前页笔迹',
                  'Saved · only current-page ink was written',
                );
        });
      }
      return identical(write, _doc.saveChain) ? !_doc.dirty : _saveNow();
    } catch (error) {
      // 更新的完整快照已排队时，等待该版本，避免旧错误覆盖其结果。
      if (!identical(write, _doc.saveChain)) return _saveNow();
      _doc.dirty = true;
      if (mounted) {
        _updateState(
          () => _doc.status = tr('保存失败：$error', 'Save failed: $error'),
        );
      }
      return false;
    }
  }

  /// 持久化当前轻量资料库索引，真正写入顺序由仓库按目标路径排队。
  Future<void> _saveLibrary() => _libraryRepository.save(_library);

  /// 将新打开文稿登记或更新到资料库，保留稳定身份、文件夹和阅读等元数据，再保存索引。
  Future<void> _rememberDocument(
    NoteDocument document, {
    String? folderId,
    Map<int, String> initialPageTitles = const <int, String>{},
  }) async {
    folderId = _folderForScope(folderId, LibraryScope.notes);
    final int existingIndex = _library.documents.indexWhere(
      (LibraryDocument item) => item.id == document.id,
    );
    final LibraryDocument fresh = _libraryRepository.fromDocument(
      document,
      folderId: folderId,
    );
    final List<LibraryDocument> documents = List<LibraryDocument>.of(
      _library.documents,
    );
    if (existingIndex < 0) {
      documents.add(
        initialPageTitles.isEmpty
            ? fresh
            : fresh.copyWith(pageTitles: initialPageTitles),
      );
    } else {
      final LibraryDocument existing = documents[existingIndex];
      documents[existingIndex] = fresh.copyWith(
        importedAt: existing.importedAt,
        favorite: existing.favorite,
        folderId: folderId ?? existing.folderId,
        trashed: false,
        bookmarkedPages: existing.bookmarkedPages,
        pageTitles: existing.pageTitles,
        pdfOutline: existing.pdfOutline,
        pdfOutlineVersion: existing.pdfOutlineVersion,
        lastPageIndex: existing.lastPageIndex.clamp(
          0,
          document.pages.length - 1,
        ),
      );
    }
    _library = LibraryState(documents: documents, folders: _library.folders);
    if (mounted) _updateState(() {});
    await _saveLibrary();
  }

  /// 按索引源路径读取页面清单并恢复阅读位置，交给统一激活流程；期间反馈打开进度，失败保留错误说明。
  Future<void> _openLibraryDocument(LibraryDocument item) async {
    try {
      _updateState(() {
        _libraryBusy = true;
        _doc.status = tr('正在打开 ${item.title}…', 'Opening ${item.title}…');
      });
      final NoteDocument indexed = await _repository.indexFromSelectedPath(
        item.sourcePath,
        documentId: item.id,
      );
      final NoteDocument document = NoteDocument(
        id: indexed.id,
        title: indexed.title,
        directory: indexed.directory,
        pages: indexed.pages,
        initialIndex: item.lastPageIndex.clamp(0, indexed.pages.length - 1),
      );
      await _useDocument(document, folderId: item.folderId);
    } catch (error) {
      if (mounted) {
        _updateState(
          () => _doc.status = tr('打开失败：$error', 'Could not open: $error'),
        );
      }
    } finally {
      if (mounted) _updateState(() => _libraryBusy = false);
    }
  }

  /// 选择并分类 OneNote、PDF 和图像输入，先展示反馈再执行受预算的导入，完成后登记资料库。
  Future<void> _importFiles() async {
    final List<File> allFiles = await _repository.pickImportFiles();
    final oneNote = allFiles
        .where(
          (f) => RegExp(
            r'\.(one|onex|onepkg)$',
            caseSensitive: false,
          ).hasMatch(f.path),
        )
        .toList();
    if (oneNote.isNotEmpty && mounted) {
      await _importOneNoteFiles(selectedFiles: oneNote);
    }
    final selected = allFiles.where((f) => !oneNote.contains(f)).toList();
    if (!mounted || selected.isEmpty || _rejectConcurrentHeavyJob()) return;
    final importedPdfs = <NoteDocument>[];
    _updateState(() {
      _libraryBusy = true;
      _doc.status = tr('准备导入…', 'Preparing import…');
    });
    try {
      // 先显示操作反馈，再启动尚未预热的 PDF 工作进程。
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      final List<File> images = selected
          .where((File file) => !file.path.toLowerCase().endsWith('.pdf'))
          .toList();
      if (images.isNotEmpty) {
        final NoteDocument document = await _repository.importImages(
          images,
          onProgress: _setImportProgress,
        );
        await _rememberDocument(document, folderId: _activeFolderId);
      }
      for (final File pdf in selected.where(
        (File file) => file.path.toLowerCase().endsWith('.pdf'),
      )) {
        final NoteDocument document = await _repository.importPdf(
          pdf,
          onProgress: _setImportProgress,
        );
        await _rememberDocument(document, folderId: _activeFolderId);
        importedPdfs.add(document);
      }
      if (mounted) {
        _updateState(() => _doc.status = tr('导入完成', 'Import complete'));
      }
    } catch (error) {
      if (mounted) {
        _updateState(
          () => _doc.status = tr('导入失败：$error', 'Import failed: $error'),
        );
      }
    } finally {
      if (mounted) _updateState(() => _libraryBusy = false);
    }
    // 先发布可用封面，目录提取不阻塞导入完成。
    // 保持串行，避免批量导入时每个 PDF 同时启动一个进程。
    for (final document in importedPdfs) {
      if (!mounted) return;
      await _ensurePdfOutline(document);
    }
  }

  /// 更新导入状态文案，已卸载时不向旧界面提交进度。
  void _setImportProgress(String message) {
    if (mounted) _updateState(() => _doc.status = message);
  }

  /// 收集纸张、可选封面和标题后创建文稿，并在当前内容域中登记、打开。
  Future<void> _createBlankNote() async {
    final _PaperDialogResult? result = await _showPaperDialog(creating: true);
    if (result == null) return;
    _updateState(() {
      _libraryBusy = true;
      _doc.status = tr('正在创建笔记…', 'Creating note…');
    });
    try {
      NoteDocument document = await _repository.createBlankNote(
        result.title,
        template: result.template,
      );
      if (result.cover != null) {
        document = await _repository.addBlankPage(
          document,
          insertIndex: 0,
          template: result.cover!,
        );
      }
      await _rememberDocument(document, folderId: _activeFolderId);
      await _useDocument(document, folderId: _activeFolderId);
    } catch (error) {
      if (mounted) {
        _updateState(
          () =>
              _doc.status = tr('创建失败：$error', 'Could not create note: $error'),
        );
      }
    } finally {
      if (mounted) _updateState(() => _libraryBusy = false);
    }
  }

  /// 打开 Markdown 编辑器。
  ///
  /// - [filePath]：资料库中的文件路径（直接编辑）。
  /// - [externalSourcePath]：外部文件原始路径（复制到 temp，只读预览）。
  void _openMarkdownEditor({
    String? filePath,
    String? externalSourcePath,
    String? initialHeading,
  }) {
    _updateState(() {
      _markdownEditorOpen = true;
      _markdownEditorSession++;
      _markdownEditorFilePath = filePath;
      _markdownInitialHeading = initialHeading;
      if (filePath != null &&
          !_markdownOpenTabs.any(
            (open) => _markdownPath(open) == _markdownPath(filePath),
          )) {
        _markdownOpenTabs.add(filePath);
      }
      _markdownExternalSourcePath = externalSourcePath;
    });
  }

  /// 使用文件选择器打开 .md 文件。
  ///
  /// 弹出系统文件对话框，只显示 .md 文件。
  /// 选中的文件走外部文件流程：复制到 %temp%，默认只读预览，
  /// 用户可选择"编辑原文件"（覆盖源文件）或"导入到资料库"。
  Future<List<File>> _pickMarkdownFiles() async {
    final OpenFilePicker picker = OpenFilePicker()
      ..filterSpecification = <String, String>{'Markdown (*.md)': '*.md'}
      ..title = tr('选择 Markdown 文件', 'Select Markdown files');
    return picker.getFiles();
  }

  /// 选择外部 Markdown 文件并进入独立编辑流程，取消时不改变当前资料库。
  Future<void> _openMarkdownFromFile() async {
    final List<File> files = await _pickMarkdownFiles();
    final File? file = files.firstOrNull;
    if (file == null) return;
    // 文件选择器打开的文件视为外部文件，走 temp 只读流程。
    _openMarkdownEditor(externalSourcePath: file.path);
  }

  /// 导入 .md 文件到资料库（复制到 dataRoot，注册到 library.json）。
  ///
  /// 支持多选。同名文件自动加数字后缀。
  Future<void> _importMarkdownFiles() async {
    final List<File> files = await _pickMarkdownFiles();
    if (files.isEmpty) return;
    final Directory target = Directory(_dataRoot);
    if (!target.existsSync()) target.createSync(recursive: true);
    int imported = 0;
    for (final File source in files) {
      final String name = source.path.split(Platform.pathSeparator).last;
      String destPath = '${target.path}${Platform.pathSeparator}$name';
      if (File(destPath).existsSync()) {
        final String base = name.endsWith('.md')
            ? name.substring(0, name.length - 3)
            : name;
        int i = 2;
        while (File(
          '${target.path}${Platform.pathSeparator}$base-$i.md',
        ).existsSync()) {
          i++;
        }
        destPath = '${target.path}${Platform.pathSeparator}$base-$i.md';
      }
      final content = await MarkdownEditorService.copyLocalImages(
        content: (await MarkdownEncoding.read(source)).$1,
        sourcePath: source.path,
        targetPath: destPath,
      );
      await File(destPath).writeAsString(content, flush: true);
      _registerMarkdownInLibrary(destPath);
      imported++;
    }
    _loadLibrary();
    _updateState(() {
      _doc.status = tr(
        '已导入 $imported 个 Markdown 文件',
        'Imported $imported Markdown file(s)',
      );
    });
  }

  /// 把 .md 文件注册到 library.json 索引（如果尚未注册）。
  void _renameMarkdownInLibrary(String oldPath, String newPath) {
    final old = _markdownPath(oldPath);
    final title = File(newPath).uri.pathSegments.last.replaceFirst(
      RegExp(r'\.md$', caseSensitive: false),
      '',
    );
    _library = LibraryState(
      documents: [
        for (final doc in _library.documents)
          if (_markdownPath(doc.sourcePath) == old)
            doc.copyWith(sourcePath: newPath, title: title)
          else
            doc,
      ],
      folders: _library.folders,
    );
    unawaited(_libraryRepository.save(_library));
  }

  /// 把 .md 文件注册到 library.json 索引（如果尚未注册）。
  void _registerMarkdownInLibrary(String mdPath) {
    final String id = _markdownStableId(mdPath);
    final bool exists = _library.documents.any(
      (LibraryDocument d) =>
          d.id == id || _markdownPath(d.sourcePath) == _markdownPath(mdPath),
    );
    if (exists) return;
    final String name = File(mdPath).uri.pathSegments.last;
    final String title = name.endsWith('.md')
        ? name.substring(0, name.length - 3)
        : name;
    final LibraryDocument doc = LibraryDocument(
      id: id,
      title: title,
      sourcePath: mdPath,
      coverPath: '',
      pageCount: 1,
      importedAt: DateTime.now(),
      lastOpenedAt: DateTime.now(),
      folderId: _folderForScope(_activeFolderId, LibraryScope.markdown),
    );
    final List<LibraryDocument> docs = List<LibraryDocument>.of(
      _library.documents,
    );
    docs.add(doc);
    _library = LibraryState(documents: docs, folders: _library.folders);
    _libraryRepository.save(_library);
  }
}
