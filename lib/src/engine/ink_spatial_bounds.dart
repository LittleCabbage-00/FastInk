part of 'ink_canvas.dart';

/// 每次套索手势只按纵向分带建立一次索引，再计算精确射线交点。
class _InkLassoIndex {
  /// 将套索线段按纵向条带建立索引，加速多笔画逐点包含检测。
  _InkLassoIndex(List<InkPoint> points) {
    for (var i = 0, j = points.length - 1; i < points.length; j = i++) {
      final a = points[i], b = points[j];
      if (a.y == b.y) continue;
      final first = (math.min(a.y, b.y) * 128).floor().clamp(0, 127);
      final last = (math.max(a.y, b.y) * 128).floor().clamp(0, 127);
      for (var band = first; band <= last; band++) {
        _bands[band].add((a, b));
      }
    }
  }

  /// _bands：按纵向分成 128 桶的套索边索引，命中点只需查询所在条带。
  final _bands = List.generate(128, (_) => <(InkPoint, InkPoint)>[]);

  /// 只查询点所在条带的边并执行射线交点计数，返回是否在套索内。
  bool contains(InkPoint point) {
    var inside = false;
    for (final (a, b) in _bands[(point.y * 128).floor().clamp(0, 127)]) {
      if ((a.y > point.y) != (b.y > point.y) &&
          point.x < (b.x - a.x) * (point.y - a.y) / (b.y - a.y) + a.x) {
        inside = !inside;
      }
    }
    return inside;
  }
}

class _InkStrokeBoundsCache {
  /// _bounds：按笔画对象缓存的归一化几何边界，先排除不可能命中的笔画。
  final Map<InkStroke, Rect> _bounds = <InkStroke, Rect>{};

  /// 清空笔画边界缓存，结构变化后不得继续用旧边界排除命中。
  void clear() => _bounds.clear();

  /// 仅移除指定笔画的旧边界缓存。
  void remove(InkStroke stroke) => _bounds.remove(stroke);

  /// 返回或计算笔画的归一化边界，缓存只对未修改的对象有效。
  Rect bounds(InkStroke stroke) => _bounds.putIfAbsent(stroke, () {
    if (stroke.points.isEmpty) return Rect.zero;
    double left = double.infinity, top = double.infinity;
    double right = double.negativeInfinity, bottom = double.negativeInfinity;
    for (final point in stroke.points) {
      left = math.min(left, point.x);
      top = math.min(top, point.y);
      right = math.max(right, point.x);
      bottom = math.max(bottom, point.y);
    }
    return Rect.fromLTRB(left, top, right, bottom);
  });

  /// 把笔画边界与按页面尺寸换算的橡皮范围比较，快速排除不相交对象。
  bool canHit(InkStroke stroke, InkPoint point, Size size, double radius) {
    if (stroke.points.isEmpty) return false;
    final Rect box = bounds(stroke);
    // 边界只在当前橡皮手势内复用；页面切换和选区变换不会留下旧坐标。
    final double horizontalRadius = radius / size.width;
    final double verticalRadius = radius / size.height;
    return point.x >= box.left - horizontalRadius &&
        point.x <= box.right + horizontalRadius &&
        point.y >= box.top - verticalRadius &&
        point.y <= box.bottom + verticalRadius;
  }
}
