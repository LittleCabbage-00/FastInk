part of 'ink_canvas.dart';

/// 在笔迹线段与橡皮圆的精确交点处分割；未擦到的采样保留原始
/// 坐标和压力，稀疏长线不会被强制密集重采样。
List<InkStroke>? cutInkStrokeOutsideCircle(
  InkStroke stroke,
  InkPoint center,
  Size size,
  double radius,
) {
  final points = stroke.points;
  if (points.isEmpty) return null;
  final radius2 = radius * radius;
  // 判定点是否处于当前擦除圆内，所有距离使用同一页面尺度。
  bool inside(InkPoint p) {
    final x = (p.x - center.x) * size.width;
    final y = (p.y - center.y) * size.height;
    return x * x + y * y < radius2 - 1e-8;
  }

  if (points.length == 1) return inside(points.first) ? [] : null;
  final fragments = <InkStroke>[];
  var current = <InkPoint>[];
  var changed = false;
  // 把一段保留片段的点追加到输出，避免连续重复点。
  void add(InkPoint p) {
    if (current.isEmpty ||
        current.last.x != p.x ||
        current.last.y != p.y ||
        current.last.pressure != p.pressure) {
      current.add(p);
    }
  }

  // 结束当前保留片段并加入结果，擦除范围两侧不得误连。
  void flush() {
    if (current.isNotEmpty) {
      fragments.add(stroke.copy(points: current));
      current = <InkPoint>[];
    }
  }

  for (var i = 1; i < points.length; i++) {
    final from = points[i - 1], to = points[i];
    final x = (from.x - center.x) * size.width;
    final y = (from.y - center.y) * size.height;
    final dx = (to.x - from.x) * size.width;
    final dy = (to.y - from.y) * size.height;
    final a = dx * dx + dy * dy;
    final b = 2 * (x * dx + y * dy);
    final c = x * x + y * y - radius2;
    final discriminant = b * b - 4 * a * c;
    if (a <= 1e-16 || discriminant <= 0) {
      if (inside(from)) {
        changed = true;
        flush();
      } else {
        add(from);
        add(to);
      }
      continue;
    }
    final root = math.sqrt(discriminant);
    final enter = math.max(0.0, (-b - root) / (2 * a));
    final exit = math.min(1.0, (-b + root) / (2 * a));
    if (exit - enter <= 1e-10) {
      add(from);
      add(to);
      continue;
    }
    changed = true;
    // 按线段参数 t 插值交点及压力，保留局部擦除后的连续宽度变化。
    InkPoint at(double t) => InkPoint(
      from.x + (to.x - from.x) * t,
      from.y + (to.y - from.y) * t,
      from.pressure + (to.pressure - from.pressure) * t,
    );
    if (enter > 0) {
      add(from);
      add(at(enter));
    }
    flush();
    if (exit < 1) {
      add(at(exit));
      add(to);
    }
  }
  flush();
  return changed ? fragments : null;
}
