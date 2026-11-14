part of '../../app/fastink_app.dart';

extension _FastInkLibraryUi on _FastInkHomeState {
  /// 按窗口宽度选择固定侧栏或抽屉，叠加资料库重任务进度反馈。
  Widget _libraryScaffold() {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool compact = constraints.maxWidth < 1100;
        return Scaffold(
          backgroundColor: colors.surface,
          drawer: compact
              ? Drawer(
                  width: math.min(300, constraints.maxWidth * 0.86),
                  child: _librarySidebar(expand: true),
                )
              : null,
          body: Stack(
            children: <Widget>[
              Row(
                children: <Widget>[
                  if (!compact) _librarySidebar(),
                  Expanded(child: _libraryMain(compact: compact)),
                ],
              ),
              if (_libraryBusy)
                Positioned.fill(
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: 0.34),
                    child: Center(
                      child: Container(
                        width: math.min(390, constraints.maxWidth - 32),
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: const Color(0xff20232a),
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: const <BoxShadow>[
                            BoxShadow(color: Colors.black38, blurRadius: 28),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            const LinearProgressIndicator(),
                            const SizedBox(height: 18),
                            Text(
                              _doc.status,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  /// 构建资料库类别、设置与外观入口，窄窗口抽屉沿用相同动作。
  Widget _librarySidebar({bool expand = false}) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Container(
      width: expand ? double.infinity : 208,
      color: colors.surfaceContainerLow,
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
      child: CustomScrollView(
        primary: false,
        slivers: <Widget>[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 2, 8, 24),
              child: Row(
                children: <Widget>[
                  Image.asset('assets/fastink_icon.png', width: 30, height: 30),
                  const SizedBox(width: 10),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'FastInk',
                        style: TextStyle(
                          color: colors.onSurface,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverList.list(
            children: [
              _libraryNavItem(
                'documents',
                Icons.folder_copy_outlined,
                tr('文稿'),
              ),
              _libraryNavItem(
                'markdown',
                Icons.edit_note_rounded,
                tr('Markdown'),
              ),
              _libraryNavItem('favorites', Icons.star_border_rounded, tr('收藏')),
              _libraryNavItem('recent', Icons.schedule_rounded, tr('最近查看')),
            ],
          ),
          SliverFillRemaining(
            hasScrollBody: false,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _libraryNavItem(
                  'trash',
                  Icons.delete_outline_rounded,
                  tr('废纸篓'),
                ),
                _libraryNavItem('settings', Icons.settings_outlined, tr('设置')),
                _themeMenu(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 创建具有选中态的类别按钮，切换时清除旧查询与展开目录，抽屉模式先关闭抽屉。
  Widget _libraryNavItem(String section, IconData icon, String label) {
    final bool selected = _librarySection == section;
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Builder(
      builder: (navContext) => Padding(
        padding: const EdgeInsets.only(bottom: 5),
        child: Material(
          color: selected ? colors.primaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            key: ValueKey('library-nav-$section'),
            borderRadius: BorderRadius.circular(10),
            onTap: () {
              if (Scaffold.maybeOf(navContext)?.isDrawerOpen ?? false) {
                Navigator.of(navContext).pop();
              }
              _searchInput.clear();
              _updateState(() {
                _librarySection = section;
                _activeFolderId = null;
              });
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              child: Row(
                children: <Widget>[
                  Icon(
                    icon,
                    size: 21,
                    color: selected
                        ? colors.onPrimaryContainer
                        : colors.onSurfaceVariant,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: selected
                            ? colors.onPrimaryContainer
                            : colors.onSurface,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
