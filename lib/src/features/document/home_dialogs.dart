part of '../../app/fastink_app.dart';

extension _FastInkDialogs on _FastInkHomeState {
  /// 打开纸张/封面模板选择器，返回确认的模板结果；取消返回 null，调用方决定是否生成页面。
  Future<_PaperDialogResult?> _showPaperDialog({
    required bool creating,
    bool addingPage = false,
  }) async {
    PaperTemplate initial = const PaperTemplate();
    final NoteDocument? active = _doc.document;
    if (!creating && active != null) {
      initial =
          await _repository.loadPaperTemplate(active.pages[_doc.pageIndex]) ??
          initial;
      if (!mounted) {
        return null;
      }
    }
    final selection = await showDialog<PaperTemplateSelection>(
      context: context,
      animationStyle: appMotionStyle(context),
      builder: (_) => PaperTemplateDialog(
        initialTemplate: initial,
        library: TemplateLibrary(_dataRoot),
        creating: creating,
        addingPage: addingPage,
        allowAllPages:
            !creating &&
            !addingPage &&
            active != null &&
            _repository.isEditableNotebook(active),
      ),
    );
    final result = selection == null
        ? null
        : _PaperDialogResult(
            title: selection.title,
            template: selection.template,
            allPages: selection.allPages,
            cover: selection.cover,
          );
    return result;
  }

  /// 检查当前页是否允许换纸，先收集模板结果再更新页面并重新装载；导入原页与自建页权限不同。
  Future<void> _changePaperTemplate() async {
    final NoteDocument? document = _doc.document;
    if (document == null) return;
    final pageIndex = _doc.pageIndex;
    final pageToken = _doc.pageToken;
    // 换纸要重写整份文稿的页面图，本文稿正在导出时改纸张等于让导出读到
    // 一半旧纸一半新纸；别的文稿在忙则不让再开一个重活。
    if (_rejectStructuralChange() || _rejectConcurrentHeavyJob()) return;
    if (!_repository.canChangePaperTemplate(document, pageIndex)) {
      await showDialog<void>(
        context: context,
        animationStyle: appMotionStyle(context),
        builder: (BuildContext dialogContext) => AlertDialog(
          title: Text(tr('导入页面保留原始尺寸')),
          content: Text(
            tr(
              '这份文稿来自 PDF、图片或外部笔记文件夹。为避免覆盖原内容，FastInk 不会直接替换它的纸张；新建笔记可自由更改模板、颜色、尺寸和方向。',
              'This document came from a PDF, images, or an external note folder. FastInk keeps imported pages intact; newly created notes can freely change paper template, color, size, and orientation.',
            ),
          ),
          actions: <Widget>[
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(tr('知道了')),
            ),
          ],
        ),
      );
      return;
    }
    final _PaperDialogResult? result = await _showPaperDialog(creating: false);
    if (result == null ||
        !mounted ||
        _doc.document?.id != document.id ||
        _doc.pageToken != pageToken ||
        _rejectStructuralChange() ||
        _rejectConcurrentHeavyJob()) {
      return;
    }
    // 只锁定页面结构。底图和笔迹分开，换纸无需刷写或重载当前笔迹。
    final String documentId = document.id;
    _doc.busyDocumentId = documentId;
    _updateState(
      () => _doc.status = tr('正在更换纸张模板…', 'Changing paper template…'),
    );
    final changed = <String>{};
    try {
      final Iterable<int> indexes = result.allPages
          ? List<int>.generate(document.pages.length, (int index) => index)
          : <int>[pageIndex];
      // 即使整本操作部分失败，已经写好的页面也要立即使用新版本。
      try {
        await _repository.applyPaperTemplate(
          document,
          indexes,
          result.template,
          onPageChanged: (page) {
            final path = page.path;
            changed.add(path);
            _paperImageRevisions.update(
              path,
              (revision) => revision + 1,
              ifAbsent: () => 1,
            );
            if (result.template.backgroundAsset == null) {
              _paperAppearanceCache[path] = (
                dark: _paperColorIsDark(result.template.color),
                hasTemplate: true,
              );
            } else {
              _paperAppearanceCache.remove(path);
            }
            _rememberPageAspectRatio(path, result.template.aspectRatio);
          },
        );
      } finally {
        if (mounted && _doc.document?.id == documentId) {
          final active = _doc.inkPage;
          if (active != null &&
              _doc.inkDocument?.id == documentId &&
              changed.contains(active.path) &&
              !_doc.pageLoading) {
            if (!_paperAppearanceCache.containsKey(active.path)) {
              await _warmPageAppearances(document, [
                _doc.pageIndex,
              ], notify: false);
            }
            if (mounted && identical(_doc.inkPage, active)) {
              await _refreshPageDisplayResolution(paperChanged: true);
            }
          }
        }
      }
      if (mounted && _doc.document?.id == documentId) {
        _updateState(
          () => _doc.status = result.allPages
              ? tr('已更换整本文稿纸张', 'Paper changed throughout the document')
              : tr('已更换当前页纸张', 'Current page paper changed'),
        );
      }
    } catch (error) {
      if (mounted && _doc.document?.id == documentId) {
        _updateState(
          () => _doc.status = tr(
            '更换纸张失败：$error',
            'Could not change paper: $error',
          ),
        );
      }
    } finally {
      // 按 id 释放：期间可能已经切到别的文稿。
      if (_doc.busyDocumentId == documentId) _doc.busyDocumentId = null;
      if (mounted) _updateState(() {});
    }
  }
}
