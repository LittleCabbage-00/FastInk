part of '../../app/fastink_app.dart';

extension _FastInkDocumentOverlays on _FastInkHomeState {
  /// 把屏幕视口通过相机逆变换映射到页内逻辑坐标，得到浮层可放置区域并裁到页面范围。
  Rect _visiblePageOverlayBounds(Size pageSize) {
    final page = Offset.zero & pageSize;
    if (_canvasViewport.isEmpty || _pageViewportRect.isEmpty) return page;
    final first =
        _viewport.zoomController.toScene(Offset.zero) -
        _pageViewportRect.topLeft;
    final last =
        _viewport.zoomController.toScene(
          _canvasViewport.bottomRight(Offset.zero),
        ) -
        _pageViewportRect.topLeft;
    final visible = page.intersect(Rect.fromPoints(first, last));
    return visible.isEmpty ? page : visible;
  }

  /// 按归一化选区计算操作条位置，避开旋转把手并限制在可见页面内；尺寸经反缩放保持屏幕大小。
  Widget _selectionActionsMenu(Size pageSize) {
    final Rect? normalized = _ink.selectionBounds;
    if (normalized == null || pageSize.isEmpty) return const SizedBox.shrink();
    final Rect bounds = Rect.fromLTRB(
      normalized.left * pageSize.width,
      normalized.top * pageSize.height,
      normalized.right * pageSize.width,
      normalized.bottom * pageSize.height,
    );
    final double documentScale = _viewport.zoomController.value
        .getMaxScaleOnAxis()
        .clamp(1.0, _settings.maximumZoom);
    final double inverseScale = 1 / documentScale;
    final double menuHeight = _ink.selectedTextStroke == null ? 34 : 40;
    final double menuWidth = _ink.selectedTextStroke == null
        ? 124
        : math
              .min(
                214,
                _visiblePageOverlayBounds(pageSize).width * documentScale - 16,
              )
              .clamp(120.0, 214.0)
              .toDouble();
    // 菜单位置用页面坐标，尺寸和边距按缩放比例换算。
    final double logicalMenuWidth = menuWidth * inverseScale;
    final double logicalMenuHeight = menuHeight * inverseScale;
    final double edge = 8 * inverseScale;
    final double gap = 8 * inverseScale;
    final visible = _visiblePageOverlayBounds(pageSize);
    final minLeft = visible.left + edge;
    final minTop = visible.top + edge;
    // 上方预留旋转柄的屏幕空间。
    final double upperHandleClearance =
        _ink.selectionMenuTopClearanceScreen * inverseScale;
    final double lowerHandleClearance =
        _ink.selectionMenuBottomClearanceScreen * inverseScale;
    final double maxLeft = math.max(
      minLeft,
      visible.right - logicalMenuWidth - edge,
    );
    final double left = (bounds.center.dx - logicalMenuWidth / 2).clamp(
      minLeft,
      maxLeft,
    );
    final double maxTop = math.max(
      minTop,
      visible.bottom - logicalMenuHeight - edge,
    );
    final double aboveTop =
        bounds.top - upperHandleClearance - gap - logicalMenuHeight;
    final double belowTop = bounds.bottom + lowerHandleClearance + gap;
    final bool canPlaceAbove = aboveTop >= minTop && aboveTop <= maxTop;
    final bool canPlaceBelow = belowTop >= minTop && belowTop <= maxTop;
    final double top =
        (canPlaceAbove
                ? aboveTop
                : canPlaceBelow
                ? belowTop
                // 选区占满页面时，将菜单置于选区上缘内侧。
                : (_ink.selectedTextStroke == null
                      ? bounds.top + 12 * inverseScale
                      : minTop))
            .clamp(minTop, maxTop);
    return Positioned(
      left: left,
      top: top,
      width: logicalMenuWidth,
      height: logicalMenuHeight,
      child: OverflowBox(
        alignment: Alignment.topLeft,
        minWidth: menuWidth,
        maxWidth: menuWidth,
        minHeight: menuHeight,
        maxHeight: menuHeight,
        child: Transform.scale(
          scale: inverseScale,
          alignment: Alignment.topLeft,
          child: Material(
            key: const ValueKey('selection-actions'),
            elevation: 6,
            color: Theme.of(context).colorScheme.inverseSurface,
            textStyle: TextStyle(
              color: Theme.of(context).colorScheme.onInverseSurface,
            ),
            borderRadius: BorderRadius.circular(9),
            child: Listener(
              onPointerDown: (event) {
                _overlayPointers.add(event.pointer);
                _touchPoints.remove(event.pointer);
              },
              onPointerUp: (event) => _overlayPointers.remove(event.pointer),
              onPointerCancel: (event) =>
                  _overlayPointers.remove(event.pointer),
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: _ink.selectedTextStroke != null
                    ? TextObjectToolbar(
                        enabled: !_doc.readOnly && !_doc.inkInputBlocked,
                        onEdit: () => _showTextProperties(pageSize),
                        onMoveMode: () => _selectTool(InkTool.lasso),
                        onMoveStart: () {
                          final center = _ink.selectionBounds?.center;
                          if (center == null) return;
                          _textToolbarMovePoint = InkPoint(
                            center.dx,
                            center.dy,
                            .5,
                          );
                          _selectTool(InkTool.lasso);
                          _ink.beginSelectionTransform(
                            _textToolbarMovePoint!,
                            pageSize,
                            hitRadius: 0,
                          );
                        },
                        onMove: (delta) {
                          final point = _textToolbarMovePoint;
                          if (point == null) return;
                          _textToolbarMovePoint = InkPoint(
                            point.x + delta.dx * inverseScale / pageSize.width,
                            point.y + delta.dy * inverseScale / pageSize.height,
                            .5,
                          );
                          _ink.updateSelectionTransform(
                            _textToolbarMovePoint!,
                            pageSize,
                          );
                        },
                        onMoveEnd: () {
                          _textToolbarMovePoint = null;
                          _ink.finishSelectionTransform();
                        },
                        onAction: (action) {
                          switch (action) {
                            case 'copy':
                              _copyInkSelection();
                            case 'cut':
                              _copyInkSelection(cut: true);
                            case 'color':
                              _recolorInkSelection();
                            case 'delete':
                              _ink.deleteSelection();
                          }
                        },
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          IconButton(
                            style: IconButton.styleFrom(
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints.tightFor(
                              width: 30,
                              height: 30,
                            ),
                            tooltip: tr(
                              '复制选区 · Ctrl+C',
                              'Copy selection · Ctrl+C',
                            ),
                            color: Theme.of(
                              context,
                            ).colorScheme.onInverseSurface,
                            onPressed: _doc.inkInputBlocked
                                ? null
                                : _copyInkSelection,
                            icon: const Icon(
                              Icons.content_copy_rounded,
                              size: 16,
                            ),
                          ),
                          IconButton(
                            style: IconButton.styleFrom(
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            tooltip: tr(
                              '剪切选区 · Ctrl+X',
                              'Cut selection · Ctrl+X',
                            ),
                            constraints: const BoxConstraints.tightFor(
                              width: 30,
                              height: 30,
                            ),
                            padding: EdgeInsets.zero,
                            color: Theme.of(
                              context,
                            ).colorScheme.onInverseSurface,
                            onPressed: _doc.inkInputBlocked || _doc.readOnly
                                ? null
                                : () => _copyInkSelection(cut: true),
                            icon: const Icon(Icons.content_cut, size: 16),
                          ),
                          IconButton(
                            style: IconButton.styleFrom(
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            tooltip: tr('选区改色', 'Recolor selection'),
                            constraints: const BoxConstraints.tightFor(
                              width: 30,
                              height: 30,
                            ),
                            padding: EdgeInsets.zero,
                            color: Theme.of(
                              context,
                            ).colorScheme.onInverseSurface,
                            onPressed: _doc.inkInputBlocked || _doc.readOnly
                                ? null
                                : _recolorInkSelection,
                            icon: const Icon(Icons.palette_outlined, size: 16),
                          ),
                          IconButton(
                            style: IconButton.styleFrom(
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints.tightFor(
                              width: 30,
                              height: 30,
                            ),
                            tooltip: tr('删除'),
                            color: Theme.of(context).colorScheme.error,
                            onPressed: _doc.inkInputBlocked || _doc.readOnly
                                ? null
                                : _ink.deleteSelection,
                            icon: const Icon(
                              Icons.delete_outline_rounded,
                              size: 18,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 订阅相机和输入内容更新紧凑文本面板；只重建依赖位置与测量的浮层。
  Widget _inlineTextEditor(Size pageSize) => AnimatedBuilder(
    animation: Listenable.merge([
      _viewport.zoomController,
      _inlineTextController,
    ]),
    builder: (_, _) => _inlineTextEditorBody(pageSize),
  );

  /// 计算文字输入面板的可见位置与固定屏幕尺寸，绑定提交/取消/样式键；输入颜色跟随主题，落字颜色仍由工具状态保存。
  Widget _inlineTextEditorBody(Size pageSize) {
    final InkPoint? point = _inlineTextPoint;
    if (point == null || pageSize.isEmpty) return const SizedBox.shrink();
    final scale = _viewport.zoomController.value.getMaxScaleOnAxis().clamp(
      1.0,
      _settings.maximumZoom,
    );
    final inverseScale = 1 / scale;
    final visible = _visiblePageOverlayBounds(pageSize);
    final double width = math.min(
      _inlineTextScreenWidth,
      math.max(80, visible.width * scale - 16),
    );
    if (_editingTextStroke == null && _needsAdaptiveText) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _adaptInlineText();
      });
    }
    final previewFontSize = _inlineTextSize.clamp(10.0, 40.0);
    // 编辑器使用紧凑的屏幕坐标输入面板；存储的字体样式与
    // 页面相对宽度独立计算，缩放视图不会改动笔迹。
    final measure = TextPainter(
      text: TextSpan(
        text: _inlineTextController.text.isEmpty
            ? ' '
            : _inlineTextController.text,
        style: TextStyle(
          fontFamily: _toolState.textFontFamily,
          fontSize: previewFontSize,
          height: 1.25,
          fontWeight: _toolState.textBold ? FontWeight.w700 : FontWeight.w400,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: math.max(20, width - 70));
    final double height = (measure.height + 12).clamp(
      40.0,
      math.min(160.0, math.max(40, visible.height * scale - 16)),
    );
    measure.dispose();
    final edge = 8 * inverseScale;
    final minLeft = visible.left + edge;
    final minTop = visible.top + edge;
    final double maxLeft = math.max(
      minLeft,
      visible.right - (width + 8) * inverseScale,
    );
    final double left = (point.x * pageSize.width).clamp(minLeft, maxLeft);
    final double maxTop = math.max(
      minTop,
      visible.bottom - (height + 8) * inverseScale,
    );
    final double top = (point.y * pageSize.height).clamp(minTop, maxTop);
    final panel = placeTextBox(
      Rect.fromLTWH(left, top, width * inverseScale, height * inverseScale),
      visible.deflate(edge),
      _textObstacles,
    );
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Positioned(
      left: panel.left,
      top: panel.top,
      width: width * inverseScale,
      height: height * inverseScale,
      child: OverflowBox(
        alignment: Alignment.topLeft,
        minWidth: width,
        maxWidth: width,
        minHeight: height,
        maxHeight: height,
        child: Transform.scale(
          scale: inverseScale,
          alignment: Alignment.topLeft,
          child: Transform.rotate(
            angle: _inlineTextAngle,
            alignment: Alignment.topLeft,
            child: Focus(
              onKeyEvent: (FocusNode node, KeyEvent event) {
                if (event is! KeyDownEvent) return KeyEventResult.ignored;
                if (event.logicalKey == LogicalKeyboardKey.escape) {
                  _cancelInlineText();
                  return KeyEventResult.handled;
                }
                final bool enter =
                    event.logicalKey == LogicalKeyboardKey.enter ||
                    event.logicalKey == LogicalKeyboardKey.numpadEnter;
                if (enter && HardwareKeyboard.instance.isControlPressed) {
                  _commitInlineText(canvasSize: pageSize);
                  return KeyEventResult.handled;
                }
                if (HardwareKeyboard.instance.isControlPressed) {
                  if (event.logicalKey == LogicalKeyboardKey.keyB) {
                    _updateState(
                      () => _toolState.textBold = !_toolState.textBold,
                    );
                    return KeyEventResult.handled;
                  }
                  if (event.logicalKey == LogicalKeyboardKey.keyI) {
                    _updateState(
                      () => _toolState.textItalic = !_toolState.textItalic,
                    );
                    return KeyEventResult.handled;
                  }
                  if (event.logicalKey == LogicalKeyboardKey.keyU) {
                    _updateState(
                      () =>
                          _toolState.textUnderline = !_toolState.textUnderline,
                    );
                    return KeyEventResult.handled;
                  }
                }
                return KeyEventResult.ignored;
              },
              child: ConstrainedBox(
                constraints: BoxConstraints.tightFor(height: height),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: <Widget>[
                    Material(
                      key: const ValueKey('inline-text-editor'),
                      elevation: 3,
                      color: colors.surface.withValues(alpha: 0.96),
                      shape: RoundedRectangleBorder(
                        side: BorderSide(color: colors.primary, width: 1.5),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: MediaQuery.withNoTextScaling(
                        child: TextField(
                          key: const ValueKey('inline-text-input'),
                          controller: _inlineTextController,
                          focusNode: _inlineTextFocus,
                          autofocus: true,
                          minLines: null,
                          maxLines: null,
                          expands: true,
                          keyboardType: TextInputType.multiline,
                          textInputAction: TextInputAction.newline,
                          textAlign: _toolState.textAlign,
                          cursorColor: colors.primary,
                          style: TextStyle(
                            // 输入面板跟随主题保证对比度，落字仍使用用户选定的颜色。
                            color: colors.onSurface,
                            fontFamily: _toolState.textFontFamily,
                            fontFamilyFallback: const <String>[
                              'Microsoft YaHei UI',
                            ],
                            fontSize: previewFontSize,
                            height: 1.25,
                            fontWeight: _toolState.textBold
                                ? FontWeight.w700
                                : FontWeight.w400,
                            fontStyle: _toolState.textItalic
                                ? FontStyle.italic
                                : FontStyle.normal,
                            decoration: _toolState.textUnderline
                                ? TextDecoration.underline
                                : TextDecoration.none,
                          ),
                          onTapOutside: (_) =>
                              _commitInlineText(canvasSize: pageSize),
                          decoration: InputDecoration(
                            hintText: tr('输入文字'),
                            hintStyle: TextStyle(
                              color: colors.onSurfaceVariant,
                            ),
                            isDense: true,
                            filled: false,
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.fromLTRB(
                              8,
                              6,
                              0,
                              6,
                            ),
                            suffixIconConstraints: const BoxConstraints(
                              minWidth: 56,
                              maxWidth: 56,
                            ),
                            suffixIcon: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                IconButton(
                                  tooltip: tr('取消（Esc）'),
                                  visualDensity: VisualDensity.compact,
                                  style: IconButton.styleFrom(
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints.tightFor(
                                    width: 28,
                                    height: 28,
                                  ),
                                  iconSize: 15,
                                  onPressed: _cancelInlineText,
                                  icon: const Icon(Icons.close_rounded),
                                ),
                                IconButton(
                                  tooltip: tr('完成（Ctrl+Enter）'),
                                  visualDensity: VisualDensity.compact,
                                  style: IconButton.styleFrom(
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints.tightFor(
                                    width: 28,
                                    height: 28,
                                  ),
                                  iconSize: 16,
                                  color: colors.primary,
                                  onPressed: () =>
                                      _commitInlineText(canvasSize: pageSize),
                                  icon: const Icon(Icons.check_rounded),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      right: -9,
                      top: 8,
                      bottom: 8,
                      width: 18,
                      child: Tooltip(
                        message: tr('拖动调整文本框宽度'),
                        child: MouseRegion(
                          cursor: SystemMouseCursors.resizeLeftRight,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onHorizontalDragUpdate: (DragUpdateDetails details) {
                              final double available = math.max(
                                160,
                                (pageSize.width - left) * scale - 8,
                              );
                              _updateState(() {
                                _autoTextWidth = false;
                                final nextWidth =
                                    (_inlineTextScreenWidth + details.delta.dx)
                                        .clamp(
                                          160.0,
                                          math.min(480.0, available),
                                        );
                                _inlineTextEditorWidth =
                                    (_inlineTextEditorWidth +
                                            (nextWidth -
                                                    _inlineTextScreenWidth) *
                                                inverseScale)
                                        .clamp(
                                          40.0,
                                          math.max(
                                            40,
                                            pageSize.width - left - edge,
                                          ),
                                        );
                                _inlineTextScreenWidth = nextWidth.toDouble();
                              });
                            },
                            child: Center(
                              child: Container(
                                width: 3,
                                height: 18,
                                decoration: BoxDecoration(
                                  color: colors.primary,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
