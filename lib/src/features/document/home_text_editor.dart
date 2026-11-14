part of '../../app/fastink_app.dart';

extension _FastInkTextEditor on _FastInkHomeState {
  /// 点击现有文字时进入该对象编辑，空白点则创建新文字；point 为归一化页面坐标。
  void _handleTextRequested(InkPoint point, Size canvasSize) {
    // 点击已有文本框进入编辑；空白处创建新框。
    final InkStroke? existing = _ink.textStrokeAt(point);
    if (existing != null) {
      _ink.selectOnly(existing);
      _beginEditingSelectedText(canvasSize);
      return;
    }
    _beginInlineText(point, canvasSize);
  }

  /// 优先在工具锚点打开紧凑设置浮层，无锚点时使用对话框；即时预览模式和半径，完成后保存默认值。
  Future<void> _showEraserSettings({BuildContext? anchorContext}) async {
    _updateState(() => _toolState.tool = InkTool.eraser);
    if (anchorContext != null) {
      final RenderObject? anchorObject = anchorContext.findRenderObject();
      final OverlayState? overlayState = Overlay.maybeOf(anchorContext);
      final RenderObject? overlayObject = overlayState?.context
          .findRenderObject();
      if (anchorObject is RenderBox && overlayObject is RenderBox) {
        EraserMode mode = EraserMode.values.firstWhere(
          (v) => v.name == _settings.eraserMode,
          orElse: () => EraserMode.stroke,
        );
        double size = _settings.eraserSize;
        final Offset anchorOffset = anchorObject.localToGlobal(
          Offset.zero,
          ancestor: overlayObject,
        );
        final Rect anchorRect = anchorOffset & anchorObject.size;
        await showMenu<void>(
          context: anchorContext,
          position: RelativeRect.fromRect(
            Rect.fromLTWH(anchorRect.left, anchorRect.bottom + 4, 310, 0),
            Offset.zero & overlayObject.size,
          ),
          constraints: const BoxConstraints.tightFor(width: 310),
          items: <PopupMenuEntry<void>>[
            _EraserSettingsPopup(
              initialMode: mode,
              initialSize: size,
              highlighterOnly: _ink.eraseHighlighterOnly,
              onHighlighterOnlyChanged: (value) =>
                  _updateState(() => _ink.eraseHighlighterOnly = value),
              onChanged: (EraserMode nextMode, double nextSize) {
                mode = nextMode;
                size = nextSize;
                if (mounted) {
                  _updateState(() {
                    _settings.eraserMode = mode.name;
                    _settings.eraserSize = size;
                  });
                }
              },
            ),
          ],
        );
        if (mounted) await _setEraserDefaults(mode: mode, size: size);
        return;
      }
    }
    await showDialog<void>(
      context: context,
      animationStyle: appMotionStyle(context),
      builder: (BuildContext dialogContext) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setDialogState) {
          // 同时更新宿主与当前对话框的临时状态，保证橡皮预览和控件显示一致。
          void update(VoidCallback change) {
            _updateState(change);
            setDialogState(() {});
          }

          return AlertDialog(
            title: Text(tr('橡皮擦')),
            content: SizedBox(
              width: 340,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(tr('仅擦除荧光笔', 'Erase highlighter only')),
                    value: _ink.eraseHighlighterOnly,
                    onChanged: (value) =>
                        update(() => _ink.eraseHighlighterOnly = value),
                  ),
                  SegmentedButton<EraserMode>(
                    segments: <ButtonSegment<EraserMode>>[
                      ButtonSegment<EraserMode>(
                        value: EraserMode.stroke,
                        icon: const Icon(Icons.auto_fix_normal_rounded),
                        label: Text(tr('整笔擦除')),
                      ),
                      ButtonSegment<EraserMode>(
                        value: EraserMode.point,
                        icon: const Icon(Icons.blur_circular_rounded),
                        label: Text(tr('局部擦除')),
                      ),
                    ],
                    selected: <EraserMode>{
                      EraserMode.values.firstWhere(
                        (v) => v.name == _settings.eraserMode,
                        orElse: () => EraserMode.stroke,
                      ),
                    },
                    onSelectionChanged: (Set<EraserMode> value) =>
                        update(() => _settings.eraserMode = value.first.name),
                  ),
                  if (_settings.eraserMode == 'point') ...<Widget>[
                    const SizedBox(height: 18),
                    Row(
                      children: <Widget>[
                        Text(
                          tr(
                            '范围 ${(_settings.eraserSize * 2).round()} px',
                            'Size ${(_settings.eraserSize * 2).round()} px',
                          ),
                        ),
                        Expanded(
                          child: Slider(
                            value: _settings.eraserSize,
                            min: 6,
                            max: 60,
                            divisions: 18,
                            onChanged: (double value) =>
                                update(() => _settings.eraserSize = value),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            actions: <Widget>[
              FilledButton(
                onPressed: () {
                  unawaited(_setEraserDefaults());
                  Navigator.pop(dialogContext);
                },
                child: Text(tr('完成')),
              ),
            ],
          );
        },
      ),
    );
  }

  /// 组合影响文本排版的字号、字体、样式和宽度模式，光标变化不会改变此签名。
  Object get _adaptiveStyleKey => (
    _inlineTextSize,
    _toolState.textFontFamily,
    _toolState.textBold,
    _toolState.textItalic,
    _autoTextWidth,
  );

  /// 判断全文或样式是否真正变化，跳过仅选区/光标更新引起的重复测量。
  bool get _needsAdaptiveText =>
      _adaptiveTextContent != _inlineTextController.text ||
      _adaptiveTextStyle != _adaptiveStyleKey;

  /// 在输入法组合结束后测量全文并寻找避开已有内容的位置，更新页面宽度与固定屏幕面板尺寸。
  void _adaptInlineText() {
    if (!_inlineTextController.value.composing.isCollapsed) return;
    if (_inlineTextPoint == null ||
        _editingTextStroke != null ||
        _inlineTextCanvasSize.isEmpty ||
        !_needsAdaptiveText) {
      return;
    }
    _adaptiveTextContent = _inlineTextController.text;
    _adaptiveTextStyle = _adaptiveStyleKey;
    final page = _inlineTextCanvasSize;
    final maximum = math.max(40.0, math.min(360.0, page.width - 16));
    final measured = measureAdaptiveText(
      _inlineTextController.text,
      TextStyle(
        fontFamily: _toolState.textFontFamily,
        fontFamilyFallback: const ['Microsoft YaHei UI'],
        fontSize: _inlineTextSize,
        fontWeight: _toolState.textBold ? FontWeight.w700 : FontWeight.w400,
        fontStyle: _toolState.textItalic ? FontStyle.italic : FontStyle.normal,
      ),
      _autoTextWidth ? maximum : _inlineTextEditorWidth,
    );
    final width = _autoTextWidth ? measured.width : _inlineTextEditorWidth;
    final scale = _viewport.zoomController.value.getMaxScaleOnAxis();
    final panelWidth = _autoTextWidth
        ? (width + 74).clamp(128.0, 420.0)
        : _inlineTextScreenWidth;
    final area = (Offset.zero & page).deflate(8);
    final preferred = Rect.fromLTWH(
      _inlineTextPoint!.x * page.width,
      _inlineTextPoint!.y * page.height,
      math.max(width, panelWidth / scale),
      math.max(measured.height + 8, 40 / scale),
    );
    final placement = placeTextBox(preferred, area, _textObstacles);
    _updateState(() {
      _inlineTextEditorWidth = width;
      _inlineTextScreenWidth = panelWidth;
      _inlineTextPoint = InkPoint(
        placement.left / page.width,
        placement.top / page.height,
        .5,
      );
    });
  }

  /// 建立新文字输入状态，记录页面尺寸与占用区域，下一帧请求输入焦点；确认前不创建持久文字对象。
  void _beginInlineText(InkPoint point, Size canvasSize) {
    if (_inlineTextPoint != null) _commitInlineText();
    _ink.clearSelection();
    _textObstacles = _ink.contentBounds(canvasSize);
    _autoTextWidth = true;
    _adaptiveTextContent = null;
    final viewScale = _viewport.zoomController.value.getMaxScaleOnAxis();
    final double availableWidth = math.max(80, canvasSize.width - 16);
    final double editorWidth = math.min(224 / viewScale, availableWidth);
    final double maxLeft = math.max(8, canvasSize.width - editorWidth - 8);
    final double maxTop = math.max(8, canvasSize.height - 110);
    final double left = (point.x * canvasSize.width).clamp(8, maxLeft);
    final double top = (point.y * canvasSize.height).clamp(8, maxTop);
    _inlineTextController.clear();
    _updateState(() {
      _editingTextStroke = null;
      _inlineTextSize = _settings.defaultTextSize;
      _inlineTextPoint = InkPoint(
        left / canvasSize.width,
        top / canvasSize.height,
        point.pressure,
      );
      _inlineTextCanvasSize = canvasSize;
      _inlineTextEditorWidth = editorWidth;
      _inlineTextScreenWidth = editorWidth * viewScale;
      _inlineTextAngle = 0;
    });
    _adaptInlineText();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _inlineTextPoint != null) _inlineTextFocus.requestFocus();
    });
  }

  /// 恢复所选文字的全文、字体和变换；超长或超出可见区域的文本转属性窗口，避免面板无法操作。
  void _beginEditingSelectedText(Size canvasSize) {
    if (_doc.readOnly || _doc.inkInputBlocked) return;
    final InkStroke? stroke = _ink.selectedTextStroke;
    if (stroke == null || stroke.points.isEmpty || canvasSize.isEmpty) return;
    final bounds = _ink.selectionBounds;
    if ((stroke.text?.length ?? 0) > 800 ||
        (bounds != null &&
            bounds.height * canvasSize.height >
                _visiblePageOverlayBounds(canvasSize).height * .7)) {
      unawaited(_showTextProperties(canvasSize));
      return;
    }
    if (_inlineTextPoint != null) _commitInlineText(canvasSize: canvasSize);
    _textObstacles = _ink.contentBounds(canvasSize, excluding: stroke);
    _autoTextWidth = false;
    final InkPoint anchor = stroke.points.first;
    final double availableWidth = math.max(80, canvasSize.width - 16);
    final InkPoint right = stroke.points[1];
    // 编辑已旋转或缩放的文本时，恢复原来的角度与尺寸。
    final Offset horizontal = Offset(
      (right.x - anchor.x) * canvasSize.width,
      (right.y - anchor.y) * canvasSize.height,
    );
    _inlineTextController.text = stroke.text ?? '';
    _inlineTextController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _inlineTextController.text.length,
    );
    _updateState(() {
      _editingTextStroke = stroke;
      final double baseWidth = math.max(
        1,
        (stroke.textBoxWidth ?? horizontal.distance / canvasSize.width) *
            canvasSize.width,
      );
      final double scale = (horizontal.distance / baseWidth).clamp(0.01, 20);
      _inlineTextSize = stroke.textSize * canvasSize.height * scale;
      _toolState.textColor = Color(stroke.color);
      _toolState.color = _toolState.textColor;
      _toolState.textBold = stroke.textWeight >= 600;
      _toolState.textItalic = stroke.textItalic;
      _toolState.textUnderline = stroke.textUnderline;
      _toolState.textAlign = stroke.textAlign;
      _toolState.textFontFamily = stroke.textFontFamily;
      _toolState.tool = InkTool.text;
      _inlineTextPoint = anchor;
      _inlineTextCanvasSize = canvasSize;
      _inlineTextEditorWidth = horizontal.distance.clamp(40, availableWidth);
      _inlineTextScreenWidth =
          (horizontal.distance *
                  _viewport.zoomController.value.getMaxScaleOnAxis())
              .clamp(192, 320);
      _inlineTextAngle = math.atan2(horizontal.dy, horizontal.dx);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _inlineTextPoint != null) _inlineTextFocus.requestFocus();
    });
  }

  /// 在当前页可编辑时提交完整文字，新增或更新目标对象并生成一次历史；输入面板主题色不写入文字颜色。
  void _commitInlineText({Size? canvasSize}) {
    final InkPoint? point = _inlineTextPoint;
    if (point == null) return;
    // 换页/旋转/导出窗口里不接受提交：此刻 _ink 里装的不是用户看到的那页，
    // 或者笔迹正在被读。编辑框原样留着（文字不丢），窗口过去再点"完成"。
    // 注意换页路径是在置位 pageLoading 之前调用的，不受影响。
    if (_doc.inkInputBlocked) return;
    final InkStroke? editing = _editingTextStroke;
    final String text = _inlineTextController.text.trim();
    final Size size = canvasSize ?? _inlineTextCanvasSize;
    // 提交前关闭编辑框，防止控制器通知时再次显示浮层。
    _updateState(() {
      _inlineTextPoint = null;
      _editingTextStroke = null;
    });
    _inlineTextFocus.unfocus();
    _inlineTextController.clear();
    if (size.isEmpty) return;
    if (editing != null) {
      _ink.updateText(
        editing,
        text,
        size,
        boxWidth: _inlineTextEditorWidth,
        color: _toolState.textColor,
        fontSize: _inlineTextSize,
        textWeight: _toolState.textBold ? 700 : 400,
        textItalic: _toolState.textItalic,
        textUnderline: _toolState.textUnderline,
        textAlign: _toolState.textAlign,
        textFontFamily: _toolState.textFontFamily,
      );
    } else if (text.isNotEmpty) {
      _ink.addText(
        point,
        size,
        text,
        _toolState.textColor,
        _inlineTextSize,
        boxWidth: _inlineTextEditorWidth,
        textWeight: _toolState.textBold ? 700 : 400,
        textItalic: _toolState.textItalic,
        textUnderline: _toolState.textUnderline,
        textAlign: _toolState.textAlign,
        textFontFamily: _toolState.textFontFamily,
      );
      if (!_toolState.textToolPinned) _selectTool(InkTool.lasso);
    }
  }

  /// 关闭纸面编辑并清空临时输入，不提交新文字或覆盖原有文本对象。
  void _cancelInlineText() {
    if (_inlineTextPoint == null) return;
    _updateState(() {
      _inlineTextPoint = null;
      _editingTextStroke = null;
    });
    _inlineTextFocus.unfocus();
    _inlineTextController.clear();
  }
}
