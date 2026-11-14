part of '../../app/fastink_app.dart';

extension _FastInkBehaviorSettingsCards on _FastInkHomeState {
  /// 构建新文字默认字号与页面显示选项，说明作用于后续操作而非重写旧对象。
  Widget _textPageSettingsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.text_fields_rounded),
              title: Text(
                tr('文本与页面显示'),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                tr(
                  '默认文字大小 ${_settings.defaultTextSize.round()} px；文本会直接在文档内原位编辑',
                  'Default text size ${_settings.defaultTextSize.round()} px; text is edited directly on the page',
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.format_size_rounded),
              title: Text(tr('默认文字大小')),
              subtitle: Slider(
                value: _settings.defaultTextSize.clamp(1, 72),
                min: 1,
                max: 72,
                divisions: 71,
                label: '${_settings.defaultTextSize.round()} px',
                onChanged: (double value) =>
                    _updateState(() => _settings.defaultTextSize = value),
                onChangeEnd: _setDefaultTextSize,
              ),
            ),
            SwitchListTile.adaptive(
              secondary: const Icon(Icons.pin_outlined),
              title: Text(tr('显示页码角标')),
              subtitle: Text(tr('在文档页面右下角显示当前页码')),
              value: _settings.showPageNumber,
              onChanged: _setShowPageNumber,
            ),
          ],
        ),
      ),
    );
  }

  /// 构建手写自动保存开关，关闭不取消切页/离开时补存；重新开启时处理待保存内容。
  Widget _autoSaveSettingsCard() {
    return Card(
      child: Column(
        children: <Widget>[
          SwitchListTile.adaptive(
            secondary: const Icon(Icons.save_outlined),
            title: Text(
              tr('自动保存'),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              _settings.autoSaveEnabled
                  ? tr(
                      '书写结束后自动保存手写笔记与 PDF 批注',
                      'Automatically save handwriting and PDF annotations after writing',
                    )
                  : tr(
                      '关闭后仍会在切页、切后台、退出和切换文稿前补存',
                      'Changes are still saved before page changes, backgrounding, exit, or document switches',
                    ),
            ),
            value: _settings.autoSaveEnabled,
            onChanged: _setAutoSaveEnabled,
          ),
        ],
      ),
    );
  }

  /// 构建套索形状、命中优先和对象类型等选择设置。
  Widget _selectionSettingsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: <Widget>[
            ListTile(
              key: const ValueKey('settings-lasso-shape'),
              leading: const Icon(Icons.gesture_rounded),
              title: Text(tr('默认框选形状', 'Default selection shape')),
              subtitle: Text(
                tr(
                  '与工具栏的自由套索、矩形框选同步保存',
                  'Shares the saved Freehand or Rectangle choice with the toolbar',
                ),
              ),
              trailing: DropdownButtonHideUnderline(
                child: DropdownButton<LassoShape>(
                  value: LassoShape.values.firstWhere(
                    (s) => s.name == _settings.lassoShape,
                  ),
                  onChanged: (value) {
                    if (value != null) unawaited(_setLassoShape(value));
                  },
                  items: [
                    DropdownMenuItem(
                      value: LassoShape.freehand,
                      child: Text(tr('自由套索', 'Freehand')),
                    ),
                    DropdownMenuItem(
                      value: LassoShape.rectangle,
                      child: Text(tr('矩形框选', 'Rectangle')),
                    ),
                  ],
                ),
              ),
            ),
            SwitchListTile.adaptive(
              secondary: const Icon(Icons.ads_click_outlined),
              title: Text(
                tr('选区手柄优先'),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(tr('点击旋转/缩放手柄时优先执行选区操作，不会误落成笔迹')),
              value: _settings.selectionPriority,
              onChanged: _setSelectionPriority,
            ),
            ListTile(
              leading: const Icon(Icons.open_with_rounded),
              title: Text(tr('手柄命中范围')),
              subtitle: Slider(
                value: _settings.selectionHitRadius,
                min: 32,
                max: 96,
                divisions: 16,
                label: '${_settings.selectionHitRadius.round()} px',
                onChanged: (double value) =>
                    _updateState(() => _settings.selectionHitRadius = value),
                onChangeEnd: _setSelectionHitRadius,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建界面外观选项，当前选中模式明确显示并委托根组件保存。
  Widget _appearanceSettingsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: <Widget>[
            const Icon(Icons.palette_outlined),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    tr('外观'),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 3),
                  Text(tr('跟随系统、浅色或深色模式')),
                ],
              ),
            ),
            _themeMenu(compact: true),
          ],
        ),
      ),
    );
  }
}
