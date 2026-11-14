part of '../../app/fastink_app.dart';

extension _FastInkDocumentTabs on _FastInkHomeState {
  /// 列出已打开手写文稿并标明当前项，附加按文件夹浏览入口；不会把标签列表误当完整资料库。
  Widget _compactDocumentSwitcher() => PopupMenuButton<String>(
    popUpAnimationStyle: appMotionStyle(context),
    key: const ValueKey('document-switcher'),
    tooltip: tr('切换文稿', 'Switch document'),
    icon: const Icon(Icons.tab_rounded),
    onSelected: (id) {
      if (id == '@browse-library') {
        unawaited(_browseLibraryDocuments());
      } else {
        unawaited(_switchDocumentTab(id));
      }
    },
    itemBuilder: (_) => [
      for (final id in _doc.openDocumentIds)
        if (_library.documents
                .where((item) => item.id == id && !item.trashed)
                .firstOrNull
            case final item?)
          PopupMenuItem(
            value: id,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                id == _doc.document?.id
                    ? Icons.check_rounded
                    : Icons.description_outlined,
              ),
              title: Text(
                item.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
      const PopupMenuDivider(),
      PopupMenuItem(
        key: const ValueKey('browse-library-documents'),
        value: '@browse-library',
        enabled: !_doc.anyBusy,
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.folder_open_rounded),
          title: Text(tr('按文件夹打开文稿', 'Browse document folders')),
        ),
      ),
    ],
  );

  /// 以当前资料库快照打开文件夹选稿窗口；取消保持当前文稿，选择不同目标后走统一文稿打开流程。
  Future<void> _browseLibraryDocuments() async {
    final selected = await showDialog<LibraryDocument>(
      context: context,
      animationStyle: appMotionStyle(context),
      builder: (_) => LibraryDocumentPicker(
        library: _library,
        currentId: _doc.document?.id,
      ),
    );
    if (selected != null && mounted && selected.id != _doc.document?.id) {
      await _openLibraryDocument(selected);
    }
  }

  /// 构建可滚动的文稿标签，点击切换、关闭按钮移除标签，当前标签双击可重命名。
  Widget _documentTabs() {
    final List<LibraryDocument> tabs = _doc.openDocumentIds
        .map(
          (String id) => _library.documents
              .where((LibraryDocument item) => item.id == id && !item.trashed)
              .firstOrNull,
        )
        .whereType<LibraryDocument>()
        .toList();
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      reverse: true,
      itemCount: tabs.length,
      separatorBuilder: (_, _) => const SizedBox(width: 5),
      itemBuilder: (BuildContext context, int index) {
        final LibraryDocument item = tabs[index];
        final bool selected = item.id == _doc.document?.id;
        return Center(
          child: Tooltip(
            message: selected
                ? '${_settings.showPerformance && _doc.performance.isNotEmpty ? '$_doc.performance · ' : ''}$_doc.status\n${tr('双击标签可重命名', 'Double-click the tab to rename')}'
                : tr('切换到 ${item.title}', 'Switch to ${item.title}'),
            child: GestureDetector(
              onDoubleTap: selected ? () => _renameDocument(item) : null,
              child: InputChip(
                selected: selected,
                showCheckmark: false,
                avatar: Icon(
                  selected
                      ? Icons.edit_note_rounded
                      : Icons.description_outlined,
                  size: 18,
                ),
                label: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 130),
                  child: Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                onPressed: () => _switchDocumentTab(item.id),
                onDeleted: () => _closeDocumentTab(item.id),
                deleteIcon: const Icon(Icons.close_rounded, size: 17),
              ),
            ),
          ),
        );
      },
    );
  }

  /// 构建文档更多操作菜单，依当前外观、只读及任务状态展示选中/禁用项，并分派相应操作。
  Widget _documentMoreMenu() => PopupMenuButton<String>(
    popUpAnimationStyle: appMotionStyle(context),
    tooltip: tr('更多'),
    icon: const Icon(Icons.more_horiz_rounded),
    onSelected: (String value) {
      switch (value) {
        case 'search':
          unawaited(_showDocumentSearch());
        case 'readonly':
          _updateState(() => _doc.readOnly = !_doc.readOnly);
        case 'rename':
          final LibraryDocument? item = _currentLibraryDocument;
          if (item != null) unawaited(_renameDocument(item));
        case 'add-page':
          unawaited(_addPage(afterIndex: _doc.pageIndex));
        case 'insert-images':
          unawaited(_insertImagePages());
        case 'embed-images':
          unawaited(_insertImagesOnCurrentPage());
        case 'paper':
          unawaited(_changePaperTemplate());
        case 'export':
          unawaited(_exportDocument());
        case 'theme-system':
          widget.onThemeModeChanged(ThemeMode.system);
        case 'theme-light':
          widget.onThemeModeChanged(ThemeMode.light);
        case 'theme-dark':
          widget.onThemeModeChanged(ThemeMode.dark);
        case 'import-external':
          unawaited(_importExternalToLibrary());
      }
    },
    itemBuilder: (_) => <PopupMenuEntry<String>>[
      PopupMenuItem(
        value: 'search',
        child: ListTile(
          leading: const Icon(Icons.search_rounded),
          title: Text(tr('搜索本文稿', 'Search this document')),
        ),
      ),
      // 外部文件模式：显示导入到资料库的选项。
      if (_doc.externalFileMode)
        PopupMenuItem<String>(
          value: 'import-external',
          child: ListTile(
            leading: const Icon(Icons.download_rounded),
            title: Text(tr('导入到资料库编辑', 'Import to library for editing')),
          ),
        ),
      PopupMenuItem<String>(
        value: 'rename',
        child: ListTile(
          leading: const Icon(Icons.drive_file_rename_outline_rounded),
          title: Text(tr('重命名文稿')),
        ),
      ),
      PopupMenuItem<String>(
        value: 'readonly',
        child: ListTile(
          leading: Icon(
            _doc.readOnly ? Icons.edit_outlined : Icons.visibility_outlined,
          ),
          title: Text(tr(_doc.readOnly ? '切换到编辑模式' : '切换到只读模式')),
          subtitle: Text(
            tr(
              _doc.readOnly ? '当前：只读' : '当前：可编辑',
              _doc.readOnly ? 'Current: Read-only' : 'Current: Editable',
            ),
          ),
        ),
      ),
      PopupMenuItem<String>(
        value: 'add-page',
        enabled: !_doc.busy,
        child: ListTile(
          leading: const Icon(Icons.add_box_outlined),
          title: Text(tr('添加页面')),
        ),
      ),
      PopupMenuItem<String>(
        value: 'embed-images',
        enabled: !_doc.busy && !_doc.inkInputBlocked,
        child: ListTile(
          leading: const Icon(Icons.image_outlined),
          title: Text(tr('将图片放入当前页', 'Place image on current page')),
        ),
      ),
      PopupMenuItem<String>(
        value: 'insert-images',
        enabled: !_doc.busy,
        child: ListTile(
          leading: const Icon(Icons.add_photo_alternate_outlined),
          title: Text(tr('插入图片页')),
        ),
      ),
      PopupMenuItem<String>(
        value: 'paper',
        enabled: !_doc.busy,
        child: ListTile(
          leading: const Icon(Icons.dashboard_customize_outlined),
          title: Text(tr('更改纸张')),
        ),
      ),
      PopupMenuItem<String>(
        value: 'export',
        enabled: !_doc.busy,
        child: ListTile(
          leading: const Icon(Icons.ios_share_rounded),
          title: Text(tr('导出 PDF / PNG / JPG')),
        ),
      ),
      const PopupMenuDivider(),
      PopupMenuItem<String>(
        value: 'theme-system',
        child: ListTile(
          leading: const Icon(Icons.brightness_auto_outlined),
          title: Text(tr('跟随系统')),
          selected: widget.themeMode == ThemeMode.system,
          trailing: widget.themeMode == ThemeMode.system
              ? const Icon(Icons.check_rounded)
              : null,
        ),
      ),
      PopupMenuItem<String>(
        value: 'theme-light',
        child: ListTile(
          leading: const Icon(Icons.light_mode_outlined),
          title: Text(tr('浅色模式')),
          selected: widget.themeMode == ThemeMode.light,
          trailing: widget.themeMode == ThemeMode.light
              ? const Icon(Icons.check_rounded)
              : null,
        ),
      ),
      PopupMenuItem<String>(
        value: 'theme-dark',
        child: ListTile(
          leading: const Icon(Icons.dark_mode_outlined),
          title: Text(tr('深色模式')),
          selected: widget.themeMode == ThemeMode.dark,
          trailing: widget.themeMode == ThemeMode.dark
              ? const Icon(Icons.check_rounded)
              : null,
        ),
      ),
    ],
  );
}
