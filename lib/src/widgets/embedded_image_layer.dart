import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../engine/ink_canvas.dart';
import '../models/models.dart';

/// 页面内图片层。图片独立于 CustomPainter 解码，选区变换时只更新对应组件。
///
/// 接受任意笔迹列表而不是 [InkController]，这样侧栏缩略图也能复用同一套
/// 四角定位逻辑去画非当前页的图片。图片的摆放尺寸取自布局约束，所以放进
/// 缩略图的页面矩形里就会自动按缩略图比例缩放。
class EmbeddedImageLayer extends StatelessWidget {
  /// 绑定当前笔画、资源路径解析和屏幕解码预算，图片内容仍保存在独立原始资源中。
  const EmbeddedImageLayer({
    super.key,
    required this.strokes,
    required this.resolvePath,
    this.repaint,
    this.cacheWidth,
    this.cacheHeight,
    this.filterQuality,
  });

  /// strokes：当前对象持有的笔画集合，元素坐标和宽度遵循 InkStroke 数据约定。
  final List<InkStroke> strokes;

  /// resolvePath：将嵌入资源标识解析为可读取的本地路径，由文稿仓库提供。
  final String Function(String asset) resolvePath;

  /// 笔迹变化时重建；静态快照（侧栏缓存里的其他页）传 null。
  final Listenable? repaint;

  /// 解码宽度上限。
  ///
  /// 主画布接电时可传 null；电池模式和侧栏缩略图必须传，否则每张嵌入
  /// 图片都会按原图尺寸解码——十几个可见缩略图能吃掉几十 MB，而它们只
  /// 需要几十像素宽。
  final int? cacheWidth;

  /// cacheHeight：显示图像的最大解码高度，单位像素；为空时不额外约束此方向。
  final int? cacheHeight;

  /// filterQuality：图像缩放采样质量，仅影响屏幕显示，不改源文件。
  final FilterQuality? filterQuality;

  /// 按提交信号更新嵌入图片层，没有通知器时直接构建，不截获画布手势。
  @override
  Widget build(BuildContext context) {
    final Listenable? source = repaint;
    if (source == null) return _build();
    return AnimatedBuilder(animation: source, builder: (_, _) => _build());
  }

  /// 筛选图片笔画并建立只读几何层，顺序与当前内容层次保持一致。
  Widget _build() => IgnorePointer(
    child: LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final Size page = constraints.biggest;
        return Stack(
          fit: StackFit.expand,
          children: <Widget>[
            for (final InkStroke stroke in strokes)
              if (stroke.kind == StrokeKind.image &&
                  stroke.imageAsset != null &&
                  stroke.points.length >= 4)
                _image(stroke, page),
          ],
        );
      },
    ),
  );

  /// 将图片资源按四角几何映射到页面，解码预算只影响屏幕采样，不改变源图。
  Widget _image(InkStroke stroke, Size page) {
    final Offset origin = Offset(
      stroke.points[0].x * page.width,
      stroke.points[0].y * page.height,
    );
    final Offset right = Offset(
      stroke.points[1].x * page.width,
      stroke.points[1].y * page.height,
    );
    final Offset bottom = Offset(
      stroke.points[3].x * page.width,
      stroke.points[3].y * page.height,
    );
    final double width = (right - origin).distance;
    final double height = (bottom - origin).distance;
    if (width < 1 || height < 1) return const SizedBox.shrink();
    return Positioned(
      left: origin.dx,
      top: origin.dy,
      child: Transform.rotate(
        angle: math.atan2(right.dy - origin.dy, right.dx - origin.dx),
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: width,
          height: height,
          child: Image(
            // fit 只缩小大图，不能把小素材反向放大到缓存上限。
            image: cacheWidth == null && cacheHeight == null
                ? FileImage(File(resolvePath(stroke.imageAsset!)))
                : ResizeImage(
                    FileImage(File(resolvePath(stroke.imageAsset!))),
                    width: cacheWidth,
                    height: cacheHeight,
                    policy: ResizeImagePolicy.fit,
                  ),
            fit: BoxFit.fill,
            gaplessPlayback: true,
            filterQuality:
                filterQuality ??
                (cacheWidth == null ? FilterQuality.high : FilterQuality.low),
            errorBuilder: (_, _, _) => const ColoredBox(
              color: Color(0x22000000),
              child: Center(child: Icon(Icons.broken_image_outlined)),
            ),
          ),
        ),
      ),
    );
  }
}
