part of '../../app/fastink_app.dart';

extension _FastInkWorkflowSettingsCards on _FastInkHomeState {
  /// 构建打开文稿、侧栏和默认工具等工作流偏好，明确它们的默认行为作用域。
  Widget _workflowSettingsCard() {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.tune_rounded),
              title: Text(
                tr('手写工作区', 'Handwriting workspace'),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                tr(
                  '这里的选项会立即作用于当前界面，并作为以后打开文稿的默认值',
                  'Changes apply to the current UI immediately and become the default for future documents',
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.pan_tool_alt_outlined),
              title: Text(tr('默认工具', 'Default tool')),
              trailing: DropdownButtonHideUnderline(
                child: DropdownButton<InkTool>(
                  value: InkTool.values.firstWhere(
                    (v) => v.name == _settings.defaultTool,
                    orElse: () => InkTool.pen,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  onChanged: (InkTool? value) {
                    if (value != null) unawaited(_setDefaultTool(value));
                  },
                  items:
                      <(InkTool, IconData, String)>[
                            (InkTool.pen, Icons.edit_rounded, '钢笔'),
                            (
                              InkTool.highlighter,
                              Icons.border_color_rounded,
                              '荧光笔',
                            ),
                            (
                              InkTool.eraser,
                              Icons.auto_fix_normal_rounded,
                              '橡皮擦',
                            ),
                            (InkTool.lasso, Icons.select_all_rounded, '框选'),
                            (InkTool.shape, Icons.category_outlined, '形状'),
                            (
                              InkTool.laser,
                              Icons.flashlight_on_outlined,
                              '激光笔',
                            ),
                            (InkTool.text, Icons.text_fields_rounded, '文本'),
                          ]
                          .map(
                            (item) => DropdownMenuItem<InkTool>(
                              value: item.$1,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  Icon(item.$2, size: 18),
                                  const SizedBox(width: 8),
                                  Text(tr(item.$3)),
                                ],
                              ),
                            ),
                          )
                          .toList(),
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.fit_screen_rounded),
              title: Text(tr('文稿默认显示比例', 'Default document fit')),
              subtitle: Text(
                tr(
                  '“适合宽度”会让页面与展开的侧栏充分利用窗口',
                  'Fit width uses the window efficiently alongside the open sidebar',
                ),
              ),
              trailing: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _settings.defaultPageFit,
                  borderRadius: BorderRadius.circular(12),
                  onChanged: (String? value) {
                    if (value != null) unawaited(_setDefaultPageFit(value));
                  },
                  items: <DropdownMenuItem<String>>[
                    DropdownMenuItem(
                      value: 'width',
                      child: Text(tr('适合宽度', 'Fit width')),
                    ),
                    DropdownMenuItem(
                      value: 'page',
                      child: Text(tr('适合整页', 'Fit page')),
                    ),
                  ],
                ),
              ),
            ),
            SwitchListTile.adaptive(
              secondary: const Icon(Icons.compress_rounded),
              title: Text(tr('紧凑工具栏', 'Compact toolbar')),
              subtitle: Text(
                tr(
                  '把形状、激光笔和文本收进“更多”，给页面留出更多宽度',
                  'Move Shapes, Laser, and Text into More to leave extra room for the page',
                ),
              ),
              value: _settings.compactToolbar,
              onChanged: _setCompactToolbar,
            ),
            SwitchListTile.adaptive(
              secondary: const Icon(Icons.view_sidebar_outlined),
              title: Text(
                tr('打开文稿时显示页面侧栏', 'Show page sidebar when opening a document'),
              ),
              subtitle: Text(
                tr('修改后当前文稿也会立即同步', 'The current document updates immediately'),
              ),
              value: _settings.openSidebarByDefault,
              onChanged: _setOpenSidebarByDefault,
            ),
            SwitchListTile.adaptive(
              secondary: const Icon(Icons.visibility_outlined),
              title: Text(tr('默认以只读模式打开', 'Open in read-only mode by default')),
              subtitle: Text(
                tr(
                  '适合主要用于阅读和批注检查的文稿',
                  'Useful for documents mainly opened for reading or review',
                ),
              ),
              value: _settings.defaultReadOnly,
              onChanged: _setDefaultReadOnly,
            ),
            ListTile(
              leading: const Icon(Icons.tab_rounded),
              title: Text(tr('侧栏默认标签', 'Default sidebar tab')),
              trailing: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  value: _settings.defaultSidebarTab,
                  borderRadius: BorderRadius.circular(12),
                  onChanged: (int? value) {
                    if (value != null) unawaited(_setDefaultSidebarTab(value));
                  },
                  items: <DropdownMenuItem<int>>[
                    DropdownMenuItem(value: 0, child: Text(tr('页面'))),
                    DropdownMenuItem(value: 1, child: Text(tr('目录'))),
                    DropdownMenuItem(value: 2, child: Text(tr('书签'))),
                  ],
                ),
              ),
            ),
            SwitchListTile.adaptive(
              secondary: Icon(Icons.delete_sweep_outlined, color: colors.error),
              title: Text(
                tr('清空当前页前确认', 'Confirm before clearing current page'),
              ),
              subtitle: Text(
                tr(
                  '避免从“更多笔迹操作”中误清空整页',
                  'Prevents accidental clearing from More ink actions',
                ),
              ),
              value: _settings.confirmClearInk,
              onChanged: _setConfirmClearInk,
            ),
          ],
        ),
      ),
    );
  }
}
