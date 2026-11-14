part of '../../app/fastink_app.dart';

extension _FastInkPageOps on _FastInkHomeState {
  /// 按文稿合并 PDF 目录读取请求，force 可重新读取；读取失败保留手工章节和已有文稿数据。
  Future<void> _ensurePdfOutline(
    NoteDocument document, {
    bool force = false,
  }) async {
    if (!_repository.isLazyPdf(document)) return;
    final item = _library.documents
        .where((item) => item.id == document.id)
        .firstOrNull;
    if (item == null || (!force && item.pdfOutlineVersion >= 1)) return;
    if (!_pdfOutlineReading.add(document.id)) return;
    try {
      final outline = await _repository.readPdfOutline(document);
      if (!mounted) return;
      _library = LibraryState(
        documents: _library.documents
            .map(
              (current) => current.id == document.id
                  ? current.copyWith(pdfOutline: outline, pdfOutlineVersion: 1)
                  : current,
            )
            .toList(),
        folders: _library.folders,
      );
      _updateState(() {});
      await _saveLibrary();
    } catch (error) {
      if (mounted) {
        _updateState(
          () => _doc.status = tr(
            '读取 PDF 目录失败：$error',
            'Could not read PDF outline: $error',
          ),
        );
        if (force) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(_doc.status)));
        }
      }
    } finally {
      _pdfOutlineReading.remove(document.id);
      if (mounted) _updateState(() {});
    }
  }

  /// 打开批量页面管理窗口，依据选择执行复制、删除或跨文稿复制，统一检查重任务与结构锁。
  Future<void> _managePages() async {
    final document = _doc.document;
    if (document == null ||
        _doc.readOnly ||
        _rejectStructuralChange() ||
        _rejectConcurrentHeavyJob()) {
      return;
    }
    final choice = await showDialog<PageBatchChoice>(
      context: context,
      animationStyle: appMotionStyle(context),
      builder: (_) =>
          PageBatchDialog(document: document, currentIndex: _doc.pageIndex),
    );
    if (choice == null ||
        !mounted ||
        _doc.document?.id != document.id ||
        !identical(_doc.document, document) ||
        _doc.readOnly ||
        _doc.anyBusy) {
      return;
    }
    if (choice.toOtherDocument) {
      await _copyPagesToOtherDocument(document, choice.indexes);
      return;
    }
    final original = document.pages[_doc.pageIndex].originalPage;
    _doc.busyDocumentId = document.id;
    _doc.lockInk(document.id);
    _updateState(() => _doc.status = tr('正在处理页面…', 'Processing pages…'));
    try {
      if (!await _saveNow() || !mounted) return;
      final updated = await _repository.batchPages(
        document,
        choice.indexes,
        duplicate: choice.duplicate,
        legacyWidthReference: _legacyInkWidthReference(_doc.pageIndex),
      );
      final target = updated.pages.indexWhere(
        (p) => p.originalPage == original,
      );
      await _activateUpdatedDocument(
        document,
        updated,
        target < 0 ? 0 : target,
      );
    } catch (error) {
      if (mounted) {
        _updateState(
          () => _doc.status = tr(
            '批量操作失败：$error',
            'Page operation failed: $error',
          ),
        );
      }
    } finally {
      _doc.unlockInk(document.id);
      if (_doc.busyDocumentId == document.id) _doc.busyDocumentId = null;
      if (mounted) _updateState(() {});
    }
  }

  /// 将源页按原顺序追加到所选目标，复制页面内容及元数据并打开第一张新增页，源文稿保留。
  Future<void> _copyPagesToOtherDocument(
    NoteDocument source,
    Set<int> indexes,
  ) async {
    final sourceItem = _currentLibraryDocument;
    final targetItem = await showDialog<LibraryDocument>(
      context: context,
      animationStyle: appMotionStyle(context),
      builder: (_) => PageCopyTargetDialog(
        documents: _library.documents
            .where(
              (item) =>
                  item.id != source.id &&
                  !item.trashed &&
                  !item.id.startsWith('md-'),
            )
            .toList(),
        pageCount: indexes.length,
      ),
    );
    if (targetItem == null ||
        !mounted ||
        !identical(_doc.document, source) ||
        _doc.readOnly ||
        _doc.anyBusy ||
        _doc.pageLoading) {
      return;
    }
    final currentTarget = _library.documents
        .where((item) => item.id == targetItem.id && !item.trashed)
        .firstOrNull;
    if (currentTarget == null) return;
    // 冻结源文稿快照前，先提交尚未保存的文字编辑。
    _commitInlineText();
    final widthReference = _legacyInkWidthReference(_doc.pageIndex);
    _doc.busyDocumentId = source.id;
    _doc.lockInk(source.id);
    _doc.lockInk(currentTarget.id);
    // 源、目标两个文稿共同参与事务；目标清单发布前，
    // 使用模态界面阻止导航和页面结构编辑。
    final navigator = Navigator.of(context, rootNavigator: true);
    final progress = DialogRoute<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(width: 20),
              Expanded(
                child: Text(
                  tr(
                    '正在复制 ${indexes.length} 页…',
                    'Copying ${indexes.length} pages…',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    unawaited(navigator.push(progress));
    _updateState(() => _doc.status = tr('正在复制页面…', 'Copying pages…'));
    bool copied = false;
    try {
      if (!await _saveNow() || !mounted) return;
      final target = await _repository.indexFromSelectedPath(
        currentTarget.sourcePath,
        documentId: currentTarget.id,
      );
      if (_doc.dirty) {
        throw StateError(
          tr('源页面尚未保存，请保存后重试。', 'Save the source page before retrying.'),
        );
      }
      final updated = await _repository.copyPagesToDocument(
        source,
        target,
        indexes,
        legacyWidthReference: widthReference,
      );
      copied = true;
      final ordered = indexes.toList()..sort();
      final bookmarks = currentTarget.bookmarkedPages.toSet();
      final titles = Map<int, String>.of(currentTarget.pageTitles);
      for (int i = 0; i < ordered.length; i++) {
        final newIndex = target.pages.length + i;
        if (sourceItem?.bookmarkedPages.contains(ordered[i]) ?? false) {
          bookmarks.add(newIndex);
        }
        final title = sourceItem?.pageTitles[ordered[i]];
        if (title != null) titles[newIndex] = title;
      }
      _library = LibraryState(
        documents: _library.documents
            .map(
              (item) => item.id == target.id
                  ? item.copyWith(
                      pageCount: updated.pages.length,
                      bookmarkedPages: bookmarks.toList()..sort(),
                      pageTitles: titles,
                    )
                  : item,
            )
            .toList(),
        folders: _library.folders,
      );
      await _saveLibrary();
      if (!mounted) return;
      await _useDocument(
        NoteDocument(
          id: updated.id,
          title: updated.title,
          directory: updated.directory,
          pages: updated.pages,
          initialIndex: target.pages.length,
        ),
        folderId: currentTarget.folderId,
      );
      if (mounted) {
        _updateState(() {
          _showPageSidebar = true;
          _doc.status = tr(
            '已复制 ${indexes.length} 页到 ${currentTarget.title}',
            'Copied ${indexes.length} pages to ${currentTarget.title}',
          );
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_doc.status)));
      }
    } catch (error) {
      if (mounted) {
        _updateState(
          () => _doc.status = copied
              ? tr(
                  '页面已复制，打开目标文稿时出错：$error',
                  'Pages copied, but opening the target failed: $error',
                )
              : tr('复制页面失败：$error', 'Could not copy pages: $error'),
        );
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_doc.status)));
      }
    } finally {
      _doc.unlockInk(source.id);
      _doc.unlockInk(currentTarget.id);
      if (_doc.busyDocumentId == source.id) _doc.busyDocumentId = null;
      if (progress.isActive) navigator.removeRoute(progress);
      if (mounted) _updateState(() {});
    }
  }

  /// 构建 PDF 层级目录与手工章节列表，点击目标定位对应页面。
  Widget _outlineList(
    NoteDocument document,
    Map<int, String> titles,
    ColorScheme colors,
  ) {
    final List<MapEntry<int, String>> entries =
        titles.entries
            .where(
              (entry) => entry.key >= 0 && entry.key < document.pages.length,
            )
            .toList()
          ..sort((a, b) => a.key.compareTo(b.key));
    final pdfOutline =
        _currentLibraryDocument?.pdfOutline ?? const <PdfOutlineEntry>[];
    if (entries.isEmpty &&
        pdfOutline.isEmpty &&
        _pdfOutlineReading.contains(document.id)) {
      return Center(
        child: Column(
          key: const ValueKey('pdf-outline-loading'),
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(height: 12),
            Text(tr('正在读取 PDF 目录…', 'Reading PDF outline…')),
          ],
        ),
      );
    }
    if (entries.isEmpty && pdfOutline.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            tr(
              '没有可显示的目录\nPDF 可点上方刷新重新读取；也可在页面菜单中设置章节标题。',
              'No outline to display. Refresh to reread PDF bookmarks, or set section titles from the page menu.',
            ),
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.onSurfaceVariant),
          ),
        ),
      );
    }
    final pageIndexes = _repository.originalPdfPageIndexes(document);
    return Material(
      type: MaterialType.transparency,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 18),
        children: [
          if (pdfOutline.isNotEmpty)
            PdfOutlineTree(
              key: ValueKey('pdf-outline-${document.id}'),
              entries: pdfOutline,
              pageIndexes: pageIndexes,
              currentIndex: _doc.pageIndex,
              onSelected: _goToPage,
            ),
          for (final entry in entries)
            ListTile(
              selected: entry.key == _doc.pageIndex,
              leading: const Icon(Icons.subject_rounded),
              title: Text(
                entry.value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                tr('第 ${entry.key + 1} 页', 'Page ${entry.key + 1}'),
              ),
              trailing: IconButton(
                tooltip: tr('编辑目录标题'),
                onPressed: () => _setPageTitle(entry.key),
                icon: const Icon(Icons.edit_outlined, size: 18),
              ),
              onTap: () => _goToPage(entry.key),
            ),
        ],
      ),
    );
  }

  /// 编辑指定页的手工章节标题，确认后更新资料库索引，取消不改变目录。
  Future<void> _setPageTitle(int pageIndex) async {
    final LibraryDocument? item = _currentLibraryDocument;
    if (item == null) return;
    final TextEditingController controller = TextEditingController(
      text: item.pageTitles[pageIndex] ?? '',
    );
    final String? value = await showDialog<String>(
      context: context,
      animationStyle: appMotionStyle(context),
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(
          tr(
            '第 ${pageIndex + 1} 页目录标题',
            'Outline title for page ${pageIndex + 1}',
          ),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: tr('章节标题（留空即移除）'),
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (String text) => Navigator.pop(dialogContext, text),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(tr('取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: Text(tr('保存')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null) return;
    final Map<int, String> updated = Map<int, String>.of(item.pageTitles);
    if (value.trim().isEmpty) {
      updated.remove(pageIndex);
    } else {
      updated[pageIndex] = value.trim();
    }
    _library = LibraryState(
      documents: _library.documents
          .map(
            (current) => current.id == item.id
                ? current.copyWith(pageTitles: updated)
                : current,
          )
          .toList(),
      folders: _library.folders,
    );
    if (mounted) _updateState(() {});
    await _saveLibrary();
  }

  /// 结构操作完成后同步页面、标题、书签和阅读位置，再通过统一文稿激活路径装载。
  Future<void> _activateUpdatedDocument(
    NoteDocument previous,
    NoteDocument updated,
    int targetIndex,
  ) async {
    final LibraryDocument? libraryItem = _library.documents
        .where((item) => item.id == previous.id)
        .firstOrNull;
    if (libraryItem != null) {
      // 把旧页面索引映射到更新后的页序；原页已删除时返回 null。
      int? remapIndex(int oldIndex) {
        if (oldIndex < 0 || oldIndex >= previous.pages.length) return null;
        final int originalPage = previous.pages[oldIndex].originalPage;
        final int mapped = updated.pages.indexWhere(
          (page) => page.originalPage == originalPage,
        );
        return mapped < 0 ? null : mapped;
      }

      final List<int> bookmarks =
          libraryItem.bookmarkedPages
              .map(remapIndex)
              .whereType<int>()
              .toSet()
              .toList()
            ..sort();
      final Map<int, String> titles = <int, String>{};
      for (final MapEntry<int, String> entry
          in libraryItem.pageTitles.entries) {
        final int? mapped = remapIndex(entry.key);
        if (mapped != null) titles[mapped] = entry.value;
      }
      _library = LibraryState(
        documents: _library.documents
            .map(
              (item) => item.id == libraryItem.id
                  ? item.copyWith(
                      bookmarkedPages: bookmarks,
                      pageTitles: titles,
                    )
                  : item,
            )
            .toList(),
        folders: _library.folders,
      );
    }
    await _saveLibrary();
    if (!mounted || _doc.document?.id != previous.id) return;
    final NoteDocument targeted = NoteDocument(
      id: updated.id,
      title: updated.title,
      directory: updated.directory,
      pages: updated.pages,
      initialIndex: targetIndex.clamp(0, updated.pages.length - 1),
    );
    await _useDocument(targeted, folderId: libraryItem?.folderId);
    _updateState(() => _showPageSidebar = true);
  }
}
