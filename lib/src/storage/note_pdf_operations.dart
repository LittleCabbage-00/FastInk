part of 'note_repository.dart';

extension NotePdfOperations on NoteRepository {
  /// 一次枚举笔迹文件，避免每个 PDF 页面分别探测两个文件。
  Future<Set<int>> savedInkPageIds(NoteDocument document) async {
    await Future.wait(
      _saveQueues.entries
          .where((e) => e.key.startsWith('${document.id}:'))
          .map((e) => e.value)
          .toList(),
    );
    final directory = Directory('$dataRoot/documents/${document.id}/pages');
    if (!await directory.exists()) return {};
    final ids = <int>{};
    await for (final file in directory.list()) {
      if (file is! File) continue;
      final match = RegExp(
        r'^(\d+)\.json(?:\.previous)?$',
      ).firstMatch(_fileName(file.path));
      if (match != null) ids.add(int.parse(match[1]!));
    }
    return ids;
  }

  /// 获取原 PDF 页面的尺寸与可安全叠加标记，供导出判断何时可复用原页面。
  Future<Map<int, ({ui.Size size, bool overlaySafe})>> pdfExportGeometry(
    NoteDocument document,
  ) async {
    final source = await originalPdfSource(document);
    if (source == null) return {};
    final result = await Process.run(_findPdfTool('pdfinfo.exe'), [
      '-f',
      '1',
      '-l',
      '999999999',
      '-box',
      source.path,
    ]);
    if (result.exitCode != 0) {
      throw StateError('PDF page sizes: ${result.stderr}');
    }
    final output = result.stdout.toString();
    final sizes = <int, ui.Size>{};
    for (final m in RegExp(
      r'Page\s+(\d+) size:\s+([\d.]+) x ([\d.]+) pts',
    ).allMatches(output)) {
      sizes[int.parse(m[1]!)] = ui.Size(
        double.parse(m[2]!),
        double.parse(m[3]!),
      );
    }
    for (final m in RegExp(r'Page\s+(\d+) rot:\s+(-?\d+)').allMatches(output)) {
      final id = int.parse(m[1]!);
      final size = sizes[id];
      if (size != null && int.parse(m[2]!) % 180 != 0) {
        sizes[id] = ui.Size(size.height, size.width);
      }
    }
    final boxes = <int, Map<String, List<double>>>{};
    for (final m in RegExp(
      r'Page\s+(\d+) (MediaBox|CropBox|TrimBox):\s+([-\d.]+)\s+([-\d.]+)\s+([-\d.]+)\s+([-\d.]+)',
    ).allMatches(output)) {
      (boxes[int.parse(m[1]!)] ??= {})[m[2]!] = [
        for (var i = 3; i <= 6; i++) double.parse(m[i]!),
      ];
    }
    return {
      for (final entry in sizes.entries)
        entry.key: (
          size: entry.value,
          // 现有栅格图使用 MediaBox；仅对带批注且裁剪几何特殊的
          // 页面进行合成，避免裁剪框变化导致笔迹坐标偏移。
          overlaySafe:
              boxes[entry.key] != null &&
              ['CropBox', 'TrimBox'].every((key) {
                final media = boxes[entry.key]!['MediaBox'],
                    other = boxes[entry.key]![key];
                return media != null &&
                    other != null &&
                    media[0].abs() < .01 &&
                    media[1].abs() < .01 &&
                    List.generate(
                      4,
                      (i) => i,
                    ).every((i) => (media[i] - other[i]).abs() < .01);
              }),
        ),
    };
  }

  /// 从原 PDF 读取目录并解析层级与页面目标，没有目录时返回空列表，不生成虚构章节。
  Future<List<PdfOutlineEntry>> readPdfOutline(NoteDocument document) async {
    final source = await originalPdfSource(document);
    if (source == null) {
      throw StateError(tr('原始 PDF 不存在', 'Original PDF does not exist'));
    }
    // 由 Poppler 解析对象流、Unicode 字符串及命名目标。
    // 仅提取第一页文字，XML 仍然包含完整目录。
    final result = await Process.run(
      _findPdfTool('pdftohtml.exe'),
      [
        '-xml',
        '-i',
        '-f',
        '1',
        '-l',
        '1',
        '-enc',
        'UTF-8',
        '-stdout',
        source.path,
      ],
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    if (result.exitCode != 0) throw StateError('PDF outline: ${result.stderr}');
    return _parsePdfOutlineInBackground(result.stdout as String);
  }

  /// 文字提取不渲染 PDF 页面，也不分配页面位图。
  Future<Map<int, String>> extractPdfSearchText(NoteDocument document) async {
    final File? source = await originalPdfSource(document);
    if (source == null) return <int, String>{};
    final ProcessResult result = await Process.run(
      _findPdfTool('pdftotext.exe'),
      <String>['-enc', 'UTF-8', '-layout', source.path, '-'],
      stdoutEncoding: utf8,
    );
    if (result.exitCode != 0) return <int, String>{};
    final List<String> pages = result.stdout.toString().split('\f');
    return <int, String>{
      for (int i = 0; i < pages.length; i++) i + 1: pages[i],
    };
  }

  /// 扫描目录中的受支持页面文件并自然排序，建立稳定文稿清单。
  Future<NoteDocument> indexFromDirectory(String directoryPath) async {
    final Directory directory = Directory(directoryPath);
    if (!await directory.exists()) {
      throw FileSystemException(
        tr('文件夹不存在', 'Folder does not exist'),
        directoryPath,
      );
    }
    final List<File> images = <File>[];
    await for (final FileSystemEntity entity in directory.list(
      followLinks: false,
    )) {
      if (entity is File && _imagePattern.hasMatch(entity.path)) {
        images.add(entity);
      }
    }
    if (images.isEmpty) {
      throw StateError(
        tr(
          '这个文件夹里没有可导入的图片页面。',
          'This folder contains no importable image pages.',
        ),
      );
    }
    images.sort((File a, File b) => _naturalCompare(a.path, b.path));
    return indexFromSelectedPath(images.first.path);
  }

  /// 复制所选图像为文稿页面并保存清单，按输入顺序组织，原图不被改写。
  Future<NoteDocument> importImages(
    List<File> files, {
    required void Function(String message) onProgress,
  }) async {
    if (files.isEmpty) throw StateError(tr('没有选择图片。', 'No images selected.'));
    if (files.length == 1 &&
        _scrblePattern.hasMatch(_fileName(files.first.path))) {
      onProgress(tr('正在扫描整本笔记…', 'Scanning the entire note…'));
      return indexFromSelectedPath(files.first.path);
    }

    final String title = files.length == 1
        ? _withoutExtension(_fileName(files.first.path))
        : tr(
            '导入的图片 ${_shortDateTime(DateTime.now())}',
            'Imported images ${_shortDateTime(DateTime.now())}',
          );
    final Directory target = await _newImportDirectory(title);
    for (int i = 0; i < files.length; i++) {
      onProgress(
        tr(
          '正在导入图片 ${i + 1} / ${files.length}',
          'Importing image ${i + 1} / ${files.length}',
        ),
      );
      final String extension = _extension(files[i].path);
      await files[i].copy(
        '${target.path}/${_safeName(title)} #${i + 1}$extension',
      );
    }
    return indexFromDirectory(target.path);
  }

  /// 建立保留原 PDF 的懒页面文稿并报告导入进度，耗时任务交由后台工作线程。
  Future<NoteDocument> importPdf(
    File pdf, {
    required void Function(String message) onProgress,
  }) async {
    // 进程启动、页面索引和清单序列化即使使用异步文件读写，
    // 仍可能阻塞首次导入；全部放到后台隔离线程，
    // 只向界面传递进度和完成的索引。
    final events = ReceivePort();
    Isolate? worker;
    try {
      worker = await Isolate.spawn(
        _importPdfWorker,
        (
          sourcePath: pdf.absolute.path,
          dataRoot: Directory(dataRoot).absolute.path,
          dpi: pdfImportDpi,
          language: AppText.locale.languageCode,
          events: events.sendPort,
        ),
        onError: events.sendPort,
        onExit: events.sendPort,
      );
      await for (final message in events) {
        if (message is String) {
          onProgress(message);
        } else if (message is NoteDocument) {
          return message;
        } else if (message is ({String error, String stack})) {
          Error.throwWithStackTrace(
            StateError(message.error),
            StackTrace.fromString(message.stack),
          );
        } else if (message is List && message.length == 2) {
          throw RemoteError('${message[0]}', '${message[1]}');
        } else if (message == null) {
          throw StateError(
            tr(
              'PDF 导入进程意外退出，请重试。',
              'The PDF import worker exited unexpectedly; please retry.',
            ),
          );
        }
      }
      throw StateError('PDF import worker returned no result');
    } finally {
      events.close();
      worker?.kill(priority: Isolate.immediate);
    }
  }

  /// 安排 PDF 导入工作线程并接收进度/结果，将元数据准备压力移出 UI 线程。
  Future<NoteDocument> _importPdfOnWorker(
    File pdf, {
    required void Function(String message) onProgress,
  }) async {
    final String title = _withoutExtension(_fileName(pdf.path));
    final Directory target = await _newImportDirectory(title);
    onProgress(tr('正在读取 PDF 页数…', 'Reading PDF page count…'));
    final int pages;

    final ProcessResult info = await Process.run(
      _findPdfTool('pdfinfo.exe'),
      <String>[pdf.path],
    );
    if (info.exitCode != 0) {
      throw StateError('Cannot read PDF: ${info.stderr}');
    }
    final RegExpMatch? pageMatch = RegExp(
      r'^Pages:\s+(\d+)',
      multiLine: true,
    ).firstMatch(info.stdout.toString());
    pages = int.tryParse(pageMatch?.group(1) ?? '') ?? 0;

    if (pages < 1) {
      throw StateError(tr('PDF 没有可导入的页面。', 'The PDF has no importable pages.'));
    }

    onProgress(tr('正在复制原始 PDF…', 'Copying the original PDF…'));
    final File localPdf = await pdf.copy('${target.path}/source.pdf');
    // 导入时只渲染首页，其余页先记录描述，后续按需转换。
    final safeTitle = _safeName(title);
    final List<NotePage> notePages = <NotePage>[
      for (int page = 1; page <= pages; page++)
        NotePage(
          index: page - 1,
          originalPage: page,
          path: '${target.path}/$safeTitle #$page.jpg',
          name: '$safeTitle #$page.jpg',
        ),
    ];
    await File('${target.path}/.fastink-pdf.json').writeAsString(
      jsonEncode(<String, Object?>{
        'version': 1,
        'source': localPdf.path,
        'pageCount': pages,
        'dpi': pdfImportDpi,
      }),
      flush: true,
    );
    final NoteDocument document = NoteDocument(
      id: _stableId('${target.path}\u0000$title'),
      title: title,
      directory: target.path,
      pages: notePages,
      initialIndex: 0,
    );
    onProgress(
      tr('正在准备第 1 页，之后按需加载…', 'Preparing page 1; later pages load on demand…'),
    );
    await (
      ensurePageImage(document, notePages.first),
      saveDocumentManifest(document),
    ).wait;
    onProgress(
      tr('PDF 已快速导入，共 $pages 页', 'PDF imported quickly: $pages pages'),
    );
    return document;
  }

  /// 根据文稿清单与来源判断是否采用 PDF 按需渲染路径。
  bool isLazyPdf(NoteDocument document) =>
      File('${document.directory}/.fastink-pdf.json').existsSync();

  /// 只有原始 PDF 栅格缓存可以清理，因为可重新渲染。
  /// 插入、复制、旋转后的背景属于永久文稿内容。
  bool isOriginalPdfPage(NoteDocument document, NotePage page) =>
      isLazyPdf(document) && _isOriginalPdfPagePath(document, page);

  /// 建立当前页面位置到原 PDF 页身份的映射，插入的自建页不冒充原始 PDF 页。
  Map<int, int> originalPdfPageIndexes(NoteDocument document) =>
      !isLazyPdf(document)
      ? {}
      : {
          for (final page in document.pages)
            if (_isOriginalPdfPagePath(document, page))
              page.originalPage: page.index,
        };

  /// 校验页面路径是否确属该 PDF 的原始缓存页，而不是新增图片或模板页。
  bool _isOriginalPdfPagePath(NoteDocument document, NotePage page) =>
      _samePath(File(page.path).parent.path, document.directory) &&
      int.tryParse(
            _scrblePattern.firstMatch(_fileName(page.path))?.group(2) ?? '',
          ) ==
          page.originalPage;

  /// 检查原 PDF 来源和页映射是否仍满足复用条件，返回 false 时改走其他导出路径。
  Future<bool> canExportOriginalPdf(NoteDocument document) async {
    if (!isLazyPdf(document)) return false;
    final metadata =
        jsonDecode(
              await File(
                '${document.directory}/.fastink-pdf.json',
              ).readAsString(),
            )
            as Map<String, Object?>;
    if (metadata['pageCount'] != document.pages.length) return false;
    for (int i = 0; i < document.pages.length; i++) {
      if (document.pages[i].originalPage != i + 1 ||
          !_isOriginalPdfPagePath(document, document.pages[i])) {
        return false;
      }
    }
    return true;
  }

  /// 返回文稿保留的原 PDF 文件，来源缺失或不适用时返回 null。
  Future<File?> originalPdfSource(NoteDocument document) async {
    if (!isLazyPdf(document)) return null;
    final ({File source, int dpi}) metadata = await _pdfMetadata(document);
    return await metadata.source.exists() ? metadata.source : null;
  }

  /// 逐页检查是否存在已保存笔迹，供无批注原稿快速导出判断。
  Future<bool> hasAnyInk(NoteDocument document) async {
    final Directory pages = Directory(
      '$dataRoot/documents/${document.id}/pages',
    );
    if (!await pages.exists()) return false;
    await for (final FileSystemEntity entity in pages.list()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      try {
        final Object? decoded = jsonDecode(await entity.readAsString());
        final Object? strokes = (decoded as Map<String, Object?>)['strokes'];
        if (strokes is List<Object?> && strokes.isNotEmpty) return true;
      } catch (_) {
        // 标注文件损坏时按有批注处理，不使用原 PDF 的快速导出路径。
        return true;
      }
    }
    return false;
  }

  /// 按输入顺序合并 PDF 到目标文件，使用随包工具并检查进程退出状态。
  Future<void> mergePdfFiles(List<File> inputs, File destination) async {
    if (inputs.isEmpty) throw ArgumentError('No PDF parts to merge.');

    if (inputs.length == 1) {
      await inputs.single.copy(destination.path);
      return;
    }
    final ProcessResult result = await Process.run(
      _findPdfTool('pdfunite.exe'),
      <String>[...inputs.map((File file) => file.path), destination.path],
    );
    if (result.exitCode != 0 || !await destination.exists()) {
      throw StateError(
        tr(
          'PDF 分块合并失败：${result.stderr}',
          'Could not merge PDF parts: ${result.stderr}',
        ),
      );
    }
  }

  /// 把当前请求页提升为渲染优先目标，减少过时预取对显式导航的阻塞。
  void prioritizePdfPage(NoteDocument document, NotePage page) {
    if (!isLazyPdf(document)) return;
    // 更新代次使旧预取失效；当前可见页的渲染继续执行。
    _prefetchGeneration++;
  }

  /// 递增预取代次，尚未开始的旧邻页任务在执行前失效。
  void cancelPdfPrefetch() => _prefetchGeneration++;

  /// 更新当前与必要邻页的缓存保护集合，淘汰时不能移除仍被显示的页面。
  void updatePdfCacheWindow(NoteDocument document, Iterable<int> pageIndexes) {
    if (!isLazyPdf(document)) return;
    // LRU 淘汰跳过传入的保护页，它们可能仍在显示或解码。
    _pdfProtectedPages[document.id] = <String>{
      document.pages.first.path,
      for (final int index in pageIndexes)
        if (index >= 0 && index < document.pages.length)
          document.pages[index].path,
    };
    unawaited(_trimPdfPageCache());
  }

  /// 返回已存在页面图或合并同页在途渲染请求，失败向调用方报告，不重复启动同页进程。
  Future<File> ensurePageImage(NoteDocument document, NotePage page) {
    final File destination = File(page.path);
    if (destination.existsSync()) {
      if (isOriginalPdfPage(document, page)) _touchPdfPage(destination.path);
      return Future<File>.value(destination);
    }
    if (!isOriginalPdfPage(document, page)) {
      return Future<File>.error(
        FileSystemException(
          tr('页面不存在', 'Page does not exist'),
          destination.path,
        ),
      );
    }
    // putIfAbsent 合并同页请求，共用一次 pdftoppm 转换；完成后移除队列项。
    return _pageRenderQueues.putIfAbsent(destination.path, () async {
      try {
        final ({File source, int dpi}) metadata = await _pdfMetadata(document);
        final File source = metadata.source;
        if (!await source.exists()) {
          throw FileSystemException(
            tr('原始 PDF 不存在', 'Original PDF does not exist'),
            source.path,
          );
        }
        final int dpi = metadata.dpi;

        final String temporaryPrefix =
            '${destination.path}.${DateTime.now().microsecondsSinceEpoch}.render';
        final ProcessResult result =
            await Process.run(_findPdfTool('pdftoppm.exe'), <String>[
              '-jpeg',
              '-jpegopt',
              'quality=86,progressive=n,optimize=n',
              '-r',
              '$dpi',
              '-f',
              '${page.originalPage}',
              '-l',
              '${page.originalPage}',
              '-singlefile',
              source.path,
              temporaryPrefix,
            ]);
        final File rendered = File('$temporaryPrefix.jpg');
        if (result.exitCode != 0 || !await rendered.exists()) {
          throw StateError(
            tr(
              'PDF 第 ${page.originalPage} 页转换失败：${result.stderr}',
              'Could not render PDF page ${page.originalPage}: ${result.stderr}',
            ),
          );
        }
        await destination.parent.create(recursive: true);
        if (await destination.exists()) await destination.delete();
        await rendered.rename(destination.path);
        _touchPdfPage(destination.path);
        return destination;
      } finally {
        _pageRenderQueues.remove(destination.path);
      }
    });
  }

  /// 按预算串行渲染规划邻页，每页启动前检查代次，快速阅读或经济策略可减少/取消。
  Future<void> prefetchPdfPages(
    NoteDocument document,
    Iterable<int> pageIndexes,
  ) {
    if (!isLazyPdf(document)) return Future<void>.value();
    final List<int> requested = pageIndexes.toSet().toList();
    // 快速滚动时丢弃旧预取窗口，以最新可见页重新规划。
    final int generation = ++_prefetchGeneration;
    _prefetchChain = _prefetchChain.catchError((Object _) {}).then((_) async {
      // 留出很短的取消窗口给快速跳页；正常阅读时尽早生成紧邻页，
      // 避免页面已经进入视口后仍在等待 PDF 转换。
      await Future<void>.delayed(const Duration(milliseconds: 80));
      if (generation != _prefetchGeneration) return;
      for (int offset = 0; offset < requested.length; offset++) {
        if (generation != _prefetchGeneration) return;
        final int index = requested[offset];
        if (index < 0 || index >= document.pages.length) continue;
        // 后台转换串行执行，限制翻页时的 CPU 峰值。
        try {
          await ensurePageImage(document, document.pages[index]);
        } catch (_) {
          // 单页预取失败后继续处理窗口中的其他页。
        }
      }
    });
    return _prefetchChain;
  }

  /// 按纸张和可选封面生成初始页面，保存模板与文稿清单，原有资料库不覆盖。
  Future<NoteDocument> createBlankNote(
    String requestedTitle, {
    PaperTemplate template = const PaperTemplate(),
  }) async {
    final String title = requestedTitle.trim().isEmpty
        ? tr('无标题笔记')
        : requestedTitle.trim();
    final Directory target = await _newImportDirectory(title);
    await File('${target.path}/.fastink-notebook.json').writeAsString(
      jsonEncode(<String, Object?>{'version': 1, 'title': title}),
      flush: true,
    );
    await _writePaperPage(
      File('${target.path}/${_safeName(title)} #1.png'),
      template,
    );
    return indexFromDirectory(target.path);
  }

  /// 判断文稿是否为可应用自绘模板的笔记来源，不把导入 PDF 原页直接当空白纸。
  bool isEditableNotebook(NoteDocument document) =>
      File('${document.directory}/.fastink-notebook.json').existsSync();

  /// 按页面身份判断是否允许换纸，自建插入页与受保护原导入页区别处理。
  bool canChangePaperTemplate(NoteDocument document, int index) =>
      isEditableNotebook(document) ||
      File('${document.pages[index].path}.paper.json').existsSync();

  /// 逐页保存新底图和模板。每成功一页通知宿主失效显示缓存，即使后续页面失败。
  Future<void> applyPaperTemplate(
    NoteDocument document,
    Iterable<int> pageIndexes,
    PaperTemplate template, {
    void Function(NotePage)? onPageChanged,
  }) async {
    final List<int> targets = pageIndexes
        .where((i) => i >= 0 && i < document.pages.length)
        .toList();
    if (targets.any((i) => !canChangePaperTemplate(document, i))) {
      throw StateError(
        tr(
          '导入的 PDF 或图片页面不能直接更换纸张模板。',
          'Imported PDF or image pages cannot have their paper template replaced directly.',
        ),
      );
    }
    for (final int index in targets) {
      if (index < 0 || index >= document.pages.length) continue;
      final page = document.pages[index];
      await _writePaperPage(File(page.path), template);
      onPageChanged?.call(page);
    }
  }
}

// 这些后台入口有意不捕获界面或仓库状态。
/// 在独立线程解析目录 XML，避免较大层级树阻塞界面。
Future<List<PdfOutlineEntry>> _parsePdfOutlineInBackground(String xml) =>
    Isolate.run(() => parsePdfOutlineXml(xml));

typedef _PdfImportRequest = ({
  String sourcePath,
  String dataRoot,
  int dpi,
  String language,
  SendPort events,
});

/// PDF 导入线程入口，准备来源、页数与清单并通过端口报告进度或错误。
Future<void> _importPdfWorker(_PdfImportRequest request) async {
  AppText.locale = ui.Locale(request.language);
  try {
    final repository = NoteRepository(
      dataRoot: request.dataRoot,
      pdfImportDpi: request.dpi,
    );
    final document = await repository._importPdfOnWorker(
      File(request.sourcePath),
      onProgress: request.events.send,
    );
    // 使用 Isolate.exit 转移页面列表，避免在界面线程再次深拷贝。
    Isolate.exit(request.events, document);
  } catch (error, stack) {
    Isolate.exit(request.events, (
      error: error.toString(),
      stack: stack.toString(),
    ));
  }
}
