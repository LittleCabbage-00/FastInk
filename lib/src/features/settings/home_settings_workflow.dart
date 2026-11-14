part of '../../app/fastink_app.dart';

/// 文稿工作区设置。修改当前状态后写入配置文件。
extension _FastInkWorkflowSettings on _FastInkHomeState {
  /// 更新独立 Markdown 配置并保存，编辑器与设置面板共享这一快照，手写设置不变。
  Future<void> _setMarkdownPreferences(MarkdownPreferences next) async {
    _updateState(() => _settings.markdown = next);
    await _settingsRepository.update(
      (current) => current.copyWith(markdown: next),
    );
  }

  /// 在独立卡片中挂载共用 Markdown 设置面板，避免与手写选项混排。
  Widget _markdownSettingsCard() => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: MarkdownSettingsPanel(
        value: _settings.markdown,
        onChanged: _setMarkdownPreferences,
      ),
    ),
  );

  /// 在统一配置更新队列中保存工作流快照，避免多个局部设置互相覆盖。
  Future<void> _saveWorkflowSettings(
    AppSettings Function(AppSettings) update,
  ) => _settingsRepository.update(update);

  /// 同步当前工具提示显示并保存偏好，已挂载控件由根通知器更新。
  Future<void> _setTooltipsEnabled(bool value) async {
    _updateState(() => _settings.tooltipsEnabled = value);
    widget.onTooltipsChanged?.call(value);
    await _saveWorkflowSettings(
      (current) => current.copyWith(tooltipsEnabled: value),
    );
  }

  /// 更新紧凑工具栏偏好并保存，工具功能保持不变。
  Future<void> _setCompactToolbar(bool value) async {
    _updateState(() => _settings.compactToolbar = value);
    await _saveWorkflowSettings(
      (current) => current.copyWith(compactToolbar: value),
    );
  }

  /// 保存以后打开文稿时的侧栏默认值，不伪装成当前页内容修改。
  Future<void> _setOpenSidebarByDefault(bool value) async {
    _updateState(() {
      _settings.openSidebarByDefault = value;
      _showPageSidebar = value;
    });
    await _saveWorkflowSettings(
      (current) => current.copyWith(openSidebarByDefault: value),
    );
  }

  /// 保存新打开文稿的默认只读状态，不改变文件系统权限。
  Future<void> _setDefaultReadOnly(bool value) async {
    _updateState(() {
      _settings.defaultReadOnly = value;
      if (_doc.document != null) _doc.readOnly = value;
    });
    await _saveWorkflowSettings(
      (current) => current.copyWith(defaultReadOnly: value),
    );
  }

  /// 保存清空笔迹前确认偏好，实际清空仍走历史事务。
  Future<void> _setConfirmClearInk(bool value) async {
    _updateState(() => _settings.confirmClearInk = value);
    await _saveWorkflowSettings(
      (current) => current.copyWith(confirmClearInk: value),
    );
  }

  /// 更新资料库状态栏可见性并持久化。
  Future<void> _setShowLibraryStatusBar(bool value) async {
    _updateState(() => _settings.showLibraryStatusBar = value);
    await _saveWorkflowSettings(
      (current) => current.copyWith(showLibraryStatusBar: value),
    );
  }

  /// 保存打开文稿时的初始侧栏页签，校验有效编号再应用。
  Future<void> _setDefaultSidebarTab(int value) async {
    final int next = value.clamp(0, 2);
    _updateState(() {
      _settings.defaultSidebarTab = next;
      _sidebarTab = next;
    });
    await _saveWorkflowSettings(
      (current) => current.copyWith(defaultSidebarTab: next),
    );
  }

  /// 保存打开文稿的默认工具，当前侧键临时工具不写回此值。
  Future<void> _setDefaultTool(InkTool value) async {
    // 默认工具只在这里修改，工具栏切换保留当前文稿的临时选择。
    _settings.defaultTool = value.name;
    _selectTool(value);
    await _saveWorkflowSettings(
      (current) => current.copyWith(defaultTool: value.name),
    );
  }

  /// 保存新文稿的默认适配方式，并按既有运行时约束同步显示。
  Future<void> _setDefaultPageFit(String value) async {
    final String next = value == 'page' ? 'page' : 'width';
    _updateState(() => _settings.defaultPageFit = next);
    _applyDefaultPageFit();
    await _saveWorkflowSettings(
      (current) => current.copyWith(defaultPageFit: next),
    );
  }
}
