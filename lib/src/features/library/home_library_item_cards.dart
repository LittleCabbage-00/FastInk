part of '../../app/fastink_app.dart';

extension _FastInkLibraryItemCards on _FastInkHomeState {
  /// 用一致图标与标签创建卡片菜单项，稳定动作值与显示语言分离。
  PopupMenuItem<String> _libraryMenuItem(
    String value,
    IconData icon,
    String label,
  ) => PopupMenuItem<String>(
    value: value,
    height: 44,
    child: Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 12),
        Expanded(child: Text(label)),
      ],
    ),
  );

  /// 显示文件夹外观、项目数和菜单，同时提供进入与文稿拖入目标。
  Widget _folderCard(LibraryFolder folder, {double previewHeight = 200}) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final int count =
        _library.folders
            .where(
              (item) =>
                  item.parentId == folder.id &&
                  !item.trashed &&
                  item.scope == folder.scope,
            )
            .length +
        _library.documents
            .where((item) => item.folderId == folder.id && !item.trashed)
            .length;
    final card = InkWell(
      key: ValueKey('folder-${folder.id}'),
      borderRadius: BorderRadius.circular(16),
      onTap: () {
        _searchInput.clear();
        _updateState(() => _activeFolderId = folder.id);
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            height: previewHeight,
            decoration: BoxDecoration(
              color: Color(folder.colorValue).withValues(alpha: .14),
              borderRadius: BorderRadius.circular(16),
              boxShadow: const <BoxShadow>[
                BoxShadow(
                  color: Color(0x18000000),
                  blurRadius: 12,
                  offset: Offset(0, 5),
                ),
              ],
            ),
            child: Stack(
              children: <Widget>[
                Center(
                  child: Icon(
                    Icons.folder_rounded,
                    color: Color(folder.colorValue),
                    size: 64,
                  ),
                ),
                Positioned(
                  right: 5,
                  top: 5,
                  child: PopupMenuButton<String>(
                    popUpAnimationStyle: appMotionStyle(context),
                    key: ValueKey('folder-menu-${folder.id}'),
                    constraints: const BoxConstraints(
                      minWidth: 220,
                      maxWidth: 300,
                    ),
                    iconColor: Color(folder.colorValue),
                    onSelected: (String value) {
                      if (value == 'rename') unawaited(_renameFolder(folder));
                      if (value == 'color') {
                        unawaited(_changeFolderColor(folder));
                      }
                      if (value == 'delete') unawaited(_deleteFolder(folder));
                    },
                    itemBuilder: (_) => <PopupMenuEntry<String>>[
                      _libraryMenuItem(
                        'rename',
                        Icons.drive_file_rename_outline_rounded,
                        tr('重命名'),
                      ),
                      _libraryMenuItem(
                        'color',
                        Icons.palette_outlined,
                        tr('更改颜色'),
                      ),
                      const PopupMenuDivider(),
                      _libraryMenuItem(
                        'delete',
                        Icons.folder_delete_outlined,
                        tr('删除文件夹'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 11),
          Text(
            folder.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colors.onSurface,
              fontSize: 15,
              height: 1.35,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            tr('$count 个项目', '$count items'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colors.onSurfaceVariant,
              fontSize: 12,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
    return _libraryDropZone(
      folderId: folder.id,
      child: Tooltip(message: folder.name, child: card),
      targetKey: ValueKey('folder-drop-${folder.id}'),
    );
  }

  /// 显示文稿缓存封面、标题和元数据，区分 Markdown/手写打开路径，并绑定收藏、移动、导出与废纸篓操作。
  Widget _documentCard(LibraryDocument item, {double previewHeight = 200}) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final bool isMarkdown = item.sourcePath.toLowerCase().endsWith('.md');
    final card = InkWell(
      key: ValueKey('document-${item.id}'),
      borderRadius: BorderRadius.circular(16),
      onTap: item.trashed
          ? null
          : isMarkdown
          ? () => _openMarkdownEditor(filePath: item.sourcePath)
          : () => _openLibraryDocument(item),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            height: previewHeight,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colors.outlineVariant),
              boxShadow: const <BoxShadow>[
                BoxShadow(
                  color: Color(0x14000000),
                  blurRadius: 12,
                  offset: Offset(0, 5),
                ),
              ],
            ),
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                if (isMarkdown)
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(
                          Icons.code_rounded,
                          size: 52,
                          color: colors.primary,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Markdown',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: colors.primary,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  LibraryNotePreview(
                    key: ValueKey(
                      'cover-${item.id}-${item.lastOpenedAt.microsecondsSinceEpoch}',
                    ),
                    root: _dataRoot,
                    documentId: item.id,
                    coverPath: item.coverPath,
                  ),
                if (item.favorite)
                  const Positioned(
                    left: 10,
                    top: 10,
                    child: Icon(Icons.star_rounded, color: Color(0xffffb300)),
                  ),
                Positioned(
                  right: 6,
                  top: 6,
                  child: PopupMenuButton<String>(
                    popUpAnimationStyle: appMotionStyle(context),
                    key: ValueKey('document-menu-${item.id}'),
                    constraints: const BoxConstraints(
                      minWidth: 220,
                      maxWidth: 300,
                    ),
                    icon: Icon(
                      Icons.more_horiz_rounded,
                      color: colors.onSurfaceVariant,
                    ),
                    onSelected: (String value) {
                      if (value == 'favorite') {
                        unawaited(_toggleFavorite(item));
                      } else if (value == 'rename') {
                        unawaited(_renameDocument(item));
                      } else if (value == 'move') {
                        unawaited(_moveDocumentToFolder(item));
                      } else if (value == 'export') {
                        unawaited(_exportLibraryDocument(item));
                      } else if (value == 'trash') {
                        unawaited(_setDocumentTrashed(item, true));
                      } else if (value == 'restore') {
                        unawaited(_setDocumentTrashed(item, false));
                      } else if (value == 'delete') {
                        unawaited(_deleteDocumentPermanently(item));
                      }
                    },
                    itemBuilder: (_) => <PopupMenuEntry<String>>[
                      if (!item.trashed)
                        _libraryMenuItem(
                          'rename',
                          Icons.drive_file_rename_outline_rounded,
                          tr('重命名'),
                        ),
                      if (!item.trashed)
                        _libraryMenuItem(
                          'favorite',
                          item.favorite
                              ? Icons.star_rounded
                              : Icons.star_border_rounded,
                          tr(item.favorite ? '取消收藏' : '加入收藏'),
                        ),
                      if (!item.trashed)
                        _libraryMenuItem(
                          'move',
                          Icons.drive_file_move_outline,
                          tr('移动到文件夹'),
                        ),
                      if (!item.trashed && !isMarkdown)
                        _libraryMenuItem(
                          'export',
                          Icons.ios_share_rounded,
                          tr('导出', 'Export'),
                        ),
                      const PopupMenuDivider(),
                      _libraryMenuItem(
                        item.trashed ? 'restore' : 'trash',
                        item.trashed
                            ? Icons.restore_from_trash_outlined
                            : Icons.delete_outline_rounded,
                        tr(item.trashed ? '恢复' : '移到废纸篓'),
                      ),
                      if (item.trashed)
                        _libraryMenuItem(
                          'delete',
                          Icons.delete_forever_outlined,
                          tr('永久删除'),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              if (isMarkdown)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
                  margin: const EdgeInsets.only(right: 6),
                  decoration: BoxDecoration(
                    color: colors.primaryContainer,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'MD',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: colors.onPrimaryContainer,
                    ),
                  ),
                ),
              Expanded(
                child: Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.onSurface,
                    fontSize: 15,
                    height: 1.35,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          Text(
            tr(
              '${item.pageCount} 页 · ${_friendlyDate(item.lastOpenedAt)}',
              '${item.pageCount} pages · ${_friendlyDate(item.lastOpenedAt)}',
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colors.onSurfaceVariant,
              fontSize: 12,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
    if (item.trashed) return card;
    return LibraryDocumentDrag(
      onDragStarted: () =>
          _updateState(() => _libraryDraggingDocumentId = item.id),
      onDragEnded: () {
        if (mounted) _updateState(() => _libraryDraggingDocumentId = null);
      },
      data: item.id,
      feedback: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: 180,
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(isMarkdown ? Icons.code : Icons.description_outlined),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
      child: Tooltip(message: item.title, child: card),
    );
  }
}
