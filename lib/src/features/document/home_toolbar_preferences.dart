part of '../../app/fastink_app.dart';

extension _FastInkToolbarPreferences on _FastInkHomeState {
  /// 统一工具控件组的背景、圆角和间隔，保证各工具栏区域视觉与命中尺寸一致。
  Widget _toolbarGroup(List<Widget> children) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(mainAxisSize: MainAxisSize.min, children: children),
      ),
    );
  }

  /// 根据当前配置获取可显示的快速颜色，缺失时使用合法默认颜色。
  List<Color> _compactColors() {
    final List<Color> result = _toolState.tool == InkTool.highlighter
        ? <Color>[
            const Color(0xffffc107),
            const Color(0xff8bc34a),
            const Color(0xffff6fae),
          ]
        : _settings.penColorPresets.map(Color.new).toList();
    if (_toolState.tool == InkTool.highlighter) return result;
    final Color contrast = _toolState.paperDark
        ? Colors.white
        : const Color(0xff202124);
    final int neutralSlot = result.indexWhere(_isNeutralInkColor);
    if (neutralSlot >= 0) {
      result[neutralSlot] = contrast;
    }
    return result;
  }

  /// 查找颜色在快速预设中的槽位；不属于预设时返回 null。
  int? _compactColorSlotIndex(Color color) {
    if (_toolState.tool != InkTool.pen) return null;
    final int neutralSlot = _settings.penColorPresets
        .map(Color.new)
        .toList()
        .indexWhere(_isNeutralInkColor);
    final Color contrast = _toolState.paperDark
        ? Colors.white
        : const Color(0xff202124);
    if (neutralSlot >= 0 && color.toARGB32() == contrast.toARGB32()) {
      return neutralSlot;
    }
    if (neutralSlot < 0 && color.toARGB32() == contrast.toARGB32()) {
      return null;
    }
    final int index = _settings.penColorPresets.indexWhere(
      (int item) => item == color.toARGB32(),
    );
    return index < 0 ? null : index;
  }

  /// 在工具栏锚点打开颜色编辑器，按槽位更新预设与当前工具颜色。
  Future<void> _showToolbarColorPalette(
    BuildContext anchorContext, {
    int? slotIndex,
  }) async {
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
    final Color? chosen = await showMenu<Color>(
      context: anchorContext,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(anchorRect.left, anchorRect.bottom + 4, 272, 0),
        Offset.zero & overlayObject.size,
      ),
      constraints: const BoxConstraints.tightFor(width: 272),
      items: <PopupMenuEntry<Color>>[
        _ColorPalettePopup(colors: _palette, selected: _toolState.color),
      ],
    );
    if (!mounted || chosen == null) return;
    final bool saveAsPenDefault = _toolState.tool == InkTool.pen;
    _updateState(() {
      _toolState.color = chosen;
      if (_toolState.tool == InkTool.pen) {
        _settings.penColor = chosen.toARGB32();
      }
      if (_toolState.tool == InkTool.highlighter) {
        _toolState.highlighterColor = chosen;
      }
      if (_toolState.tool == InkTool.text) _toolState.textColor = chosen;
      if (slotIndex != null &&
          slotIndex >= 0 &&
          slotIndex < _settings.penColorPresets.length) {
        _settings.penColorPresets[slotIndex] = chosen.toARGB32();
      }
    });
    if (slotIndex != null) await _persistPenColorPresets();
    if (saveAsPenDefault) await _setDefaultPenColor(chosen);
  }

  /// 返回当前笔类对应的快速宽度列表，普通笔与荧光笔分开读取。
  List<double> _compactWidths() {
    return List<double>.of(
      _toolState.tool == InkTool.highlighter
          ? _settings.highlighterWidthPresets
          : _settings.penWidthPresets,
    );
  }

  /// 显示颜色选择面板并把确认颜色传给调用方，取消不触发颜色修改。
  Future<void> _showColorPalette({
    int? slotIndex,
    bool penDefaults = false,
  }) async {
    await showDialog<void>(
      context: context,
      animationStyle: appMotionStyle(context),
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(tr('选择颜色')),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final Color color in _palette)
                Semantics(
                  button: true,
                  label:
                      '#${color.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () {
                      final bool saveAsPenDefault =
                          penDefaults || _toolState.tool == InkTool.pen;
                      _updateState(() {
                        if (!penDefaults || _toolState.tool == InkTool.pen) {
                          _toolState.color = color;
                        }
                        if (saveAsPenDefault) {
                          _settings.penColor = color.toARGB32();
                        }
                        if (!penDefaults &&
                            _toolState.tool == InkTool.highlighter) {
                          _toolState.highlighterColor = color;
                        }
                        if (!penDefaults && _toolState.tool == InkTool.text) {
                          _toolState.textColor = color;
                        }
                        if (slotIndex != null &&
                            slotIndex >= 0 &&
                            slotIndex < _settings.penColorPresets.length) {
                          _settings.penColorPresets[slotIndex] = color
                              .toARGB32();
                        }
                      });
                      if (slotIndex != null) {
                        unawaited(_persistPenColorPresets());
                      }
                      if (saveAsPenDefault) {
                        unawaited(_setDefaultPenColor(color));
                      }
                      Navigator.pop(dialogContext);
                    },
                    child: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color:
                              (penDefaults
                                      ? _settings.penColor
                                      : _toolState.color.toARGB32()) ==
                                  color.toARGB32()
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.outlineVariant,
                          width: 3,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
