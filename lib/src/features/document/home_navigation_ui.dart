part of '../../app/fastink_app.dart';

extension _FastInkNavigationUi on _FastInkHomeState {
  /// 创建可切换的页面导航按钮，选中外观与语义状态反映侧栏当前是否显示。
  Widget _pageSidebarButton({bool compact = false}) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      toggled: _showPageSidebar,
      child: Tooltip(
        message: _showPageSidebar
            ? tr('收起页面导航（页面 / 目录 / 书签）', 'Hide pages, outline and bookmarks')
            : tr('展开页面导航（页面 / 目录 / 书签）', 'Show pages, outline and bookmarks'),
        child: TextButton.icon(
          key: const ValueKey('page-sidebar-toggle'),
          onPressed: () =>
              _updateState(() => _showPageSidebar = !_showPageSidebar),
          style: TextButton.styleFrom(
            minimumSize: const Size(0, 40),
            padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 10),
            foregroundColor: _showPageSidebar
                ? colors.onSecondaryContainer
                : colors.onSurfaceVariant,
            backgroundColor: _showPageSidebar
                ? colors.secondaryContainer
                : Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          icon: Icon(
            _showPageSidebar
                ? Icons.view_sidebar_rounded
                : Icons.view_sidebar_outlined,
            size: 19,
          ),
          label: Text(
            compact ? tr('页面', 'Pages') : tr('页面导航', 'Page navigator'),
            maxLines: 1,
          ),
        ),
      ),
    );
  }

  /// 按窗口宽度构建紧凑或完整文档导航，保留返回、页码、文稿切换等主要入口。
  Widget _navigationRow(NoteDocument? document, {required bool compact}) {
    if (compact) {
      return Row(
        children: <Widget>[
          IconButton.filledTonal(
            tooltip: tr('返回资料库'),
            onPressed: _goToLibrary,
            icon: const Icon(Icons.arrow_back_rounded, size: 20),
          ),
          _pageSidebarButton(compact: true),
          _compactDocumentSwitcher(),
          _pageNavigator(document, compact: true),
          if (MediaQuery.sizeOf(context).width >= 760)
            IconButton(
              tooltip: tr(_currentPageBookmarked ? '取消当前页书签' : '收藏当前页'),
              isSelected: _currentPageBookmarked,
              onPressed: _toggleCurrentPageBookmark,
              icon: const Icon(Icons.bookmark_border_rounded),
              selectedIcon: const Icon(Icons.bookmark_rounded),
            ),
          if (MediaQuery.sizeOf(context).width >= 840)
            _saveStatusIndicator(compact: true),
          const Spacer(),
          if (MediaQuery.sizeOf(context).width >= 680)
            IconButton(
              tooltip: tr('搜索本文稿', 'Search this document'),
              onPressed: _showDocumentSearch,
              icon: const Icon(Icons.search_rounded),
            ),
          _documentMoreMenu(),
          _fullscreenButton(),
        ],
      );
    }
    return Row(
      children: <Widget>[
        IconButton.filledTonal(
          tooltip: tr('返回资料库'),
          onPressed: _goToLibrary,
          icon: const Icon(Icons.arrow_back_rounded, size: 20),
        ),
        _pageSidebarButton(),
        const SizedBox(width: 8),
        if (document != null) ...<Widget>[
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 220),
              child: InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: () {
                  final LibraryDocument? item = _currentLibraryDocument;
                  if (item != null) unawaited(_renameDocument(item));
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Flexible(
                        child: Text(
                          document.title,
                          style: Theme.of(context).textTheme.titleSmall,
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.edit_rounded,
                        size: 14,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
        _pageNavigator(document),
        IconButton(
          tooltip: tr(_currentPageBookmarked ? '取消当前页书签' : '收藏当前页'),
          isSelected: _currentPageBookmarked,
          onPressed: _toggleCurrentPageBookmark,
          icon: const Icon(Icons.bookmark_border_rounded),
          selectedIcon: const Icon(Icons.bookmark_rounded),
        ),
        IconButton(
          tooltip: tr('在当前页后添加页面'),
          // 导出期间页面结构锁死，见 _rejectStructuralChange。
          onPressed: _doc.busy
              ? null
              : () => _addPage(afterIndex: _doc.pageIndex),
          icon: const Icon(Icons.add_box_outlined),
        ),
        IconButton(
          tooltip: tr(_doc.readOnly ? '切换到编辑模式' : '切换到只读模式'),
          isSelected: _doc.readOnly,
          onPressed: () => _updateState(() => _doc.readOnly = !_doc.readOnly),
          icon: const Icon(Icons.edit_outlined),
          selectedIcon: const Icon(Icons.visibility_outlined),
        ),
        IconButton(
          tooltip: tr('更改纸张模板、颜色、大小和方向'),
          onPressed: _changePaperTemplate,
          icon: const Icon(Icons.dashboard_customize_outlined),
        ),
        IconButton(
          tooltip: tr('导出 PDF、PNG 或 JPG'),
          onPressed: _exportDocument,
          icon: const Icon(Icons.ios_share_rounded),
        ),
        IconButton(
          tooltip: tr('搜索本文稿 · Ctrl+F', 'Search this document · Ctrl+F'),
          onPressed: _showDocumentSearch,
          icon: const Icon(Icons.search_rounded),
        ),
        _themeMenu(compact: true),
        _fullscreenButton(),
        const SizedBox(width: 8),
        _saveStatusIndicator(),
        const SizedBox(width: 8),
        Expanded(child: _documentTabs()),
        _compactDocumentSwitcher(),
      ],
    );
  }

  /// 构建页码输入与首末边界按钮，数字按相同基线排版；显示页码为一基，内部页索引为零基。
  Widget _pageNavigator(NoteDocument? document, {bool compact = false}) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final TextStyle? numberStyle = Theme.of(context).textTheme.labelLarge
        ?.copyWith(
          height: 1,
          fontFeatures: const [FontFeature.tabularFigures()],
        );
    final int total = document?.pages.length ?? 0;
    final numberStrut = StrutStyle.fromTextStyle(
      numberStyle ?? const TextStyle(fontSize: 14),
      forceStrutHeight: true,
    );
    // 页数达到四位数时适当放宽输入区，小文档仍保持紧凑。
    final int digits = math.max(2, total.toString().length);
    final double fieldWidth = (digits * 8.5 + 12).clamp(36, 54);
    final bool canGoBack = document != null && _doc.pageIndex > 0;
    final bool canGoForward =
        document != null && _doc.pageIndex < document.pages.length - 1;

    return Semantics(
      container: true,
      label: tr('页码导航', 'Page navigation'),
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          color: colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _pageStepButton(
              tooltip: tr('上一页'),
              icon: Icons.keyboard_arrow_up_rounded,
              onPressed: canGoBack ? () => _goToPage(_doc.pageIndex - 1) : null,
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                SizedBox(
                  width: fieldWidth,
                  height: 28,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.surface,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: TextField(
                        key: const ValueKey('page-number-input'),
                        controller: _pageInput,
                        enabled: document != null,
                        textAlign: TextAlign.center,
                        textAlignVertical: TextAlignVertical.center,
                        keyboardType: TextInputType.number,
                        inputFormatters: <TextInputFormatter>[
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        onSubmitted: _goToSubmitted,
                        onTap: () => _pageInput.selection = TextSelection(
                          baseOffset: 0,
                          extentOffset: _pageInput.text.length,
                        ),
                        onTapOutside: (_) {
                          // 未确认的页码不应伪装成已经跳转成功的当前页。
                          _pageInput.text = '${_doc.pageIndex + 1}';
                          FocusManager.instance.primaryFocus?.unfocus();
                        },
                        style: numberStyle,
                        strutStyle: numberStrut,
                        // Windows 的 InputDecorator 与可编辑文字报告的基线不同，
                        // 因此将页码胶囊背景绘制在输入装饰之外。
                        decoration: null,
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 6, right: 2),
                  child: Text(
                    '/ $total',
                    key: const ValueKey('page-number-total'),
                    strutStyle: numberStrut,
                    style: numberStyle?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            _pageStepButton(
              tooltip: tr('下一页'),
              icon: Icons.keyboard_arrow_down_rounded,
              onPressed: canGoForward
                  ? () => _goToPage(_doc.pageIndex + 1)
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  /// 创建固定屏幕尺寸的单步翻页按钮，没有有效回调时禁用。
  Widget _pageStepButton({
    required String tooltip,
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, size: 19),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 40, height: 40),
      visualDensity: VisualDensity.compact,
    );
  }

  /// 根据错误、保存中和脏页状态展示保存反馈，不将状态文案当作真正的磁盘成功凭据。
  Widget _saveStatusIndicator({bool compact = false}) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final bool failed =
        _doc.status.contains('失败') ||
        _doc.status.toLowerCase().contains('failed');
    final bool saving =
        _doc.status.contains('正在后台保存') ||
        _doc.status.contains('正在保存') ||
        _doc.status.toLowerCase().contains('saving');
    final String label = failed
        ? tr('保存失败', 'Save failed')
        : saving
        ? tr('保存中', 'Saving')
        : _doc.dirty
        ? tr('未保存', 'Unsaved')
        : tr('已保存', 'Saved');
    final IconData icon = failed
        ? Icons.error_outline_rounded
        : saving
        ? Icons.sync_rounded
        : _doc.dirty
        ? Icons.edit_note_rounded
        : Icons.check_circle_outline_rounded;
    final Color color = failed
        ? colors.error
        : saving || _doc.dirty
        ? colors.primary
        : colors.onSurfaceVariant;
    return Tooltip(
      message: _doc.status,
      child: AnimatedSwitcher(
        duration: appMotionDuration(context, 180),
        child: compact
            ? SizedBox(
                key: ValueKey<String>('save-$label-compact'),
                width: 34,
                height: 34,
                child: Icon(icon, color: color, size: 20),
              )
            : Chip(
                key: ValueKey<String>('save-$label'),
                visualDensity: VisualDensity.compact,
                avatar: Icon(icon, color: color, size: 17),
                label: Text(label),
              ),
      ),
    );
  }
}
