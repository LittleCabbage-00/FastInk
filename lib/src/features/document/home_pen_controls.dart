part of '../../app/fastink_app.dart';

extension _FastInkPenControls on _FastInkHomeState {
  /// 根据窗口宽度决定是否压缩工具图标布局，不改变工具本身功能。
  bool get _compactToolIcons => MediaQuery.sizeOf(context).width < 900;

  /// 构建笔迹与文稿相关的更多操作入口，根据只读和忙碌状态限制修改。
  Widget _toolbarActionsMenu() => PopupMenuButton<String>(
    popUpAnimationStyle: appMotionStyle(context),
    tooltip: tr('更多笔迹操作'),
    icon: const Icon(Icons.more_horiz_rounded),
    // 改写笔迹的条目统一避开加载/旋转/导出窗口（见 inkInputBlocked），
    // 全选只是选中、不动内容，不受限制。
    onSelected: (String value) {
      if (value == 'front' || value == 'back') {
        if (_doc.readOnly || _doc.inkInputBlocked) return;
        _ink.reorderSelection(toFront: value == 'front');
      } else if (value == 'clipboard-copy') {
        _copyInkSelection();
      } else if (value == 'clipboard-cut') {
        _copyInkSelection(cut: true);
      } else if (value == 'clipboard-paste') {
        unawaited(_pasteClipboard());
      } else if (value == 'recolor') {
        unawaited(_recolorInkSelection());
      } else if (value == 'select-all') {
        _selectTool(InkTool.lasso);
        _ink.selectAll();
      } else if (value == 'copy') {
        if (_doc.inkInputBlocked) return;
        _ink.duplicateSelection();
      } else if (value == 'delete') {
        if (_doc.inkInputBlocked) return;
        _ink.deleteSelection();
      } else if (value == 'clear') {
        unawaited(_clearCurrentPageInk());
      }
    },
    itemBuilder: (_) => <PopupMenuEntry<String>>[
      PopupMenuItem<String>(
        value: 'front',
        enabled: _ink.hasSelection && !_doc.readOnly && !_doc.inkInputBlocked,
        child: ListTile(
          title: Text(tr('选区置于顶层', 'Bring selection to front')),
          subtitle: Text(
            tr('图片与笔迹分别排序', 'Images and ink are ordered separately'),
          ),
        ),
      ),
      PopupMenuItem<String>(
        value: 'back',
        enabled: _ink.hasSelection && !_doc.readOnly && !_doc.inkInputBlocked,
        child: ListTile(
          title: Text(tr('选区置于底层', 'Send selection to back')),
          subtitle: Text(
            tr('图片与笔迹分别排序', 'Images and ink are ordered separately'),
          ),
        ),
      ),
      PopupMenuItem<String>(
        value: 'clipboard-copy',
        enabled: _ink.hasSelection && !_doc.inkInputBlocked,
        child: Text(tr('复制选区 · Ctrl+C', 'Copy selection · Ctrl+C')),
      ),
      PopupMenuItem<String>(
        value: 'clipboard-cut',
        enabled: _ink.hasSelection && !_doc.readOnly && !_doc.inkInputBlocked,
        child: Text(tr('剪切选区 · Ctrl+X', 'Cut selection · Ctrl+X')),
      ),
      PopupMenuItem<String>(
        value: 'clipboard-paste',
        enabled: !_doc.readOnly && !_doc.inkInputBlocked,
        child: Text(
          tr('粘贴选区或图片 · Ctrl+V', 'Paste selection or image · Ctrl+V'),
        ),
      ),
      PopupMenuItem<String>(
        value: 'recolor',
        enabled: _ink.hasSelection && !_doc.readOnly && !_doc.inkInputBlocked,
        child: Text(tr('选区改色', 'Recolor selection')),
      ),
      const PopupMenuDivider(),
      PopupMenuItem<String>(
        value: 'select-all',
        enabled: _ink.strokes.isNotEmpty,
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.select_all_rounded),
          title: Text(tr('全选当前页')),
        ),
      ),
      PopupMenuItem<String>(
        value: 'copy',
        enabled: _ink.hasSelection && !_doc.readOnly && !_doc.inkInputBlocked,
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.control_point_duplicate_rounded),
          title: Text(tr('生成所选内容副本')),
        ),
      ),
      PopupMenuItem<String>(
        value: 'delete',
        enabled: _ink.hasSelection && !_doc.readOnly && !_doc.inkInputBlocked,
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.delete_outline_rounded),
          title: Text(tr('删除所选笔迹')),
        ),
      ),
      PopupMenuItem<String>(
        value: 'clear',
        enabled: _ink.canUndo && !_doc.inkInputBlocked,
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.delete_sweep_outlined),
          title: Text(tr('清空当前页笔迹')),
        ),
      ),
    ],
  );

  /// 在允许编辑时按配置确认清空当前页笔迹，走可撤销历史，不删除页面底图。
  Future<void> _clearCurrentPageInk() async {
    if (!_ink.canUndo) return;
    if (_settings.confirmClearInk) {
      final bool confirmed =
          await showDialog<bool>(
            context: context,
            animationStyle: appMotionStyle(context),
            builder: (BuildContext dialogContext) => AlertDialog(
              icon: const Icon(Icons.delete_sweep_outlined),
              title: Text(tr('清空当前页笔迹？', 'Clear ink from the current page?')),
              content: Text(
                tr(
                  '这会移除当前页的全部笔迹；清空后仍可立即撤销。',
                  'This removes all ink from the current page. You can still undo immediately afterward.',
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: Text(tr('取消')),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: Text(tr('清空', 'Clear')),
                ),
              ],
            ),
          ) ??
          false;
      if (!confirmed) return;
    }
    // 确认框是异步的，期间可能正好在换页、旋转或导出：此刻 _ink 里装的
    // 不是用户看到的那页，清空打在即将被替换或正在被读的笔迹上，提交块
    // 结尾的 dirty=false 会把它无声吞掉。和撤销按钮同一套拒绝条件。
    if (_doc.inkInputBlocked) {
      _updateState(
        () => _doc.status = tr(
          '页面正在更新，请稍后再清空笔迹',
          'The page is being updated; try clearing ink again in a moment',
        ),
      );
      return;
    }
    _ink.clear();
  }

  /// 复用笔型菜单的稳定组件与签名，避免保存状态刷新时导致按钮闪烁。
  Widget _penToolMenu() {
    final signature = (
      _settings.penStyle,
      _toolState.tool == InkTool.pen,
      Theme.of(context),
      AppText.locale,
      _compactToolIcons,
    );
    if (_stablePenMenuSignature != signature || _stablePenMenu == null) {
      _stablePenMenuSignature = signature;
      _stablePenMenu = RepaintBoundary(
        key: const ValueKey('pen-type-button'),
        child: _buildPenToolMenu(),
      );
    }
    return _stablePenMenu!;
  }

  /// 创建笔型选择菜单，显示当前笔型并绑定默认样式更新。
  Widget _buildPenToolMenu() {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final String label = switch (_settings.penStyle) {
      'fountain' => tr('钢笔'),
      'ball' => tr('圆珠笔'),
      'brush' => tr('画笔'),
      'pencil' => tr('铅笔'),
      _ => tr('钢笔'),
    };
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: MenuAnchor(
        alignmentOffset: const Offset(0, 6),
        menuChildren: PenStyle.values.map((PenStyle style) {
          final (
            IconData icon,
            String title,
            String subtitle,
          ) = switch (style) {
            PenStyle.fountain => (Icons.edit_rounded, '钢笔', '自然压感，适合日常书写'),
            PenStyle.ball => (
              Icons.horizontal_rule_rounded,
              '圆珠笔',
              '粗细稳定，不随压力变化',
            ),
            PenStyle.brush => (Icons.brush_rounded, '画笔', '压感明显，适合标题与绘画'),
            PenStyle.pencil => (Icons.draw_outlined, '铅笔', '较轻的压感线条，适合草稿'),
          };
          return MenuItemButton(
            leadingIcon: Icon(icon),
            trailingIcon: style.name == _settings.penStyle
                ? const Icon(Icons.check_rounded)
                : null,
            onPressed: () {
              _updateState(() => _settings.penStyle = style.name);
              _selectTool(InkTool.pen);
            },
            child: SizedBox(
              width: 220,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(tr(title)),
                  Text(
                    tr(subtitle),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          );
        }).toList(),
        builder:
            (BuildContext context, MenuController controller, Widget? child) {
              return Tooltip(
                message: _toolState.tool == InkTool.pen
                    ? tr(
                        '$label · 再点一次切换笔型',
                        '$label · click again to choose a pen',
                      )
                    : tr('切换到$label', 'Switch to $label'),
                child: _compactToolIcons
                    ? IconButton(
                        isSelected: _toolState.tool == InkTool.pen,
                        icon: const Icon(Icons.edit_rounded, size: 20),
                        onPressed: () {
                          if (_toolState.tool != InkTool.pen) {
                            _selectTool(InkTool.pen);
                          } else if (controller.isOpen) {
                            controller.close();
                          } else {
                            controller.open();
                          }
                        },
                      )
                    : ChoiceChip(
                        avatar: const Icon(Icons.edit_rounded, size: 18),
                        label: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Text(label),
                            const SizedBox(width: 2),
                            const Icon(Icons.arrow_drop_down_rounded, size: 18),
                          ],
                        ),
                        selected: _toolState.tool == InkTool.pen,
                        selectedColor: colors.secondaryContainer,
                        onSelected: (_) {
                          if (_toolState.tool != InkTool.pen) {
                            _selectTool(InkTool.pen);
                          } else if (controller.isOpen) {
                            controller.close();
                          } else {
                            controller.open();
                          }
                        },
                      ),
              );
            },
      ),
    );
  }

  /// 创建反映当前选中工具的按钮，点击通过统一切换入口保留各工具独立样式。
  Widget _toolButton(
    InkTool tool,
    IconData icon,
    String label,
    String tooltip, {
    required VoidCallback onPressed,
  }) {
    if (_compactToolIcons) {
      return IconButton(
        tooltip: tooltip,
        isSelected: _toolState.tool == tool,
        onPressed: onPressed,
        icon: Icon(icon, size: 20),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Tooltip(
        message: tooltip,
        child: ChoiceChip(
          avatar: Icon(icon, size: 18),
          label: Text(label),
          selected: _toolState.tool == tool,
          onSelected: (_) => onPressed(),
        ),
      ),
    );
  }
}
