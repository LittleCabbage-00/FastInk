part of 'ink_canvas.dart';

/// 创建和提交笔迹、形状与文本。
///
/// 所有坐标都按页面宽高归一化保存，使批注在缩放、窗口变化和导出时
/// 仍能落在同一内容位置；屏幕像素只用于命中半径和文本排版测量。
extension InkControllerDrawing on InkController {
  /// 开始一条笔画，记录首点、颜色、宽度和种类；实际持久提交在 finish 时完成。
  void begin(
    InkPoint point,
    Color color,
    double width,
    StrokeKind kind, [
    PenStyle penStyle = PenStyle.fountain,
  ]) {
    _clearActivePathCache();
    if (selectedStrokes.isNotEmpty || lassoPoints.isNotEmpty) {
      selectedStrokes.clear();
      lassoPoints.clear();
      _selectionChanged();
    }
    activeStroke = InkStroke(
      color: color.toARGB32(),
      width: width,
      kind: kind,
      penStyle: penStyle,
      points: <InkPoint>[point],
    );
    _activeChanged();
  }

  /// 向当前活动笔画追加采样点并增量更新路径；不重放已有长路径，不逐点生成撤销条目。
  void append(InkPoint point) {
    final InkStroke? active = activeStroke;
    if (active == null) return;
    final InkPoint previous = active.points.last;
    final double dx = point.x - previous.x;
    final double dy = point.y - previous.y;
    // 丢弃距离过近的采样点，减少抖动、文件体积和重绘线段数量。
    if (dx * dx + dy * dy < 0.00000004) return;
    active.points.add(point);
    _activeChanged();
  }

  /// 将尚未抬笔的钢笔笔画收敛为起点到终点的直线。
  /// 返回 false 表示笔画过短或当前工具不适合拉直。
  bool straightenActiveStroke(Size canvasSize, {double minimumLength = 24}) {
    final InkStroke? active = activeStroke;
    if (active == null ||
        active.kind != StrokeKind.pen ||
        active.points.length < 2 ||
        canvasSize.isEmpty) {
      return false;
    }
    final InkPoint start = active.points.first;
    final InkPoint end = active.points.last;
    final double dx = (end.x - start.x) * canvasSize.width;
    final double dy = (end.y - start.y) * canvasSize.height;
    if (math.sqrt(dx * dx + dy * dy) < minimumLength) return false;
    active.points
      ..clear()
      ..addAll(<InkPoint>[start, end]);
    _clearActivePathCache();
    _activeChanged();
    return true;
  }

  /// 拉直后继续拖动笔尖时只改变终点，抬笔前仍可调整长度和角度。
  void updateStraightenedStroke(InkPoint end) {
    final InkStroke? active = activeStroke;
    if (active == null || active.points.length != 2) return;
    active.points[1] = end;
    _clearActivePathCache();
    _activeChanged();
  }

  /// 开始可拖动的几何形状，以起点和页面尺寸作为生成基准。
  void beginShape(
    InkPoint point,
    Color color,
    double width,
    ShapeType shapeType, {
    Size canvasSize = const Size(1, 1),
  }) {
    _shapeCanvasSize = canvasSize.isEmpty ? const Size(1, 1) : canvasSize;
    begin(point, color, width, StrokeKind.pen, PenStyle.ball);
    _shapeStart = point;
    updateShape(point, shapeType);
  }

  /// 按当前拖动点和形状类型重算活动几何，源点仍使用归一化页面坐标。
  void updateShape(InkPoint current, ShapeType shapeType) {
    final InkStroke? active = activeStroke;
    final InkPoint? start = _shapeStart;
    if (active == null || start == null) return;
    final List<InkPoint> points = <InkPoint>[];
    switch (shapeType) {
      case ShapeType.line:
        points.addAll(<InkPoint>[start, current]);
        break;
      case ShapeType.arrow:
        final double dx = (current.x - start.x) * _shapeCanvasSize.width;
        final double dy = (current.y - start.y) * _shapeCanvasSize.height;
        final double length = math.sqrt(dx * dx + dy * dy);
        points.addAll(<InkPoint>[start, current]);
        if (length > 0) {
          final double head = math.min(
            length * .3,
            _shapeCanvasSize.shortestSide * .035,
          );
          final double ux = dx / length, uy = dy / length;
          // 在箭头方向两侧计算箭翼点，sign 区分左右侧。
          InkPoint wing(double sign) => InkPoint(
            current.x +
                (-ux * head + sign * uy * head * .5) / _shapeCanvasSize.width,
            current.y +
                (-uy * head - sign * ux * head * .5) / _shapeCanvasSize.height,
            current.pressure,
          );
          points.addAll(<InkPoint>[wing(1), current, wing(-1)]);
        }
        break;
      case ShapeType.triangle:
        points.addAll(<InkPoint>[
          InkPoint((start.x + current.x) / 2, start.y, current.pressure),
          current,
          InkPoint(start.x, current.y, current.pressure),
          InkPoint((start.x + current.x) / 2, start.y, current.pressure),
        ]);
        break;
      case ShapeType.diamond:
        final double mx = (start.x + current.x) / 2,
            my = (start.y + current.y) / 2;
        points.addAll(<InkPoint>[
          InkPoint(mx, start.y, current.pressure),
          InkPoint(current.x, my, current.pressure),
          InkPoint(mx, current.y, current.pressure),
          InkPoint(start.x, my, current.pressure),
          InkPoint(mx, start.y, current.pressure),
        ]);
        break;
      case ShapeType.rectangle:
        points.addAll(<InkPoint>[
          start,
          InkPoint(current.x, start.y, current.pressure),
          current,
          InkPoint(start.x, current.y, current.pressure),
          start,
        ]);
        break;
      case ShapeType.ellipse:
        final double centerX = (start.x + current.x) / 2;
        final double centerY = (start.y + current.y) / 2;
        final double radiusX = (current.x - start.x).abs() / 2;
        final double radiusY = (current.y - start.y).abs() / 2;
        // 固定 48 段在常用缩放范围内足够平滑，也避免形状产生过多节点。
        for (int i = 0; i <= 48; i++) {
          final double angle = math.pi * 2 * i / 48;
          points.add(
            InkPoint(
              centerX + math.cos(angle) * radiusX,
              centerY + math.sin(angle) * radiusY,
              current.pressure,
            ),
          );
        }
        break;
    }
    active.points
      ..clear()
      ..addAll(points);
    _activeChanged();
  }

  /// 完成活动笔画并合入当前页，生成一次历史和提交通知；没有活动输入时不创建空笔画。
  void finish() {
    final InkStroke? active = activeStroke;
    if (active == null) return;
    // 一次落笔只生成一条撤销记录；移动过程不重复复制整页历史。
    final _InkHistorySnapshot before = _captureHistory();
    strokes.add(active);
    _commitHistoryChange(before);
    activeStroke = null;
    _clearActivePathCache();
    _shapeStart = null;
    _activeChanged();
    _committedChanged(appendOnly: true);
    onCommitted();
  }

  /// 放弃未提交笔画并清理活动路径，不删除已提交内容。
  void cancel() {
    activeStroke = null;
    _clearActivePathCache();
    _shapeStart = null;
    _activeChanged();
  }

  /// 按页面尺寸把字号、宽度和锚点转换为文本笔画，保留完整源文与样式并生成一次可撤销提交。
  void addText(
    InkPoint anchor,
    Size canvasSize,
    String value,
    Color color,
    double fontSize, {
    double? boxWidth,
    int textWeight = 400,
    bool textItalic = false,
    bool textUnderline = false,
    TextAlign textAlign = TextAlign.left,
    String textFontFamily = 'Segoe UI Variable',
  }) {
    final String text = value.trim();
    if (text.isEmpty || canvasSize.isEmpty) return;
    final double availableWidth = math.max(
      40,
      canvasSize.width * (1 - anchor.x) - 12,
    );
    // textBoxWidth 是排版宽度，四个点是变换后的可见框；调整框时按宽度重新排版。
    final double layoutWidth = (boxWidth ?? math.min(280, availableWidth))
        .clamp(40, availableWidth);
    final TextPainter layout = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontFamily: textFontFamily,
          fontFamilyFallback: const <String>['Microsoft YaHei UI'],
          fontSize: fontSize,
          fontWeight: FontWeight.values.firstWhere(
            (FontWeight weight) => weight.value == textWeight,
            orElse: () => FontWeight.w400,
          ),
          fontStyle: textItalic ? FontStyle.italic : FontStyle.normal,
          decoration: textUnderline
              ? TextDecoration.underline
              : TextDecoration.none,
        ),
      ),
      textAlign: textAlign,
      textWidthBasis: TextWidthBasis.parent,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: layoutWidth);
    final double right = (anchor.x + layoutWidth / canvasSize.width).clamp(
      0.0,
      1.0,
    );
    // 选区必须包住实际绘制内容，包括用户尚未调整大小、
    // 因而超出页面范围的完整文字。
    final double bottom = anchor.y + layout.height / canvasSize.height;
    layout.dispose();
    final InkStroke stroke = InkStroke(
      color: color.toARGB32(),
      width: 1,
      text: text,
      textSize: fontSize / canvasSize.height,
      textBoxWidth: layoutWidth / canvasSize.width,
      textWeight: textWeight,
      textItalic: textItalic,
      textUnderline: textUnderline,
      textAlign: textAlign,
      textFontFamily: textFontFamily,
      points: <InkPoint>[
        anchor,
        InkPoint(right, anchor.y, 0.5),
        InkPoint(right, bottom, 0.5),
        InkPoint(anchor.x, bottom, 0.5),
      ],
    );
    final _InkHistorySnapshot before = _captureHistory();
    strokes.add(stroke);
    selectedStrokes
      ..clear()
      ..add(stroke);
    _commitHistoryChange(before);
    _committedChanged(appendOnly: true);
    _selectionChanged();
    onCommitted();
  }

  /// 在可见区域中央插入图片并选中。placementBounds 使用页面逻辑坐标，
  /// 为空时按整页布局。保存的四角始终按整页宽高归一化。
  void addImage(
    String asset,
    double aspectRatio,
    Size canvasSize, {
    Rect? placementBounds,
  }) {
    if (asset.isEmpty ||
        !aspectRatio.isFinite ||
        aspectRatio <= 0 ||
        canvasSize.isEmpty) {
      return;
    }
    final page = Offset.zero & canvasSize;
    final visible = placementBounds?.intersect(page) ?? page;
    final area = visible.isEmpty ? page : visible;
    double width = math.min(area.width * 0.62, 560);
    double height = width / aspectRatio;
    if (height > area.height * 0.72) {
      height = area.height * 0.72;
      width = height * aspectRatio;
    }
    final double left = (area.center.dx - width / 2) / canvasSize.width;
    final double top = (area.center.dy - height / 2) / canvasSize.height;
    final double right = left + width / canvasSize.width;
    final double bottom = top + height / canvasSize.height;
    final InkStroke stroke = InkStroke(
      color: 0,
      width: 1,
      kind: StrokeKind.image,
      imageAsset: asset,
      points: <InkPoint>[
        InkPoint(left, top, 0.5),
        InkPoint(right, top, 0.5),
        InkPoint(right, bottom, 0.5),
        InkPoint(left, bottom, 0.5),
      ],
    );
    final _InkHistorySnapshot before = _captureHistory();
    strokes.add(stroke);
    selectedStrokes
      ..clear()
      ..add(stroke);
    _commitHistoryChange(before);
    _committedChanged(appendOnly: true);
    _selectionChanged();
    onCommitted();
  }

  /// 复制选中内容后走统一粘贴路径，确保得到独立对象和正确历史。
  void duplicateSelection() => pasteStrokes(copySelection());

  /// 更新指定文本的全文、样式和几何；尺寸单位以给定页面为准，整体作为一次历史操作提交。
  void updateText(
    InkStroke original,
    String value,
    Size canvasSize, {
    double? boxWidth,
    Color? color,
    double? fontSize,
    int? textWeight,
    bool? textItalic,
    bool? textUnderline,
    TextAlign? textAlign,
    String? textFontFamily,
    InkPoint? anchor,
    double? rotation,
    bool resetScale = false,
  }) {
    final int index = strokes.indexOf(original);
    final String text = value.trim();
    if (index < 0 ||
        original.text == null ||
        original.points.length < 4 ||
        canvasSize.isEmpty) {
      return;
    }
    final _InkHistorySnapshot before = _captureHistory();
    if (text.isEmpty) {
      strokes.removeAt(index);
      selectedStrokes.clear();
    } else {
      final InkPoint oldOrigin = original.points[0];
      final InkPoint origin = anchor ?? oldOrigin;
      final InkPoint oldRight = original.points[1];
      final Offset horizontal = Offset(
        (oldRight.x - oldOrigin.x) * canvasSize.width,
        (oldRight.y - oldOrigin.y) * canvasSize.height,
      );
      final double oldBaseWidth = math.max(
        1,
        (original.textBoxWidth ?? horizontal.distance / canvasSize.width) *
            canvasSize.width,
      );
      // 编辑时使用显示尺寸，保存时按可见宽度与排版宽度之比还原基础尺寸。
      // 自动避让按实际显示字号排版，清除旧缩放，避免两套字号计算产生换行误差。
      final double scale = resetScale
          ? 1
          : (horizontal.distance / oldBaseWidth).clamp(0.01, 20);
      final double nextDisplayedWidth = (boxWidth ?? horizontal.distance).clamp(
        40.0,
        canvasSize.width,
      );
      final double nextBaseWidth = nextDisplayedWidth / scale;
      final double nextBaseFontSize =
          (fontSize ?? original.textSize * canvasSize.height * scale) / scale;
      final int nextWeight = textWeight ?? original.textWeight;
      final bool nextItalic = textItalic ?? original.textItalic;
      final bool nextUnderline = textUnderline ?? original.textUnderline;
      final TextAlign nextAlign = textAlign ?? original.textAlign;
      final String nextFamily = textFontFamily ?? original.textFontFamily;
      final TextPainter newLayout = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            fontFamily: nextFamily,
            fontFamilyFallback: const <String>['Microsoft YaHei UI'],
            fontSize: nextBaseFontSize,
            fontWeight: FontWeight.values.firstWhere(
              (FontWeight weight) => weight.value == nextWeight,
              orElse: () => FontWeight.w400,
            ),
            fontStyle: nextItalic ? FontStyle.italic : FontStyle.normal,
            decoration: nextUnderline
                ? TextDecoration.underline
                : TextDecoration.none,
          ),
        ),
        textAlign: nextAlign,
        textWidthBasis: TextWidthBasis.parent,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: nextBaseWidth);
      final double angle = rotation ?? math.atan2(horizontal.dy, horizontal.dx);
      final double cosine = math.cos(angle);
      final double sine = math.sin(angle);
      final double displayedHeight = newLayout.height * scale;
      newLayout.dispose();
      final InkPoint right = InkPoint(
        origin.x + nextDisplayedWidth * cosine / canvasSize.width,
        origin.y + nextDisplayedWidth * sine / canvasSize.height,
        oldRight.pressure,
      );
      final InkPoint bottom = InkPoint(
        origin.x - displayedHeight * sine / canvasSize.width,
        origin.y + displayedHeight * cosine / canvasSize.height,
        0.5,
      );
      final InkStroke updated = InkStroke(
        color: (color ?? Color(original.color)).toARGB32(),
        width: original.width,
        kind: original.kind,
        penStyle: original.penStyle,
        text: text,
        textSize: nextBaseFontSize / canvasSize.height,
        textBoxWidth: nextBaseWidth / canvasSize.width,
        textWeight: nextWeight,
        textItalic: nextItalic,
        textUnderline: nextUnderline,
        textAlign: nextAlign,
        textFontFamily: nextFamily,
        points: <InkPoint>[
          origin,
          right,
          InkPoint(
            right.x + bottom.x - origin.x,
            right.y + bottom.y - origin.y,
            0.5,
          ),
          bottom,
        ],
      );
      strokes[index] = updated;
      selectedStrokes
        ..clear()
        ..add(updated);
    }
    _commitHistoryChange(before);
    _committedChanged(appendOnly: true);
    _selectionChanged();
    onCommitted();
  }
}
