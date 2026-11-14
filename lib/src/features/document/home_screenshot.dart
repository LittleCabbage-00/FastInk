part of '../../app/fastink_app.dart';

extension _FastInkScreenshot on _FastInkHomeState {
  /// 构建截图和剪贴板相关入口，区分软件内纸面捕获与外部屏幕捕获。
  Widget _screenshotMenu() => PopupMenuButton<String>(
    popUpAnimationStyle: appMotionStyle(context),
    key: const ValueKey('screenshot-menu'),
    tooltip: tr('截图与标注', 'Screenshot and annotate'),
    icon: const Icon(Icons.screenshot_monitor_outlined),
    enabled: !_captureBusy && !_doc.busy && !_doc.inkInputBlocked,
    onSelected: (value) => unawaited(
      value == 'paste'
          ? _pasteClipboardImage()
          : _startScreenshot(external: value == 'desktop'),
    ),
    itemBuilder: (_) => [
      PopupMenuItem(
        value: 'desktop',
        child: ListTile(
          leading: const Icon(Icons.screenshot_monitor_outlined),
          title: Text(tr('截取屏幕上的资料', 'Capture desktop region')),
          subtitle: Text(
            tr('隐藏 FastInk，截图后编辑', 'Hide FastInk, then capture and annotate'),
          ),
        ),
      ),
      PopupMenuItem(
        value: 'page',
        child: ListTile(
          leading: const Icon(Icons.crop),
          title: Text(tr('截取当前笔记 / PDF 区域', 'Capture note / PDF region')),
        ),
      ),
      PopupMenuItem(
        value: 'paste',
        enabled: !_doc.readOnly,
        child: ListTile(
          leading: const Icon(Icons.content_paste_go_outlined),
          title: Text(tr('粘贴剪贴板图片', 'Paste clipboard image')),
        ),
      ),
    ],
  );

  /// 把截图编码字节解码为屏幕编辑图像，调用方在完成后负责释放返回的 ui.Image。
  Future<ui.Image> _decodeScreenshot(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    try {
      return (await codec.getNextFrame()).image;
    } finally {
      codec.dispose();
    }
  }

  /// 准备软件内/外部截图并打开编辑器，捕获期间独占侧键输入；完成、取消或失败都清理独占状态。
  Future<void> _startScreenshot({required bool external}) async {
    final target = _doc.document;
    if (_captureBusy ||
        _doc.busy ||
        target == null ||
        _doc.pageImage == null ||
        _doc.inkInputBlocked) {
      return;
    }
    final token = _doc.pageToken;
    final canInsert = !_doc.readOnly;
    _commitInlineText();
    _captureBusy = true;
    _toolState.heldPenButton = 0;
    _doc.lockInk(target.id);
    bool ownsInkLock = true;
    final bridge = WindowsCapture();
    WindowsFullscreen? editorWindow;
    ScreenshotDocument? capture;
    ui.Image? source;
    Directory? temporary;
    final navigator = Navigator.of(context);
    final loading = DialogRoute<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(
        canPop: false,
        child: Center(child: CircularProgressIndicator()),
      ),
    );
    unawaited(navigator.push(loading));
    try {
      if (external) {
        final handle = _windowFullscreen.windowHandle;
        bridge.hideWindow(handle);
        try {
          await Future<void>.delayed(const Duration(milliseconds: 240));
          if (!mounted) return;
          final pixels = bridge.captureDesktop();
          final ready = Completer<ui.Image>();
          ui.decodeImageFromPixels(
            pixels.bgra,
            pixels.width,
            pixels.height,
            ui.PixelFormat.bgra8888,
            ready.complete,
          );
          source = await ready.future;
        } finally {
          bridge.restoreWindow();
        }
      } else {
        if (!await _saveNow()) {
          throw StateError(
            tr('笔迹未保存成功，请重试', 'Ink was not saved; please retry'),
          );
        }
        temporary = await Directory.systemTemp.createTemp('fastink_capture_');
        final file = File('${temporary.path}/page.png');
        await _exportRepository.exportImage(
          target,
          _doc.currentPage!,
          file,
          NoteExportFormat.png,
        );
        source = await _decodeScreenshot(await file.readAsBytes());
      }
      if (!mounted) return;
      capture = await ScreenshotDocument.create(source);
      source = null; // ownership transferred to the editor document
      if (!mounted) return;
      if (!Platform.environment.containsKey('FLUTTER_TEST') &&
          !_immersiveMode) {
        editorWindow = WindowsFullscreen(
          windowHandle: _windowFullscreen.windowHandle,
        )..setEnabled(true);
      }
      navigator.removeRoute(loading);
      final result = await showDialog<Uint8List>(
        context: context,
        animationStyle: appMotionStyle(context),
        barrierDismissible: false,
        useSafeArea: false,
        builder: (_) => Dialog.fullscreen(
          child: ScreenshotEditor(
            document: capture!,
            canInsert: canInsert,
            nativePenButtons: _capturePenButtons,
            penButtons: {
              for (final (mask, button) in [
                (kPrimaryStylusButton, 1),
                (kSecondaryStylusButton, 2),
              ])
                mask: (
                  tool: _actionForPhysicalButton(button).tool,
                  eraser: _eraserModeForButton(button),
                ),
            },
            penButtonMomentary: _settings.penButtonMomentary,
            stylusOnly: _settings.stylusOnly,
            penStyle: PenStyle.values.firstWhere(
              (style) => style.name == _settings.penStyle,
              orElse: () => PenStyle.fountain,
            ),
            penPressure: (event) => effectivePenPressure(
              event,
              enabled: _settings.pressureEnabled,
              curve: PressureCurve.values.firstWhere(
                (curve) => curve.name == _settings.pressureCurve,
                orElse: () => PressureCurve.linear,
              ),
              sensitivity: _settings.pressureSensitivity,
              fallback: _nativePressure.forEvent,
            ),
            penColor: Color(_settings.penColor),
            penWidth: _settings.penWidth,
            highlighterColor: _toolState.highlighterColor,
            highlighterWidth: _settings.highlighterWidth,
            eraserMode: _configuredEraserMode,
            eraserSize: _settings.eraserSize,
            shape: _toolState.shapeType,
            laserColor: Color(_settings.laserColor),
            laserWidth: _settings.laserWidth,
            laserMode: LaserMode.values.firstWhere(
              (mode) => mode.name == _settings.laserMode,
              orElse: () => LaserMode.trail,
            ),
            onCopy: (png) =>
                bridge.writeImage(_windowFullscreen.windowHandle, png),
            onSave: _saveScreenshot,
          ),
        ),
      );
      editorWindow?.dispose();
      editorWindow = null;
      // 退出动画尚未结束时，离开的路由仍可能继续绘制。
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (result != null &&
          mounted &&
          _doc.document?.id == target.id &&
          _doc.pageToken == token &&
          !_doc.readOnly) {
        // 对话框结束后释放自己的锁。插入阶段核对页令牌，清理临时文件
        // 不能重新锁住已经选中、可以拖动的图片。
        _doc.unlockInk(target.id);
        ownsInkLock = false;
        await _insertScreenshot(result, target, token);
      }
    } catch (error) {
      if (mounted) {
        _captureMessage(tr('截图失败：$error', 'Screenshot failed: $error'));
      }
    } finally {
      if (loading.isActive) navigator.removeRoute(loading);
      try {
        bridge.restoreWindow();
      } finally {
        editorWindow?.dispose();
      }
      source?.dispose();
      capture?.dispose();
      if (ownsInkLock) _doc.unlockInk(target.id);
      _captureBusy = false;
      if (mounted) {
        _updateState(() {});
        _canvasFocus.requestFocus();
      }
      if (temporary != null) {
        try {
          await temporary.delete(recursive: true);
        } catch (_) {}
      }
    }
  }

  /// 选择输出位置并保存 PNG，取消或失败返回 false，错误通过界面反馈。
  Future<bool> _saveScreenshot(Uint8List png) async {
    final picker = SaveFilePicker()
      ..title = tr('保存截图', 'Save screenshot')
      ..fileName = 'FastInk-${DateTime.now().millisecondsSinceEpoch}.png'
      ..defaultExtension = 'png'
      ..filterSpecification = {'PNG (*.png)': '*.png'};
    final file = picker.getFile();
    if (file == null) return false;
    await file.writeAsBytes(png, flush: true);
    return true;
  }

  /// 显示截图操作反馈，已卸载时不再更新旧界面。
  void _captureMessage(String message) {
    _updateState(() => _doc.status = message);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  /// 把截图保存为文稿图片资源并创建可编辑图片对象，异步完成前后检查目标页归属。
  Future<void> _insertScreenshot(
    Uint8List bytes,
    NoteDocument document,
    int token,
  ) async {
    // 检查截图请求对应的文稿和页仍是当前操作目标，避免迟到结果插入别页。
    bool current() =>
        mounted &&
        _doc.document?.id == document.id &&
        _doc.pageToken == token &&
        !_doc.readOnly &&
        !_doc.inkInputBlocked;
    if (!current()) return;
    final temp = await Directory.systemTemp.createTemp('fastink_paste_');
    try {
      final file = File('${temp.path}/screenshot.png');
      final image = await _decodeScreenshot(bytes);
      final aspect = image.width / image.height;
      image.dispose();
      await file.writeAsBytes(bytes, flush: true);
      final asset = await _repository.importEmbeddedImage(document, file);
      if (!current() || _doc.pageImage == null || _pageViewportRect.isEmpty) {
        return;
      }
      final pageSize = _pageViewportRect.size;
      _ink.addImage(
        asset,
        aspect,
        pageSize,
        placementBounds: _visiblePageOverlayBounds(pageSize),
      );
      _selectTool(InkTool.lasso);
      _canvasFocus.requestFocus();
      await _saveNow();
      if (mounted && _doc.dirty) {
        _captureMessage(
          tr(
            '截图已插入，但保存失败，请重试保存',
            'Screenshot inserted, but saving failed; please save again',
          ),
        );
      } else if (mounted) {
        _captureMessage(
          tr(
            '截图已插入，可移动、缩放或旋转',
            'Screenshot inserted; move, resize or rotate it',
          ),
        );
      }
    } finally {
      try {
        await temp.delete(recursive: true);
      } catch (_) {}
    }
  }

  /// 读取系统剪贴板图片并复用图片资源插入流程，失败不删除现有内容。
  Future<void> _pasteClipboardImage() async {
    final document = _doc.document;
    if (_captureBusy ||
        document == null ||
        _doc.readOnly ||
        _doc.inkInputBlocked) {
      return;
    }
    final token = _doc.pageToken;
    _captureBusy = true;
    try {
      final png = await WindowsCapture().readImage(
        _windowFullscreen.windowHandle,
      );
      if (!mounted) return;
      if (png == null) {
        _captureMessage(tr('剪贴板里没有图片', 'No image on the clipboard'));
        return;
      }
      await _insertScreenshot(png, document, token);
    } catch (error) {
      if (mounted) {
        _captureMessage(tr('粘贴图片失败：$error', 'Could not paste image: $error'));
      }
    } finally {
      _captureBusy = false;
    }
  }

  /// 优先按有效剪贴板类型处理应用内选区或系统图片，避免旧应用内内容覆盖新的外部复制。
  Future<void> _pasteClipboard() async {
    if (_copiedInk.isNotEmpty &&
        (!Platform.isWindows ||
            Platform.environment.containsKey('FLUTTER_TEST') ||
            _inkClipboardSequence == WindowsCapture().clipboardSequence)) {
      await _pasteInkSelection();
    } else {
      await _pasteClipboardImage();
    }
  }
}
