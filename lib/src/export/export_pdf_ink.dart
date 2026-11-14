part of 'export_repository.dart';

extension ExportPdfInk on ExportRepository {
  /// 分离可发送的图层数据；PDF 对象树在后台构建，不携带界面或仓库状态。
  Future<_PreparedPdfInkPage> _prepareInkOverlayPage(
    NoteDocument document,
    ui.Size size,
    PageInk ink,
  ) async {
    final layers = <_PdfInkLayer>[];
    final images = ink.strokes
        .where((s) => s.kind == StrokeKind.image)
        .toList();
    if (images.isNotEmpty) {
      layers.add(
        _PdfRasterInkLayer(await _rasterInkLayer(document, size, images)),
      );
    }
    var vectors = <InkStroke>[];
    var text = <InkStroke>[];
    // 把累计普通矢量笔画封装为一层，遇到需栅格化的内容时维持原绘制顺序。
    void flushVectors() {
      if (vectors.isEmpty) return;
      layers.add(_PdfVectorInkLayer(vectors));
      vectors = [];
    }

    // 将需要字体排版的文本层完成栅格准备，避免跨线程携带不可发送的 Flutter 绘制对象。
    Future<void> flushText() async {
      if (text.isEmpty) return;
      layers.add(
        _PdfRasterInkLayer(await _rasterInkLayer(document, size, text)),
      );
      text = [];
    }

    for (final stroke in ink.strokes) {
      if (stroke.kind == StrokeKind.image) continue;
      if (stroke.text != null) {
        flushVectors();
        text.add(stroke);
      } else {
        if (text.isNotEmpty) {
          await flushText();
        }
        vectors.add(stroke);
      }
    }
    flushVectors();
    await flushText();
    return _PreparedPdfInkPage(size, layers);
  }

  /// 仅图片和文字批注需要栅格化，PDF 背景保持矢量。
  Future<Uint8List> _rasterInkLayer(
    NoteDocument document,
    ui.Size size,
    List<InkStroke> strokes,
  ) async {
    final scale = math.min(2.0, 4096 / math.max(size.width, size.height));
    final pixels = ui.Size(
      (size.width * scale).ceilToDouble(),
      (size.height * scale).ceilToDouble(),
    );
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    try {
      final budget = Stopwatch()..start();
      for (final stroke in strokes) {
        if (budget.elapsedMilliseconds >= 8) {
          await Future<void>.delayed(Duration.zero);
          budget.reset();
        }
        if (stroke.kind == StrokeKind.image) {
          final asset = stroke.imageAsset;
          if (asset == null ||
              !await File(
                notes.resolveEmbeddedImagePath(document, asset),
              ).exists()) {
            throw FileSystemException('Missing embedded image', asset);
          }
          await _paintEmbeddedImage(canvas, pixels, document, stroke);
        } else {
          _paintStroke(canvas, pixels, stroke);
        }
      }
    } catch (_) {
      if (recorder.isRecording) recorder.endRecording().dispose();
      rethrow;
    }
    final picture = recorder.endRecording();
    late final ui.Image image;
    try {
      image = await picture.toImage(
        pixels.width.toInt(),
        pixels.height.toInt(),
      );
    } finally {
      picture.dispose();
    }
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) throw StateError('Cannot encode PDF annotation layer');
      return bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);
    } finally {
      image.dispose();
    }
  }
}

/// 图层顺序保留原有文字/笔迹叠放关系，连续文字可共用一张透明图。
sealed class _PdfInkLayer {}

class _PdfVectorInkLayer extends _PdfInkLayer {
  /// 保存可由 PDF 直接绘制的笔画集合，生成阶段不再持有 Flutter 画布。
  _PdfVectorInkLayer(this.strokes);

  /// strokes：当前对象持有的笔画集合，元素坐标和宽度遵循 InkStroke 数据约定。
  final List<InkStroke> strokes;
}

class _PdfRasterInkLayer extends _PdfInkLayer {
  /// 保存已经准备好的图像层字节，字体或混合内容可复用该层进入后台 PDF 构建。
  _PdfRasterInkLayer(this.bytes);

  /// bytes：本次渲染/编码产生的字节缓冲，格式由所在类型与调用入口约定。
  final Uint8List bytes;
}

class _PreparedPdfInkPage {
  /// 保存页面尺寸和按顺序准备的叠加层，供后台写入 PDF。
  _PreparedPdfInkPage(this.size, this.layers);

  /// size：PDF 叠加页的页面尺寸，绘制时按 PDF 页面坐标解释。
  final ui.Size size;

  /// layers：保持绘制顺序的 PDF 矢量/栅格笔迹层，透明叠加不能随意重排。
  final List<_PdfInkLayer> layers;
}

/// 入口只捕获可发送的页面数据，压缩与 PDF 序列化不会阻塞进度面板。
Future<void> _writePreparedPdfInk(
  List<_PreparedPdfInkPage> pages,
  String path, {
  void Function(double)? onProgress,
}) async {
  final receive = onProgress == null ? null : ReceivePort();
  double reported = 0;
  // 按阶段更新 0–1 导出进度，避免内部工作量被误报为页面已保存。
  void emit(double value) {
    final next = value.clamp(reported, 1.0);
    reported = next;
    onProgress?.call(next);
  }

  final subscription = receive?.listen(
    (event) => emit((event as num).toDouble()),
  );
  try {
    await _runPreparedPdfInk(pages, path, receive?.sendPort);
    emit(1);
  } finally {
    await subscription?.cancel();
    receive?.close();
  }
}

/// 在工作线程构建准备好的 PDF 笔迹层，并把进度和错误传回主线程。
Future<void> _runPreparedPdfInk(
  List<_PreparedPdfInkPage> pages,
  String path,
  SendPort? progress,
) => Isolate.run(() => _buildPreparedPdfInk(pages, path, progress));

/// 按页面尺寸和层序输出 PDF 叠加文件，图像与矢量层不能随意重排。
Future<void> _buildPreparedPdfInk(
  List<_PreparedPdfInkPage> pages,
  String path,
  SendPort? progress,
) async {
  // 使用快速无损压缩；后续 qpdf 保留已有压缩流，避免重复压缩扫描页。
  final pdf = pw.Document(compress: true, deflate: ZLibCodec(level: 1).encode);
  final total = pages.fold<int>(
    0,
    (n, p) =>
        n +
        p.layers.fold<int>(
          0,
          (n, l) => n + (l is _PdfVectorInkLayer ? l.strokes.length : 1),
        ),
  );
  // 同一分块内相同图片只解码、编码一次；不同页面仍各自排版。
  final imageProviders = <String, pw.MemoryImage>{};
  final imageLengths = <int, int>{};
  for (final page in pages) {
    for (final layer in page.layers) {
      if (layer is _PdfRasterInkLayer) {
        imageLengths.update(
          layer.bytes.length,
          (n) => n + 1,
          ifAbsent: () => 1,
        );
      }
    }
  }
  int completed = 0;
  for (final page in pages) {
    final size = page.size;
    final widgets = <pw.Widget>[];
    for (final layer in page.layers) {
      if (layer is _PdfRasterInkLayer) {
        // 大小唯一的扫描图不可能重复，不额外计算大块数据的指纹。
        final pw.MemoryImage image;
        if (imageLengths[layer.bytes.length]! > 1) {
          final digest = crypto.sha256.convert(layer.bytes).toString();
          image = imageProviders.putIfAbsent(
            digest,
            () => pw.MemoryImage(layer.bytes),
          );
        } else {
          image = pw.MemoryImage(layer.bytes);
        }
        widgets.add(pw.Image(image, fit: pw.BoxFit.fill));
        completed++;
      } else if (layer is _PdfVectorInkLayer) {
        widgets.add(
          pw.CustomPaint(
            size: PdfPoint(size.width, size.height),
            painter: (canvas, _) {
              for (final stroke in layer.strokes) {
                _paintVectorExportInk(canvas, size, stroke);
                if (++completed % 64 == 0) {
                  progress?.send(.95 * completed / math.max(1, total));
                }
              }
            },
          ),
        );
      }
    }
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(size.width, size.height, marginAll: 0),
        build: (_) => pw.Stack(fit: pw.StackFit.expand, children: widgets),
      ),
    );
  }
  // 已在工作线程内，直接写 PDF 流，避免 save() 再复制对象树到第二个线程。
  final stream = PdfStream();
  await pdf.write(stream);
  await File(path).writeAsBytes(stream.output(), flush: true);
}

/// 按笔型和点列中的有效压力计算导出宽度系数，保持与屏幕笔型语义一致。
double _exportPressureFactor(InkStroke stroke, double pressure) =>
    switch (stroke.penStyle) {
      PenStyle.ball => 1.0,
      PenStyle.fountain => .20 + pressure * 1.35,
      PenStyle.brush => .10 + pressure * 1.85,
      PenStyle.pencil => .22 + pressure * .82,
    };

/// 把归一化笔画点映射到 PDF 页面坐标并绘制压力线段，导出不复用低分辨率屏幕瓦片。
void _paintVectorExportInk(PdfGraphics canvas, ui.Size size, InkStroke stroke) {
  if (stroke.points.isEmpty) return;
  final highlight = stroke.kind == StrokeKind.highlighter;
  final color = ui.Color(stroke.color);
  final opacity = highlight
      ? 88 / 255
      : stroke.penStyle == PenStyle.pencil
      ? 205 / 255
      : color.a;
  final pdfColor = PdfColor(color.r, color.g, color.b);
  final widthForStroke = inkPixelWidth(stroke.width, size);
  canvas
    ..saveContext()
    ..setGraphicState(
      PdfGraphicState(
        opacity: opacity,
        blendMode: highlight ? PdfBlendMode.multiply : PdfBlendMode.normal,
      ),
    )
    ..setStrokeColor(pdfColor)
    ..setFillColor(pdfColor)
    ..setLineCap(PdfLineCap.round)
    ..setLineJoin(PdfLineJoin.round);
  final first = stroke.points.first;
  if (stroke.points.length == 1) {
    final radius = highlight
        ? widthForStroke / 2
        : math.max(
            .35,
            widthForStroke * _exportPressureFactor(stroke, first.pressure) / 2,
          );
    canvas
      ..drawEllipse(
        first.x * size.width,
        (1 - first.y) * size.height,
        radius,
        radius,
      )
      ..fillPath();
  } else if (highlight) {
    canvas
      ..setLineWidth(widthForStroke)
      ..moveTo(first.x * size.width, (1 - first.y) * size.height);
    for (final point in stroke.points.skip(1)) {
      canvas.lineTo(point.x * size.width, (1 - point.y) * size.height);
    }
    canvas.strokePath();
  } else if (opacity == 1) {
    double? activeWidth;
    for (var i = 1; i < stroke.points.length; i++) {
      final a = stroke.points[i - 1], b = stroke.points[i];
      final width = math.max(
        .4,
        widthForStroke * _exportPressureFactor(stroke, b.pressure),
      );
      if (activeWidth != width) {
        if (activeWidth != null) canvas.strokePath();
        canvas
          ..setLineWidth(width)
          ..moveTo(a.x * size.width, (1 - a.y) * size.height);
        activeWidth = width;
      }
      // 圆连接与相邻圆端帽的几何覆盖一致；变压宽度处仍分段，不删采样点。
      canvas.lineTo(b.x * size.width, (1 - b.y) * size.height);
    }
    canvas.strokePath();
  } else {
    for (var i = 1; i < stroke.points.length; i++) {
      final a = stroke.points[i - 1], b = stroke.points[i];
      canvas
        ..setLineWidth(
          math.max(
            .4,
            widthForStroke * _exportPressureFactor(stroke, b.pressure),
          ),
        )
        ..drawLine(
          a.x * size.width,
          (1 - a.y) * size.height,
          b.x * size.width,
          (1 - b.y) * size.height,
        )
        ..strokePath();
    }
  }

  canvas.restoreContext();
}
