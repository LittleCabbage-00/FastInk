part of '../../app/fastink_app.dart';

extension _FastInkOneNoteImport on _FastInkHomeState {
  /// 运行本地 OneNote 批量转换，按源分区组建立手写文件夹与章节，保留警告和源副本，完成后登记转换文稿。
  Future<void> _importOneNoteFiles({List<File>? selectedFiles}) async {
    if (_libraryBusy || _rejectConcurrentHeavyJob()) return;
    final files = selectedFiles ?? await _repository.pickOneNoteFiles();
    if (!mounted || files.isEmpty) return;
    final parent = _folderForScope(_activeFolderId, LibraryScope.notes);
    _updateState(() => _libraryBusy = true);
    var imported = 0;
    final warnings = <String>[];
    try {
      for (final file in files) {
        final batch = await _repository.importOneNote(
          file,
          onProgress: _setImportProgress,
        );
        warnings.addAll(batch.warnings);
        final folderIds = <String, String>{};
        final package = file.path.toLowerCase().endsWith('.onepkg');
        String? root = parent;
        if (package) {
          final name = file.uri.pathSegments.last.replaceFirst(
            RegExp(r'\.onepkg$', caseSensitive: false),
            '',
          );
          final folder = _libraryRepository.newFolder(
            name,
            parentId: parent,
            scope: LibraryScope.notes,
          );
          _library = LibraryState(
            documents: _library.documents,
            folders: [..._library.folders, folder],
          );
          root = folder.id;
        }
        for (final item in batch.documents) {
          String? destination = root;
          var path = '';
          for (final group in item.groups) {
            path += '/$group';
            var id = folderIds[path];
            if (id == null) {
              final folder = _libraryRepository.newFolder(
                group,
                parentId: destination,
                scope: LibraryScope.notes,
              );
              _library = LibraryState(
                documents: _library.documents,
                folders: [..._library.folders, folder],
              );
              id = folder.id;
              folderIds[path] = id;
            }
            destination = id;
          }
          await _rememberDocument(
            item.document,
            folderId: destination,
            initialPageTitles: item.pageTitles,
          );
          imported++;
        }
      }
      if (mounted) {
        _updateState(
          () => _doc.status = tr(
            '已导入 $imported 个可编辑 OneNote 分区',
            'Imported $imported editable OneNote sections',
          ),
        );
        if (warnings.isNotEmpty) {
          await showDialog<void>(
            context: context,
            animationStyle: appMotionStyle(context),
            builder: (context) => AlertDialog(
              title: Text(
                tr(
                  'OneNote 导入完成，部分格式需要检查',
                  'OneNote imported; review some formatting',
                ),
              ),
              content: SizedBox(
                width: 480,
                height: 240,
                child: SingleChildScrollView(
                  child: SelectableText(
                    '${tr('文字、图片与成功解析的笔迹可继续编辑。原文件与详细报告已保存在资料库的 imports 目录。', 'Text, images and decoded ink remain editable. Original files and detailed reports are saved under imports in your library.')}\n\n${warnings.take(20).join('\n')}',
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(tr('知道了', 'OK')),
                ),
              ],
            ),
          );
        }
      }
    } catch (error) {
      if (mounted) {
        final message = tr(
          'OneNote 导入失败：$error',
          'OneNote import failed: $error',
        );
        _updateState(() => _doc.status = message);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) _updateState(() => _libraryBusy = false);
    }
  }
}
