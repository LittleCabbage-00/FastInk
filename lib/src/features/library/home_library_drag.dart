part of '../../app/fastink_app.dart';

extension _FastInkLibraryDrag on _FastInkHomeState {
  /// 校验目标目录是否属于指定内容域且有效，非法/缺失目标返回空归属。
  String? _folderForScope(String? id, LibraryScope scope) => _library.folders
      .where((f) => f.id == id && f.scope == scope && !f.trashed)
      .firstOrNull
      ?.id;

  /// 检查文稿与目标目录是否满足移动条件，排除忙碌、废纸篓、跨域和无变化操作。
  bool _canMoveLibraryDocument(String id, String? folderId) {
    if (_libraryBusy) return false;
    final doc = _library.documents.where((d) => d.id == id).firstOrNull;
    if (doc == null || doc.trashed || doc.folderId == folderId) return false;
    if (doc.scope != _libraryScope) return false;
    return folderId == null || _folderForScope(folderId, doc.scope) != null;
  }

  /// 乐观更新索引归属并保存，保存失败恢复原快照，目录移动不复制正文大文件。
  Future<void> _moveLibraryDocument(String id, String? folderId) async {
    if (!_canMoveLibraryDocument(id, folderId)) return;
    final previous = _library;
    final doc = _library.documents.firstWhere((d) => d.id == id);
    final updated = LibraryState(
      folders: _library.folders,
      documents: [
        for (final item in _library.documents)
          item.id == id
              ? item.copyWith(folderId: folderId, clearFolder: folderId == null)
              : item,
      ],
    );
    _updateState(() {
      _library = updated;
      _doc.status = tr('已移动“${doc.title}”', 'Moved “${doc.title}”');
    });
    try {
      await _saveLibrary();
    } catch (error) {
      if (!mounted) return;
      _updateState(() {
        if (identical(_library, updated)) _library = previous;
        _doc.status = tr('移动保存失败：$error', 'Could not save move: $error');
      });
    }
  }

  /// 创建统一拖放目标，按 canMove 判定接受文稿，并在悬停时显示目标反馈。
  Widget _libraryDropZone({
    required String? folderId,
    required Widget child,
    required Key targetKey,
  }) => DragTarget<String>(
    key: targetKey,
    onWillAcceptWithDetails: (details) =>
        _canMoveLibraryDocument(details.data, folderId),
    onAcceptWithDetails: (details) =>
        unawaited(_moveLibraryDocument(details.data, folderId)),
    builder: (context, candidates, rejected) {
      final colors = Theme.of(context).colorScheme;
      return DecoratedBox(
        decoration: BoxDecoration(
          color: candidates.isEmpty
              ? Colors.transparent
              : colors.primary.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            width: 2,
            color: candidates.isEmpty ? Colors.transparent : colors.primary,
          ),
        ),
        child: child,
      );
    },
  );
}
