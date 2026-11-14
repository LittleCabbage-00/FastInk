part of '../../app/fastink_app.dart';

/// 资料库、配置位置和废纸篓相关操作。
///
/// 这里严格区分 FastInk 自己创建的副本和用户的外部源文件；永久删除
/// 只清理应用拥有的数据，不能顺带删除导入前的原文件。
extension _HomeStorageActions on _FastInkHomeState {
  /// 根据 restore 选择创建或恢复可编辑备份，持有资料库忙碌状态并显示进度，恢复目标为新目录。
  Future<void> _backupLibrary({bool restore = false}) async {
    if (_libraryBusy || _doc.anyBusy) return;
    final picker = DirectoryPicker()
      ..title = restore
          ? tr(
              '选择包含 fastink-backup.json 的备份文件夹',
              'Choose a FastInk backup folder',
            )
          : tr('选择备份保存位置', 'Choose a backup location');
    final folder = picker.getDirectory();
    if (folder == null || !mounted) return;
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final target = restore
        ? '${Directory(_dataRoot).parent.path}/FastInk-restored-$stamp'
        : '${folder.path}/FastInk-backup-$stamp';
    _updateState(() {
      _libraryBusy = true;
      _doc.status = tr('正在校验资料库…', 'Checking library…');
    });
    try {
      if (!await _saveNow() || !mounted) return;
      await _saveLibrary();
      // 将备份/恢复阶段文案转发到资料库进度反馈，组件卸载后忽略。
      void progress(String message) {
        if (mounted) _updateState(() => _doc.status = message);
      }

      if (restore) {
        await LibraryBackup.restore(folder.path, target, progress: progress);
        final current = await _settingsRepository.load();
        if (_settings.configStorageLocation == 'document') {
          await SettingsRepository.activateStorage(
            settings: current,
            location: 'document',
            dataRoot: target,
          );
        } else {
          await _settingsRepository.saveDataRoot(target);
        }
        _dataRoot = target;
        // 先前打开的页面不能把旧内容保存到恢复后的资料库。
        _doc.inkDocument = null;
        _doc.inkPage = null;
        _doc.dirty = false;
        _ink.replace(const []);
        _configureRepositories(target);
        _doc.openDocumentIds.clear();
        _pageInkCache.clear();
        _library = await _libraryRepository.load();
      } else {
        await LibraryBackup.create(_dataRoot, target, progress: progress);
      }
      if (mounted) {
        _updateState(
          () => _doc.status =
              '${restore ? tr('恢复完成', 'Restored') : tr('备份完成', 'Backed up')}：$target',
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_doc.status),
            duration: const Duration(seconds: 8),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        _updateState(
          () => _doc.status = tr(
            '备份/恢复失败：$error',
            'Backup/restore failed: $error',
          ),
        );
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_doc.status)));
      }
    } finally {
      if (mounted) _updateState(() => _libraryBusy = false);
    }
  }

  /// 让用户选择新资料库位置，复制并重写内部路径后统一切换仓库，不能只修改一条显示路径。
  Future<void> _chooseStorageLocation() async {
    final DirectoryPicker picker = DirectoryPicker()
      ..title = tr(
        '选择保存位置（将在其中创建 FastInkData）',
        'Choose a location (FastInkData will be created inside it)',
      );
    final Directory? selected = picker.getDirectory();
    if (selected == null) return;
    final String target = selected.path.toLowerCase().endsWith('fastinkdata')
        ? selected.path
        : '${selected.path}/FastInkData';
    if (File(target).absolute.path.toLowerCase() ==
        File(_dataRoot).absolute.path.toLowerCase()) {
      return;
    }
    final bool confirmed =
        await showDialog<bool>(
          context: context,
          animationStyle: appMotionStyle(context),
          builder: (BuildContext dialogContext) => AlertDialog(
            icon: const Icon(Icons.drive_file_move_outline),
            title: Text(tr('迁移整个资料库？', 'Move the entire library?')),
            content: Text(
              tr(
                '文稿、页面、笔迹、书签和分类将复制到：\n$target\n\n迁移校验成功后，新内容会保存到这里。旧位置暂时保留作备份。',
                'Documents, pages, ink, bookmarks, and folders will be copied to:\n$target\n\nAfter verification, new content will be saved there. The old location remains as a backup.',
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(tr('取消')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(tr('开始迁移', 'Start migration')),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    _updateState(() {
      _libraryBusy = true;
      _doc.status = tr('正在迁移并校验资料库…', 'Moving and verifying the library…');
    });
    try {
      // 先把内存中的笔迹和索引落盘，迁移时复制的才是完整快照。
      if (!await _saveNow() || !mounted) return;
      await _saveLibrary();
      await StorageMigration.copyLibrary(
        sourceRoot: _dataRoot,
        destinationRoot: target,
      );
      final LibraryRepository nextLibrary = LibraryRepository(root: target);
      // 目标资料库必须能重新读取，校验成功后才切换运行时仓库。
      // 原目录暂时保留，迁移异常时仍可继续使用。
      final LibraryState loaded = await nextLibrary.load();
      final AppSettings settings = await _settingsRepository.load();
      if (_settings.configStorageLocation == 'document') {
        await SettingsRepository.activateStorage(
          settings: settings,
          location: 'document',
          dataRoot: target,
        );
      } else {
        await _settingsRepository.saveDataRoot(target);
      }
      _dataRoot = target;
      _configureRepositories(target);
      _library = loaded;
      if (mounted) {
        _updateState(
          () => _doc.status = tr('资料库已迁移到 $target', 'Library moved to $target'),
        );
      }
    } catch (error) {
      if (mounted) {
        _updateState(
          () => _doc.status = tr(
            '迁移失败，仍使用原位置：$error',
            'Migration failed; the original location is still in use: $error',
          ),
        );
      }
    } finally {
      if (mounted) _updateState(() => _libraryBusy = false);
    }
  }

  /// 通过系统打开当前资料库目录，不在此方法内搬动文件。
  Future<void> _openStorageLocation() async {
    await Directory(_dataRoot).create(recursive: true);
    await Process.start('explorer.exe', <String>[_dataRoot]);
  }

  /// 按用户选择切换配置存储位置并更新活动仓库，资料库内容目录保持独立。
  Future<void> _setConfigStorageLocation(String location) async {
    if (location == _settings.configStorageLocation || _libraryBusy) return;
    _updateState(() {
      _libraryBusy = true;
      _doc.status = tr('正在切换配置保存位置…', 'Changing the settings location…');
    });
    try {
      // 配置位置切换不移动文稿，只复制 settings.json 并更新位置指针。
      final AppSettings current = await _settingsRepository.load();
      final String target = await SettingsRepository.activateStorage(
        settings: current,
        location: location,
        dataRoot: _dataRoot,
      );
      if (mounted) {
        _updateState(() {
          _settings.configStorageLocation = location;
          _doc.status = tr(
            '配置已保存到 $target',
            'Settings are now saved to $target',
          );
        });
      }
    } catch (error) {
      if (mounted) {
        _updateState(
          () => _doc.status = tr(
            '配置位置切换失败：$error',
            'Could not change the settings location: $error',
          ),
        );
      }
    } finally {
      if (mounted) _updateState(() => _libraryBusy = false);
    }
  }

  /// 通过系统打开实际配置目录，便于查看设置文件。
  Future<void> _openConfigStorageLocation() async {
    final String root = SettingsRepository.activeConfigRoot;
    await Directory(root).create(recursive: true);
    await Process.start('explorer.exe', <String>[root]);
  }

  /// 切换文稿收藏标志并保存索引，不改变所属文件夹或源文件。
  Future<void> _toggleFavorite(LibraryDocument item) async {
    final List<LibraryDocument> documents = _library.documents
        .map(
          (LibraryDocument current) => current.id == item.id
              ? current.copyWith(favorite: !current.favorite)
              : current,
        )
        .toList();
    _updateState(() {
      _library = LibraryState(documents: documents, folders: _library.folders);
    });
    await _saveLibrary();
  }

  /// 切换文稿的废纸篓状态，恢复时保留合法归属，移入不等于立即永久删除。
  Future<void> _setDocumentTrashed(LibraryDocument item, bool trashed) async {
    final List<LibraryDocument> documents = _library.documents
        .map(
          (LibraryDocument current) => current.id == item.id
              ? current.copyWith(trashed: trashed)
              : current,
        )
        .toList();
    _updateState(() {
      _library = LibraryState(documents: documents, folders: _library.folders);
    });
    await _saveLibrary();
  }

  /// 展示不可恢复删除的数量和确认入口，取消返回 false。
  Future<bool> _confirmPermanentDelete({required int count}) async {
    return await showDialog<bool>(
          context: context,
          animationStyle: appMotionStyle(context),
          builder: (BuildContext dialogContext) => AlertDialog(
            icon: const Icon(Icons.delete_forever_outlined),
            title: Text(
              count == 1
                  ? tr('永久删除这份文稿？', 'Delete this document permanently?')
                  : tr('清空废纸篓？', 'Empty the trash?'),
            ),
            content: Text(
              count == 1
                  ? tr(
                      'FastInk 中的文稿和笔迹将永久删除。若它来自外部文件夹，原始页面不会被删除。',
                      'The document and its ink will be permanently deleted from FastInk. Original pages from an external folder will not be deleted.',
                    )
                  : tr(
                      '废纸篓中的 $count 份文稿和笔迹将永久删除，此操作无法撤销。',
                      '$count documents and their ink will be permanently deleted. This cannot be undone.',
                    ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(tr('取消')),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(dialogContext).colorScheme.error,
                  foregroundColor: Theme.of(dialogContext).colorScheme.onError,
                ),
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(tr('永久删除')),
              ),
            ],
          ),
        ) ??
        false;
  }

  /// 确认后删除资料库拥有的文稿内容并更新索引，不能删除外部原始来源。
  Future<void> _deleteDocumentPermanently(LibraryDocument item) async {
    if (!await _confirmPermanentDelete(count: 1)) return;
    _updateState(() {
      _libraryBusy = true;
      _doc.status = tr(
        '正在永久删除 ${item.title}…',
        'Permanently deleting ${item.title}…',
      );
    });
    bool diskError = false;
    try {
      await _repository.deleteDocumentStorage(item.id, item.sourcePath);
    } catch (_) {
      diskError = true;
    }
    // 无论磁盘删除是否成功，都从索引中移除（文件可能已不存在）。
    final List<LibraryDocument> documents = _library.documents
        .where((LibraryDocument current) => current.id != item.id)
        .toList();
    _library = LibraryState(documents: documents, folders: _library.folders);
    await _saveLibrary();
    if (mounted) {
      _updateState(() {
        _doc.status = diskError
            ? tr(
                '磁盘文件删除失败，资料库条目已移除',
                'Could not delete the files. The library entry was removed.',
              )
            : tr('已永久删除 ${item.title}', 'Permanently deleted ${item.title}');
        _libraryBusy = false;
      });
    }
  }

  /// 确认后逐项清理废纸篓索引和属于资料库的存储，报告失败而不删除未授权外部路径。
  Future<void> _emptyTrash() async {
    final List<LibraryDocument> trashed = _library.documents
        .where((LibraryDocument item) => item.trashed)
        .toList();
    if (trashed.isEmpty ||
        !await _confirmPermanentDelete(count: trashed.length)) {
      return;
    }
    _updateState(() {
      _libraryBusy = true;
      _doc.status = tr('正在清空废纸篓…', 'Emptying the trash…');
    });
    int failed = 0;
    for (final LibraryDocument item in trashed) {
      try {
        await _repository.deleteDocumentStorage(item.id, item.sourcePath);
      } catch (_) {
        failed++;
      }
    }
    final Set<String> deletedIds = trashed.map((item) => item.id).toSet();
    _library = LibraryState(
      documents: _library.documents
          .where((LibraryDocument item) => !deletedIds.contains(item.id))
          .toList(),
      folders: _library.folders,
    );
    await _saveLibrary();
    if (mounted) {
      _updateState(() {
        _doc.status = failed > 0
            ? tr(
                '$failed 项磁盘文件删除失败，废纸篓条目已移除',
                'Could not delete $failed item(s) from disk. Trash entries were removed.',
              )
            : tr('废纸篓已清空', 'Trash emptied');
        _libraryBusy = false;
      });
    }
  }

  /// 按当前文稿身份查找有效资料库记录，不存在或没有活动文稿时返回 null。
  LibraryDocument? get _currentLibraryDocument {
    // 文稿编辑状态和首页资料库使用不同模型，通过稳定 id 建立关联。
    final String? id = _doc.document?.id;
    if (id == null) return null;
    return _library.documents
        .where((LibraryDocument item) => item.id == id)
        .firstOrNull;
  }

  /// 确认新标题后更新索引与当前显示状态，稳定文稿身份和页面笔迹不变。
  Future<void> _renameDocument(LibraryDocument item) async {
    final TextEditingController controller = TextEditingController(
      text: item.title,
    );
    final String? entered = await showDialog<String>(
      context: context,
      animationStyle: appMotionStyle(context),
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(tr('重命名文稿')),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 80,
          decoration: InputDecoration(
            labelText: tr('文稿名称', 'Document name'),
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (String value) => Navigator.pop(dialogContext, value),
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
    final String title = entered?.trim() ?? '';
    if (title.isEmpty || title == item.title) return;

    _updateState(() => _doc.status = tr('正在重命名…', 'Renaming…'));
    try {
      final NoteDocument base = _doc.document?.id == item.id
          ? _doc.document!
          : await _repository.indexFromSelectedPath(
              item.sourcePath,
              documentId: item.id,
            );
      final NoteDocument renamed = NoteDocument(
        id: base.id,
        title: title,
        directory: base.directory,
        pages: base.pages,
        initialIndex: base.initialIndex,
      );
      await _repository.saveDocumentManifest(renamed);
      _library = LibraryState(
        documents: _library.documents
            .map(
              (LibraryDocument current) => current.id == item.id
                  ? current.copyWith(title: title)
                  : current,
            )
            .toList(),
        folders: _library.folders,
      );
      if (_doc.document?.id == item.id) _doc.document = renamed;
      await _saveLibrary();
      if (mounted) {
        _updateState(
          () => _doc.status = tr('已重命名为“$title”', 'Renamed to “$title”'),
        );
      }
    } catch (error) {
      if (mounted) {
        _updateState(
          () => _doc.status = tr('重命名失败：$error', 'Rename failed: $error'),
        );
      }
    }
  }
}
