part of '../../app/fastink_app.dart';

extension _FastInkTextControls on _FastInkHomeState {
  /// 输入面板存在时返回当前编辑字号，否则返回新文字默认字号。
  double get _currentTextSize =>
      _inlineTextPoint != null ? _inlineTextSize : _settings.defaultTextSize;

  /// 创建文字字号、字体、粗斜体和对齐控件，区分默认值与当前编辑值。
  Widget _textToolOptions() {
    const List<String> fonts = <String>[
      'Segoe UI Variable',
      'Microsoft YaHei UI',
      'Arial',
      'Calibri',
      'Times New Roman',
      'Consolas',
    ];
    return KeyedSubtree(
      key: const ValueKey<String>('text-options'),
      child: _toolbarGroup(<Widget>[
        PopupMenuButton<String>(
          popUpAnimationStyle: appMotionStyle(context),
          tooltip: tr('字体'),
          onSelected: (String value) =>
              _updateState(() => _toolState.textFontFamily = value),
          itemBuilder: (_) => <PopupMenuEntry<String>>[
            for (final String font in fonts)
              PopupMenuItem<String>(
                value: font,
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(font, style: TextStyle(fontFamily: font)),
                    ),
                    if (font == _toolState.textFontFamily)
                      const Icon(Icons.check_rounded, size: 18),
                  ],
                ),
              ),
          ],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  _toolState.textFontFamily == 'Segoe UI Variable'
                      ? tr('系统字体')
                      : _toolState.textFontFamily,
                  style: TextStyle(fontFamily: _toolState.textFontFamily),
                ),
                const Icon(Icons.arrow_drop_down_rounded, size: 18),
              ],
            ),
          ),
        ),
        IconButton(
          tooltip: tr('减小字号'),
          visualDensity: VisualDensity.compact,
          onPressed: _currentTextSize <= 1
              ? null
              : () => _updateState(() {
                  _settings.defaultTextSize = (_currentTextSize - 1).clamp(
                    1,
                    512,
                  );
                  _inlineTextSize = _settings.defaultTextSize;
                }),
          icon: const Icon(Icons.remove_rounded, size: 18),
        ),
        PopupMenuButton<double>(
          popUpAnimationStyle: appMotionStyle(context),
          tooltip: tr('字号'),
          onSelected: (double value) {
            if (value == -1) {
              unawaited(_customTextSize());
              return;
            }
            _updateState(() {
              _settings.defaultTextSize = value;
              _inlineTextSize = value;
            });
          },
          itemBuilder: (_) => <PopupMenuEntry<double>>[
            PopupMenuItem<double>(
              value: -1,
              child: Text(tr('自定义字号…', 'Custom font size…')),
            ),
            for (final double size in const <double>[
              12,
              16,
              20,
              24,
              28,
              32,
              40,
              48,
              64,
              72,
            ])
              PopupMenuItem<double>(
                value: size,
                child: Row(
                  children: <Widget>[
                    Expanded(child: Text('${size.round()} pt')),
                    if ((_currentTextSize - size).abs() < 0.1)
                      const Icon(Icons.check_rounded, size: 18),
                  ],
                ),
              ),
          ],
          child: SizedBox(
            width: 38,
            child: Text(
              _currentTextSize.toStringAsFixed(
                _currentTextSize % 1 == 0 ? 0 : 1,
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
        IconButton(
          tooltip: tr('增大字号'),
          visualDensity: VisualDensity.compact,
          onPressed: _currentTextSize >= 512
              ? null
              : () => _updateState(() {
                  _settings.defaultTextSize = (_currentTextSize + 1).clamp(
                    1,
                    512,
                  );
                  _inlineTextSize = _settings.defaultTextSize;
                }),
          icon: const Icon(Icons.add_rounded, size: 18),
        ),
        _textFormatButton(
          tooltip: tr('粗体（Ctrl+B）'),
          label: 'B',
          selected: _toolState.textBold,
          onPressed: () =>
              _updateState(() => _toolState.textBold = !_toolState.textBold),
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        _textFormatButton(
          tooltip: tr('斜体（Ctrl+I）'),
          label: 'I',
          selected: _toolState.textItalic,
          onPressed: () => _updateState(
            () => _toolState.textItalic = !_toolState.textItalic,
          ),
          style: const TextStyle(fontStyle: FontStyle.italic),
        ),
        _textFormatButton(
          tooltip: tr('下划线（Ctrl+U）'),
          label: 'U',
          selected: _toolState.textUnderline,
          onPressed: () => _updateState(
            () => _toolState.textUnderline = !_toolState.textUnderline,
          ),
          style: const TextStyle(decoration: TextDecoration.underline),
        ),
        PopupMenuButton<TextAlign>(
          popUpAnimationStyle: appMotionStyle(context),
          tooltip: tr('对齐方式'),
          icon: Icon(switch (_toolState.textAlign) {
            TextAlign.center => Icons.format_align_center_rounded,
            TextAlign.right => Icons.format_align_right_rounded,
            _ => Icons.format_align_left_rounded,
          }),
          onSelected: (TextAlign value) =>
              _updateState(() => _toolState.textAlign = value),
          itemBuilder: (_) => <PopupMenuEntry<TextAlign>>[
            PopupMenuItem(
              value: TextAlign.left,
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.format_align_left_rounded),
                title: Text(tr('左对齐')),
              ),
            ),
            PopupMenuItem(
              value: TextAlign.center,
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.format_align_center_rounded),
                title: Text(tr('居中')),
              ),
            ),
            PopupMenuItem(
              value: TextAlign.right,
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.format_align_right_rounded),
                title: Text(tr('右对齐')),
              ),
            ),
          ],
        ),
        Builder(
          builder: (BuildContext anchorContext) => IconButton(
            tooltip: tr('文字颜色'),
            onPressed: () => unawaited(_showToolbarColorPalette(anchorContext)),
            icon: DecoratedBox(
              decoration: BoxDecoration(
                color: _toolState.textColor,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white70, width: 1.5),
              ),
              child: const SizedBox(width: 19, height: 19),
            ),
          ),
        ),
        IconButton(
          tooltip: tr(_toolState.textToolPinned ? '取消连续插入文本框' : '固定文本工具，连续插入'),
          isSelected: _toolState.textToolPinned,
          onPressed: () => _updateState(
            () => _toolState.textToolPinned = !_toolState.textToolPinned,
          ),
          icon: const Icon(Icons.push_pin_outlined),
          selectedIcon: const Icon(Icons.push_pin_rounded),
        ),
      ]),
    );
  }

  /// 创建具有明确选中状态的文本格式按钮，点击只切换对应样式。
  Widget _textFormatButton({
    required String tooltip,
    required String label,
    required bool selected,
    required VoidCallback onPressed,
    required TextStyle style,
  }) => IconButton(
    tooltip: tooltip,
    visualDensity: VisualDensity.compact,
    isSelected: selected,
    onPressed: onPressed,
    icon: Text(label, style: style),
    selectedIcon: DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Text(label, style: style),
      ),
    ),
  );
}
