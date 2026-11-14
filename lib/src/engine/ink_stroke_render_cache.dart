part of 'ink_canvas.dart';

/// 仅用于显示的容量受限缓存；PageInk 始终是可编辑的原始数据。
/// 新增笔迹复用旧缓存；修改、撤销或替换操作使相关缓存失效。
class _InkStrokeRenderCache {
  /// _limitBytes：静态 Picture 缓存的字节预算上限，超出时淘汰旧对象。
  static const int _limitBytes = 24 * 1024 * 1024;

  /// 按笔画、页面尺寸和显示墨色缓存，换纸不会回放旧墨色。
  final _pictures = <(InkStroke, Size, int), (ui.Picture, int)>{};

  /// _bounds：按笔画身份和页面尺寸缓存的逻辑坐标边界。
  final _bounds = <(InkStroke, Size), Rect>{};

  /// _boundsSizes：边界缓存中已出现的页面尺寸集合，用于控制尺寸切换后的缓存量。
  final _boundsSizes = <Size, bool>{};

  /// _lastBoundsSize：最近查询边界使用的页面尺寸，用于识别尺寸切换。
  Size? _lastBoundsSize;

  /// _versions：各笔画的渲染版本，内容改变后旧 Picture 与瓦片必须失效。
  final _versions = <InkStroke, int>{};

  /// epoch：渲染缓存的整体代次，清空或失效时用于区分旧布局。
  int epoch = 0;

  /// _bytes：当前缓存估算占用字节数，随创建、淘汰和清空同步更新。
  int _bytes = 0;

  /// 返回指定笔画当前显示版本，未出现过的对象按初始版本处理。
  int version(InkStroke stroke) => _versions[stroke] ?? 0;

  /// 按页面尺寸计算并缓存笔画的逻辑边界；文字需使用真实排版而非只看锚点。
  Rect bounds(InkStroke stroke, Size size) {
    if (_lastBoundsSize != size) {
      _boundsSizes.remove(size);
      _boundsSizes[size] = true;
      _lastBoundsSize = size;
      while (_boundsSizes.length > 2) {
        final oldest = _boundsSizes.keys.first;
        _boundsSizes.remove(oldest);
        _bounds.removeWhere((key, _) => key.$2 == oldest);
      }
    }
    return _bounds.putIfAbsent((stroke, size), () {
      if (stroke.points.isEmpty) return Rect.zero;
      var left = double.infinity, top = double.infinity;
      var right = double.negativeInfinity, bottom = double.negativeInfinity;
      for (final p in stroke.points) {
        left = math.min(left, p.x * size.width);
        right = math.max(right, p.x * size.width);
        top = math.min(top, p.y * size.height);
        bottom = math.max(bottom, p.y * size.height);
      }
      final padding = stroke.text != null
          ? math.max(2.0, stroke.textSize * size.height * .5)
          : math.max(2.0, inkPixelWidth(stroke.width, size) * 1.5);
      return Rect.fromLTRB(left, top, right, bottom).inflate(padding);
    });
  }

  /// 递增目标笔画显示版本并释放相应旧绘制记录，使空间瓦片能识别内容已变。
  void invalidate(Iterable<InkStroke> strokes) {
    final changed = strokes.toSet();
    for (final stroke in changed) {
      _versions[stroke] = version(stroke) + 1;
    }
    for (final key
        in _pictures.keys.where((k) => changed.contains(k.$1)).toList()) {
      final entry = _pictures.remove(key)!;
      _bytes -= entry.$2;
      entry.$1.dispose();
    }
    _bounds.removeWhere((key, _) => changed.contains(key.$1));
  }

  /// 优先回放已缓存的单笔绘制记录，缓存未命中时才建立 Picture 并纳入预算。
  void paint(Canvas canvas, Size size, InkStroke stroke, {bool? paperDark}) {
    if (stroke.kind == StrokeKind.image && stroke.text == null) return;
    final color = _displayStrokeColor(stroke, paperDark);
    final key = (stroke, size, color.toARGB32());
    var entry = _pictures.remove(key);
    if (entry == null) {
      final recorder = ui.PictureRecorder();
      _paintBatchedInkStroke(Canvas(recorder), size, stroke, color: color);
      final picture = recorder.endRecording();
      entry = (picture, math.max(512, picture.approximateBytesUsed));
      if (entry.$2 > _limitBytes) {
        canvas.drawPicture(picture);
        picture.dispose();
        return;
      }
      while (_pictures.isNotEmpty &&
          (_bytes + entry.$2 > _limitBytes || _pictures.length >= 8192)) {
        final oldest = _pictures.remove(_pictures.keys.first)!;
        _bytes -= oldest.$2;
        oldest.$1.dispose();
      }
      _bytes += entry.$2;
    }
    _pictures[key] = entry;
    canvas.drawPicture(entry.$1);
  }

  /// 释放所有 Picture 和边界索引并更新整体代次，不删除原笔迹。
  void clear() {
    for (final entry in _pictures.values) {
      entry.$1.dispose();
    }
    _pictures.clear();
    _bounds.clear();
    _boundsSizes.clear();
    _lastBoundsSize = null;
    _versions.clear();
    epoch++;
    _bytes = 0;
  }
}

/// 将压力宽度相近的线段分桶批量绘制，减少逐段画笔与 Path 调用开销。
void _paintBatchedInkStroke(
  Canvas canvas,
  Size size,
  InkStroke stroke, {
  Color? color,
}) {
  // 保留文字、正片叠底、半透明叠加及铅笔纹理。
  if (stroke.text != null ||
      stroke.kind != StrokeKind.pen ||
      stroke.penStyle == PenStyle.pencil ||
      Color(stroke.color).a < 1 ||
      stroke.points.length < 2) {
    _paintInkStroke(canvas, size, stroke, color: color);
    return;
  }
  final buckets = <int, List<double>>{};
  final width = inkPixelWidth(stroke.width, size);
  for (var i = 1; i < stroke.points.length; i++) {
    final from = stroke.points[i - 1], to = stroke.points[i];
    // 布局误差最多为 1/16 像素，并保留原始压力数据。
    final bucket =
        (math.max(.8, width * _pressureFactor(stroke, to.pressure)) * 8)
            .round();
    (buckets[bucket] ??= []).addAll([
      from.x * size.width,
      from.y * size.height,
      to.x * size.width,
      to.y * size.height,
    ]);
  }
  final paint = Paint()
    ..color = color ?? Color(stroke.color)
    ..strokeCap = StrokeCap.round
    ..isAntiAlias = true;
  for (final bucket in buckets.entries) {
    paint.strokeWidth = bucket.key / 8;
    canvas.drawRawPoints(
      ui.PointMode.lines,
      Float32List.fromList(bucket.value),
      paint,
    );
  }
}
