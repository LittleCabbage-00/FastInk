part of 'ink_canvas.dart';

/// 自动避让的过渡只作用于显示层。正文在开始时一次提交到最终位置，
/// 保存、导出和撤销始终读取最终笔迹，不记录任何动画中间状态。
extension InkTextRelocation on InkController {
  /// 保存文本起始四角和排除目标后的背景快照，最终文本几何已提交，动画仅改变显示。
  void startTextRelocation(InkStroke target, List<InkPoint> from) {
    finishTextRelocation();
    if (target.text == null ||
        target.points.length < 4 ||
        from.length < 4 ||
        !strokes.contains(target)) {
      return;
    }
    _relocatingText = target;
    _relocationFrom = List.of(from.take(4));
    _relocationProgress = 0;
    _relocationBackground = strokes
        .where((s) => !identical(s, target))
        .toList();
    _committedRevision.value++;
    _activeChanged();
    _selectionChanged();
  }

  /// 应用 0–1 的显示插值进度，只通知相关显示层，不向历史栈追加中间坐标。
  void updateTextRelocation(double progress) {
    if (!isTextRelocating) return;
    _relocationProgress = progress.clamp(0, 1);
    _activeChanged();
  }

  /// 终止显示动画并恢复正常静态绘制，用户接管编辑时不改变已保存的最终位置。
  void finishTextRelocation() {
    if (!isTextRelocating) return;
    _relocatingText = null;
    _relocationFrom = const [];
    _relocationBackground = null;
    _relocationProgress = 1;
    _committedRevision.value++;
    _activeChanged();
    _selectionChanged();
  }
}

/// 在起始与最终四角之间插值绘制文本及定位框，避免动画目标在背景里重复出现。
void _paintTextRelocation(
  Canvas canvas,
  Size size,
  InkController controller,
  bool? paperDark,
) {
  final stroke = controller._relocatingText;
  if (stroke == null) return;
  final t = controller._relocationProgress;
  final corners = [
    for (var i = 0; i < 4; i++)
      Offset(
        (controller._relocationFrom[i].x * (1 - t) + stroke.points[i].x * t) *
            size.width,
        (controller._relocationFrom[i].y * (1 - t) + stroke.points[i].y * t) *
            size.height,
      ),
  ];
  final origin = Offset(
    stroke.points[0].x * size.width,
    stroke.points[0].y * size.height,
  );
  // 避让结果已清除旋转，动画通过四角插值把旧旋转和旧尺寸平滑过渡到新框。
  final width = (stroke.points[1].x - stroke.points[0].x) * size.width;
  final height = (stroke.points[3].y - stroke.points[0].y) * size.height;
  if (width <= 0 || height <= 0) return;
  final horizontal = (corners[1] - corners[0]) / width;
  final vertical = (corners[3] - corners[0]) / height;
  canvas.save();
  canvas.translate(corners[0].dx, corners[0].dy);
  canvas.transform(
    Float64List.fromList([
      horizontal.dx,
      horizontal.dy,
      0,
      0,
      vertical.dx,
      vertical.dy,
      0,
      0,
      0,
      0,
      1,
      0,
      0,
      0,
      0,
      1,
    ]),
  );
  canvas.translate(-origin.dx, -origin.dy);
  controller._committedRenderCache.paint(
    canvas,
    size,
    stroke,
    paperDark: paperDark,
  );
  canvas.restore();
  final outline = Path()..moveTo(corners.first.dx, corners.first.dy);
  for (final point in corners.skip(1)) {
    outline.lineTo(point.dx, point.dy);
  }
  outline.close();
  canvas.drawPath(
    outline,
    Paint()
      ..color = const Color(0xff2f80ed)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5 / controller.selectionViewScale,
  );
}
