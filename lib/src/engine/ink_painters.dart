part of 'ink_canvas.dart';

/// 只将接近黑白的灰色视作自动对比色，深蓝等有色笔迹保留原色。
bool isNeutralPaperInk(Color color) {
  final low = math.min(color.r, math.min(color.g, color.b));
  final high = math.max(color.r, math.max(color.g, color.b));
  return high - low < .065 && (high <= .28 || low >= .95);
}

/// 为模板纸张解析屏幕墨色，保留原始 ARGB 数据及透明度。
Color _displayStrokeColor(InkStroke stroke, bool? paperDark) {
  final color = colorFromArgb(stroke.color);
  if (paperDark == null ||
      stroke.kind == StrokeKind.highlighter ||
      !isNeutralPaperInk(color)) {
    return color;
  }
  final lightInk = color.r > .5;
  if (paperDark == lightInk) return color;
  return (paperDark ? Colors.white : const Color(0xff202124)).withValues(
    alpha: color.a,
  );
}

/// 绘制已经提交的笔迹，只监听 committedRevision。
class _CommittedInkPainter extends CustomPainter {
  /// 订阅已提交笔迹版本，静态层不跟随每个新增采样点整页重绘。
  _CommittedInkPainter(this.controller, this.paperDark)
    : super(repaint: controller.committedRepaint);

  /// controller：该组件或绘制层使用的控制器，由构造方传入，具体内容遵循声明类型。
  final InkController controller;

  /// 模板纸色明暗，为空时保留笔迹原色。
  final bool? paperDark;

  /// 按页面逻辑尺寸绘制已提交笔迹，复用每条笔画的绘制缓存。
  @override
  void paint(Canvas canvas, Size size) {
    for (final InkStroke stroke in controller._displayStrokes) {
      controller._committedRenderCache.paint(
        canvas,
        size,
        stroke,
        paperDark: paperDark,
      );
    }
  }

  /// 笔迹提交由控制器信号触发，此处检查纸色变化。
  @override
  bool shouldRepaint(covariant _CommittedInkPainter oldDelegate) =>
      oldDelegate.paperDark != paperDark;
}

/// 绘制当前正在书写的一条笔迹，避免每个采样点重画历史内容。
class _ActiveInkPainter extends CustomPainter {
  /// 只订阅当前活动笔迹版本，新增采样通过增量 Path 显示。
  _ActiveInkPainter(this.controller, this.paperDark)
    : super(repaint: controller.activeRepaint);

  /// controller：该组件或绘制层使用的控制器，由构造方传入，具体内容遵循声明类型。
  final InkController controller;

  /// 活动笔迹沿用已提交笔迹的纸色对比策略。
  final bool? paperDark;

  /// 绘制正在输入的笔迹和移动中的文本框。
  @override
  void paint(Canvas canvas, Size size) {
    _paintTextRelocation(canvas, size, controller, paperDark);
    final InkStroke? active = controller.activeStroke;
    if (active != null) {
      _paintActiveInkStroke(canvas, size, controller, active, paperDark);
    }
  }

  /// 活动笔迹变化由控制器通知，此处检查纸色变化。
  @override
  bool shouldRepaint(covariant _ActiveInkPainter oldDelegate) =>
      oldDelegate.paperDark != paperDark;
}

/// 增量记录钢笔的活动笔迹。线段按四分之一像素的压感宽度归入 Path，
/// 每次采样只追加尾部；形状和荧光笔仍完整绘制，以保留实时几何与叠加。
void _paintActiveInkStroke(
  Canvas canvas,
  Size size,
  InkController controller,
  InkStroke stroke,
  bool? paperDark,
) {
  if (stroke.kind != StrokeKind.pen || stroke.points.length < 2) {
    controller._clearActivePathCache();
    _paintInkStroke(
      canvas,
      size,
      stroke,
      color: _displayStrokeColor(stroke, paperDark),
    );
    return;
  }
  final int cachedCount = controller._activePathPointCount;
  final InkPoint? cachedLast = controller._activePathLastPoint;
  final bool prefixUnchanged =
      cachedCount > 0 &&
      cachedCount <= stroke.points.length &&
      cachedLast != null &&
      _sameInkPoint(stroke.points[cachedCount - 1], cachedLast);
  final bool appendable =
      identical(controller._activePathStroke, stroke) &&
      controller._activePathSize == size &&
      controller._activePaths.isNotEmpty &&
      stroke.points.length >= cachedCount &&
      prefixUnchanged;
  if (!appendable) controller._clearActivePathCache();

  final int firstSegment = controller._activePaths.isEmpty
      ? 1
      : controller._activePathPointCount;
  _appendActivePenSegments(controller, size, stroke, firstSegment);
  controller
    .._activePathSize = size
    .._activePathStroke = stroke
    .._activePathPointCount = stroke.points.length
    .._activePathLastPoint = stroke.points.last;
  final Paint paint = Paint()
    ..color = _displayStrokeColor(stroke, paperDark)
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..isAntiAlias = true;
  if (stroke.penStyle == PenStyle.pencil) {
    paint.color = paint.color.withAlpha(205);
  }
  for (final MapEntry<int, Path> entry in controller._activePaths.entries) {
    paint.strokeWidth = entry.key / 4;
    canvas.drawPath(entry.value, paint);
  }
}

/// 比较两采样点的位置与压力，避免把同位置但压力不同的点误当重复。
bool _sameInkPoint(InkPoint a, InkPoint b) =>
    a.x == b.x && a.y == b.y && a.pressure == b.pressure;

/// 只把活动笔画新增线段加入按宽度分桶的 Path；长笔画不需要逐点重放历史采样。
void _appendActivePenSegments(
  InkController controller,
  Size size,
  InkStroke stroke,
  int firstSegment,
) {
  final double pixelWidth = inkPixelWidth(stroke.width, size);
  for (int i = math.max(1, firstSegment); i < stroke.points.length; i++) {
    final InkPoint from = stroke.points[i - 1];
    final InkPoint to = stroke.points[i];
    final double width = math.max(
      0.8,
      pixelWidth * _pressureFactor(stroke, to.pressure),
    );
    final int bucket = math.max(1, (width * 4).round());
    final Path path = controller._activePaths.putIfAbsent(bucket, Path.new);
    path
      ..moveTo(from.x * size.width, from.y * size.height)
      ..lineTo(to.x * size.width, to.y * size.height);
  }
}

/// 绘制套索、选区边框和屏幕尺寸固定的变换控制柄。
class _SelectionPainter extends CustomPainter {
  /// 订阅选择相关版本，套索和把手变化不必重画底图与静态笔迹。
  _SelectionPainter(this.controller)
    : super(repaint: controller.selectionRepaint);

  /// controller：该组件或绘制层使用的控制器，由构造方传入，具体内容遵循声明类型。
  final InkController controller;

  /// 绘制套索轮廓、边界和变换手柄。文本框定位动画期间隐藏选区。
  @override
  void paint(Canvas canvas, Size size) {
    if (controller.isTextRelocating) return;
    final Paint lassoPaint = Paint()
      ..color = const Color(0xff2f80ed)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    if (controller.lassoPoints.isNotEmpty) {
      final Path path = Path();
      final InkPoint first = controller.lassoPoints.first;
      path.moveTo(first.x * size.width, first.y * size.height);
      for (int i = 1; i < controller.lassoPoints.length; i++) {
        final InkPoint point = controller.lassoPoints[i];
        path.lineTo(point.x * size.width, point.y * size.height);
      }
      canvas.drawPath(path, lassoPaint);
    }

    final Rect? normalized = controller.selectionBounds;
    if (normalized == null) return;
    final Rect bounds = Rect.fromLTRB(
      normalized.left * size.width,
      normalized.top * size.height,
      normalized.right * size.width,
      normalized.bottom * size.height,
    );
    final double inverseScale = 1 / controller.selectionViewScale;
    final double padding = _selectionPaddingScreen * inverseScale;
    final Rect visualBounds = bounds.inflate(padding);
    lassoPaint.strokeWidth = 1.6 * inverseScale;
    final Paint fill = Paint()
      ..color = const Color(0x122f80ed)
      ..style = PaintingStyle.fill;
    canvas.drawRect(visualBounds, fill);
    canvas.drawRect(visualBounds, lassoPaint);

    final Paint handlePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    final Paint handleBorder = Paint()
      ..color = const Color(0xff2f80ed)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2 * inverseScale;
    final double handleRadius = _selectionHandleRadiusScreen * inverseScale;
    final Offset scaleHandle = visualBounds.bottomRight;
    canvas.drawCircle(scaleHandle, handleRadius, handlePaint);
    canvas.drawCircle(scaleHandle, handleRadius, handleBorder);
    canvas.drawCircle(
      scaleHandle,
      2.2 * inverseScale,
      Paint()..color = const Color(0xff2f80ed),
    );

    final double rotateY = math.max(
      handleRadius,
      visualBounds.top - _selectionRotateGapScreen * inverseScale,
    );
    final Offset rotateHandle = Offset(visualBounds.center.dx, rotateY);
    canvas.drawLine(
      Offset(visualBounds.center.dx, visualBounds.top),
      Offset(visualBounds.center.dx, rotateY + handleRadius),
      lassoPaint,
    );
    canvas.drawCircle(rotateHandle, handleRadius, handlePaint);
    canvas.drawCircle(rotateHandle, handleRadius, handleBorder);
    canvas.drawArc(
      Rect.fromCircle(center: rotateHandle, radius: 3.3 * inverseScale),
      -math.pi * 0.2,
      math.pi * 1.45,
      false,
      Paint()
        ..color = const Color(0xff2f80ed)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4 * inverseScale
        ..strokeCap = StrokeCap.round,
    );
  }

  /// 选区变换由控制器的选择信号触发重绘。
  @override
  bool shouldRepaint(covariant _SelectionPainter oldDelegate) => false;
}

/// 橡皮范围提示仅随光标移动刷新，不进入笔迹数据。
class _EraserCursorPainter extends CustomPainter {
  /// 订阅橡皮悬停位置与半径，移动时仅刷新光标覆盖层。
  _EraserCursorPainter({required this.position, required this.radius})
    : super(repaint: position);

  /// position：橡皮光标的悬停位置通知器，null 表示隐藏光标。
  final ValueNotifier<Offset?> position;

  /// radius：橡皮光标的逻辑像素半径，和命中范围按同一比例换算。
  final double radius;

  /// 有悬停位置时绘制橡皮的实际擦除范围。
  @override
  void paint(Canvas canvas, Size size) {
    final point = position.value;
    if (point == null) return;
    canvas.drawCircle(
      point,
      radius,
      Paint()
        ..color = const Color(0x242f80ed)
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      point,
      radius,
      Paint()
        ..color = const Color(0xff2f80ed)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..isAntiAlias = true,
    );
    final TextPainter text = TextPainter(
      text: TextSpan(
        text: '${(radius * 2).round()}',
        style: const TextStyle(
          color: Color(0xff1f5eae),
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    text.paint(canvas, point - Offset(text.width / 2, text.height / 2));
  }

  /// 光标移动由位置通知触发，替换位置源或改变半径时重绘。
  @override
  bool shouldRepaint(covariant _EraserCursorPainter oldDelegate) =>
      oldDelegate.position != position || oldDelegate.radius != radius;
}

/// 按笔画种类绘制文字、形状或压力线段，输入坐标根据页面逻辑尺寸解释。
void _paintInkStroke(
  Canvas canvas,
  Size size,
  InkStroke stroke, {
  Color? color,
}) {
  if (stroke.points.isEmpty) return;
  // 图片由独立组件解码和缓存，笔迹画布只负责覆盖在图片上的墨迹。
  if (stroke.kind == StrokeKind.image) return;
  if (stroke.text != null && stroke.points.length >= 4) {
    // 文本四角记录的是页面归一化变换；排版宽度单独保存，
    // 旋转或缩放后仍可重新编辑而不改变换行结果。
    final Offset origin = Offset(
      stroke.points[0].x * size.width,
      stroke.points[0].y * size.height,
    );
    final Offset right = Offset(
      stroke.points[1].x * size.width,
      stroke.points[1].y * size.height,
    );
    final Offset bottom = Offset(
      stroke.points[3].x * size.width,
      stroke.points[3].y * size.height,
    );
    final Offset horizontal = right - origin;
    final Offset vertical = bottom - origin;
    final TextPainter layout = TextPainter(
      text: TextSpan(
        text: stroke.text,
        style: TextStyle(
          color: color ?? colorFromArgb(stroke.color),
          fontFamily: stroke.textFontFamily,
          fontFamilyFallback: const <String>['Microsoft YaHei UI'],
          fontSize: stroke.textSize * size.height,
          fontWeight: FontWeight.values.firstWhere(
            (FontWeight weight) => weight.value == stroke.textWeight,
            orElse: () => FontWeight.w400,
          ),
          fontStyle: stroke.textItalic ? FontStyle.italic : FontStyle.normal,
          decoration: stroke.textUnderline
              ? TextDecoration.underline
              : TextDecoration.none,
        ),
      ),
      textAlign: stroke.textAlign,
      textWidthBasis: TextWidthBasis.parent,
      textDirection: TextDirection.ltr,
    );
    final double? normalizedBaseWidth = stroke.textBoxWidth;
    if (normalizedBaseWidth != null) {
      final double baseWidth = math.max(1, normalizedBaseWidth * size.width);
      layout.layout(maxWidth: baseWidth);
      final double scale = horizontal.distance / baseWidth;
      if (layout.height <= 0 || scale <= 0) return;
      canvas
        ..save()
        ..translate(origin.dx, origin.dy)
        ..rotate(math.atan2(horizontal.dy, horizontal.dx))
        ..scale(scale);
      layout.paint(canvas, Offset.zero);
      canvas.restore();
      return;
    }
    layout.layout();
    if (layout.width <= 0 || layout.height <= 0) return;
    canvas
      ..save()
      ..translate(origin.dx, origin.dy)
      ..rotate(math.atan2(horizontal.dy, horizontal.dx))
      ..scale(
        horizontal.distance / layout.width,
        vertical.distance / layout.height,
      );
    layout.paint(canvas, Offset.zero);
    canvas.restore();
    return;
  }
  final Paint paint = Paint()
    ..color = color ?? colorFromArgb(stroke.color)
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..isAntiAlias = true;
  if (stroke.penStyle == PenStyle.pencil) {
    paint.color = paint.color.withAlpha(205);
  }
  // 归一化粗细换算成当前绘制目标的像素粗细。最小宽度钳制留在像素侧：
  // 缩略图上的下限本来就该比主画布小。
  final double pixelWidth = inkPixelWidth(stroke.width, size);

  if (stroke.kind == StrokeKind.highlighter) {
    if (stroke.points.length == 1) {
      final InkPoint point = stroke.points.first;
      paint
        ..style = PaintingStyle.fill
        ..color = paint.color.withAlpha(88)
        ..blendMode = BlendMode.multiply;
      canvas.drawCircle(
        Offset(point.x * size.width, point.y * size.height),
        pixelWidth / 2,
        paint,
      );
      return;
    }
    final Path path = Path();
    final InkPoint first = stroke.points.first;
    path.moveTo(first.x * size.width, first.y * size.height);
    for (int i = 1; i < stroke.points.length; i++) {
      final InkPoint point = stroke.points[i];
      path.lineTo(point.x * size.width, point.y * size.height);
    }
    paint
      ..color = paint.color.withAlpha(88)
      ..strokeWidth = pixelWidth
      ..blendMode = BlendMode.multiply;
    canvas.drawPath(path, paint);
    return;
  }

  if (stroke.points.length == 1) {
    final InkPoint point = stroke.points.first;
    paint.style = PaintingStyle.fill;
    canvas.drawCircle(
      Offset(point.x * size.width, point.y * size.height),
      math.max(0.7, pixelWidth * _pressureFactor(stroke, point.pressure) / 2),
      paint,
    );
    return;
  }

  // 压感逐线段应用，既保留笔锋变化，也避免为每段构造独立 Path。
  for (int i = 1; i < stroke.points.length; i++) {
    final InkPoint from = stroke.points[i - 1];
    final InkPoint to = stroke.points[i];
    paint.strokeWidth = math.max(
      0.8,
      pixelWidth * _pressureFactor(stroke, to.pressure),
    );
    canvas.drawLine(
      Offset(from.x * size.width, from.y * size.height),
      Offset(to.x * size.width, to.y * size.height),
      paint,
    );
  }
}

/// 将采样压力映射为笔型对应的宽度系数，圆珠笔等固定宽度笔型不随压力变化。
double _pressureFactor(InkStroke stroke, double pressure) =>
    penPressureWidthFactor(stroke.penStyle, pressure);
