import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../storage/image_export_encoder.dart';

class MarkdownExportBoundary extends RepaintBoundary {
  /// 建立导出可读取的重绘边界，子内容仍使用正常 Flutter 布局。
  const MarkdownExportBoundary({super.key, required super.child});

  /// 创建能够暴露自身 OffsetLayer 的导出边界渲染对象。
  @override
  MarkdownExportRenderBoundary createRenderObject(BuildContext context) =>
      MarkdownExportRenderBoundary();
}

class MarkdownExportRenderBoundary extends RenderRepaintBoundary {
  /// 返回已经建立的边界绘制层；调用前必须完成布局与绘制。
  OffsetLayer get exportLayer => layer! as OffsetLayer;
}

/// 使用与阅读器一致的 Markdown 排版，包含中日韩文字、公式和
/// 图片；PDF 每次只栅格化一条 A4 高度的内容。
class MarkdownRenderExport {
  /// 按完整内容高度分段捕获渲染层并写入目标格式，处理超屏正文，及时释放中间图像以控制内存。
  static Future<void> write({
    required MarkdownExportRenderBoundary boundary,
    required File target,
    required String format,
    required void Function(int done, int total) onProgress,
    double pixelRatio = 1.5,
    int jpgQuality = 94,
  }) async {
    final size = boundary.size;
    final layer = boundary.exportLayer;
    if (format == 'pdf') {
      final document = pw.Document(compress: true);
      final height =
          size.width * PdfPageFormat.a4.height / PdfPageFormat.a4.width;
      final count = math.max(1, (size.height / height).ceil());
      for (int page = 0; page < count; page++) {
        final top = page * height;
        final image = await layer.toImage(
          ui.Rect.fromLTWH(
            0,
            top,
            size.width,
            math.min(height, size.height - top),
          ),
          pixelRatio: pixelRatio.clamp(1, 2),
        );
        try {
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final bitmap = pw.MemoryImage(bytes!.buffer.asUint8List());
          document.addPage(
            pw.Page(
              pageFormat: PdfPageFormat.a4,
              margin: pw.EdgeInsets.zero,
              build: (_) => pw.Align(
                alignment: pw.Alignment.topLeft,
                child: pw.Image(bitmap, width: PdfPageFormat.a4.width),
              ),
            ),
          );
        } finally {
          image.dispose();
        }
        onProgress(page + 1, count);
        await Future<void>.delayed(Duration.zero);
      }
      await target.writeAsBytes(await document.save(), flush: true);
      return;
    }
    // 长图同时受总像素数和渲染器最大边长限制。
    final ratio = math.min(
      pixelRatio.clamp(1.0, 2.0),
      math.min(
        math.sqrt(16000000 / (size.width * size.height)),
        16000 / math.max(size.width, size.height),
      ),
    );
    if (size.width * ratio < 250) {
      throw StateError('文档过长，长图会无法阅读，请使用 PDF 导出');
    }
    final image = await layer.toImage(ui.Offset.zero & size, pixelRatio: ratio);
    try {
      if (format == 'png') {
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await target.writeAsBytes(bytes!.buffer.asUint8List(), flush: true);
      } else {
        final bytes = await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        final encoder = await ImageExportEncoder.start();
        try {
          await encoder.writeJpeg(
            Uint8List.sublistView(bytes!),
            image.width,
            image.height,
            target,
            jpgQuality.clamp(70, 100),
          );
        } finally {
          await encoder.dispose();
        }
      }
    } finally {
      image.dispose();
    }
    onProgress(1, 1);
  }
}
