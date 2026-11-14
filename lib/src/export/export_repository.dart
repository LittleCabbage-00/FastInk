import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart' as crypto;
import 'package:filepicker_windows/filepicker_windows.dart';
import 'package:flutter/painting.dart' as painting;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/models.dart';
import '../storage/note_repository.dart';
import '../core/app_localizations.dart';
import '../models/export_progress.dart';
import '../storage/image_export_encoder.dart';
export '../models/export_progress.dart';

part 'export_image_operations.dart';
part 'export_pdf_fast.dart';
part 'export_pdf_ink.dart';

enum NoteExportFormat { pdf, png, jpg }

/// 将页面背景和笔迹合成为 PDF 或图片。
///
/// 导入的 PDF 复用原始页面，再叠加尺寸受限的批注层。
/// 纯图片笔记分批编码，避免一次加载全部位图。
class ExportRepository {
  /// 绑定文稿读取仓库与图像质量、PDF 分段和预取预算；显示缓存策略不应改变这些导出参数。
  ExportRepository(
    this.notes, {
    int jpgQuality = 94,
    int pdfPagesPerPart = 6,
    int exportPrefetchPages = 1,
    this.onTiming,
  }) : _jpgQuality = jpgQuality.clamp(70, 100),
       _pdfPagesPerPart = pdfPagesPerPart.clamp(2, 16),
       _exportPrefetchPages = exportPrefetchPages.clamp(0, 4);

  /// notes：导出读取笔迹、底图和嵌入图片的文稿仓库依赖。
  final NoteRepository notes;

  /// 可选的原 PDF 导出阶段耗时采样；未传入时不输出诊断日志。
  final void Function(String phase, Duration elapsed)? onTiming;

  /// _jpgQuality：当前 JPG 编码质量百分比，与显示缓存采样质量无关。
  int _jpgQuality;

  /// _pdfPagesPerPart：PDF 分段构建的每段页面数预算，限制单次文档构建的内存量。
  int _pdfPagesPerPart;

  /// _exportPrefetchPages：导出过程中提前读取的页面数量预算，不能无限预先解码。
  int _exportPrefetchPages;

  /// _inkWidthReference：旧笔宽转换使用的页面基准，缺失旧布局信息时用于兼容还原。
  double _inkWidthReference = legacyInkWidthFallbackReference;

  /// v2 旧笔迹换算成归一化粗细时的页面基准（几何平均边长）。
  ///
  /// 导出是脱离界面的，拿不到页面布局，所以由调用方在开始导出前按当前页
  /// 设置。几何平均对 90° 旋转不变，同一份文稿里横竖页共用同一个值。
  double get inkWidthReference => _inkWidthReference;

  /// 设置旧笔宽兼容基准，并限制为合法可用数值，防止旧格式导出宽度失真。
  set inkWidthReference(double value) => _inkWidthReference =
      value.isFinite && value > 0 ? value : legacyInkWidthFallbackReference;

  /// jpgQuality：Markdown JPG 导出质量百分比。
  int get jpgQuality => _jpgQuality;

  /// 更新jpgQuality：Markdown JPG 导出质量百分比。
  set jpgQuality(int value) => _jpgQuality = value.clamp(70, 100);

  /// 读取或更新 PDF 每段页面预算，设置限制在 2–16 页以控制内存。
  int get pdfPagesPerPart => _pdfPagesPerPart;

  /// 读取或更新 PDF 每段页面预算，设置限制在 2–16 页以控制内存。
  set pdfPagesPerPart(int value) => _pdfPagesPerPart = value.clamp(2, 16);

  /// exportPrefetchPages：逐页导出预先读取的页面数量预算。
  int get exportPrefetchPages => _exportPrefetchPages;

  /// 更新exportPrefetchPages：逐页导出预先读取的页面数量预算。
  set exportPrefetchPages(int value) =>
      _exportPrefetchPages = value.clamp(0, 4);

  /// 选择批量图像输出目录，用户取消返回 null，不启动导出。
  Future<Directory?> pickImageDirectory() async {
    final DirectoryPicker picker = DirectoryPicker()
      ..title = tr('选择批量导出图片的文件夹', 'Choose a folder for exported images');
    return picker.getDirectory();
  }

  /// 按标题与格式选择单个输出文件，取消返回 null。
  Future<File?> pickDestination(String title, NoteExportFormat format) async {
    final String extension = format.name;
    final SaveFilePicker picker = SaveFilePicker()
      ..title = tr(
        '导出 ${format.name.toUpperCase()}',
        'Export ${format.name.toUpperCase()}',
      )
      ..fileName = '${_safeFileName(title)}.$extension'
      ..defaultExtension = extension
      ..filterSpecification = <String, String>{
        switch (format) {
          NoteExportFormat.pdf => tr('PDF 文档 (*.pdf)', 'PDF document (*.pdf)'),
          NoteExportFormat.png => tr('PNG 图片 (*.png)', 'PNG image (*.png)'),
          NoteExportFormat.jpg => tr('JPEG 图片 (*.jpg)', 'JPEG image (*.jpg)'),
        }: '*.$extension',
      };
    return picker.getFile();
  }

  /// 优先尝试原稿安全复用，否则按段生成并合并 PDF；逐页读入必要内容并报告进度，完成前不把临时段当最终结果。
  Future<File> exportPdf(
    NoteDocument document,
    File destination, {
    List<int>? pageIndexes,
    void Function(String message)? onProgress,
    void Function(ExportProgress progress)? onUpdate,
  }) async {
    final indexes =
        pageIndexes ?? List<int>.generate(document.pages.length, (i) => i);
    if (indexes.isEmpty ||
        indexes.any((i) => i < 0 || i >= document.pages.length)) {
      throw ArgumentError('No valid pages selected for export.');
    }
    // 更新带阶段文案和可选 0–1 比例的导出进度，允许只更新文本但不虚构完成比例。
    void report(String message, double? value) {
      onProgress?.call(message);
      onUpdate?.call(ExportProgress(message, value: value));
    }

    report(tr('正在检查页面与批注…', 'Checking pages and annotations…'), 0);
    if (await _exportOriginalPages(document, destination, indexes, report)) {
      return destination;
    }
    // 纯图片笔记继续使用内存受限的栅格导出，并显示进度。
    var renderedCount = 0;
    final legacyProgress = onProgress;
    onProgress = (message) {
      legacyProgress?.call(message);
      if (message.contains('Creating PDF:') || message.contains('正在合成 PDF')) {
        renderedCount++;
      }
      onUpdate?.call(
        ExportProgress(
          message,
          value: math.min(.92, renderedCount / indexes.length * .92),
        ),
      );
    };
    await destination.parent.create(recursive: true);
    // 分块页数由设备内存档位决定，限制 PDF 编码器同时持有的页面字节数。
    // 分块数量会增加，但峰值内存不会随整本文稿页数增长。
    final int pagesPerPart = _pdfPagesPerPart;
    if (indexes.length <= pagesPerPart) {
      await _writePdfPart(
        document,
        indexes,
        destination,
        totalPages: indexes.length,
        completedBeforePart: 0,
        onProgress: onProgress,
      );
      report(tr('导出完成', 'Export complete'), 1);
      return destination;
    }

    final int token = DateTime.now().microsecondsSinceEpoch;
    final Directory working = Directory(
      '${destination.parent.path}/.${_safeFileName(document.title)}-fastink-export-$token',
    );
    final File merged = File('${destination.path}.$token.tmp.pdf');
    final List<File> parts = <File>[];
    await working.create(recursive: true);
    try {
      // 临时分块放在目标文件旁，合并成功后再原子替换最终文件。
      // 导出失败时 finally 会清理中间文件，不留下半份成品。
      for (int offset = 0; offset < indexes.length; offset += pagesPerPart) {
        final List<int> partIndexes = indexes
            .skip(offset)
            .take(pagesPerPart)
            .toList(growable: false);
        final File part = File(
          '${working.path}/part-${(parts.length + 1).toString().padLeft(4, '0')}.pdf',
        );
        await _writePdfPart(
          document,
          partIndexes,
          part,
          totalPages: indexes.length,
          completedBeforePart: offset,
          onProgress: onProgress,
        );
        parts.add(part);
      }
      onProgress.call(
        tr(
          '正在合并 ${parts.length} 个 PDF 分块…',
          'Merging ${parts.length} PDF parts…',
        ),
      );
      await notes.mergePdfFiles(parts, merged);
      if (await destination.exists()) await destination.delete();
      await merged.rename(destination.path);
      report(tr('导出完成', 'Export complete'), 1);
      return destination;
    } finally {
      if (await merged.exists()) await merged.delete();
      if (await working.exists()) await working.delete(recursive: true);
    }
  }

  /// 构建有限页数的 PDF 临时段，复用当前段的图像编码结果并在完成后释放资源。
  Future<void> _writePdfPart(
    NoteDocument document,
    List<int> indexes,
    File destination, {
    required int totalPages,
    required int completedBeforePart,
    Set<int>? nonEmptyInkIds,
    void Function(String message)? onProgress,
  }) async {
    final prepared = <_PreparedPdfInkPage>[];
    for (int i = 0; i < indexes.length; i++) {
      final NotePage page = document.pages[indexes[i]];
      // 预取数量由内存档位控制。低内存设备减少并行页面，高档位则让
      // 磁盘读取、页面渲染和编码适度重叠。
      final List<int> upcoming = <int>[
        for (int offset = 1; offset <= _exportPrefetchPages; offset++)
          if (i + offset < indexes.length) indexes[i + offset],
      ];
      if (upcoming.isNotEmpty) {
        unawaited(notes.prefetchPdfPages(document, upcoming));
      }
      onProgress?.call(
        tr(
          '正在合成 PDF：${completedBeforePart + i + 1} / $totalPages 页',
          'Creating PDF: ${completedBeforePart + i + 1} / $totalPages pages',
        ),
      );
      final _RenderedPage rendered = await _renderPage(
        document,
        page,
        preserveSourceWhenUnannotated: true,
        pageInk:
            nonEmptyInkIds != null &&
                !nonEmptyInkIds.contains(page.originalPage)
            ? const PageInk(strokes: [])
            : null,
      );
      final double ratio = rendered.width / rendered.height;
      final double pageHeight = PdfPageFormat.a4.height;
      final double pageWidth = pageHeight * ratio;
      prepared.add(
        _PreparedPdfInkPage(ui.Size(pageWidth, pageHeight), [
          _PdfRasterInkLayer(rendered.bytes),
        ]),
      );
    }
    await destination.parent.create(recursive: true);
    await _writePreparedPdfInk(prepared, destination.path);
  }

  /// 按页面尺寸绘制导出笔画，文字、图片与普通压力线段遵循各自数据约定。
  void _paintStroke(ui.Canvas canvas, ui.Size size, InkStroke stroke) {
    if (stroke.points.isEmpty) return;
    if (stroke.text != null && stroke.points.length >= 4) {
      // 文本的四个归一化点同时描述位置、旋转和可见尺寸。
      // 导出时复用这一变换，确保与编辑画布中的显示一致。
      final ui.Offset origin = ui.Offset(
        stroke.points[0].x * size.width,
        stroke.points[0].y * size.height,
      );
      final ui.Offset right = ui.Offset(
        stroke.points[1].x * size.width,
        stroke.points[1].y * size.height,
      );
      final ui.Offset bottom = ui.Offset(
        stroke.points[3].x * size.width,
        stroke.points[3].y * size.height,
      );
      final ui.Offset horizontal = right - origin;
      final ui.Offset vertical = bottom - origin;
      final painting.TextPainter layout = painting.TextPainter(
        text: painting.TextSpan(
          text: stroke.text,
          style: painting.TextStyle(
            color: ui.Color(stroke.color),
            fontFamily: stroke.textFontFamily,
            fontFamilyFallback: const <String>['Microsoft YaHei UI'],
            fontSize: stroke.textSize * size.height,
            fontWeight: ui.FontWeight.values.firstWhere(
              (ui.FontWeight weight) => weight.value == stroke.textWeight,
              orElse: () => ui.FontWeight.w400,
            ),
            fontStyle: stroke.textItalic
                ? ui.FontStyle.italic
                : ui.FontStyle.normal,
            decoration: stroke.textUnderline
                ? painting.TextDecoration.underline
                : painting.TextDecoration.none,
          ),
        ),
        textAlign: stroke.textAlign,
        textWidthBasis: painting.TextWidthBasis.parent,
        textDirection: ui.TextDirection.ltr,
      );
      final double? normalizedBaseWidth = stroke.textBoxWidth;
      if (normalizedBaseWidth != null) {
        final double baseWidth = math.max(1, normalizedBaseWidth * size.width);
        layout.layout(maxWidth: baseWidth);
        final double scale = horizontal.distance / baseWidth;
        if (layout.height <= 0 || scale <= 0) {
          layout.dispose();
          return;
        }
        canvas
          ..save()
          ..translate(origin.dx, origin.dy)
          ..rotate(math.atan2(horizontal.dy, horizontal.dx))
          ..scale(scale);
        layout.paint(canvas, ui.Offset.zero);
        canvas.restore();
        layout.dispose();
        return;
      }
      layout.layout();
      if (layout.width <= 0 || layout.height <= 0) {
        layout.dispose();
        return;
      }
      canvas
        ..save()
        ..translate(origin.dx, origin.dy)
        ..rotate(math.atan2(horizontal.dy, horizontal.dx))
        ..scale(
          horizontal.distance / layout.width,
          vertical.distance / layout.height,
        );
      layout.paint(canvas, ui.Offset.zero);
      canvas.restore();
      layout.dispose();
      return;
    }
    final ui.Paint paint = ui.Paint()
      ..color = ui.Color(stroke.color)
      ..style = ui.PaintingStyle.stroke
      ..strokeCap = ui.StrokeCap.round
      ..strokeJoin = ui.StrokeJoin.round
      ..isAntiAlias = true;
    if (stroke.penStyle == PenStyle.pencil) {
      paint.color = paint.color.withAlpha(205);
    }
    // 归一化粗细 × 导出图片的几何平均边长。用页面比例换算，屏幕和导出
    // 才会一样粗——以前直接用 stroke.width 当图片像素，导出比屏幕细。
    final double pixelWidth = inkPixelWidth(stroke.width, size);
    if (stroke.kind == StrokeKind.highlighter) {
      paint
        ..color = paint.color.withAlpha(88)
        ..strokeWidth = pixelWidth
        ..blendMode = ui.BlendMode.multiply;
      final ui.Path path = ui.Path();
      final InkPoint first = stroke.points.first;
      path.moveTo(first.x * size.width, first.y * size.height);
      for (final InkPoint point in stroke.points.skip(1)) {
        path.lineTo(point.x * size.width, point.y * size.height);
      }
      if (stroke.points.length == 1) {
        canvas.drawCircle(
          ui.Offset(first.x * size.width, first.y * size.height),
          pixelWidth / 2,
          paint..style = ui.PaintingStyle.fill,
        );
      } else {
        canvas.drawPath(path, paint);
      }
      return;
    }
    if (stroke.points.length == 1) {
      final InkPoint point = stroke.points.first;
      canvas.drawCircle(
        ui.Offset(point.x * size.width, point.y * size.height),
        math.max(0.7, pixelWidth * _pressureFactor(stroke, point.pressure) / 2),
        paint..style = ui.PaintingStyle.fill,
      );
      return;
    }
    // 不删点、不量化压感。相同精确宽度的实线段共享一次原生绘制调用。
    // 半透明与铅笔仍逐段叠加，避免改变交叉处的透明度。
    if (paint.color.a == 1 && stroke.points.length > 8) {
      final batches = <double, List<double>>{};
      for (int i = 1; i < stroke.points.length; i++) {
        final from = stroke.points[i - 1], to = stroke.points[i];
        final width = math.max(
          .8,
          pixelWidth * _pressureFactor(stroke, to.pressure),
        );
        (batches[width] ??= []).addAll([
          from.x * size.width,
          from.y * size.height,
          to.x * size.width,
          to.y * size.height,
        ]);
      }
      for (final batch in batches.entries) {
        paint.strokeWidth = batch.key;
        canvas.drawRawPoints(
          ui.PointMode.lines,
          Float32List.fromList(batch.value),
          paint,
        );
      }
      return;
    }
    // 普通笔迹逐段使用终点压感计算宽度，避免整条笔迹只能取一个粗细。
    for (int i = 1; i < stroke.points.length; i++) {
      final InkPoint from = stroke.points[i - 1];
      final InkPoint to = stroke.points[i];
      paint.strokeWidth = math.max(
        0.8,
        pixelWidth * _pressureFactor(stroke, to.pressure),
      );
      canvas.drawLine(
        ui.Offset(from.x * size.width, from.y * size.height),
        ui.Offset(to.x * size.width, to.y * size.height),
        paint,
      );
    }
  }

  /// 将标题转换为合法导出文件名，避免路径分隔符或保留字符逃离输出目录。
  String _safeFileName(String value) {
    final String sanitized = value.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
    return sanitized.trim().isEmpty
        ? tr('FastInk 导出', 'FastInk Export')
        : sanitized.trim();
  }

  /// 计算导出笔型对应的压力宽度倍率，不直接修改原始压力点列。
  double _pressureFactor(InkStroke stroke, double pressure) =>
      switch (stroke.penStyle) {
        PenStyle.ball => 1.0,
        PenStyle.fountain => 0.20 + pressure * 1.35,
        PenStyle.brush => 0.10 + pressure * 1.85,
        PenStyle.pencil => 0.22 + pressure * 0.82,
      };
}

class _RenderedPage {
  /// 保存一页已编码图像字节和像素宽高，作为写入阶段的明确交接对象。
  const _RenderedPage(this.bytes, this.width, this.height);

  /// bytes：本次渲染/编码产生的字节缓冲，格式由所在类型与调用入口约定。
  final Uint8List bytes;

  /// width：已渲染页面位图宽度，单位像素，用于编码和页面比例。
  final int width;

  /// height：已渲染页面位图高度，单位像素，用于编码和页面比例。
  final int height;
}
