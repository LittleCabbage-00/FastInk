part of '../../app/fastink_app.dart';

extension _FastInkCanvasShortcuts on _FastInkHomeState {
  /// 在画布和文档工具栏共用编辑按键。文字输入保留自己的剪贴板和历史。
  KeyEventResult _handleCanvasEditKey(KeyEvent event) {
    final action = canvasEditShortcut(event);
    if (action == null || _doc.document == null || _inlineTextPoint != null) {
      return KeyEventResult.ignored;
    }
    final focused = FocusManager.instance.primaryFocus?.context;
    if (focused?.findAncestorStateOfType<EditableTextState>() != null) {
      return KeyEventResult.ignored;
    }
    final canEdit = !_doc.readOnly && !_doc.inkInputBlocked;
    switch (action) {
      case CanvasEditShortcut.undo when canEdit:
        _ink.undo();
      case CanvasEditShortcut.redo when canEdit:
        _ink.redo();
      case CanvasEditShortcut.copy
          when _ink.hasSelection && !_doc.inkInputBlocked:
        _copyInkSelection();
      case CanvasEditShortcut.cut when canEdit && _ink.hasSelection:
        _copyInkSelection(cut: true);
      case CanvasEditShortcut.paste when canEdit:
        unawaited(_pasteClipboard());
      case CanvasEditShortcut.duplicate when canEdit && _ink.hasSelection:
        _ink.duplicateSelection();
      case CanvasEditShortcut.delete when canEdit && _ink.hasSelection:
        _ink.deleteSelection();
      case CanvasEditShortcut.escape when _ink.hasSelection:
        _ink.clearSelection();
      case CanvasEditShortcut.save when canEdit:
        unawaited(_saveNow());
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  /// 分派画布快捷键，区分修饰键、内容编辑和导航；文本输入交给输入框自身处理，修改笔迹前检查锁状态。
  KeyEventResult _handleCanvasKey(FocusNode node, KeyEvent event) {
    final bool isShift =
        event.logicalKey == LogicalKeyboardKey.shift ||
        event.logicalKey == LogicalKeyboardKey.shiftLeft ||
        event.logicalKey == LogicalKeyboardKey.shiftRight;
    final bool isControl =
        event.logicalKey == LogicalKeyboardKey.control ||
        event.logicalKey == LogicalKeyboardKey.controlLeft ||
        event.logicalKey == LogicalKeyboardKey.controlRight;
    if (isShift || isControl) {
      // 修饰键本身不触发界面重建；组合键在实际事件发生时读取硬件状态。
      return KeyEventResult.ignored;
    }
    if (event is! KeyDownEvent || _inlineTextPoint != null) {
      // 文本框获得焦点后，快捷键由文本编辑器处理。
      return KeyEventResult.ignored;
    }
    final LogicalKeyboardKey key = event.logicalKey;
    final bool control = HardwareKeyboard.instance.isControlPressed;
    final bool shift = HardwareKeyboard.instance.isShiftPressed;
    final edit = _handleCanvasEditKey(event);
    if (edit == KeyEventResult.handled) return edit;
    if (control && key == LogicalKeyboardKey.keyF) {
      unawaited(_showDocumentSearch());
      return KeyEventResult.handled;
    }
    if (!control && key == LogicalKeyboardKey.keyL) {
      _selectTool(InkTool.laser);
      return KeyEventResult.handled;
    }
    if (control && shift && key == LogicalKeyboardKey.keyE) {
      unawaited(_exportDocument());
      return KeyEventResult.handled;
    }
    if (control && shift && key == LogicalKeyboardKey.keyN) {
      unawaited(_createBlankNote());
      return KeyEventResult.handled;
    }
    if (control && !shift && key == LogicalKeyboardKey.keyR) {
      final LibraryDocument? item = _currentLibraryDocument;
      if (item != null) unawaited(_renameDocument(item));
      return KeyEventResult.handled;
    }
    if (control && !shift && key == LogicalKeyboardKey.keyO) {
      unawaited(_openImportShortcut());
      return KeyEventResult.handled;
    }
    if (control && !shift && key == LogicalKeyboardKey.keyW) {
      final String? id = _doc.document?.id;
      if (id != null) unawaited(_closeDocumentTab(id));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.pageUp) {
      _goToPage(_doc.pageIndex - 1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.pageDown) {
      _goToPage(_doc.pageIndex + 1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.home) {
      _goToPage(0);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.end) {
      _goToPage((_doc.document?.pages.length ?? 1) - 1);
      return KeyEventResult.handled;
    }
    if (control && key == LogicalKeyboardKey.keyA) {
      _selectTool(InkTool.lasso);
      _ink.selectAll();
      return KeyEventResult.handled;
    }
    if (control &&
        (key == LogicalKeyboardKey.equal ||
            key == LogicalKeyboardKey.numpadAdd)) {
      _stepZoom(0.25);
      return KeyEventResult.handled;
    }
    if (control &&
        (key == LogicalKeyboardKey.minus ||
            key == LogicalKeyboardKey.numpadSubtract)) {
      _stepZoom(-0.25);
      return KeyEventResult.handled;
    }
    if (control &&
        (key == LogicalKeyboardKey.digit0 ||
            key == LogicalKeyboardKey.numpad0)) {
      _applyDefaultPageFit();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// 先结束当前文稿交互并回到资料库，再打开导入选择，复用资料库导入进度与资源限制。
  Future<void> _openImportShortcut() async {
    await _goToLibrary();
    if (mounted && _doc.document == null) await _importFiles();
  }
}
