part of '../../app/fastink_app.dart';

extension _FastInkSettingsUi on _FastInkHomeState {
  /// 按通用、手写、Markdown 分类构建设置卡片，分类入口固定，滚动状态按类别独立保存。
  Widget _settingsPanel() {
    final colors = Theme.of(context).colorScheme;
    final description = switch (_settingsCategory) {
      'ink' => tr(
        '用于手写笔记、PDF 批注和截图编辑。',
        'Applies to notes, PDF annotations and screenshot editing.',
      ),
      'markdown' => tr(
        '只影响 Markdown；与编辑器内的设置同步。',
        'Applies to Markdown only; shared with the editor settings.',
      ),
      _ => tr(
        '外观、语言与存储对整个软件生效。',
        'Appearance, language and storage apply to the whole app.',
      ),
    };
    final cards = switch (_settingsCategory) {
      'ink' => <Widget>[
        _penInputSettingsCard(),
        _penDefaultsSettingsCard(),
        _eraserSettingsCard(),
        _selectionSettingsCard(),
        _textPageSettingsCard(),
        _autoSaveSettingsCard(),
        _workflowSettingsCard(),
        _gesturePerformanceSettingsCard(),
        _importExportSettingsCard(),
        _laserSettingsCard(),
        _memoryStrategySettingsCard(),
      ],
      'markdown' => <Widget>[_markdownSettingsCard()],
      _ => <Widget>[
        _languageSettingsCard(),
        _appearanceSettingsCard(),
        _sharedInterfaceSettingsCard(),
        _storageSettingsCard(),
        if (Platform.isWindows) _contextMenuSettingsCard(),
        _aboutSettingsCard(),
      ],
    };
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 840),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 深入某个设置页面后，仍保留分类切换入口。
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final (id, icon, label) in [
                    ('general', Icons.settings_outlined, tr('通用', 'General')),
                    ('ink', Icons.draw_outlined, tr('手写笔记', 'Handwriting')),
                    ('markdown', Icons.edit_document, 'Markdown'),
                  ])
                    ChoiceChip(
                      key: ValueKey('settings-category-$id'),
                      avatar: Icon(icon, size: 18),
                      label: Text(label),
                      selected: _settingsCategory == id,
                      showCheckmark: false,
                      onSelected: (_) =>
                          _updateState(() => _settingsCategory = id),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
              child: Text(
                description,
                style: TextStyle(color: colors.onSurfaceVariant),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                key: PageStorageKey('settings-panel-$_settingsCategory'),
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                child: Column(
                  key: const ValueKey('settings-panel'),
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var index = 0; index < cards.length; index++) ...[
                      if (index > 0) const SizedBox(height: 14),
                      cards[index],
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建语言以外的共享界面选项，仅展示对整个应用真正生效的偏好。
  Widget _sharedInterfaceSettingsCard() => Card(
    child: Column(
      children: [
        SwitchListTile.adaptive(
          secondary: const Icon(Icons.info_outline_rounded),
          title: Text(tr('显示工具提示', 'Show tooltips')),
          subtitle: Text(
            tr(
              '鼠标悬停后显示按钮说明和快捷键',
              'Show button descriptions and shortcuts while hovering',
            ),
          ),
          value: _settings.tooltipsEnabled,
          onChanged: _setTooltipsEnabled,
        ),
        SwitchListTile.adaptive(
          secondary: const Icon(Icons.view_agenda_outlined),
          title: Text(tr('显示资料库状态栏', 'Show library status bar')),
          subtitle: Text(
            tr('显示保存、导入和错误状态', 'Show save, import, and error status'),
          ),
          value: _settings.showLibraryStatusBar,
          onChanged: _setShowLibraryStatusBar,
        ),
      ],
    ),
  );
}
