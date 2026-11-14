part of '../../app/fastink_app.dart';

extension _FastInkLibraryCards on _FastInkHomeState {
  /// 构建新建/导入合并入口，根据手写或 Markdown 域展示对应动作；废纸篓由上层隐藏入口。
  Widget _newLibraryMenu(ColorScheme colors, {bool compact = false}) {
    final bool isMarkdown = _librarySection == 'markdown';
    return PopupMenuButton<String>(
      popUpAnimationStyle: appMotionStyle(context),
      key: ValueKey('library-new-menu-${_activeFolderId ?? 'root'}'),
      tooltip: tr('新建或导入'),
      onSelected: (String value) =>
          unawaited(_handleNewLibraryMenuSelection(value)),
      itemBuilder: (_) => <PopupMenuEntry<String>>[
        if (!isMarkdown)
          PopupMenuItem<String>(
            value: 'note',
            child: ListTile(
              leading: const Icon(Icons.menu_book_rounded),
              title: Text(tr('新建笔记')),
            ),
          ),
        if (isMarkdown)
          PopupMenuItem<String>(
            value: 'new-md',
            child: ListTile(
              leading: const Icon(Icons.edit_note_rounded),
              title: Text(tr('新建 Markdown')),
            ),
          ),
        PopupMenuItem<String>(
          value: 'folder',
          child: ListTile(
            leading: const Icon(Icons.create_new_folder_outlined),
            title: Text(tr('新建文件夹')),
          ),
        ),
        const PopupMenuDivider(),
        if (!isMarkdown)
          PopupMenuItem<String>(
            value: 'files',
            child: ListTile(
              leading: const Icon(Icons.file_download_outlined),
              title: Text(tr('导入 PDF / 图片')),
            ),
          ),
        if (isMarkdown)
          PopupMenuItem<String>(
            value: 'import-md',
            child: ListTile(
              leading: const Icon(Icons.file_download_outlined),
              title: Text(tr('导入 Markdown')),
            ),
          ),
        if (!isMarkdown)
          PopupMenuItem<String>(
            value: 'onenote',
            child: ListTile(
              leading: const Icon(Icons.note_alt_outlined),
              title: Text(tr('导入 OneNote', 'Import OneNote')),
              subtitle: const Text('.one / .onex / .onepkg'),
            ),
          ),
      ],
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 12 : 18,
          vertical: compact ? 11 : 14,
        ),
        decoration: BoxDecoration(
          color: colors.primary,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.add_rounded, color: colors.onPrimary),
            ...<Widget>[
              const SizedBox(width: 6),
              Text(
                tr('新建 / 导入', 'New / Import'),
                style: TextStyle(
                  color: colors.onPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 按稳定动作标识分派新建、导入或文件夹创建，显示标签翻译不能影响行为匹配。
  Future<void> _handleNewLibraryMenuSelection(String value) async {
    // PopupMenu 的结果会在退场动画结束前返回。稍等一帧动画周期再打开
    // 对话框，可避免菜单与模态框短暂叠在一起。
    await Future<void>.delayed(appMotionDuration(context, 180));
    if (!mounted) return;
    switch (value) {
      case 'note':
        await _createBlankNote();
      case 'new-md':
        _openMarkdownEditor();
      case 'folder':
        await _createFolder();
      case 'files':
        await _importFiles();
      case 'import-md':
        await _importMarkdownFiles();
      case 'onenote':
        await _importOneNoteFiles();
    }
  }

  /// 将当前资料库类别映射到手写或 Markdown 文件夹域。
  LibraryScope get _libraryScope => _librarySection == 'markdown'
      ? LibraryScope.markdown
      : LibraryScope.notes;

  /// 按类别、目录和查询筛选轻量记录，计算自适应卡片尺寸；浏览/搜索/各文件夹使用独立滚动状态键。
  Widget _libraryGrid({String? folderId, bool dense = false}) {
    if (!_libraryLoaded) {
      return const Center(child: CircularProgressIndicator());
    }
    final query = _searchInput.text.trim().toLowerCase();
    final scoped =
        _librarySection == 'documents' || _librarySection == 'markdown';
    var documents = _library.documents.where((item) {
      if (query.isNotEmpty && !item.title.toLowerCase().contains(query)) {
        return false;
      }
      if (_librarySection == 'trash') return item.trashed;
      if (item.trashed || item.scope != _libraryScope) return false;
      if (scoped && (query.isEmpty || folderId != null)) {
        return item.folderId == folderId;
      }
      if (_librarySection == 'favorites') return item.favorite;
      return true;
    }).toList()..sort((a, b) => b.lastOpenedAt.compareTo(a.lastOpenedAt));
    if (_librarySection == 'recent') documents = documents.take(30).toList();
    final folders = scoped
        ? _library.folders
              .where(
                (f) =>
                    !f.trashed &&
                    f.scope == _libraryScope &&
                    (query.isNotEmpty || f.parentId == folderId) &&
                    (query.isEmpty || f.name.toLowerCase().contains(query)),
              )
              .toList()
        : <LibraryFolder>[];
    final grid = LayoutBuilder(
      builder: (context, constraints) {
        final padding = dense ? 16.0 : 24.0;
        final gap = dense ? 14.0 : 20.0;
        final minimum = dense ? 148.0 : 180.0;
        final available = math.max(1.0, constraints.maxWidth - padding * 2);
        final columns = math.max(
          1,
          ((available + gap) / (minimum + gap)).floor(),
        );
        final cardWidth = (available - gap * (columns - 1)) / columns;
        final previewHeight = (cardWidth * 1.18).clamp(
          dense ? 130.0 : 150.0,
          dense ? 170.0 : 204.0,
        );
        final textScale = MediaQuery.textScalerOf(context);
        final captionHeight = math
            .max(
              58.0,
              textScale.scale(15) * 1.35 + textScale.scale(12) * 1.35 + 18,
            )
            .ceilToDouble();
        if (documents.isEmpty && folders.isEmpty) {
          return _emptyLibraryState(inFolder: folderId != null);
        }
        return GridView.builder(
          // 浏览、搜索和各个文件夹分别记住位置，返回文稿时不跳回列表顶部。
          key: PageStorageKey(
            'library-grid-$_librarySection-${folderId ?? 'root'}-${query.isEmpty ? 'browse' : 'search'}',
          ),
          padding: EdgeInsets.fromLTRB(padding, 16, padding, 24),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisExtent: previewHeight + captionHeight,
            crossAxisSpacing: gap,
            mainAxisSpacing: 18,
          ),
          itemCount: folders.length + documents.length,
          itemBuilder: (context, index) => index < folders.length
              ? _folderCard(folders[index], previewHeight: previewHeight)
              : _documentCard(
                  documents[index - folders.length],
                  previewHeight: previewHeight,
                ),
        );
      },
    );
    if (!scoped) return grid;
    return _libraryDropZone(
      folderId: folderId,
      child: grid,
      targetKey: ValueKey('library-drop-${folderId ?? 'root'}'),
    );
  }

  /// 在主文稿网格上展开文件夹面板并展示合适的拖出目标，保持资料库顶部入口可访问。
  Widget _libraryBrowser() => LayoutBuilder(
    builder: (context, constraints) {
      final folderKey = ValueKey(_activeFolderId);
      final reducedMotion = reducedAppMotion(context);
      final duration = Duration(milliseconds: reducedMotion ? 0 : 160);
      final draggingFromFolder =
          _libraryDraggingDocumentId != null &&
          _library.documents.any(
            (d) => d.id == _libraryDraggingDocumentId && d.folderId != null,
          );
      return Stack(
        children: [
          // 文件夹面板覆盖在原有根目录网格上；是否打开文件夹
          // 均不改变根网格的宽度、卡片密度或纵向起点。
          Positioned.fill(
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: constraints.maxWidth,
                height: constraints.maxHeight,
                child: _libraryGrid(),
              ),
            ),
          ),
          if (_activeFolderId != null)
            Positioned(
              key: const ValueKey('library-root-drop-slot'),
              left: 12,
              top: 8,
              width: constraints.maxWidth / 2 - 24,
              height: 44,
              child: IgnorePointer(
                ignoring: !draggingFromFolder,
                child: AnimatedOpacity(
                  opacity: draggingFromFolder ? 1 : 0,
                  duration: appMotionDuration(context, 100),
                  child: Material(
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                    child: _libraryDropZone(
                      folderId: null,
                      targetKey: const ValueKey('library-root-drop'),
                      child: Center(
                        child: Text(
                          tr('拖到这里移出文件夹', 'Drop here to move to root'),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          Positioned(
            key: const ValueKey('library-folder-slot'),
            right: 0,
            top: 0,
            bottom: 0,
            width: constraints.maxWidth / 2,
            child: IgnorePointer(
              ignoring: _activeFolderId == null,
              child: AnimatedSwitcher(
                key: const ValueKey('library-folder-transition'),
                duration: duration,
                reverseDuration: Duration(
                  milliseconds: reducedMotion ? 0 : 180,
                ),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                layoutBuilder: (current, previous) => Stack(
                  fit: StackFit.expand,
                  children: [...previous, ?current],
                ),
                transitionBuilder: (child, animation) => IgnorePointer(
                  ignoring: child.key != folderKey,
                  child: FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween(
                        begin: const Offset(.06, .015),
                        end: Offset.zero,
                      ).animate(animation),
                      child: ScaleTransition(
                        scale: Tween(begin: .97, end: 1.0).animate(animation),
                        alignment: Alignment.centerRight,
                        child: child,
                      ),
                    ),
                  ),
                ),
                child: _activeFolderId == null
                    ? const SizedBox.shrink(key: ValueKey('closed-folder'))
                    : KeyedSubtree(
                        key: folderKey,
                        child: RepaintBoundary(child: _libraryFolderPanel()),
                      ),
              ),
            ),
          ),
        ],
      );
    },
  );

  /// 显示当前有效目录的标题、父级导航、关闭按钮与密集文稿网格，不把文件夹替换为整页路由。
  Widget _libraryFolderPanel() {
    final folder = _library.folders
        .where(
          (f) =>
              f.id == _activeFolderId && f.scope == _libraryScope && !f.trashed,
        )
        .firstOrNull;
    if (folder == null) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 12, 16, 16),
      child: Material(
        key: const ValueKey('library-folder-panel'),
        elevation: 5,
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 8, 8),
              child: Row(
                children: [
                  IconButton(
                    tooltip: tr('返回上一级'),
                    onPressed: _openParentFolder,
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                  Icon(Icons.folder_rounded, color: Color(folder.colorValue)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      folder.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('close-library-folder'),
                    tooltip: tr('关闭'),
                    onPressed: () => _updateState(() => _activeFolderId = null),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            if (folder.parentId != null)
              _libraryDropZone(
                folderId: folder.parentId,
                targetKey: const ValueKey('library-parent-drop'),
                child: SizedBox(
                  height: 36,
                  child: Center(
                    child: Text(
                      tr('拖到这里移到上一级', 'Drop here to move up one level'),
                    ),
                  ),
                ),
              ),
            const Divider(height: 1),
            Expanded(child: _libraryGrid(folderId: folder.id, dense: true)),
          ],
        ),
      ),
    );
  }

  /// 按查询、文件夹和废纸篓状态显示空内容说明，不把尚未载入当作资料丢失。
  Widget _emptyLibraryState({bool inFolder = false}) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final bool isMarkdown = _librarySection == 'markdown';
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              _librarySection == 'trash'
                  ? Icons.delete_outline_rounded
                  : isMarkdown
                  ? Icons.edit_note_rounded
                  : Icons.auto_stories_outlined,
              size: 66,
              color: colors.outline,
            ),
            const SizedBox(height: 16),
            Text(
              tr(
                _searchInput.text.trim().isNotEmpty
                    ? '没有找到匹配的文稿'
                    : inFolder
                    ? tr(
                        '文件夹是空的\n拖入文稿或点击上方“+”新建',
                        'This folder is empty\nDrag in a document or use + to create one',
                      )
                    : _librarySection == 'trash'
                    ? '废纸篓是空的'
                    : isMarkdown
                    ? '还没有 Markdown 文档\n点击上方按钮新建或打开'
                    : '这里还没有文稿',
              ),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colors.onSurfaceVariant,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (!inFolder &&
                _librarySection == 'documents' &&
                _searchInput.text.trim().isEmpty) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                tr('点右上角“新建”，或直接导入 PDF、图片和笔记文件夹'),
                style: TextStyle(color: colors.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
