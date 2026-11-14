part of '../../app/fastink_app.dart';

extension _FastInkLassoControls on _FastInkHomeState {
  /// 构建套索形状与对象类型过滤设置，变更后影响后续选择而非直接修改已有内容。
  Widget _lassoToolMenu() {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return MenuAnchor(
      menuChildren: <Widget>[
        for (final (
              String label,
              String english,
              bool value,
              ValueChanged<bool> change,
            )
            in <(String, String, bool, ValueChanged<bool>)>[
              (
                '手写笔迹',
                'Handwriting',
                _ink.selectHandwriting,
                (value) => _ink.selectHandwriting = value,
              ),
              (
                '荧光笔',
                'Highlighter',
                _ink.selectHighlighter,
                (value) => _ink.selectHighlighter = value,
              ),
              (
                '文字',
                'Text',
                _ink.selectText,
                (value) => _ink.selectText = value,
              ),
              (
                '图片',
                'Images',
                _ink.selectImages,
                (value) => _ink.selectImages = value,
              ),
            ])
          CheckboxMenuButton(
            value: value,
            closeOnActivate: false,
            onChanged: (value) => _updateState(() {
              change(value ?? true);
              _ink.clearSelection();
            }),
            child: Text(tr(label, english)),
          ),
        const Divider(),
        for (final (
              LassoShape shape,
              IconData icon,
              String label,
              String english,
            )
            in const <(LassoShape, IconData, String, String)>[
              (
                LassoShape.freehand,
                Icons.gesture_rounded,
                '自由套索',
                'Freehand lasso',
              ),
              (
                LassoShape.rectangle,
                Icons.crop_square_rounded,
                '矩形框选',
                'Rectangle lasso',
              ),
            ])
          MenuItemButton(
            leadingIcon: Icon(icon),
            trailingIcon: shape.name == _settings.lassoShape
                ? const Icon(Icons.check_rounded, size: 18)
                : null,
            onPressed: () => unawaited(_setLassoShape(shape)),
            child: Text(tr(label, english)),
          ),
      ],
      builder:
          (BuildContext context, MenuController controller, Widget? child) {
            return Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Tooltip(
                message: _toolState.tool == InkTool.lasso
                    ? tr(
                        '再点一次切换自由套索或矩形框选',
                        'Click again to change the lasso shape',
                      )
                    : tr(
                        '选择笔迹；再次点击可切换选区形状',
                        'Select ink; click again to change the lasso shape',
                      ),
                child: _compactToolIcons
                    ? IconButton(
                        isSelected: _toolState.tool == InkTool.lasso,
                        icon: Icon(
                          _settings.lassoShape == 'rectangle'
                              ? Icons.crop_square_rounded
                              : Icons.gesture_rounded,
                          size: 20,
                        ),
                        onPressed: () {
                          if (_toolState.tool != InkTool.lasso) {
                            _selectTool(InkTool.lasso);
                          } else if (controller.isOpen) {
                            controller.close();
                          } else {
                            controller.open();
                          }
                        },
                      )
                    : ChoiceChip(
                        avatar: Icon(
                          _settings.lassoShape == 'rectangle'
                              ? Icons.crop_square_rounded
                              : Icons.gesture_rounded,
                          size: 18,
                        ),
                        label: Text(tr('选择')),
                        selected: _toolState.tool == InkTool.lasso,
                        selectedColor: colors.secondaryContainer,
                        onSelected: (_) {
                          if (_toolState.tool != InkTool.lasso) {
                            _selectTool(InkTool.lasso);
                          } else if (controller.isOpen) {
                            controller.close();
                          } else {
                            controller.open();
                          }
                        },
                      ),
              ),
            );
          },
    );
  }

  /// lassoShape：自由套索或矩形套索的名称。
  Future<void> _setLassoShape(LassoShape value) async {
    _updateState(() => _settings.lassoShape = value.name);
    await _settings.saveString('lassoShape', value.name);
  }
}
