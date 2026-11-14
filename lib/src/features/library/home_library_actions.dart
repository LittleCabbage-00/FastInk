part of '../../app/fastink_app.dart';

extension _FastInkLibraryActions on _FastInkHomeState {
  /// 在当前手写或 Markdown 内容域创建文件夹，校验名称并保留当前父目录关系。
  Future<void> _createFolder() async {
    final scope = _libraryScope;
    final parentId = _activeFolderId;
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      animationStyle: appMotionStyle(context),
      builder: (dialogContext) => AlertDialog(
        title: Text(tr('新建文件夹')),
        content: TextField(
          key: const ValueKey('library-folder-name'),
          controller: controller,
          autofocus: true,
          onSubmitted: (value) => Navigator.pop(dialogContext, value),
          decoration: InputDecoration(
            labelText: tr('文件夹名称'),
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(tr('取消')),
          ),
          FilledButton(
            key: const ValueKey('library-create-folder'),
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: Text(tr('创建')),
          ),
        ],
      ),
    );
    // 等对话框退出动画完成后再释放控制器。
    unawaited(
      Future<void>.delayed(
        const Duration(milliseconds: 300),
        controller.dispose,
      ),
    );
    if (!mounted || name == null || name.trim().isEmpty) return;
    _updateState(
      () => _library = LibraryState(
        documents: _library.documents,
        folders: [
          ..._library.folders,
          _libraryRepository.newFolder(
            name.trim(),
            parentId: _folderForScope(parentId, scope),
            scope: scope,
          ),
        ],
      ),
    );
    await _saveLibrary();
  }

  /// 展示同一内容域的目标目录选择，确认后只修改文稿文件夹归属并保存索引。
  Future<void> _moveDocumentToFolder(LibraryDocument item) async {
    final result = await showDialog<String>(
      context: context,
      animationStyle: appMotionStyle(context),
      builder: (dialogContext) => SimpleDialog(
        title: Text(tr('移动文稿到')),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogContext, '__root__'),
            child: ListTile(
              leading: const Icon(Icons.home_outlined),
              title: Text(
                item.scope == LibraryScope.markdown
                    ? 'Markdown'
                    : tr('文稿（根目录）'),
              ),
            ),
          ),
          for (final folder in _orderedFolders(item.scope))
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, folder.id),
              child: Padding(
                padding: EdgeInsets.only(left: _folderDepth(folder) * 18.0),
                child: ListTile(
                  leading: Icon(
                    Icons.folder_rounded,
                    color: Color(folder.colorValue),
                  ),
                  title: Text(folder.name),
                ),
              ),
            ),
        ],
      ),
    );
    if (!mounted || result == null) return;
    await _moveLibraryDocument(item.id, result == '__root__' ? null : result);
  }

  /// 按父子层级排列指定内容域的合法文件夹，用于目标选择和缩进显示。
  List<LibraryFolder> _orderedFolders(LibraryScope scope) {
    final List<LibraryFolder> result = <LibraryFolder>[];
    final seen = <String>{};
    // 递归收集指定父目录的子目录，保持层级显示次序并防止重复遍历。
    void addChildren(String? parentId) {
      final List<LibraryFolder> children =
          _library.folders
              .where(
                (folder) =>
                    !folder.trashed &&
                    folder.scope == scope &&
                    folder.parentId == parentId,
              )
              .toList()
            ..sort((a, b) => a.name.compareTo(b.name));
      for (final LibraryFolder folder in children) {
        if (!seen.add(folder.id)) continue;
        result.add(folder);
        addChildren(folder.id);
      }
    }

    addChildren(null);
    return result;
  }

  /// 计算文件夹的有效父链深度，用于缩进，缺失父项或循环引用不能无限遍历。
  int _folderDepth(LibraryFolder folder) {
    int depth = 0;
    String? parentId = folder.parentId;
    final Set<String> seen = <String>{folder.id};
    while (parentId != null && seen.add(parentId)) {
      final LibraryFolder? parent = _library.folders
          .where((item) => item.id == parentId)
          .firstOrNull;
      if (parent == null) break;
      depth++;
      parentId = parent.parentId;
    }
    return depth;
  }

  /// 将资料库当前展开目录切到有效父目录，顶层父目录为空时返回根视图。
  void _openParentFolder() {
    final LibraryFolder? current = _library.folders
        .where((folder) => folder.id == _activeFolderId)
        .firstOrNull;
    _updateState(() => _activeFolderId = current?.parentId);
  }

  /// 确认新的文件夹名称后更新索引，稳定编号与内部文稿归属不变。
  Future<void> _renameFolder(LibraryFolder folder) async {
    final TextEditingController controller = TextEditingController(
      text: folder.name,
    );
    final String? value = await showDialog<String>(
      context: context,
      animationStyle: appMotionStyle(context),
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(tr('重命名文件夹')),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 80,
          onSubmitted: (value) => Navigator.pop(dialogContext, value),
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
    unawaited(
      Future<void>.delayed(
        const Duration(milliseconds: 300),
        controller.dispose,
      ),
    );
    if (value == null || value.trim().isEmpty) return;
    _library = LibraryState(
      documents: _library.documents,
      folders: _library.folders
          .map(
            (item) =>
                item.id == folder.id ? item.copyWith(name: value.trim()) : item,
          )
          .toList(),
    );
    if (mounted) _updateState(() {});
    await _saveLibrary();
  }

  /// 修改文件夹显示色并持久化，不重写文稿页面或底图。
  Future<void> _changeFolderColor(LibraryFolder folder) async {
    const List<Color> colors = <Color>[
      Color(0xff5965df),
      Color(0xff7e57c2),
      Color(0xffec407a),
      Color(0xffef5350),
      Color(0xffff8f00),
      Color(0xff43a047),
      Color(0xff00897b),
      Color(0xff039be5),
      Color(0xff607d8b),
    ];
    final Color? selected = await showDialog<Color>(
      context: context,
      animationStyle: appMotionStyle(context),
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(tr('文件夹颜色')),
        content: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: colors
              .map(
                (color) => InkWell(
                  borderRadius: BorderRadius.circular(30),
                  onTap: () => Navigator.pop(dialogContext, color),
                  child: CircleAvatar(backgroundColor: color, radius: 22),
                ),
              )
              .toList(),
        ),
      ),
    );
    if (selected == null) return;
    _library = LibraryState(
      documents: _library.documents,
      folders: _library.folders
          .map(
            (item) => item.id == folder.id
                ? item.copyWith(colorValue: selected.toARGB32())
                : item,
          )
          .toList(),
    );
    if (mounted) _updateState(() {});
    await _saveLibrary();
  }

  /// 按现有删除规则处理文件夹及其层级归属，确认前不修改资料库索引。
  Future<void> _deleteFolder(LibraryFolder folder) async {
    final bool confirmed =
        await showDialog<bool>(
          context: context,
          animationStyle: appMotionStyle(context),
          builder: (BuildContext dialogContext) => AlertDialog(
            title: Text(tr('删除文件夹？')),
            content: Text(tr('文件夹内的文稿和子文件夹会移到上一级，不会被删除。')),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(tr('取消')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(tr('删除文件夹')),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    _library = LibraryState(
      documents: _library.documents.map((item) {
        if (item.folderId != folder.id) return item;
        return item.copyWith(
          folderId: folder.parentId,
          clearFolder: folder.parentId == null,
        );
      }).toList(),
      folders: _library.folders
          .where((item) => item.id != folder.id)
          .map(
            (item) => item.parentId == folder.id
                ? item.copyWith(
                    parentId: folder.parentId,
                    clearParent: folder.parentId == null,
                  )
                : item,
          )
          .toList(),
    );
    if (_activeFolderId == folder.id) _activeFolderId = folder.parentId;
    if (mounted) {
      _updateState(
        () => _doc.status = tr(
          '文件夹已删除，内容已移到上一级',
          'Folder deleted; its contents were moved up one level',
        ),
      );
    }
    await _saveLibrary();
  }
}
