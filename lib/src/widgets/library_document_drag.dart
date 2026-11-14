import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// 鼠标与笔可立即拖动，手指需长按，保留正常滚动操作。
class LibraryDocumentDrag extends StatelessWidget {
  /// 创建不可变的 LibraryDocumentDrag 参数对象；各参数保存在对应字段中，不在构造时执行外部读写。
  /// data：资料库拖动携带的文稿编号，不直接携带整本文稿内容。
  /// child：由当前组件包裹的子组件，布局、绘制或交互能力在外层补充。
  /// feedback：拖动时的反馈组件，不承担真正的文稿位置更新。
  /// onDragStarted：拖动开始回调，宿主据此显示适用的文件夹/移出目标。
  /// onDragEnded：拖动结束回调，宿主清除临时拖动状态。
  const LibraryDocumentDrag({
    super.key,
    required this.data,
    required this.child,
    required this.feedback,
    this.onDragStarted,
    this.onDragEnded,
  });

  /// data：资料库拖动携带的文稿编号，不直接携带整本文稿内容。
  final String data;

  /// child：由当前组件包裹的子组件，布局、绘制或交互能力在外层补充。
  final Widget child;

  /// feedback：拖动时的反馈组件，不承担真正的文稿位置更新。
  final Widget feedback;

  /// onDragStarted：拖动开始回调，宿主据此显示适用的文件夹/移出目标。
  final VoidCallback? onDragStarted;

  /// onDragEnded：拖动结束回调，宿主清除临时拖动状态。
  final VoidCallback? onDragEnded;

  /// 按输入路径创建文稿拖动包装，携带稳定编号并展示轻量反馈，实际目录写入由落点负责。
  @override
  Widget build(BuildContext context) => _DocumentDraggable(
    data: data,
    feedback: feedback,
    touch: true,
    onDragStarted: onDragStarted,
    onDragEnd: (_) => onDragEnded?.call(),
    childWhenDragging: Opacity(opacity: .3, child: child),
    child: _DocumentDraggable(
      data: data,
      feedback: feedback,
      touch: false,
      onDragStarted: onDragStarted,
      onDragEnd: (_) => onDragEnded?.call(),
      childWhenDragging: Opacity(opacity: .3, child: child),
      child: child,
    ),
  );
}

class _DocumentDraggable extends Draggable<String> {
  /// 创建不可变的 _DocumentDraggable 参数对象；各参数保存在对应字段中，不在构造时执行外部读写。
  /// touch：本次拖动是否来自触摸路径，用于区分长按与鼠标拖动启动方式。
  const _DocumentDraggable({
    required super.data,
    required super.feedback,
    required super.child,
    required super.childWhenDragging,
    required this.touch,
    super.onDragStarted,
    super.onDragEnd,
  }) : super(
         rootOverlay: true,
         maxSimultaneousDrags: 1,
         dragAnchorStrategy: pointerDragAnchorStrategy,
       );

  /// touch：本次拖动是否来自触摸路径，用于区分长按与鼠标拖动启动方式。
  final bool touch;

  /// 创建适合当前拖动入口的手势识别器，使鼠标/触摸启动策略与页面点击分开。
  @override
  MultiDragGestureRecognizer createRecognizer(
    GestureMultiDragStartCallback onStart,
  ) {
    final recognizer = touch
        ? DelayedMultiDragGestureRecognizer(
            delay: const Duration(milliseconds: 350),
            supportedDevices: {PointerDeviceKind.touch},
            allowedButtonsFilter: (buttons) => buttons == kPrimaryButton,
          )
        : ImmediateMultiDragGestureRecognizer(
            supportedDevices: {
              PointerDeviceKind.mouse,
              PointerDeviceKind.stylus,
            },
            allowedButtonsFilter: (buttons) => buttons == kPrimaryButton,
          );
    return recognizer..onStart = onStart;
  }
}
