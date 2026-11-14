part of 'ink_canvas.dart';

/// 页面尺寸、瓦片区域、内容代次、栅格密度和模板纸色策略。
typedef _InkRasterKey = (Size, Rect, int, double, bool?);

// 相邻缓存块预留两圈物理像素，避免非整数缩放时滤镜采到透明边缘而露白缝。
/// _inkRasterGutter：瓦片光栅化时额外保留的物理像素边缘，避免分数缩放时采样出接缝。
const double _inkRasterGutter = 2;

/// 将原始显示密度量化并限制，减少细小缩放变化引发整批瓦片重建。
double _inkRasterDensity(double raw) => math
    .pow(2, (math.log(math.max(.125, raw)) / math.ln2 * 2).ceil() / 2)
    .toDouble();

/// 根据栅格密度计算逻辑瓦片边长；经济模式合并小瓦片，减少组件与合成批次。
double _inkTileExtent(double density, {bool economical = false}) =>
    (economical ? 256 : 128) /
    math.pow(
      2,
      math.max(0, (math.log(math.max(1, density / 8)) / math.ln2).ceil()),
    );

class _InkTileData {
  /// 建立空间瓦片描述，收集相关笔画并结合其显示版本形成修订标识。
  _InkTileData(this.cell, this.rect, this.strokes, _InkStrokeRenderCache cache)
    : revision = Object.hashAll([
        cache.epoch,
        for (final s in strokes) Object.hash(s, cache.version(s)),
      ]),
      hasHighlighter = strokes.any((s) => s.kind == StrokeKind.highlighter);

  /// cell：瓦片在固定空间网格中的列、行编号。
  final (int, int) cell;

  /// rect：瓦片覆盖的页面逻辑矩形，绘制与命中必须使用同一坐标系。
  final Rect rect;

  /// strokes：当前对象持有的笔画集合，元素坐标和宽度遵循 InkStroke 数据约定。
  final List<InkStroke> strokes;

  /// revision：该显示数据的修订编号，内容变化后旧缓存键失效。
  final int revision;

  /// hasHighlighter：瓦片是否包含透明荧光笔，影响合成与重绘路径。
  final bool hasHighlighter;
}

class _InkTileCache {
  /// limitBytes：瓦片图像缓存的字节上限，预算调整后立即尝试淘汰。
  int limitBytes = 48 * 1024 * 1024;

  /// 把 MB 预算换算为字节并立即淘汰超预算图像，原笔迹集合不受影响。
  void setBudget(int megabytes) {
    limitBytes = megabytes.clamp(8, 96) * 1024 * 1024;
    _trim(0);
  }

  /// 为 incoming 字节的新图像腾出空间，淘汰时显式释放旧 GPU 图像。
  void _trim(int incoming) {
    while (_images.isNotEmpty && _bytes + incoming > limitBytes) {
      // 淘汰条目后必须 dispose 图像，仅从映射移除不会释放底层图形资源。
      final old = _images.remove(_images.keys.first)!;
      _bytes -= old.width * old.height * 4;
      old.dispose();
    }
  }

  /// _images：栅格缓存键到 GPU 图像的映射，移除条目时必须 dispose 图像。
  final _images = <_InkRasterKey, ui.Image>{};

  /// _layouts：根据尺寸、笔画修订与网格参数缓存的瓦片布局。
  final _layouts =
      <(Size, double), (int, List<InkStroke>, List<_InkTileData>)>{};

  /// _pending：已经排队但尚未完成的任务，按键合并，避免重复创建同一结果。
  final _pending = <_InkRasterKey, Future<bool>>{};

  /// _queue：串行任务链，前一次失败通过调用方捕获后不阻塞后续任务。
  Future<void> _queue = Future.value();

  /// _bytes：当前缓存估算占用字节数，随创建、淘汰和清空同步更新；_generation：任务代次；异步结果必须与当前代次一致才能提交，作废缓存时递增。
  int _bytes = 0, _generation = 0;

  /// _disposed：所属缓存是否已释放，异步任务返回后不能再提交资源。
  bool _disposed = false;

  /// preparedCount：测试记录的已完成光栅准备次数，不影响业务判定。
  int preparedCount = 0;

  /// 按页面尺寸、笔画修订和空间网格生成可复用瓦片布局，不随平移重新分配整页几何。
  List<_InkTileData> layout(
    Size size,
    List<InkStroke> strokes,
    int revision,
    _InkStrokeRenderCache cache,
    double extent,
  ) {
    // 布局键只含页面尺寸与空间网格，平移相机不应重分整页瓦片。
    final key = (size, extent);
    final old = _layouts.remove(key);
    if (old != null && old.$1 == revision && identical(old.$2, strokes)) {
      _layouts[key] = old;
      return old.$3;
    }
    // 每个网格单元只关联相交笔画，删除或擦除后可以局部重绘。
    final cells = <(int, int), List<InkStroke>>{};
    for (final stroke in strokes) {
      if (stroke.kind == StrokeKind.image && stroke.text == null) continue;
      final rect = cache.bounds(stroke, size).intersect(Offset.zero & size);
      if (rect.isEmpty) continue;
      for (
        var y = (rect.top / extent).floor();
        y <= (rect.bottom / extent).floor();
        y++
      ) {
        for (
          var x = (rect.left / extent).floor();
          x <= (rect.right / extent).floor();
          x++
        ) {
          (cells[(x, y)] ??= []).add(stroke);
        }
      }
    }
    final result = [
      for (final entry in cells.entries)
        _InkTileData(
          entry.key,
          Rect.fromLTWH(
            entry.key.$1 * extent,
            entry.key.$2 * extent,
            extent,
            extent,
          ).intersect(Offset.zero & size),
          entry.value,
          cache,
        ),
    ];
    _layouts[key] = (revision, strokes, result);
    while (_layouts.length > 2) {
      _layouts.remove(_layouts.keys.first);
    }
    return result;
  }

  /// 查询可用栅格图并维护最近使用次序；未命中返回 null 以便矢量回退。
  ui.Image? image(_InkRasterKey key) {
    final result = _images.remove(key);
    if (result != null) _images[key] = result;
    return result;
  }

  /// 合并同键的异步光栅任务并串行生成图像；提交前检查代次和释放状态，过期图像必须 dispose。
  Future<bool> prepare(
    _InkRasterKey key,
    Rect rect,
    bool Function() isCurrent,
    void Function(Canvas) draw, {
    Future<bool> Function()? waitForTurn,
  }) {
    if (_disposed || !isCurrent()) return Future.value(false);
    if (_images.containsKey(key)) return Future.value(true);
    // 同一个栅格身份已有任务时共享 Future，避免重复排队与纹理上传。
    final pending = _pending[key];
    if (pending != null) return pending;
    // 捕获本次代次；清空、换页或释放后，任务即使完成也不能提交。
    final generation = _generation;
    // 输出宽度按显示密度和 gutter 计算，gutter 防止分数缩放采样出现接缝。
    final width = math.max(
      1,
      (rect.width * key.$4 + _inkRasterGutter * 2).ceil(),
    );
    // 输出高度同样包含额外采样边缘，最终显示仍裁到真实瓦片矩形。
    final height = math.max(
      1,
      (rect.height * key.$4 + _inkRasterGutter * 2).ceil(),
    );
    if (width > 2048 || height > 2048) return Future.value(false);
    final result = _queue
        .then((_) async {
          if (_disposed || generation != _generation || !isCurrent()) {
            return false;
          }
          if (waitForTurn != null && !await waitForTurn()) return false;
          if (_disposed || generation != _generation || !isCurrent()) {
            return false;
          }
          final recorder = ui.PictureRecorder();
          final canvas = Canvas(recorder)
            ..scale(key.$4)
            ..translate(_inkRasterGutter / key.$4, _inkRasterGutter / key.$4);
          draw(canvas);
          // Picture 只用于生成当前图像；转换完成或失败后都应释放。
          final picture = recorder.endRecording();
          ui.Image image;
          try {
            image = await picture.toImage(width, height);
          } finally {
            picture.dispose();
          }
          if (_disposed || generation != _generation || !isCurrent()) {
            image.dispose();
            return false;
          }
          // RGBA 显示位图按每像素 4 字节估算预算，和原始笔迹点数分开。
          final bytes = width * height * 4;
          _trim(bytes);
          _images[key] = image;
          _bytes += bytes;
          preparedCount++;
          return true;
        })
        .catchError((Object _) => false);
    _pending[key] = result;
    _queue = result.then((_) {
      _pending.remove(key);
    });
    return result;
  }

  /// 作废排队结果并释放全部瓦片图像与布局缓存，避免旧任务完成后重新占用内存。
  void clear() {
    _generation++;
    for (final image in _images.values) {
      image.dispose();
    }
    _images.clear();
    _layouts.clear();
    _pending.clear();
    _bytes = 0;
  }

  /// 标记缓存不可用并执行清理，后续异步任务不得再提交图像。
  void dispose() {
    _disposed = true;
    clear();
  }
}
