import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../engine/ink_canvas.dart';
import '../models/models.dart';

/// 截图工具。裁切只通过工具栏进入，侧键只分派标注动作。
enum CaptureTool {
  crop,
  select,
  pen,
  highlighter,
  eraser,
  laser,
  line,
  arrow,
  rectangle,
  ellipse,
  triangle,
  diamond,
  text,
  mosaic,
}

class CaptureMark {
  /// 创建一条截图标注，存放工具、点列及绘制样式。
  /// tool：当前画布输入工具；与临时侧键工具共同决定本次手势的行为。
  /// points：截图标注的图像坐标点列，不是页面归一化坐标。
  /// 绘制颜色。
  /// width：截图标注线宽，单位原截图图像逻辑像素。
  /// text：对象保存的完整文字内容；非文字对象可为空，不用截断显示文本替代源文。
  /// angle：截图标注自身的旋转角，单位弧度，整张截图旋转另用 turns。
  const CaptureMark({
    required this.tool,
    required this.points,
    this.color = const Color(0xffed4245),
    this.width = 4,
    this.text = '',
    this.angle = 0,
    this.penStyle = PenStyle.ball,
    this.pressures,
  });

  /// tool：当前画布输入工具；与临时侧键工具共同决定本次手势的行为。
  final CaptureTool tool;

  /// points：截图标注的图像坐标点列，不是页面归一化坐标。
  final List<Offset> points;

  /// 绘制颜色。
  final Color color;

  /// width：截图标注线宽，单位原截图图像逻辑像素。
  final double width;

  /// text：对象保存的完整文字内容；非文字对象可为空，不用截断显示文本替代源文。
  final String text;

  /// angle：截图标注自身的旋转角，单位弧度，整张截图旋转另用 turns。
  final double angle;

  /// 标注钢笔的笔型，非手写工具使用默认固定宽度。
  final PenStyle penStyle;

  /// 与手写点一一对应的有效压力，为空时是固定宽度的旧标注。
  final List<double>? pressures;

  /// 计算标注的图像坐标外接矩形，文字先按实际字体测量，旋转对象的命中也以该几何为依据。
  Rect get bounds {
    if (tool == CaptureTool.text) {
      final painter = textPainter();
      final result = points.first & painter.size;
      painter.dispose();
      return result;
    }
    return Rect.fromLTRB(
      points.map((p) => p.dx).reduce(math.min),
      points.map((p) => p.dy).reduce(math.min),
      points.map((p) => p.dx).reduce(math.max),
      points.map((p) => p.dy).reduce(math.max),
    ).inflate(tool == CaptureTool.mosaic ? 0 : width / 2);
  }

  /// 按标注全文、颜色和样式建立文字排版对象，调用方在绘制后负责释放。
  TextPainter textPainter() => TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        color: color,
        fontSize: width * 6 + 12,
        fontFamily: 'Microsoft YaHei UI',
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();

  /// 返回沿图像坐标 delta 平移的新标注，保留颜色、宽度和其他内容属性。
  CaptureMark move(Offset delta) => CaptureMark(
    tool: tool,
    points: points.map((p) => p + delta).toList(),
    color: color,
    width: width,
    text: text,
    angle: angle,
    penStyle: penStyle,
    pressures: pressures,
  );

  /// 返回增加 delta 弧度旋转的新标注，整张图像的四分之一圈旋转另行处理。
  CaptureMark rotate(double delta) => CaptureMark(
    tool: tool,
    points: points,
    color: color,
    width: width,
    text: text,
    angle: angle + delta,
    penStyle: penStyle,
    pressures: pressures,
  );

  /// 按点位和容差判断标注命中，区分文字/几何的实际边界与线条距离。
  bool hit(Offset p, double tolerance) {
    final center = bounds.center;
    final d = p - center;
    final local =
        center +
        Offset(
          d.dx * math.cos(-angle) - d.dy * math.sin(-angle),
          d.dx * math.sin(-angle) + d.dy * math.cos(-angle),
        );
    return bounds.inflate(tolerance).contains(local);
  }
}

class _CaptureSnapshot {
  /// 保存一时刻的裁切区域、标注结构与整图方向，供一次操作的撤销恢复。
  _CaptureSnapshot(this.crop, this.marks, this.turns);

  /// crop：当前截图裁切矩形，使用原截图坐标；为空表示尚未限定区域。
  final Rect? crop;

  /// marks：截图中的可编辑标注对象列表，移动/旋转后仍可单独选择。
  final List<CaptureMark> marks;

  /// turns：整张截图的四分之一圈旋转次数，与单个标注的弧度角分开。
  final int turns;
}

/// 所有编辑均在本地完成，仅将合成后的裁剪区域导出为 PNG。
class ScreenshotDocument extends ChangeNotifier {
  /// 绑定原始截图与马赛克缓存，selectAll 控制是否默认选中整个图像区域，不修改原始图片。
  ScreenshotDocument(this.image, this.mosaics, {bool selectAll = false}) {
    if (selectAll) crop = imageRect;
  }

  /// image：当前截图原始解码图像，所属文档负责最终释放，导出前不直接改像素。
  final ui.Image image;

  /// mosaics：按马赛克强度缓存的低分辨率图像，显示与导出共同使用。
  final Map<int, ui.Image> mosaics;

  /// crop：当前截图裁切矩形，使用原截图坐标；为空表示尚未限定区域。
  Rect? crop;

  /// marks：截图中的可编辑标注对象列表，移动/旋转后仍可单独选择。
  List<CaptureMark> marks = [];

  /// turns：整张截图的四分之一圈旋转次数，与单个标注的弧度角分开。
  int turns = 0;

  /// selected：当前选中标注的列表索引，为空表示没有选择。
  int? selected;

  /// _undo：当前编辑器的撤销历史控制器或栈，独立于其他文稿的内容历史；_redo：截图中已撤销的状态栈，新内容提交后清空旧重做分支。
  final List<_CaptureSnapshot> _undo = [], _redo = [];

  /// 返回原截图的完整图像坐标边界，裁切和指针约束以此为限。
  Rect get imageRect =>
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());

  /// 根据整图四分之一圈旋转次数交换显示宽高，不重采样原图。
  Size get displaySize => turns.isEven
      ? imageRect.size
      : Size(image.height.toDouble(), image.width.toDouble());

  /// 判断截图状态栈是否存在可撤销操作。
  bool get canUndo => _undo.isNotEmpty;

  /// 判断截图当前撤销分支是否还可恢复。
  bool get canRedo => _redo.isNotEmpty;

  /// 复制当前裁切、标注列表和方向为独立历史快照，标注对象按值式更新。
  _CaptureSnapshot _snapshot() => _CaptureSnapshot(crop, List.of(marks), turns);

  /// 在完整截图操作前保存历史起点并清空旧重做分支，连续拖动不逐点堆积历史。
  void checkpoint() {
    _undo.add(_snapshot());
    if (_undo.length > 80) _undo.removeAt(0);
    _redo.clear();
  }

  /// 通知截图界面当前模型发生变化，不独立创建新的历史条目。
  void changed() => notifyListeners();

  /// 恢复指定快照的裁切、标注和方向并刷新当前选择状态。
  void _restore(_CaptureSnapshot snapshot) {
    crop = snapshot.crop;
    marks = List.of(snapshot.marks);
    turns = snapshot.turns;
    selected = null;
    notifyListeners();
  }

  /// 将当前截图状态移到重做栈，再恢复最近一次修改前快照。
  void undo() {
    if (!canUndo) return;
    _redo.add(_snapshot());
    _restore(_undo.removeLast());
  }

  /// 将当前状态移回撤销栈，并恢复最近撤销的截图快照。
  void redo() {
    if (!canRedo) return;
    _undo.add(_snapshot());
    _restore(_redo.removeLast());
  }

  /// 加入一个已确认标注并更新选择与历史，草稿预览不通过此入口提交。
  void add(CaptureMark mark) {
    checkpoint();
    marks = [...marks, mark];
    selected = marks.length - 1;
    notifyListeners();
  }

  /// 删除当前选中标注并产生一次历史，没有有效选择时保持原内容。
  void deleteSelected() {
    final i = selected;
    if (i == null) return;
    checkpoint();
    marks.removeAt(i);
    selected = null;
    notifyListeners();
  }

  /// 更新一次擦除预览。自由笔迹按文稿的圆形剪裁算法切开，其他标注作为对象擦除。
  void eraseAt(Offset point, double radius, EraserMode mode) {
    final next = <CaptureMark>[];
    var changed = false;
    for (final mark in marks) {
      if (!mark.hit(point, radius)) {
        next.add(mark);
        continue;
      }
      if (mark.tool != CaptureTool.pen &&
          mark.tool != CaptureTool.highlighter) {
        changed = true;
        continue;
      }
      // 先把旋转后的点换成图像坐标。剪开后无需靠片段外接框重新旋转。
      final center = mark.bounds.center;
      final cos = math.cos(mark.angle), sin = math.sin(mark.angle);
      final stroke = InkStroke(
        color: mark.color.toARGB32(),
        width: mark.width,
        points: [
          for (final (index, p) in mark.points.indexed)
            InkPoint(
              center.dx + (p.dx - center.dx) * cos - (p.dy - center.dy) * sin,
              center.dy + (p.dx - center.dx) * sin + (p.dy - center.dy) * cos,
              mark.pressures?[index] ?? 1,
            ),
        ],
      );
      // 单位尺寸下 InkPoint 的数值直接代表原图像素，与橡皮半径一致。
      final parts = cutInkStrokeOutsideCircle(
        stroke,
        InkPoint(point.dx, point.dy, 1),
        const Size(1, 1),
        radius + mark.width / 2,
      );
      if (parts == null) {
        next.add(mark);
        continue;
      }
      changed = true;
      if (mode == EraserMode.point) {
        for (final part in parts) {
          next.add(
            CaptureMark(
              tool: mark.tool,
              color: mark.color,
              width: mark.width,
              penStyle: mark.penStyle,
              points: part.points.map((p) => Offset(p.x, p.y)).toList(),
              pressures: mark.pressures == null
                  ? null
                  : part.points.map((p) => p.pressure).toList(),
            ),
          );
        }
      }
    }
    if (changed) {
      marks = next;
      selected = null;
    }
  }

  /// 以给定弧度旋转当前标注，整体作为一次可撤销操作。
  void rotateSelected(double angle) {
    final i = selected;
    if (i == null) return;
    checkpoint();
    marks[i] = marks[i].rotate(angle);
    notifyListeners();
  }

  /// 将整图方向增加四分之一圈，裁切与显示坐标通过统一转换保持一致。
  void rotateImage() {
    checkpoint();
    turns = (turns + 1) % 4;
    notifyListeners();
  }

  /// 把原图点映射到当前整图旋转后的显示坐标，供预览绘制使用。
  Offset toDisplay(Offset p) => switch (turns) {
    1 => Offset(image.height - p.dy, p.dx),
    2 => Offset(image.width - p.dx, image.height - p.dy),
    3 => Offset(p.dy, image.width - p.dx),
    _ => p,
  };

  /// 把旋转后的显示点逆变换回原图坐标，框选与标注命中不能直接使用屏幕点。
  Offset fromDisplay(Offset p) => switch (turns) {
    1 => Offset(p.dy, image.height - p.dx),
    2 => Offset(image.width - p.dx, image.height - p.dy),
    3 => Offset(image.width - p.dy, p.dx),
    _ => p,
  };

  /// 将原图矩形的角点映射成当前显示方向下的外接矩形。
  Rect displayRect(Rect r) =>
      Rect.fromPoints(toDisplay(r.topLeft), toDisplay(r.bottomRight));

  /// 在画布应用整图旋转与平移，使原图内容按当前 turns 显示而不改写像素。
  void transform(Canvas canvas, double width, double height) {
    switch (turns) {
      case 1:
        canvas.translate(height, 0);
        canvas.rotate(math.pi / 2);
      case 2:
        canvas.translate(width, height);
        canvas.rotate(math.pi);
      case 3:
        canvas.translate(0, width);
        canvas.rotate(-math.pi / 2);
    }
  }

  /// 按层序绘制原图、马赛克、已确认标注和可选草稿，所有对象使用原图坐标。
  void paintContent(Canvas canvas, {CaptureMark? draft}) {
    canvas.drawImage(image, Offset.zero, Paint());
    for (final mark in [...marks, ?draft]) {
      canvas.save();
      final center = mark.bounds.center;
      canvas.translate(center.dx, center.dy);
      canvas.rotate(mark.angle);
      canvas.translate(-center.dx, -center.dy);
      final paint = Paint()
        ..color = mark.color
        ..strokeWidth = mark.width
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      final rect = Rect.fromPoints(mark.points.first, mark.points.last);
      switch (mark.tool) {
        case CaptureTool.pen:
          final pressures = mark.pressures;
          if (pressures != null && mark.penStyle != PenStyle.ball) {
            if (mark.penStyle == PenStyle.pencil) {
              paint.color = mark.color.withAlpha(205);
            }
            if (mark.points.length == 1) {
              final radius =
                  mark.width *
                  penPressureWidthFactor(mark.penStyle, pressures.single) /
                  2;
              canvas.drawCircle(
                mark.points.single,
                radius,
                Paint()..color = paint.color,
              );
              break;
            }
            for (var i = 1; i < mark.points.length; i++) {
              paint.strokeWidth =
                  mark.width *
                  penPressureWidthFactor(mark.penStyle, pressures[i]);
              if (mark.points[i - 1] == mark.points[i]) {
                canvas.drawCircle(
                  mark.points[i],
                  paint.strokeWidth / 2,
                  Paint()..color = paint.color,
                );
              } else {
                canvas.drawLine(mark.points[i - 1], mark.points[i], paint);
              }
            }
            break;
          }
          continue freehand;
        freehand:
        case CaptureTool.highlighter:
        case CaptureTool.laser:
          if (mark.tool == CaptureTool.highlighter) {
            paint.color = mark.color.withAlpha(88);
            paint.blendMode = BlendMode.multiply;
          }
          if (mark.points.length == 1 ||
              mark.points.every((p) => p == mark.points.first)) {
            canvas.drawCircle(
              mark.points.first,
              mark.width / 2,
              Paint()
                ..color = paint.color
                ..blendMode = paint.blendMode,
            );
            break;
          }
          final path = Path()
            ..moveTo(mark.points.first.dx, mark.points.first.dy);
          for (final p in mark.points.skip(1)) {
            path.lineTo(p.dx, p.dy);
          }
          canvas.drawPath(path, paint);
        case CaptureTool.rectangle:
          canvas.drawRect(rect, paint);
        case CaptureTool.ellipse:
          canvas.drawOval(rect, paint);
        case CaptureTool.line:
          canvas.drawLine(mark.points.first, mark.points.last, paint);
        case CaptureTool.triangle:
          canvas.drawPath(
            Path()
              ..moveTo(rect.center.dx, rect.top)
              ..lineTo(rect.right, rect.bottom)
              ..lineTo(rect.left, rect.bottom)
              ..close(),
            paint,
          );
        case CaptureTool.diamond:
          canvas.drawPath(
            Path()
              ..moveTo(rect.center.dx, rect.top)
              ..lineTo(rect.right, rect.center.dy)
              ..lineTo(rect.center.dx, rect.bottom)
              ..lineTo(rect.left, rect.center.dy)
              ..close(),
            paint,
          );
        case CaptureTool.arrow:
          final a = mark.points.first, b = mark.points.last;
          canvas.drawLine(a, b, paint);
          final theta = math.atan2(b.dy - a.dy, b.dx - a.dx);
          final length = math.max(12.0, mark.width * 4);
          canvas.drawPath(
            Path()
              ..moveTo(
                b.dx - length * math.cos(theta - .5),
                b.dy - length * math.sin(theta - .5),
              )
              ..lineTo(b.dx, b.dy)
              ..lineTo(
                b.dx - length * math.cos(theta + .5),
                b.dy - length * math.sin(theta + .5),
              ),
            paint,
          );
        case CaptureTool.text:
          final text = mark.textPainter();
          text.paint(canvas, mark.points.first);
          text.dispose();
        case CaptureTool.mosaic:
          final cell = mosaics.keys.reduce(
            (a, b) => (a - mark.width).abs() < (b - mark.width).abs() ? a : b,
          );
          final pixelated = mosaics[cell]!;
          canvas.save();
          canvas.clipRect(rect);
          canvas.drawImageRect(
            pixelated,
            Rect.fromLTWH(
              0,
              0,
              pixelated.width.toDouble(),
              pixelated.height.toDouble(),
            ),
            imageRect,
            Paint()
              ..filterQuality = FilterQuality.none
              ..isAntiAlias = false,
          );
          canvas.restore();
        case CaptureTool.crop:
        case CaptureTool.select:
        case CaptureTool.eraser:
          break;
      }
      canvas.restore();
    }
  }

  /// 按当前裁切与整图方向合成最终 PNG 字节，等待图像编码完成并释放中间绘制资源。
  Future<Uint8List> exportPng() async {
    final area = crop?.intersect(imageRect);
    if (area == null || area.width < 1 || area.height < 1) {
      throw StateError('Select a screenshot region first');
    }
    final snapped = Rect.fromLTRB(
      area.left.floorToDouble(),
      area.top.floorToDouble(),
      area.right.ceilToDouble(),
      area.bottom.ceilToDouble(),
    );
    final w = snapped.width.toInt(), h = snapped.height.toInt();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    transform(canvas, w.toDouble(), h.toDouble());
    canvas.clipRect(Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()));
    canvas.translate(-snapped.left, -snapped.top);
    paintContent(canvas);
    final picture = recorder.endRecording();
    final output = await picture.toImage(
      turns.isEven ? w : h,
      turns.isEven ? h : w,
    );
    picture.dispose();
    try {
      final bytes = await output.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) throw StateError('PNG encoding failed');
      return bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);
    } finally {
      output.dispose();
    }
  }

  /// 从截图字节建立解码图像和适用马赛克缓存，返回可编辑模型，失败释放已创建的图像。
  static Future<ScreenshotDocument> create(
    ui.Image image, {
    bool selectAll = false,
  }) async {
    final mosaics = <int, ui.Image>{};
    try {
      for (final cell in [8, 18, 36]) {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        final w = math.max(1, (image.width / cell).ceil()),
            h = math.max(1, (image.height / cell).ceil());
        canvas.drawImageRect(
          image,
          Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
          Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
          Paint()..filterQuality = FilterQuality.medium,
        );
        final picture = recorder.endRecording();
        try {
          mosaics[cell] = await picture.toImage(w, h);
        } finally {
          picture.dispose();
        }
      }
      return ScreenshotDocument(image, mosaics, selectAll: selectAll);
    } catch (_) {
      for (final preview in mosaics.values) {
        preview.dispose();
      }
      rethrow;
    }
  }

  /// 释放截图底图及所有已生成的马赛克预览。
  @override
  void dispose() {
    for (final preview in mosaics.values) {
      preview.dispose();
    }
    image.dispose();
    super.dispose();
  }
}
