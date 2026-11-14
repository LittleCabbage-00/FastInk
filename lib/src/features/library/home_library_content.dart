part of '../../app/fastink_app.dart';

extension _FastInkLibraryContent on _FastInkHomeState {
  /// 构建资料库标题、搜索/新建入口、状态栏和内容，窗口宽度只改变布局，不取消主要操作。
  Widget _libraryMain({required bool compact}) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final String heading = switch (_librarySection) {
      'favorites' => tr('收藏'),
      'recent' => tr('最近查看'),
      'trash' => tr('废纸篓'),
      'settings' => tr('设置'),
      'markdown' => tr('Markdown 文档'),
      _ => tr('文稿'),
    };
    return Column(
      children: <Widget>[
        Container(
          key: const ValueKey('library-header'),
          height: _librarySection == 'settings'
              ? 72
              : compact
              ? 120
              : 80,
          padding: EdgeInsets.symmetric(horizontal: compact ? 14 : 24),
          color: colors.surfaceContainerLowest,
          child: compact
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Builder(
                          builder: (BuildContext buttonContext) => IconButton(
                            tooltip: tr('打开资料库导航'),
                            onPressed: () =>
                                Scaffold.of(buttonContext).openDrawer(),
                            icon: const Icon(Icons.menu_rounded),
                          ),
                        ),
                        Expanded(
                          child: _libraryHeading(
                            heading,
                            colors,
                            compact: true,
                          ),
                        ),
                        if (_librarySection == 'trash')
                          IconButton(
                            tooltip: tr('清空废纸篓'),
                            onPressed: _emptyTrash,
                            icon: const Icon(Icons.delete_forever_outlined),
                          ),
                        if (_librarySection != 'settings' &&
                            _librarySection != 'trash')
                          _newLibraryMenu(colors, compact: true),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (_librarySection != 'settings')
                      Row(
                        children: <Widget>[
                          Expanded(child: _librarySearch(colors)),
                          if (_librarySection == 'markdown') ...<Widget>[
                            const SizedBox(width: 8),
                            IconButton.filledTonal(
                              tooltip: tr('打开外部 Markdown 文件'),
                              onPressed: _openMarkdownFromFile,
                              icon: const Icon(Icons.folder_open_rounded),
                            ),
                          ],
                        ],
                      ),
                  ],
                )
              : Row(
                  children: <Widget>[
                    _libraryHeading(heading, colors),
                    if (_librarySection != 'settings') ...<Widget>[
                      const SizedBox(width: 24),
                      Expanded(child: _librarySearch(colors)),
                      const SizedBox(width: 12),
                      if (_librarySection == 'trash')
                        OutlinedButton.icon(
                          onPressed: _emptyTrash,
                          icon: const Icon(Icons.delete_forever_outlined),
                          label: Text(tr('清空废纸篓')),
                        )
                      else if (_librarySection == 'markdown')
                        OutlinedButton.icon(
                          onPressed: _openMarkdownFromFile,
                          icon: const Icon(Icons.folder_open_rounded),
                          label: Text(tr('打开外部文件')),
                        ),
                      if (_librarySection != 'trash') ...<Widget>[
                        const SizedBox(width: 10),
                        _newLibraryMenu(colors),
                      ],
                    ],
                  ],
                ),
        ),
        if (_settings.showLibraryStatusBar)
          Container(
            height: 34,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 32),
            color: colors.surface,
            child: Text(
              _doc.status,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color:
                    _doc.status.contains('失败') ||
                        _doc.status.toLowerCase().contains('failed')
                    ? colors.error
                    : colors.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          ),
        Expanded(
          child: AnimatedSwitcher(
            duration: appMotionDuration(context, 180),
            child: _librarySection == 'settings'
                ? _settingsPanel()
                : KeyedSubtree(
                    // 搜索只更新现有列表，不为每个字符创建一棵退场界面。
                    key: ValueKey<String>('library-browser-$_librarySection'),
                    child: _libraryBrowser(),
                  ),
          ),
        ),
      ],
    );
  }

  /// 使用统一标题样式和省略策略显示类别名称，完整索引标题仍保留。
  Widget _libraryHeading(
    String heading,
    ColorScheme colors, {
    bool compact = false,
  }) => Text(
    heading,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: TextStyle(
      color: colors.onSurface,
      fontSize: compact ? 22 : 26,
      fontWeight: FontWeight.w700,
    ),
  );

  /// 绑定资料库搜索控制器与焦点，提供清除查询入口；正文文稿搜索由另一窗口处理。
  Widget _librarySearch(ColorScheme colors) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 420),
    child: TextField(
      key: const ValueKey('library-search'),
      controller: _searchInput,
      focusNode: _librarySearchFocus,
      style: TextStyle(color: colors.onSurface),
      decoration: InputDecoration(
        hintText: tr('搜索文稿'),
        hintStyle: TextStyle(color: colors.onSurfaceVariant),
        prefixIcon: Icon(Icons.search_rounded, color: colors.onSurfaceVariant),
        suffixIcon: _searchInput.text.isEmpty
            ? null
            : IconButton(
                key: const ValueKey('clear-library-search'),
                tooltip: tr('清除搜索', 'Clear search'),
                onPressed: _searchInput.clear,
                icon: const Icon(Icons.close_rounded, size: 18),
              ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        filled: true,
        fillColor: colors.surfaceContainerHighest,
        border: OutlineInputBorder(
          borderSide: BorderSide.none,
          borderRadius: BorderRadius.circular(12),
        ),
        isDense: true,
      ),
    ),
  );

  /// 显示指定逻辑侧键的动作选择，修改通过统一映射与持久化入口执行。
  Widget _penButtonActionTile({
    required int logicalButton,
    required PenButtonAction action,
  }) {
    return ListTile(
      leading: CircleAvatar(radius: 15, child: Text('$logicalButton')),
      title: Text(
        tr(
          logicalButton == 1 ? '一键动作' : '二键动作',
          logicalButton == 1 ? 'Button 1 action' : 'Button 2 action',
        ),
      ),
      subtitle: DropdownButtonHideUnderline(
        child: DropdownButton<PenButtonAction>(
          isExpanded: true,
          value: action,
          borderRadius: BorderRadius.circular(12),
          onChanged: (PenButtonAction? value) {
            if (value != null) {
              unawaited(_setPenButtonAction(logicalButton, value));
            }
          },
          items: PenButtonAction.values
              .map(
                (PenButtonAction value) => DropdownMenuItem<PenButtonAction>(
                  value: value,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(value.icon, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          value.label,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}
