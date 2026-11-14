part of '../../app/fastink_app.dart';

extension _FastInkFullscreen on _FastInkHomeState {
  /// 切换平台全屏与书写布局，保留待定位页，下一帧恢复画布焦点；平台失败时显示错误而不假装成功。
  void _setImmersive(bool enabled) {
    if (_immersiveMode == enabled || (enabled && _doc.document == null)) return;
    _commitInlineText();
    try {
      _windowFullscreen.setEnabled(enabled);
      _viewport.pendingViewportPage = _doc.pageIndex;
      _updateState(() => _immersiveMode = enabled);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _doc.document != null) _canvasFocus.requestFocus();
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              tr('切换全屏失败：$error', 'Could not change fullscreen: $error'),
            ),
          ),
        );
      }
    }
  }

  /// 处理资料库搜索、文档编辑和全屏按键，弹出路由显示时不抢占按键。
  KeyEventResult _handleFullscreenKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || ModalRoute.of(context)?.isCurrent == false) {
      return KeyEventResult.ignored;
    }
    if (_doc.document == null) {
      if (HardwareKeyboard.instance.isControlPressed &&
          event.logicalKey == LogicalKeyboardKey.keyF &&
          _librarySection != 'settings') {
        _librarySearchFocus.requestFocus();
        _searchInput.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _searchInput.text.length,
        );
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        // 先退出搜索，再关闭文件夹；不抢占对话框中的 Esc。
        if (_searchInput.text.isNotEmpty) {
          _searchInput.clear();
          return KeyEventResult.handled;
        }
        if (_activeFolderId != null) {
          _updateState(() => _activeFolderId = null);
          return KeyEventResult.handled;
        }
      }
      return KeyEventResult.ignored;
    }
    // 画布已处理的事件不会冒泡到这里，工具栏获焦后仍可编辑。
    final edit = _handleCanvasEditKey(event);
    if (edit == KeyEventResult.handled) return edit;
    if (event.logicalKey == LogicalKeyboardKey.f11) {
      _setImmersive(!_immersiveMode);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape && _immersiveMode) {
      _setImmersive(false);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// 按当前状态创建进入或退出全屏按钮，提示对应 F11/Esc 操作。
  Widget _fullscreenButton() => IconButton(
    key: ValueKey(_immersiveMode ? 'exit-fullscreen' : 'enter-fullscreen'),
    tooltip: _immersiveMode
        ? tr('退出全屏 · F11 / Esc', 'Exit fullscreen · F11 / Esc')
        : tr('全屏书写 · F11', 'Fullscreen writing · F11'),
    onPressed: () => _setImmersive(!_immersiveMode),
    icon: Icon(
      _immersiveMode ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
    ),
  );

  /// 创建全屏书写的最小工具区，保留返回、当前工具及退出全屏。
  Widget _immersiveToolbar() => Row(
    key: const ValueKey('immersive-toolbar'),
    children: [
      IconButton(
        key: const ValueKey('fullscreen-back'),
        tooltip: tr('返回资料库'),
        onPressed: _goToLibrary,
        icon: const Icon(Icons.arrow_back_rounded),
      ),
      Expanded(child: _inkToolbar()),
      _fullscreenButton(),
    ],
  );
}
