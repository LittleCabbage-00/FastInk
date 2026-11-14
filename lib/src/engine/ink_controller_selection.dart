part of 'ink_canvas.dart';

/// 选区命中、变换和橡皮擦处理。
///
/// 命中检测先用包围盒排除绝大多数无关笔迹，再做线段级精确计算；
/// 控制柄始终按屏幕像素计算，页面缩放不会让它变得难以点击。
extension InkControllerSelection on InkController {
  /// 倒序检查绘制列表，返回包含 [point] 的最上层文本框。
  InkStroke? textStrokeAt(InkPoint point) {
    final Offset target = Offset(point.x, point.y);
    for (final InkStroke stroke in strokes.reversed) {
      if (stroke.text == null || stroke.points.length < 4) continue;
      bool inside = false;
      for (
        int i = 0, j = stroke.points.length - 1;
        i < stroke.points.length;
        j = i++
      ) {
        final InkPoint a = stroke.points[i];
        final InkPoint b = stroke.points[j];
        final bool crosses =
            (a.y > target.dy) != (b.y > target.dy) &&
            target.dx < (b.x - a.x) * (target.dy - a.y) / (b.y - a.y) + a.x;
        if (crosses) inside = !inside;
      }
      if (inside) return stroke;
    }
    return null;
  }

  /// 返回点击位置最上层的文字或图片对象，供套索工具直接点选。
  InkStroke? objectStrokeAt(InkPoint point) {
    final Offset target = Offset(point.x, point.y);
    for (final InkStroke stroke in strokes.reversed) {
      if (!canSelectStroke(stroke)) continue;
      if ((stroke.text == null && stroke.kind != StrokeKind.image) ||
          stroke.points.length < 4) {
        continue;
      }
      bool inside = false;
      for (
        int i = 0, j = stroke.points.length - 1;
        i < stroke.points.length;
        j = i++
      ) {
        final InkPoint a = stroke.points[i];
        final InkPoint b = stroke.points[j];
        final bool crosses =
            (a.y > target.dy) != (b.y > target.dy) &&
            target.dx < (b.x - a.x) * (target.dy - a.y) / (b.y - a.y) + a.x;
        if (crosses) inside = !inside;
      }
      if (inside) return stroke;
    }
    return null;
  }

  /// 清空旧选择并仅选择指定对象，通知选区显示与工具栏。
  void selectOnly(InkStroke stroke) {
    if (!strokes.contains(stroke)) return;
    selectedStrokes
      ..clear()
      ..add(stroke);
    lassoPoints.clear();
    _selectionChanged();
  }

  /// 按页面逻辑尺寸、半径和橡皮模式命中并擦除；返回是否真正改变内容，连续事件由外层事务合并。
  bool eraseAt(InkPoint point, Size size, double radius, EraserMode mode) {
    // 一次擦除手势共享边界缓存和历史事务；松笔后统一提交撤销记录。
    _InkHistorySnapshot? before;
    final double radiusSquared = radius * radius;
    bool changed = false;

    // 判断候选采样点是否落在当前橡皮的实际范围内。
    bool isInside(InkPoint candidate) {
      final double dx = (candidate.x - point.x) * size.width;
      final double dy = (candidate.y - point.y) * size.height;
      return dx * dx + dy * dy <= radiusSquared;
    }

    // 判断笔画线段是否与擦除区域相交，避免只有端点命中才擦除的遗漏。
    bool segmentHits(InkPoint a, InkPoint b) {
      final double ax = a.x * size.width;
      final double ay = a.y * size.height;
      final double bx = b.x * size.width;
      final double by = b.y * size.height;
      final double px = point.x * size.width;
      final double py = point.y * size.height;
      final double vx = bx - ax;
      final double vy = by - ay;
      final double lengthSquared = vx * vx + vy * vy;
      final double t = lengthSquared == 0
          ? 0
          : (((px - ax) * vx + (py - ay) * vy) / lengthSquared).clamp(0.0, 1.0);
      final double dx = px - (ax + vx * t);
      final double dy = py - (ay + vy * t);
      return dx * dx + dy * dy <= radiusSquared;
    }

    // 对一条笔画执行当前擦除命中判定，先用边界排除再检查细节。
    bool strokeHits(InkStroke stroke) {
      if (stroke.points.any(isInside)) return true;
      for (int j = 1; j < stroke.points.length; j++) {
        if (segmentHits(stroke.points[j - 1], stroke.points[j])) return true;
      }
      return false;
    }

    // 倒序处理可安全地原地删除笔迹，也符合“上层内容先命中”的视觉顺序。
    for (int i = strokes.length - 1; i >= 0; i--) {
      final InkStroke stroke = strokes[i];
      if (eraseHighlighterOnly && stroke.kind != StrokeKind.highlighter) {
        continue;
      }
      // 空间边界是廉价的粗筛；只有可能相交的笔迹才进入逐线段检测。
      if (!_eraserBounds.canHit(stroke, point, size, radius)) continue;
      final cuts =
          mode == EraserMode.point &&
              stroke.text == null &&
              stroke.kind != StrokeKind.image
          ? cutInkStrokeOutsideCircle(stroke, point, size, radius)
          : null;
      if (mode == EraserMode.point &&
          stroke.text == null &&
          stroke.kind != StrokeKind.image) {
        if (cuts == null) continue;
      } else if (!strokeHits(stroke)) {
        continue;
      }
      before ??= _historyTransactionStart ?? _captureHistory();
      changed = true;
      _eraserBounds.remove(stroke);
      if (mode == EraserMode.stroke ||
          stroke.text != null ||
          stroke.kind == StrokeKind.image) {
        strokes.removeAt(i);
        continue;
      }

      strokes
        ..removeAt(i)
        ..insertAll(i, cuts!);
    }
    if (changed) {
      if (selectedStrokes.isNotEmpty) {
        final remaining = strokes.toSet();
        selectedStrokes.removeWhere(
          (selected) => !remaining.contains(selected),
        );
      }
      _commitHistoryChange(before!);
      if (_historyTransactionStart != null) {
        // 手势中只刷新笔迹层；状态栏和保存队列在松手时更新一次。
        _committedRevision.value++;
        _selectionChanged(notifyToolbar: false);
      } else {
        _committedChanged(appendOnly: true);
        _selectionChanged();
        onCommitted();
      }
    }
    return changed;
  }

  /// 开始套索并保存首点，结束时才根据闭合区域更新选择。
  void beginLasso(InkPoint point) {
    _rectangularLasso = false;
    selectedStrokes.clear();
    lassoPoints
      ..clear()
      ..add(point);
    _selectionChanged();
  }

  /// 追加套索采样点，保留当前输入轨迹供选择预览。
  void appendLasso(InkPoint point) {
    if (lassoPoints.isEmpty) return;
    final InkPoint previous = lassoPoints.last;
    final double dx = point.x - previous.x;
    final double dy = point.y - previous.y;
    // 套索无需保存每个触摸采样，适度抽稀能降低命中计算和重绘负担。
    if (dx * dx + dy * dy < 0.000004) return;
    lassoPoints.add(point);
    _selectionChanged(notifyToolbar: false);
  }

  /// 由起止点重建矩形套索区域，和自由套索共享后续命中逻辑。
  void setRectangleLasso(InkPoint start, InkPoint end) {
    _rectangularLasso = true;
    final double left = math.min(start.x, end.x);
    final double top = math.min(start.y, end.y);
    final double right = math.max(start.x, end.x);
    final double bottom = math.max(start.y, end.y);
    lassoPoints
      ..clear()
      ..addAll(<InkPoint>[
        InkPoint(left, top, start.pressure),
        InkPoint(right, top, start.pressure),
        InkPoint(right, bottom, start.pressure),
        InkPoint(left, bottom, start.pressure),
        InkPoint(left, top, start.pressure),
      ]);
    _selectionChanged(notifyToolbar: false);
  }

  /// 结束套索采样，结合类型过滤与空间命中得到最终选中对象。
  void finishLasso() {
    if (lassoPoints.length >= 3) {
      double left = 1;
      double top = 1;
      double right = 0;
      double bottom = 0;
      for (final InkPoint point in lassoPoints) {
        left = math.min(left, point.x);
        top = math.min(top, point.y);
        right = math.max(right, point.x);
        bottom = math.max(bottom, point.y);
      }
      final Rect lassoBounds = Rect.fromLTRB(left, top, right, bottom);
      final polygon = _rectangularLasso ? null : _InkLassoIndex(lassoPoints);
      for (final InkStroke stroke in strokes) {
        if (stroke.points.isEmpty || !canSelectStroke(stroke)) continue;
        // 先比较包围盒，避免对完全不相邻的笔迹运行多边形检测。
        if (!lassoBounds.overlaps(
          _eraserBounds.bounds(stroke).inflate(0.000001),
        )) {
          continue;
        }
        final bool hits = _rectangularLasso
            ? stroke.points.any(
                    (InkPoint point) =>
                        lassoBounds.contains(Offset(point.x, point.y)),
                  ) ||
                  _strokeCrossesRectangle(stroke, lassoBounds)
            : stroke.points.any(polygon!.contains);
        if (hits) selectedStrokes.add(stroke);
      }
    }
    lassoPoints.clear();
    _rectangularLasso = false;
    _selectionChanged();
  }

  /// 检测笔画线段与矩形相交，解决穿过框但所有采样点都在框外的情况。
  bool _strokeCrossesRectangle(InkStroke stroke, Rect rectangle) {
    for (int index = 1; index < stroke.points.length; index++) {
      final InkPoint a = stroke.points[index - 1];
      final InkPoint b = stroke.points[index];
      final double dx = b.x - a.x;
      final double dy = b.y - a.y;
      final List<double> p = <double>[-dx, dx, -dy, dy];
      final List<double> q = <double>[
        a.x - rectangle.left,
        rectangle.right - a.x,
        a.y - rectangle.top,
        rectangle.bottom - a.y,
      ];
      double enter = 0;
      double exit = 1;
      bool outside = false;
      // 用 Liang–Barsky 裁剪检测穿过选区的线段，包括两端均在框外的情况。
      for (int edge = 0; edge < 4; edge++) {
        if (p[edge].abs() < 1e-12) {
          if (q[edge] < 0) outside = true;
          continue;
        }
        final double t = q[edge] / p[edge];
        if (p[edge] < 0) {
          enter = math.max(enter, t);
        } else {
          exit = math.min(exit, t);
        }
      }
      if (!outside && enter <= exit) return true;
    }
    return false;
  }

  /// 根据命中把手、边框与选区确定平移/缩放/旋转类型，保存起始几何；未命中时返回 null。
  SelectionTransform? beginSelectionTransform(
    InkPoint point,
    Size size, {
    double hitRadius = 64,
    bool includeInterior = true,
  }) {
    final Rect? bounds = selectionBounds;
    if (bounds == null) return null;
    // 控制柄使用固定屏幕尺寸，命中半径需换算为页面坐标。
    final double inverseScale = 1 / selectionViewScale;
    final double padding = _selectionPaddingScreen * inverseScale;
    final double handleX = bounds.right * size.width + padding;
    final double handleY = bounds.bottom * size.height + padding;
    final double dx = point.x * size.width - handleX;
    final double dy = point.y * size.height - handleY;
    final double scaleDistanceSquared = dx * dx + dy * dy;
    final bool singleImage =
        selectedStrokes.length == 1 &&
        selectedStrokes.single.kind == StrokeKind.image;
    // 小图的内部要留出移动区域，避免较大的控制柄热区盖住整张图。
    final bool insideImage =
        singleImage && bounds.contains(Offset(point.x, point.y));
    final double localHitRadius =
        (insideImage
            ? 0.0
            : singleImage
            ? math.min(18.0, hitRadius)
            : hitRadius) *
        inverseScale;
    final bool onScaleHandle =
        scaleDistanceSquared <= localHitRadius * localHitRadius;
    final double rotateX = bounds.center.dx * size.width;
    final double rotateY = math.max(
      _selectionHandleRadiusScreen * inverseScale,
      bounds.top * size.height -
          padding -
          _selectionRotateGapScreen * inverseScale,
    );
    final double rotateDx = point.x * size.width - rotateX;
    final double rotateDy = point.y * size.height - rotateY;
    final double rotateDistanceSquared =
        rotateDx * rotateDx + rotateDy * rotateDy;
    final bool onRotateHandle =
        rotateDistanceSquared <= localHitRadius * localHitRadius &&
        (!onScaleHandle || rotateDistanceSquared < scaleDistanceSquared);
    final double edgePadding = math.max(
      18 * inverseScale / size.width,
      18 * inverseScale / size.height,
    );
    final Rect expanded = bounds.inflate(edgePadding);
    final Offset localPoint = Offset(point.x, point.y);
    final bool hasInterior =
        bounds.width > edgePadding * 2 && bounds.height > edgePadding * 2;
    final bool insideMoveArea = includeInterior
        ? expanded.contains(localPoint)
        : hasInterior &&
              expanded.contains(localPoint) &&
              !bounds.deflate(edgePadding).contains(localPoint);
    if (!onRotateHandle && !onScaleHandle && !insideMoveArea) {
      return null;
    }
    // 旋转柄优先于缩放柄，内容很小时两个命中圆重叠也不会选错操作。
    _selectionTransform = onRotateHandle
        ? SelectionTransform.rotate
        : onScaleHandle
        ? SelectionTransform.scale
        : SelectionTransform.move;
    // 拖动开始时只保存一次原始点；后续帧始终从该快照计算，
    // 避免连续缩放和旋转积累浮点误差。
    beginHistoryTransaction(captureSelectedPoints: true);
    _transformStart = point;
    _transformBounds = bounds;
    _transformStartAngle = math.atan2(
      point.y * size.height - bounds.center.dy * size.height,
      point.x * size.width - bounds.center.dx * size.width,
    );
    _selectionChangedDuringDrag = false;
    _transformOrigin
      ..clear()
      ..addEntries(
        selectedStrokes.map(
          (InkStroke stroke) => MapEntry<InkStroke, List<InkPoint>>(
            stroke,
            List<InkPoint>.of(stroke.points),
          ),
        ),
      );
    return _selectionTransform;
  }
}
