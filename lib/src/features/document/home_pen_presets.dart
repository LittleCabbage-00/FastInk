part of '../../app/fastink_app.dart';

extension _FastInkPenPresets on _FastInkHomeState {
  /// 创建快速颜色按钮，选中状态来自当前工具颜色；点击可选择或编辑对应颜色槽。
  Widget _colorButton(Color color) {
    final bool selected = _toolState.color.toARGB32() == color.toARGB32();
    return Builder(
      builder: (BuildContext anchorContext) => Tooltip(
        message:
            '#${color.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () {
            if (selected) {
              final int? slotIndex = _compactColorSlotIndex(color);
              unawaited(
                _showToolbarColorPalette(anchorContext, slotIndex: slotIndex),
              );
              return;
            }
            _updateState(() {
              _toolState.color = color;
              if (_toolState.tool == InkTool.eraser) {
                _toolState.tool = _toolState.lastInkTool;
              }
              if (_toolState.tool == InkTool.pen) {
                _settings.penColor = color.toARGB32();
              } else if (_toolState.tool == InkTool.highlighter) {
                _toolState.highlighterColor = color;
              } else if (_toolState.tool == InkTool.text) {
                _toolState.textColor = color;
              }
            });
            if (_toolState.tool == InkTool.pen) {
              unawaited(_setDefaultPenColor(color));
            }
          },
          child: Container(
            width: 32,
            height: 32,
            margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? const Color(0xff9da7ff) : Colors.white38,
                width: selected ? 3 : 1,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 创建普通笔/荧光笔的快速宽度按钮，标明当前选择并保留可见粗细预览。
  Widget _widthButton(double width, int presetIndex) {
    final bool selected = (_toolState.width - width).abs() < 0.1;
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 7),
      child: Tooltip(
        message: selected
            ? tr('再次点击，自定义这一档粗细', 'Click again to customize this width')
            : tr('选择这一档粗细', 'Select this width'),
        child: Builder(
          builder: (BuildContext anchorContext) => ChoiceChip(
            key: ValueKey('width-preset-$presetIndex'),
            selected: selected,
            showCheckmark: false,
            selectedColor: colors.secondaryContainer,
            label: Text(
              width == width.roundToDouble()
                  ? '${width.round()}'
                  : width.toStringAsFixed(1),
            ),
            avatar: Container(
              key: ValueKey('width-preview-$presetIndex'),
              width: (width + 2).clamp(3, 18),
              height: (width + 2).clamp(3, 18),
              decoration: BoxDecoration(
                // 此处表示粗细，相邻颜色按钮表示笔迹颜色；
                // 即使选中黑色笔迹，也要在深色工具栏上清晰可见。
                color: selected
                    ? colors.onSecondaryContainer
                    : colors.onSurface,
                shape: BoxShape.circle,
              ),
            ),
            onSelected: (_) {
              if (selected) {
                unawaited(
                  _showWidthPresetEditor(
                    anchorContext,
                    presetIndex,
                    highlighter: _toolState.tool == InkTool.highlighter,
                  ),
                );
                return;
              }
              _selectWidthPreset(
                width,
                highlighter: _toolState.tool == InkTool.highlighter,
              );
            },
          ),
        ),
      ),
    );
  }

  /// 选择或更新指定宽度槽，分别维护普通笔与荧光笔预设并保存设置。
  Future<void> _selectWidthPreset(
    double width, {
    required bool highlighter,
  }) async {
    _updateState(() {
      _toolState.width = width;
      if (highlighter) {
        _settings.highlighterWidth = width;
      } else {
        _settings.penWidth = width;
      }
    });
    await _settingsRepository.update(
      (current) => highlighter
          ? current.copyWith(highlighterWidth: width)
          : current.copyWith(penWidth: width),
    );
  }

  /// 打开自定义笔宽编辑，校验有效范围后更新指定槽位，取消保持原值。
  Future<void> _showWidthPresetEditor(
    BuildContext anchorContext,
    int presetIndex, {
    required bool highlighter,
  }) async {
    final List<double> presets = highlighter
        ? _settings.highlighterWidthPresets
        : _settings.penWidthPresets;
    if (presetIndex < 0 || presetIndex >= presets.length) return;
    final double minimum = highlighter ? 4 : 0.5;
    final double maximum = highlighter ? 48 : 24;
    double value = presets[presetIndex];
    final RenderObject? anchorObject = anchorContext.findRenderObject();
    final OverlayState? overlayState = Overlay.maybeOf(anchorContext);
    final RenderObject? overlayObject = overlayState?.context
        .findRenderObject();
    if (anchorObject is! RenderBox || overlayObject is! RenderBox) return;
    final Offset anchorOffset = anchorObject.localToGlobal(
      Offset.zero,
      ancestor: overlayObject,
    );
    final Rect anchorRect = anchorOffset & anchorObject.size;
    await showMenu<double>(
      context: anchorContext,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(
          anchorRect.left,
          anchorRect.bottom + 4,
          math.max(anchorRect.width, 270),
          0,
        ),
        Offset.zero & overlayObject.size,
      ),
      constraints: const BoxConstraints.tightFor(width: 270),
      items: <PopupMenuEntry<double>>[
        _WidthPresetPopup(
          initialValue: value,
          minimum: minimum,
          maximum: maximum,
          divisions: highlighter ? 44 : 47,
          color: Theme.of(context).colorScheme.onSurface,
          onChanged: (double next) => value = next,
        ),
      ],
    );
    if (!mounted || (value - presets[presetIndex]).abs() < 0.001) return;
    final List<double> updated = List<double>.of(presets);
    updated[presetIndex] = value;
    updated.sort();
    _updateState(() {
      if (highlighter) {
        _settings.highlighterWidthPresets = updated;
        _settings.highlighterWidth = value;
      } else {
        _settings.penWidthPresets = updated;
        _settings.penWidth = value;
      }
      if ((_toolState.tool == InkTool.highlighter) == highlighter) {
        _toolState.width = value;
      }
    });
    await _settingsRepository.update(
      (current) => highlighter
          ? current.copyWith(
              highlighterWidth: value,
              highlighterWidthPresets: updated,
            )
          : current.copyWith(penWidth: value, penWidthPresets: updated),
    );
  }
}
