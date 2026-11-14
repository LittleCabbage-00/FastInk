part of '../../app/fastink_app.dart';

extension _FastInkPageMutations on _FastInkHomeState {
  /// **本文稿**正在跑后台任务（导出、换纸）时拒绝结构性改动：增删页、
  /// 旋转、排序。
  ///
  /// 导出是逐页读盘生成的，中途改页面会让结果既不是开始时的样子、也不是
  /// 结束时的样子。要"以点导出按钮那一刻的状态导出"，就只能整段锁住。
  /// 判据是 [_doc.busy]（跟着文稿走）：别的文稿在导出不该拦住本文稿。
  /// 返回 true 表示本次操作已被拒绝。
  bool _rejectStructuralChange() {
    if (!_doc.busy) return false;
    _updateState(
      () => _doc.status = tr(
        '本文稿正在后台处理，完成后才能修改页面',
        'This document is being processed; page edits resume when it finishes',
      ),
    );
    return true;
  }

  /// 重型后台任务（导出、换纸、旋转）互斥：同一时刻全局只跑一个。
  ///
  /// 与 [_rejectStructuralChange] 的分工：那个管"本文稿正在被处理"，这个管
  /// "已经有一个重活在跑，先别开新的"。重活并行会互相覆盖进度、抢磁盘，
  /// 旋转还会把页面换成新文件，正好被导出的旧路径读到。
  /// 返回 true 表示本次操作已被拒绝。
  bool _rejectConcurrentHeavyJob() {
    if (!_doc.anyBusy && !_libraryBusy) return false;
    _updateState(
      () => _doc.status = tr(
        '后台任务正在进行，请稍后再试',
        'A background task is running; try again in a moment',
      ),
    );
    return true;
  }

  /// 选择图片并收集为当前文稿资源，创建可编辑图片对象；页面输入被锁时拒绝插入。
  Future<void> _insertImagesOnCurrentPage() async {
    final NoteDocument? document = _doc.document;
    if (document == null || _doc.pageImage == null || _doc.readOnly) return;
    final List<File> images = await _repository.pickEmbeddedImageFiles(
      initialDirectory: document.directory,
    );
    if (images.isEmpty) return;
    // 文件选择器是异步的，期间可能正好在换页或旋转：此刻 _ink 里装的不是
    // 用户看到的那页，图片会加错页。等状态稳定后重新触发即可。
    if (_doc.inkInputBlocked) {
      _updateState(
        () => _doc.status = tr(
          '页面正在更新，请稍后再插入图片',
          'The page is being updated; try inserting again in a moment',
        ),
      );
      return;
    }
    _updateState(() => _doc.status = tr('正在导入图片…', 'Importing images…'));
    try {
      for (final File image in images) {
        final ({int width, int height}) dimensions =
            await readImageFileDimensions(image.path);
        final String asset = await _repository.importEmbeddedImage(
          document,
          image,
        );
        _ink.addImage(
          asset,
          dimensions.width / dimensions.height,
          Size(
            _doc.pageImage!.width.toDouble(),
            _doc.pageImage!.height.toDouble(),
          ),
        );
      }
      await _saveNow();
      if (mounted) {
        _selectTool(InkTool.lasso);
        _updateState(
          () => _doc.status = tr('图片已放入当前页', 'Images placed on page'),
        );
      }
    } catch (error) {
      if (mounted) {
        _updateState(
          () => _doc.status = tr(
            '导入图片失败：$error',
            'Could not import image: $error',
          ),
        );
      }
    }
  }

  /// 在 afterIndex 后创建页面，模板默认沿用当前页并通过统一结构更新流程激活。
  Future<void> _addPage({required int afterIndex}) async {
    final NoteDocument? document = _doc.document;
    if (document == null || _rejectStructuralChange()) return;
    final _PaperDialogResult? result = await _showPaperDialog(
      creating: false,
      addingPage: true,
    );
    if (result == null) return;
    _updateState(() => _doc.status = tr('正在添加页面…', 'Adding page…'));
    try {
      final int insertIndex = (afterIndex + 1).clamp(0, document.pages.length);
      final NoteDocument updated = await _repository.addBlankPage(
        document,
        insertIndex: insertIndex,
        template: result.template,
      );
      _rememberPageAspectRatio(
        updated.pages[insertIndex].path,
        result.template.aspectRatio,
      );
      await _activateUpdatedDocument(document, updated, insertIndex);
      if (mounted) {
        _updateState(
          () => _doc.status = tr(
            '已添加第 ${insertIndex + 1} 页',
            'Added page ${insertIndex + 1}',
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        _updateState(
          () => _doc.status = tr('添加页面失败：$error', 'Could not add page: $error'),
        );
      }
    }
  }

  /// 把所选图片作为新页面插入文稿，保存当前笔迹后更新索引、书签和章节映射。
  Future<void> _insertImagePages() async {
    final NoteDocument? document = _doc.document;
    if (document == null || _rejectStructuralChange()) return;
    final List<File> images = await _repository.pickImageFiles(
      initialDirectory: document.directory,
    );
    if (images.isEmpty) return;
    if (!await _saveNow() || !mounted) return;
    _updateState(
      () => _doc.status = tr(
        '正在插入 ${images.length} 张图片…',
        'Inserting ${images.length} images…',
      ),
    );
    try {
      final int insertIndex = (_doc.pageIndex + 1).clamp(
        0,
        document.pages.length,
      );
      final NoteDocument updated = await _repository.insertImagePages(
        document,
        insertIndex,
        images,
      );
      final String insertedPath = updated.pages[insertIndex].path;
      _rememberPageAspectRatio(
        insertedPath,
        await _samplePageAspectRatio(insertedPath),
      );
      await _activateUpdatedDocument(document, updated, insertIndex);
      if (mounted) {
        _updateState(() => _doc.status = tr('图片页已插入', 'Image pages inserted'));
      }
    } catch (error) {
      if (mounted) {
        _updateState(
          () => _doc.status = tr(
            '插入图片失败：$error',
            'Could not insert images: $error',
          ),
        );
      }
    }
  }

  /// 复制指定页的底图、笔迹及页面设置，生成新页面身份再重建文稿索引。
  Future<void> _duplicatePage(int pageIndex) async {
    final NoteDocument? document = _doc.document;
    if (document == null || _rejectStructuralChange()) return;
    if (!await _saveNow() || !mounted) return;
    _updateState(() => _doc.status = tr('正在复制页面…', 'Duplicating page…'));
    try {
      final NoteDocument updated = await _repository.duplicatePage(
        document,
        pageIndex,
        legacyWidthReference: _legacyInkWidthReference(pageIndex),
      );
      final double? sourceRatio =
          _pageAspectRatioCache[document.pages[pageIndex].path];
      if (sourceRatio != null) {
        _rememberPageAspectRatio(
          updated.pages[pageIndex + 1].path,
          sourceRatio,
        );
      }
      await _activateUpdatedDocument(document, updated, pageIndex + 1);
      if (mounted) {
        _updateState(() => _doc.status = tr('页面已复制', 'Page duplicated'));
      }
    } catch (error) {
      if (mounted) {
        _updateState(
          () => _doc.status = tr(
            '复制页面失败：$error',
            'Could not duplicate page: $error',
          ),
        );
      }
    }
  }

  /// 将所选页设置为资料库封面引用，刷新相应预览记录，不改变正文页序。
  Future<void> _setPageAsCover(int pageIndex) async {
    final NoteDocument? document = _doc.document;
    if (document == null || _rejectStructuralChange()) return;
    if (pageIndex == 0) {
      _updateState(
        () => _doc.status = tr('当前页已经是封面', 'This page is already the cover'),
      );
      return;
    }
    if (!await _saveNow() || !mounted) return;
    _updateState(() => _doc.status = tr('正在更新封面…', 'Updating cover…'));
    try {
      final NoteDocument updated = await _repository.reorderPages(
        document,
        pageIndex,
        0,
      );
      await _activateUpdatedDocument(document, updated, 0);
      if (mounted) {
        _updateState(
          () => _doc.status = tr('已将当前页设为封面', 'Current page set as cover'),
        );
      }
    } catch (error) {
      if (mounted) {
        _updateState(
          () =>
              _doc.status = tr('设置封面失败：$error', 'Could not set cover: $error'),
        );
      }
    }
  }

  /// 旋转页面底图并同步变换笔迹、文字和图片几何；持有文稿锁，失败时恢复可操作状态。
  Future<void> _rotatePage(int pageIndex, {bool clockwise = true}) async {
    final NoteDocument? document = _doc.document;
    if (document == null ||
        _rejectStructuralChange() ||
        _rejectConcurrentHeavyJob()) {
      return;
    }
    final int sourceOriginal = document.pages[pageIndex].originalPage;
    // 先占住锁和重活名额，再刷盘：刷盘也要 await，提前置位才没有重入窗口。
    // 旋转会把该页笔迹重写成新坐标，窗口里的落笔还在旧坐标系里，锁住；
    // 同时它会把页面换成新文件，中途不能让导出拿着旧路径开跑。
    // 两者都按文稿记账：这期间切到别的文稿照常能写、能增删页。
    _doc.lockInk(document.id);
    _doc.busyDocumentId = document.id;
    _updateState(() => _doc.status = tr('正在旋转页面…', 'Rotating page…'));
    try {
      if (!await _saveNow() || !mounted) return;
      final String sourcePath = document.pages[pageIndex].path;
      final double? sourceRatio = _pageAspectRatioCache[sourcePath];
      final NoteDocument updated = await _repository.rotatePage(
        document,
        pageIndex,
        clockwise: clockwise,
        legacyWidthReference: _legacyInkWidthReference(pageIndex),
      );
      // 旋转目标就是内存里这页时，内存那份已是旧朝向的过期货：放弃归属，
      // 免得加载替换前的任何保存把旧朝向写回去（保存键还是 originalPage）。
      // 旋转别的页时归属照旧。
      if (_doc.inkPage?.originalPage == sourceOriginal) {
        _doc.inkDocument = null;
        _doc.inkPage = null;
        _doc.dirty = false;
        _doc.saveTimer?.cancel();
      }
      final String rotatedPath = updated.pages[pageIndex].path;
      if (sourceRatio != null && sourceRatio > 0) {
        _rememberPageAspectRatio(rotatedPath, 1 / sourceRatio);
      } else {
        _rememberPageAspectRatio(
          rotatedPath,
          await _samplePageAspectRatio(rotatedPath),
        );
      }
      await _activateUpdatedDocument(document, updated, pageIndex);
      if (mounted) {
        _updateState(() => _doc.status = tr('页面已旋转', 'Page rotated'));
      }
    } catch (error) {
      if (mounted) {
        _updateState(
          () => _doc.status = tr(
            '旋转页面失败：$error',
            'Could not rotate page: $error',
          ),
        );
      }
    } finally {
      _doc.unlockInk(document.id);
      if (_doc.busyDocumentId == document.id) _doc.busyDocumentId = null;
    }
  }

  /// 移除指定页并更新页序映射，至少保留一页；不会把此结构操作冒充画布笔迹撤销。
  Future<void> _deletePage(int pageIndex) async {
    final NoteDocument? document = _doc.document;
    if (document == null || _rejectStructuralChange()) return;
    if (document.pages.length <= 1) {
      _updateState(
        () => _doc.status = tr(
          '文稿至少需要保留一页',
          'A document must keep at least one page',
        ),
      );
      return;
    }
    final bool confirmed =
        await showDialog<bool>(
          context: context,
          animationStyle: appMotionStyle(context),
          builder: (BuildContext dialogContext) => AlertDialog(
            title: Text(
              tr('删除第 ${pageIndex + 1} 页？', 'Delete page ${pageIndex + 1}?'),
            ),
            content: Text(
              tr(
                '该页背景和 FastInk 笔迹将从本文稿中移除。',
                'The page background and FastInk ink will be removed from this document.',
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(tr('取消')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(tr('删除')),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    if (!await _saveNow() || !mounted) return;
    try {
      final NoteDocument updated = await _repository.deletePage(
        document,
        pageIndex,
      );
      await _activateUpdatedDocument(
        document,
        updated,
        math.min(pageIndex, updated.pages.length - 1),
      );
      if (mounted) {
        _updateState(() => _doc.status = tr('页面已删除', 'Page deleted'));
      }
    } catch (error) {
      if (mounted) {
        _updateState(
          () => _doc.status = tr(
            '删除页面失败：$error',
            'Could not delete page: $error',
          ),
        );
      }
    }
  }

  /// 按拖动旧/新索引重排页面并重新映射当前位置、书签与章节标题。
  Future<void> _reorderPages(int oldIndex, int newIndex) async {
    final NoteDocument? document = _doc.document;
    if (document == null || oldIndex == newIndex) return;
    if (_rejectStructuralChange()) return;
    if (!await _saveNow() || !mounted) return;
    final int currentOriginal = document.pages[_doc.pageIndex].originalPage;
    try {
      final NoteDocument updated = await _repository.reorderPages(
        document,
        oldIndex,
        newIndex,
      );
      final int targetIndex = updated.pages.indexWhere(
        (page) => page.originalPage == currentOriginal,
      );
      await _activateUpdatedDocument(document, updated, targetIndex);
      if (mounted) {
        _updateState(() => _doc.status = tr('页面顺序已保存', 'Page order saved'));
      }
    } catch (error) {
      if (mounted) {
        _updateState(
          () => _doc.status = tr(
            '页面排序失败：$error',
            'Could not reorder pages: $error',
          ),
        );
      }
    }
  }
}
