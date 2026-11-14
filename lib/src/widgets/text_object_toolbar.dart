import '../platform/render_power_policy.dart';
import 'package:flutter/material.dart';
import '../core/app_localizations.dart';

/// 文本只保留明确的编辑、拖动入口；低频操作收进带文字的菜单。
/// 拖动手柄直接变换选区，不要求先切换套索再回到正文拖拽。
class TextObjectToolbar extends StatelessWidget {
  /// 接收选中文本的显示位置及编辑、移动和菜单回调。
  /// enabled：是否允许该组件接受当前操作；禁用不等于删除其显示内容。
  /// onEdit：请求编辑当前文本全文的回调，具体面板选择由宿主处理。
  /// onMoveMode：请求切换到文本移动模式的回调，不直接改写对象几何。
  /// onMoveStart：开始一整次工具条拖动的回调，宿主在此建立变换基准和历史事务。
  /// onMove：工具条拖动增量回调，Offset 为当前手势坐标下的逻辑像素增量。
  /// onMoveEnd：结束工具条拖动的回调，宿主据此统一提交历史。
  /// onAction：工具条菜单动作回调，字符串为稳定动作标识而非翻译后的标签。
  const TextObjectToolbar({
    super.key,
    required this.enabled,
    required this.onEdit,
    required this.onMoveMode,
    required this.onMoveStart,
    required this.onMove,
    required this.onMoveEnd,
    required this.onAction,
  });

  /// enabled：是否允许该组件接受当前操作；禁用不等于删除其显示内容。
  final bool enabled;

  /// onEdit：请求编辑当前文本全文的回调，具体面板选择由宿主处理；onMoveMode：请求切换到文本移动模式的回调，不直接改写对象几何；onMoveStart：开始一整次工具条拖动的回调，宿主在此建立变换基准和历史事务；onMoveEnd：结束工具条拖动的回调，宿主据此统一提交历史。
  final VoidCallback onEdit, onMoveMode, onMoveStart, onMoveEnd;

  /// onMove：工具条拖动增量回调，Offset 为当前手势坐标下的逻辑像素增量。
  final ValueChanged<Offset> onMove;

  /// onAction：工具条菜单动作回调，字符串为稳定动作标识而非翻译后的标签。
  final ValueChanged<String> onAction;

  /// 构建固定屏幕尺寸的文字编辑、拖动和更多操作条，拖动回调合并一次历史，禁用状态仍允许受支持的只读动作。
  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onInverseSurface;
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
        child: SizedBox(
          width: 210,
          height: 36,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              SizedBox(
                width: 78,
                child: Tooltip(
                  message: tr('编辑文字'),
                  child: TextButton.icon(
                    onPressed: enabled ? onEdit : null,
                    style: TextButton.styleFrom(
                      foregroundColor: color,
                      minimumSize: Size.zero,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                    ),
                    icon: const Icon(Icons.edit_note_rounded, size: 18),
                    label: Text(
                      tr('编辑', 'Edit'),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: 92,
                child: Tooltip(
                  message: tr('拖动这里移动文本框', 'Drag here to move the text box'),
                  child: MouseRegion(
                    cursor: enabled
                        ? SystemMouseCursors.grab
                        : SystemMouseCursors.basic,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: enabled ? onMoveMode : null,
                      onPanStart: enabled ? (_) => onMoveStart() : null,
                      onPanUpdate: enabled ? (d) => onMove(d.delta) : null,
                      onPanEnd: enabled ? (_) => onMoveEnd() : null,
                      onPanCancel: enabled ? onMoveEnd : null,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 8,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.drag_indicator, color: color, size: 18),
                            Text(
                              tr('拖动', 'Move'),
                              style: TextStyle(color: color, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: 36,
                child: PopupMenuButton<String>(
                  popUpAnimationStyle: appMotionStyle(context),
                  tooltip: tr('更多文本操作', 'More text actions'),
                  icon: Icon(Icons.more_horiz, color: color, size: 20),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 190),
                  onSelected: onAction,
                  itemBuilder: (_) => [
                    for (final (id, icon, label) in [
                      ('copy', Icons.copy_outlined, tr('复制')),
                      ('cut', Icons.content_cut, tr('剪切', 'Cut')),
                      (
                        'color',
                        Icons.palette_outlined,
                        tr('文字颜色', 'Text color'),
                      ),
                      ('delete', Icons.delete_outline, tr('删除')),
                    ])
                      PopupMenuItem(
                        value: id,
                        enabled: id == 'copy' || enabled,
                        child: Row(
                          children: [
                            Icon(icon, size: 18),
                            const SizedBox(width: 12),
                            Text(label),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
