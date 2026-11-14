part of '../../app/fastink_app.dart';

extension _FastInkToolbar on _FastInkHomeState {
  /// 按当前工具、窗口和只读/任务状态构建书写工具栏，横向溢出通过滚动访问。
  Widget _inkToolbar() {
    final List<double> widths = _compactWidths();
    final List<Color> colors = _compactColors();
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // 右侧缩放区需要稳定占位。普通 Surface 窗口也应尽早折叠
        // 次要工具，避免按钮贴边以及切换工具后整条工具栏漂移。
        final bool compact =
            _settings.compactToolbar || constraints.maxWidth < 1320;
        final Widget content = _doc.readOnly
            ? SingleChildScrollView(
                key: const ValueKey<String>('read-only-toolbar'),
                scrollDirection: Axis.horizontal,
                child: _toolbarGroup(<Widget>[
                  _screenshotMenu(),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        const Icon(Icons.visibility_outlined, size: 18),
                        const SizedBox(width: 7),
                        Text(tr('只读模式 · 可翻页和缩放')),
                      ],
                    ),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: () => _updateState(() => _doc.readOnly = false),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: Text(tr('继续编辑')),
                  ),
                  if (!_immersiveMode) _zoomIndicator(),
                ]),
              )
            : Row(
                key: const ValueKey<String>('editing-toolbar'),
                children: <Widget>[
                  Expanded(
                    child: Listener(
                      onPointerSignal: _handleToolbarScroll,
                      child: _toolbarScroller(
                        SingleChildScrollView(
                          controller: _toolbarScroll,
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 5,
                          ),
                          child: Row(
                            children: <Widget>[
                              _toolbarGroup(<Widget>[
                                _penToolMenu(),
                                _toolButton(
                                  InkTool.highlighter,
                                  Icons.border_color,
                                  tr('荧光笔'),
                                  tr('荧光笔'),
                                  onPressed: () =>
                                      _selectTool(InkTool.highlighter),
                                ),
                                Builder(
                                  builder: (BuildContext anchorContext) =>
                                      _toolButton(
                                        InkTool.eraser,
                                        Icons.auto_fix_normal_rounded,
                                        tr('橡皮'),
                                        tr(
                                          '橡皮擦；再次点击可设置整笔或局部擦除',
                                          'Eraser; click again to choose whole-stroke or partial erasing',
                                        ),
                                        onPressed: () {
                                          if (_toolState.tool ==
                                              InkTool.eraser) {
                                            unawaited(
                                              _showEraserSettings(
                                                anchorContext: anchorContext,
                                              ),
                                            );
                                          } else {
                                            _updateState(
                                              () => _toolState.tool =
                                                  InkTool.eraser,
                                            );
                                          }
                                        },
                                      ),
                                ),
                                _lassoToolMenu(),
                                _screenshotMenu(),
                                if (!compact) ...<Widget>[
                                  _toolButton(
                                    InkTool.shape,
                                    Icons.category_outlined,
                                    tr('形状'),
                                    tr(
                                      '形状工具：拖动绘制直线、矩形或椭圆',
                                      'Drag to draw a line, rectangle, or ellipse',
                                    ),
                                    onPressed: () => _selectTool(InkTool.shape),
                                  ),
                                  _toolButton(
                                    InkTool.laser,
                                    Icons.flashlight_on_outlined,
                                    tr('激光'),
                                    tr(
                                      '激光指示：轨迹短暂显示，不会写入文稿',
                                      'Temporary laser trail that is not saved to the document',
                                    ),
                                    onPressed: () => _selectTool(InkTool.laser),
                                  ),
                                  _toolButton(
                                    InkTool.text,
                                    Icons.text_fields_rounded,
                                    tr('文本'),
                                    tr(
                                      '文本工具：点击页面直接编辑文字',
                                      'Click the page to edit text in place',
                                    ),
                                    onPressed: () => _selectTool(InkTool.text),
                                  ),
                                ] else
                                  _moreDrawingToolsMenu(),
                              ]),
                              const SizedBox(width: 7),
                              AnimatedSwitcher(
                                duration: appMotionDuration(context, 170),
                                switchInCurve: Curves.easeOutCubic,
                                switchOutCurve: Curves.easeInCubic,
                                transitionBuilder:
                                    (
                                      Widget child,
                                      Animation<double> animation,
                                    ) => FadeTransition(
                                      opacity: animation,
                                      child: SizeTransition(
                                        sizeFactor: animation,
                                        axis: Axis.horizontal,
                                        child: child,
                                      ),
                                    ),
                                child: _activeToolOptions(colors, widths),
                              ),
                              const SizedBox(width: 7),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  _historyControls(),
                  if (!_immersiveMode) ...[
                    const SizedBox(width: 6),
                    _toolbarGroup(<Widget>[_zoomIndicator()]),
                    const SizedBox(width: 4),
                  ],
                ],
              );
        return AnimatedSwitcher(
          duration: appMotionDuration(context, 190),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          child: content,
        );
      },
    );
  }

  /// 给工具栏配置可见滚动条与横向滚动容器，避免窄窗口直接裁掉功能。
  Widget _toolbarScroller(Widget child) => Scrollbar(
    key: const ValueKey('tool-options-scrollbar'),
    controller: _toolbarScroll,
    thumbVisibility: true,
    thickness: 3,
    child: child,
  );

  /// 构建撤销、重做及历史相关入口，按钮能力来自当前页历史与笔迹锁。
  Widget _historyControls() => KeyedSubtree(
    key: const ValueKey('ink-history-controls'),
    child: _toolbarGroup(<Widget>[
      IconButton(
        tooltip: tr('撤销'),
        visualDensity: VisualDensity.compact,
        // 加载/旋转/导出窗口里禁用：此时内存笔迹即将被
        // 替换或正在被读，撤销改的是上一页的内容，提交
        // 后会被无痕吞掉（见 inkInputBlocked）。
        onPressed: _ink.canUndo && !_doc.inkInputBlocked ? _ink.undo : null,
        icon: const Icon(Icons.undo),
      ),
      IconButton(
        tooltip: tr('重做'),
        visualDensity: VisualDensity.compact,
        onPressed: _ink.canRedo && !_doc.inkInputBlocked ? _ink.redo : null,
        icon: const Icon(Icons.redo),
      ),
      _toolbarActionsMenu(),
    ]),
  );

  /// 根据当前工具选择笔宽、颜色、橡皮、文字、激光或套索设置区域，不混用各工具参数。
  Widget _activeToolOptions(List<Color> colors, List<double> widths) {
    if (_toolState.tool == InkTool.eraser) {
      return _toolbarGroup(<Widget>[
        Builder(
          builder: (BuildContext anchorContext) => ActionChip(
            key: const ValueKey<String>('eraser-options'),
            avatar: Icon(
              _settings.eraserMode == 'stroke'
                  ? Icons.auto_fix_normal_rounded
                  : Icons.blur_circular_rounded,
              size: 17,
            ),
            label: Text(
              _settings.eraserMode == 'stroke'
                  ? tr('整笔擦除')
                  : tr(
                      '局部 ${(_settings.eraserSize * 2).round()} px',
                      'Partial ${(_settings.eraserSize * 2).round()} px',
                    ),
            ),
            onPressed: () =>
                unawaited(_showEraserSettings(anchorContext: anchorContext)),
          ),
        ),
      ]);
    }
    if (_toolState.tool == InkTool.shape) {
      return _toolbarGroup(<Widget>[
        PopupMenuButton<ShapeType>(
          popUpAnimationStyle: appMotionStyle(context),
          key: const ValueKey<String>('shape-options'),
          tooltip: tr('形状类型'),
          onSelected: (ShapeType value) {
            _updateState(() => _toolState.shapeType = value);
            _selectTool(InkTool.shape);
          },
          itemBuilder: (_) => <PopupMenuEntry<ShapeType>>[
            for (final (ShapeType type, IconData icon, String zh, String en)
                in <(ShapeType, IconData, String, String)>[
                  (ShapeType.arrow, Icons.north_east, '箭头', 'Arrow'),
                  (ShapeType.triangle, Icons.change_history, '三角形', 'Triangle'),
                  (ShapeType.diamond, Icons.diamond_outlined, '菱形', 'Diamond'),
                ])
              PopupMenuItem<ShapeType>(
                value: type,
                child: ListTile(leading: Icon(icon), title: Text(tr(zh, en))),
              ),

            PopupMenuItem<ShapeType>(
              value: ShapeType.line,
              child: ListTile(
                leading: const Icon(Icons.horizontal_rule_rounded),
                title: Text(tr('直线')),
              ),
            ),
            PopupMenuItem<ShapeType>(
              value: ShapeType.rectangle,
              child: ListTile(
                leading: const Icon(Icons.rectangle_outlined),
                title: Text(tr('矩形')),
              ),
            ),
            PopupMenuItem<ShapeType>(
              value: ShapeType.ellipse,
              child: ListTile(
                leading: const Icon(Icons.circle_outlined),
                title: Text(tr('椭圆')),
              ),
            ),
          ],
          child: Chip(
            avatar: const Icon(Icons.expand_more_rounded, size: 17),
            label: Text(switch (_toolState.shapeType) {
              ShapeType.arrow => tr('箭头', 'Arrow'),
              ShapeType.triangle => tr('三角形', 'Triangle'),
              ShapeType.diamond => tr('菱形', 'Diamond'),
              ShapeType.line => tr('直线'),
              ShapeType.rectangle => tr('矩形'),
              ShapeType.ellipse => tr('椭圆'),
            }),
          ),
        ),
      ]);
    }
    if (_toolState.tool == InkTool.text) return _textToolOptions();
    if (_toolState.tool == InkTool.laser) return _laserToolOptions();
    if (_toolState.tool == InkTool.lasso) {
      return const SizedBox(key: ValueKey<String>('no-tool-options'));
    }
    return KeyedSubtree(
      key: ValueKey<String>('ink-options-${_toolState.tool.name}'),
      child: _toolbarGroup(<Widget>[
        for (final Color color in colors) _colorButton(color),
        Builder(
          builder: (BuildContext anchorContext) => IconButton(
            tooltip: tr('更多颜色'),
            visualDensity: VisualDensity.compact,
            onPressed: () => unawaited(_showToolbarColorPalette(anchorContext)),
            icon: const Icon(Icons.palette_outlined),
          ),
        ),
        for (int index = 0; index < widths.length; index++)
          _widthButton(widths[index], index),
      ]),
    );
  }

  /// 把次要绘图工具收纳到菜单，选择后仍通过统一工具切换逻辑执行。
  Widget _moreDrawingToolsMenu() => PopupMenuButton<InkTool>(
    popUpAnimationStyle: appMotionStyle(context),
    tooltip: tr('更多工具'),
    icon: const Icon(Icons.more_horiz_rounded),
    onSelected: _selectTool,
    itemBuilder: (_) => <PopupMenuEntry<InkTool>>[
      for (final (InkTool tool, IconData icon, String label)
          in const <(InkTool, IconData, String)>[
            (InkTool.shape, Icons.category_outlined, '形状'),
            (InkTool.laser, Icons.flashlight_on_outlined, '激光笔'),
            (InkTool.text, Icons.text_fields_rounded, '文本'),
          ])
        PopupMenuItem<InkTool>(
          value: tool,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(icon),
            title: Text(tr(label)),
            trailing: _toolState.tool == tool
                ? const Icon(Icons.check_rounded, size: 18)
                : null,
          ),
        ),
    ],
  );
}
