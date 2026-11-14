part of '../../app/fastink_app.dart';

extension _FastInkDocumentShell on _FastInkHomeState {
  /// 创建外观选择菜单，显示当前选中模式；compact 仅改变触发控件布局，不改变持久化范围。
  Widget _themeMenu({bool compact = false}) {
    final IconData icon = switch (widget.themeMode) {
      ThemeMode.light => Icons.light_mode_outlined,
      ThemeMode.dark => Icons.dark_mode_outlined,
      ThemeMode.system => Icons.brightness_auto_outlined,
    };
    final String label = switch (widget.themeMode) {
      ThemeMode.light => tr('浅色'),
      ThemeMode.dark => tr('深色'),
      ThemeMode.system => tr('跟随系统'),
    };
    return PopupMenuButton<ThemeMode>(
      popUpAnimationStyle: appMotionStyle(context),
      tooltip: '${tr('外观')}: $label',
      onSelected: widget.onThemeModeChanged,
      itemBuilder: (_) => <PopupMenuEntry<ThemeMode>>[
        for (final (ThemeMode mode, IconData itemIcon, String itemLabel)
            in <(ThemeMode, IconData, String)>[
              (ThemeMode.system, Icons.brightness_auto_outlined, '跟随系统'),
              (ThemeMode.light, Icons.light_mode_outlined, '浅色模式'),
              (ThemeMode.dark, Icons.dark_mode_outlined, '深色模式'),
            ])
          PopupMenuItem<ThemeMode>(
            value: mode,
            child: Row(
              children: <Widget>[
                Icon(itemIcon),
                const SizedBox(width: 12),
                Expanded(child: Text(tr(itemLabel))),
                if (widget.themeMode == mode)
                  const Icon(Icons.check_rounded, size: 18),
              ],
            ),
          ),
      ],
      child: compact
          ? Padding(
              padding: const EdgeInsets.all(8),
              child: Icon(icon, size: 21),
            )
          : ListTile(
              dense: true,
              leading: Icon(icon),
              title: Text(tr('外观')),
              subtitle: Text(label),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
    );
  }

  /// 提交纸面输入并等待保存队列，然后拆下当前画布、作废旧页任务并返回资料库；旧位图延后到当前帧结束释放。
  Future<void> _goToLibrary() async {
    if (_immersiveMode) _setImmersive(false);
    _commitInlineText();
    if (!await _saveNow() || !mounted) return;
    final ui.Image? image = _doc.pageImage;
    // 旧位图可能仍用于当前帧，资料库首帧结束后再释放。
    ++_doc.pageToken;
    _updateState(() {
      _doc.document = null;
      _viewport.documentViewportLayout = null;
      _viewport.documentLayoutId = null;
      _doc.pageImage = null;
      _pageInkCache.clear();
      // 迟到的滚动定时器和串行链里的旧文稿任务一并掐掉：generation 对不上
      // 就不会再把旧文稿的笔迹写进刚清空的缓存。
      _sidebarThumbnailTimer?.cancel();
      _sidebarThumbnailGeneration++;
      _doc.readOnly = false;
      _doc.externalFileMode = false;
      _doc.externalTempPath = null;
      _doc.performance = '';
      _doc.status = tr('资料库已就绪');
    });
    if (image != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => image.dispose());
    }
  }

  /// 按选中路径建立文稿索引并进入统一激活流程；错误写入状态反馈，不让异常直接替换成空文稿。
  Future<void> _openPath(String path) async {
    try {
      _updateState(
        () => _doc.status = tr('正在扫描页面文件名…', 'Scanning page filenames…'),
      );
      final NoteDocument document = await _repository.indexFromSelectedPath(
        path,
      );
      await _useDocument(document);
    } catch (error) {
      if (mounted) {
        _updateState(
          () => _doc.status = tr('打开失败：$error', 'Could not open: $error'),
        );
      }
    }
  }

  /// 右键上下文菜单触发：把外部文件复制到 %temp% 后以只读模式打开。
  ///
  /// 流程：
  ///   1. 创建 %temp%/FastInk 临时目录
  ///   2. 异步复制文件到该目录（保留原文件名，不阻塞 UI）
  ///   3. 用 _openPath 打开临时副本
  ///   4. 标记为只读模式，不写回原文件
  Future<void> _openExternalFile(String filePath) async {
    try {
      final File source = File(filePath);
      if (!source.existsSync()) {
        _updateState(
          () =>
              _doc.status = tr('文件不存在：$filePath', 'File not found: $filePath'),
        );
        return;
      }
      final String tempDir = _tempExternalDir();
      final Directory dir = Directory(tempDir);
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      final String fileName = filePath.split(Platform.pathSeparator).last;
      final String destPath = '$tempDir${Platform.pathSeparator}$fileName';
      _updateState(
        () => _doc.status = tr('正在复制到临时目录…', 'Copying to temp directory…'),
      );
      // 异步复制，避免大文件阻塞 UI。
      final File dest = File(destPath);
      if (!dest.existsSync() ||
          dest.lastModifiedSync().isBefore(source.lastModifiedSync())) {
        await source.copy(destPath);
      }
      // 用只读模式打开临时副本。
      _doc.readOnly = true;
      _doc.externalFileMode = true;
      _doc.externalTempPath = destPath;
      await _openPath(destPath);
    } catch (error) {
      if (mounted) {
        _updateState(() {
          _doc.status = tr(
            '外部文件打开失败：$error',
            'External file open failed: $error',
          );
        });
      }
    }
  }

  /// 返回 FastInk 临时文件目录路径。
  String _tempExternalDir() {
    final String base =
        Platform.environment['TEMP'] ??
        Platform.environment['TMP'] ??
        Platform.environment['LOCALAPPDATA'] ??
        Directory.systemTemp.path;
    return '$base${Platform.pathSeparator}FastInk';
  }

  /// 外部文件导入到资料库：把临时副本复制到资料库存储，切换到编辑模式。
  ///
  /// 使用 [_doc.externalTempPath] 定位临时副本（由 [_openExternalFile] 记录），
  /// 避免从 doc.directory 错误拼接路径。
  Future<void> _importExternalToLibrary() async {
    final String? tempPath = _doc.externalTempPath;
    if (tempPath == null) return;
    try {
      _updateState(() {
        _doc.status = tr('正在导入到资料库…', 'Importing to library…');
      });
      // _openPath 会处理索引和去重，将文件复制到资料库存储。
      final String importSource = tempPath;
      _doc.externalFileMode = false;
      _doc.readOnly = false;
      _doc.externalTempPath = null;
      await _openPath(importSource);
    } catch (error) {
      if (mounted) {
        _updateState(() {
          _doc.status = tr('导入失败：$error', 'Import failed: $error');
        });
      }
    }
  }

  /// 激活新文稿前提交旧输入与保存，预热页面几何后重置相机/侧栏/工具，并装载初始页；取消旧文稿可见页定时任务以免被拉回首页。
  Future<void> _useDocument(NoteDocument document, {String? folderId}) async {
    _commitInlineText();
    if (!await _saveNow() || !mounted) return;
    await _rememberDocument(document, folderId: folderId);
    unawaited(_ensurePdfOutline(document));
    // 打开编辑器前先读取当前页和相邻页的文件头。首帧就采用真实纸张比例，
    // 不会先画一张默认竖版 A4，再在图片解码完成后突然改尺寸。
    await _warmPageAppearances(document, <int>[
      document.initialIndex,
      document.initialIndex - 1,
      document.initialIndex + 1,
    ]);
    _doc.openDocumentIds
      ..remove(document.id)
      ..add(document.id);
    if (_doc.openDocumentIds.length > 5) _doc.openDocumentIds.removeAt(0);
    _doc.document = document;
    _doc.pageIndex = document.initialIndex;
    _viewport.pendingViewportPage = document.initialIndex;
    _viewport.pendingVisiblePage = null;
    _viewport.documentViewportLayout = null;
    _viewport.documentLayoutId = null;
    _viewport.documentLayoutRevision = -1;
    _doc.readOnly = _settings.defaultReadOnly;
    _showPageSidebar = _settings.openSidebarByDefault;
    _sidebarTab = _settings.defaultSidebarTab;
    _applyDefaultFitOnNextLayout = true;
    _resetZoom(notify: false);
    // _resetZoom 把相机设回单位矩阵并通知监听者。此时组件树里还是上一份
    // 文稿的 _VirtualDocumentViewport（换树要等下一帧），它拿着自己那份
    // 旧布局算出"视口中心 = 旧文稿第 0 页"，回调 _scheduleVisiblePage(0)。
    // 那个页码和刚设好的 initialIndex 不同，于是排下一个 72ms 后
    // _loadPage(0) 的定时器——后面没有任何地方取消它，新文稿会被拽回
    // 第一页。所以必须在 _resetZoom 之后再清一次。
    _viewport.pendingVisiblePage = null;
    _viewport.visiblePageTimer?.cancel();
    // 换文稿（以及增删页、旋转、排序这些走同一条路径的改动）之后，
    // 缓存里的笔迹快照不再对应磁盘上的内容，整体作废重读。
    _pageInkCache.clear();
    // 同时掐掉旧文稿的侧栏加载：150ms 去抖定时器和串行链里还在排队的
    // 任务都捕获了旧 document，不作废 generation 就会把旧文稿的笔迹
    // 填进刚清空的缓存，甚至继续为旧文稿跑 pdftoppm。
    _sidebarThumbnailTimer?.cancel();
    _sidebarThumbnailGeneration++;
    _selectTool(
      InkTool.values.firstWhere(
        (v) => v.name == _settings.defaultTool,
        orElse: () => InkTool.pen,
      ),
    );
    await _loadPage(document.initialIndex);
  }

  /// 根据已保存索引切换到另一打开文稿；当前项或已不存在/已删除目标不重复激活。
  Future<void> _switchDocumentTab(String documentId) async {
    if (_doc.document?.id == documentId) return;
    final LibraryDocument? item = _library.documents
        .where((LibraryDocument value) => value.id == documentId)
        .firstOrNull;
    if (item != null && !item.trashed) await _openLibraryDocument(item);
  }

  /// 移除指定标签；关闭活动项时等待保存，再打开剩余最后一项，没有标签则返回资料库。
  Future<void> _closeDocumentTab(String documentId) async {
    final bool current = _doc.document?.id == documentId;
    if (current) {
      _commitInlineText();
      if (!await _saveNow() || !mounted) return;
    }
    _updateState(() => _doc.openDocumentIds.remove(documentId));
    if (!current) return;
    final String? nextId = _doc.openDocumentIds.isEmpty
        ? null
        : _doc.openDocumentIds.last;
    if (nextId == null) {
      await _goToLibrary();
    } else {
      await _switchDocumentTab(nextId);
    }
  }
}
