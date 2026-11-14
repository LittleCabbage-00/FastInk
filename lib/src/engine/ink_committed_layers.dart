part of 'ink_canvas.dart';

/// 删除、拆分或重排笔迹时，空间瓦片的位置保持固定。
/// 只更新与改动相交的瓦片；拖动页面时合成尺寸受限的图像瓦片。
class _CommittedInkLayers extends StatelessWidget {
  /// 接收可见区域、墨色对比和渲染档位，组织已提交笔迹的瓦片。
  /// controller：该组件或绘制层使用的控制器，由构造方传入，具体内容遵循声明类型。
  /// strokes：当前对象持有的笔画集合，元素坐标和宽度遵循 InkStroke 数据约定。
  /// previewScale：缩略图相对原页面的显示倍数；为空时使用主视口的栅格策略。
  const _CommittedInkLayers({
    required this.controller,
    required this.strokes,
    this.previewScale,
    this.paperDark,
  });

  /// controller：该组件或绘制层使用的控制器，由构造方传入，具体内容遵循声明类型。
  final InkController controller;

  /// strokes：当前对象持有的笔画集合，元素坐标和宽度遵循 InkStroke 数据约定。
  final List<InkStroke> strokes;

  /// previewScale：缩略图相对原页面的显示倍数；为空时使用主视口的栅格策略。
  final double? previewScale;

  /// 模板纸色策略也参与栅格缓存键，换纸后立即用正确颜色回退绘制。
  final bool? paperDark;

  /// 按静态笔迹和可见区域建立瓦片组件，只绘制覆盖当前可见矩形的瓦片，已有子图像尽量复用。
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([
      controller.committedRepaint,
      if (previewScale == null) controller._viewRevision,
    ]),
    builder: (context, _) => LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final density = previewScale == null
            ? controller._rasterViewScale
            : _inkRasterDensity(
                MediaQuery.devicePixelRatioOf(context) * previewScale!,
              );
        // 低密度下合并小瓦片，减少组件、裁切、纹理上传和合成批次。
        final extent = previewScale == null
            ? controller._tileExtent
            : _inkTileExtent(
                density,
                economical: controller._economicalRendering,
              );
        final tiles = controller._tileCache.layout(
          size,
          identical(strokes, controller.strokes)
              ? controller._displayStrokes
              : strokes,
          controller._committedRevision.value,
          controller._committedRenderCache,
          extent,
        );
        final visible = previewScale != null
            ? Offset.zero & size
            : (controller._visiblePageRect ?? (Offset.zero & size));
        return Stack(
          fit: StackFit.expand,
          children: [
            for (final tile in tiles)
              if (!tile.rect.isEmpty && tile.rect.overlaps(visible))
                Positioned.fromRect(
                  key: ValueKey(('ink-tile', extent, tile.cell)),
                  rect: tile.rect,
                  child: _InkTile(
                    controller: controller,
                    tile: tile,
                    sourceSize: size,
                    density: density,
                    paperDark: paperDark,
                  ),
                ),
          ],
        );
      },
    ),
  );
}

class _InkTile extends StatefulWidget {
  /// 接收瓦片坐标、像素密度和缓存刷新所需的渲染状态。
  /// controller：该组件或绘制层使用的控制器，由构造方传入，具体内容遵循声明类型。
  /// tile：当前组件显示的空间瓦片数据，包含几何范围、笔画与修订号。
  /// sourceSize：原页面的逻辑尺寸，缩略图绘制需先按此尺寸解释坐标。
  /// density：每个页面逻辑像素对应的缓存像素数，控制显示精度与内存量。
  const _InkTile({
    required this.controller,
    required this.tile,
    required this.sourceSize,
    required this.density,
    required this.paperDark,
  });

  /// controller：该组件或绘制层使用的控制器，由构造方传入，具体内容遵循声明类型。
  final InkController controller;

  /// tile：当前组件显示的空间瓦片数据，包含几何范围、笔画与修订号。
  final _InkTileData tile;

  /// sourceSize：原页面的逻辑尺寸，缩略图绘制需先按此尺寸解释坐标。
  final Size sourceSize;

  /// density：每个页面逻辑像素对应的缓存像素数，控制显示精度与内存量。
  final double density;

  /// 本瓦片的模板纸色明暗，为空时使用原始墨色。
  final bool? paperDark;

  /// 调度当前瓦片的光栅生成和过期检查。
  @override
  State<_InkTile> createState() => _InkTileState();
}

class _InkTileState extends State<_InkTile> {
  /// _timer：尚未执行的延迟任务，更新或释放所属对象时需取消。
  Timer? _timer;

  /// _generation：任务代次；异步结果必须与当前代次一致才能提交，作废缓存时递增。
  int _generation = 0;

  /// 组合原页面尺寸、瓦片矩形、内容修订与显示密度形成栅格身份，任何部分变化都不能误用旧图。
  _InkRasterKey get _key => (
    widget.sourceSize,
    widget.tile.rect,
    widget.tile.revision,
    widget.density,
    widget.paperDark,
  );

  /// 首次挂载瓦片时安排受预算约束的光栅准备；未完成期间保留可用矢量显示。
  @override
  void initState() {
    super.initState();
    _schedule();
  }

  /// 瓦片内容、几何或密度变化时使旧生成请求失效并安排新任务。
  @override
  void didUpdateWidget(covariant _InkTile old) {
    super.didUpdateWidget(old);
    if (old.tile.revision != widget.tile.revision ||
        old.sourceSize != widget.sourceSize ||
        old.density != widget.density ||
        old.paperDark != widget.paperDark ||
        old.controller != widget.controller) {
      _schedule();
    }
  }

  /// 合并延迟生成请求，经济模式等待输入/导航空隙，提交前核对代次与缓存生命周期。
  void _schedule() {
    _timer?.cancel();
    final generation = ++_generation;
    // 丢弃过期任务；连续快速修改期间继续显示矢量预览。
    if (widget.tile.hasHighlighter) return;
    _timer = Timer(const Duration(milliseconds: 60), () async {
      final key = _key, tile = widget.tile;
      final controller = widget.controller;
      final sourceSize = widget.sourceSize;
      final prepared = await controller._tileCache.prepare(
        key,
        tile.rect,
        () => mounted && generation == _generation,
        (canvas) {
          canvas.translate(-tile.rect.left, -tile.rect.top);
          for (final stroke in tile.strokes) {
            controller._committedRenderCache.paint(
              canvas,
              sourceSize,
              stroke,
              paperDark: key.$5,
            );
          }
        },
        waitForTurn: () => controller._waitForRasterTurn(
          () => mounted && generation == _generation,
        ),
      );
      if (prepared && mounted && generation == _generation) setState(() {});
    });
  }

  /// 递增瓦片代次并取消定时器，忽略仍在生成的旧瓦片。
  @override
  void dispose() {
    _generation++;
    _timer?.cancel();
    super.dispose();
  }

  /// 按静态笔迹和可见区域建立瓦片组件，只绘制覆盖当前可见矩形的瓦片，已有子图像尽量复用。
  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(
      isComplex: true,
      painter: _InkTilePainter(
        widget.controller,
        widget.tile,
        widget.sourceSize,
        _key,
        widget.controller._tileCache.image(_key) != null,
        widget.controller._economicalRendering,
      ),
    ),
  );
}

class _InkTilePainter extends CustomPainter {
  /// 绑定单块数据和缓存键，是否已栅格化决定本帧绘制路径，原笔画保留以供回退。
  _InkTilePainter(
    this.controller,
    this.tile,
    this.sourceSize,
    this.key,
    this.hasRaster,
    this.economical,
  );

  /// controller：该组件或绘制层使用的控制器，由构造方传入，具体内容遵循声明类型。
  final InkController controller;

  /// tile：当前组件显示的空间瓦片数据，包含几何范围、笔画与修订号。
  final _InkTileData tile;

  /// sourceSize：原页面的逻辑尺寸，缩略图绘制需先按此尺寸解释坐标。
  final Size sourceSize;

  /// key：缓存或组件身份键；键的各部分共同决定能否复用当前结果。
  final _InkRasterKey key;

  /// hasRaster：当前瓦片是否已有可用栅格图，决定使用图像还是矢量回退。
  final bool hasRaster;

  /// economical：是否使用经济显示策略，仅影响缓存和显示路径。
  final bool economical;

  /// 命中栅格图时裁到瓦片几何并低成本回放，未命中时按同一位置绘制矢量，额外 gutter 防止缩放接缝。
  @override
  void paint(Canvas canvas, Size size) {
    assert(() {
      controller._debugCommittedPaintCount++;
      return true;
    }());
    canvas.save();
    // 分块的公共边界不能各自做半透明抗锯齿，否则文字会被接缝切出白线。
    canvas.clipRect(Offset.zero & size, doAntiAlias: false);
    final image = controller._tileCache.image(key);
    if (image != null) {
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(
          0,
          0,
          size.width * key.$4 + _inkRasterGutter * 2,
          size.height * key.$4 + _inkRasterGutter * 2,
        ),
        (Offset.zero & size).inflate(_inkRasterGutter / key.$4),
        Paint()
          ..filterQuality = economical
              ? FilterQuality.low
              : FilterQuality.medium,
      );
    } else {
      canvas.translate(-tile.rect.left, -tile.rect.top);
      for (final stroke in tile.strokes) {
        controller._committedRenderCache.paint(
          canvas,
          sourceSize,
          stroke,
          paperDark: key.$5,
        );
      }
    }
    canvas.restore();
  }

  /// 瓦片键、缓存状态或省电档位变化后重绘。
  @override
  bool shouldRepaint(covariant _InkTilePainter old) =>
      old.controller != controller ||
      old.key != key ||
      old.economical != economical ||
      old.hasRaster != hasRaster;
}
