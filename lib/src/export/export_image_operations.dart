part of 'export_repository.dart';

extension ExportImageOperations on ExportRepository {
  /// 导出所选页面为指定图像文件，先确保页面与笔迹可读取，再编码并报告进度。
  Future<File> exportImage(
    NoteDocument document,
    NotePage page,
    File destination,
    NoteExportFormat format, {
    void Function(String message)? onProgress,
    void Function(ExportProgress progress)? onUpdate,
  }) async {
    await _exportImagePages(
      document,
      [page],
      [destination],
      format,
      onProgress,
      onUpdate,
    );
    return destination;
  }

  /// 批量导出文稿页面到所选目录，按页命名并检查目标与源内容路径冲突。
  Future<Directory> exportImages(
    NoteDocument document,
    Directory destination,
    NoteExportFormat format, {
    void Function(String message)? onProgress,
    void Function(ExportProgress progress)? onUpdate,
  }) async {
    if (format == NoteExportFormat.pdf) {
      throw ArgumentError(
        tr(
          '批量图片导出仅支持 PNG 或 JPG。',
          'Batch image export supports PNG or JPG only.',
        ),
      );
    }
    await destination.create(recursive: true);
    final int digits = math.max(3, '${document.pages.length}'.length);
    final baseName = _safeFileName(document.title);
    final targets = [
      for (var i = 0; i < document.pages.length; i++)
        File(
          '${destination.path}/$baseName-${'${i + 1}'.padLeft(digits, '0')}.${format.name}',
        ),
    ];
    await _exportImagePages(
      document,
      document.pages,
      targets,
      format,
      onProgress,
      onUpdate,
    );
    return destination;
  }

  /// 串行/受预算流水处理多页图像，复用后台 JPEG 编码器并及时释放上一页缓冲。
  Future<void> _exportImagePages(
    NoteDocument document,
    List<NotePage> pages,
    List<File> targets,
    NoteExportFormat format,
    void Function(String)? onProgress,
    void Function(ExportProgress)? onUpdate,
  ) async {
    if (format == NoteExportFormat.pdf || pages.isEmpty) {
      throw ArgumentError('Select pages and a PNG or JPG format.');
    }
    // 规范化目标路径以便可靠比较，防止不同拼写绕过覆盖源文件检查。
    String canonical(String path) =>
        File(path).absolute.path.replaceAll('\\', '/').toLowerCase();
    // 目录只解析一次，防止 OneDrive 或目录联接的别名使
    // 输出位置覆盖原始页面；不逐页探测磁盘路径。
    final directories = <String, Future<String>>{};
    // 解析目录真实比较键，create 控制是否允许先创建输出目录。
    Future<String> directoryKey(Directory directory, {bool create = false}) =>
        directories.putIfAbsent(canonical(directory.path), () async {
          if (create) await directory.create(recursive: true);
          try {
            return canonical(await directory.resolveSymbolicLinks());
          } on FileSystemException {
            return canonical(directory.path);
          }
        });
    // 解析文件目标的规范比较键，结合父目录身份避免链接或拼写差异导致误覆盖。
    Future<String> fileKey(File file, {bool create = false}) async =>
        '${await directoryKey(file.parent, create: create)}/${file.uri.pathSegments.last.toLowerCase()}';
    final sources = <String>{};
    for (final page in document.pages) {
      sources.add(await fileKey(File(page.path)));
    }
    final original = await notes.originalPdfSource(document);
    if (original != null) sources.add(await fileKey(original));
    final stateRoot = await directoryKey(
      Directory('${notes.dataRoot}/documents/${document.id}'),
    );
    for (final target in targets) {
      final key = await fileKey(target, create: true);
      if (sources.contains(key) || key.startsWith('$stateRoot/')) {
        throw ArgumentError(
          'Export destination would overwrite a source page or PDF.',
        );
      }
    }
    final inkIds = await notes.savedInkPageIds(document);
    final quality = _jpgQuality;
    final prefetch = _exportPrefetchPages;
    var completed = 0;
    // 更新当前页面导出阶段的状态文案，不以频繁 setState 重建画布。
    void report(String message) {
      onProgress?.call(message);
      onUpdate?.call(ExportProgress(message, value: completed / pages.length));
    }

    report(tr('准备导出图片…', 'Preparing image export…'));
    ImageExportEncoder? encoder;
    Future<void>? pending;
    Object? writeError;
    StackTrace? writeStack;
    final temporaries = <File>{};
    // 等待当前后台编码任务结束再重用相关缓冲，失败向外层传播。
    Future<void> join() async {
      await pending;
      if (writeError != null) {
        Error.throwWithStackTrace(writeError!, writeStack!);
      }
    }

    final token = DateTime.now().microsecondsSinceEpoch;
    try {
      if (format == NoteExportFormat.jpg) {
        encoder = await ImageExportEncoder.start();
      }
      for (var index = 0; index < pages.length; index++) {
        final page = pages[index];
        final upcoming = [
          for (var offset = 1; offset <= prefetch; offset++)
            if (index + offset < pages.length) pages[index + offset].index,
        ];
        if (upcoming.isNotEmpty) {
          unawaited(notes.prefetchPdfPages(document, upcoming));
        }
        report(
          tr(
            '正在处理图片：${index + 1} / ${pages.length} 页',
            'Processing image: ${index + 1} / ${pages.length} pages',
          ),
        );
        final ink = inkIds.contains(page.originalPage)
            ? await notes.loadPageInk(
                document,
                page,
                legacyWidthReference: _inkWidthReference,
                background: true,
              )
            : const PageInk(strokes: []);
        await notes.ensurePageImage(document, page);
        final source = File(page.path);
        final copy =
            format == NoteExportFormat.png &&
            ink.strokes.isEmpty &&
            await _isPng(source);
        final rendered = copy
            ? null
            : await _renderPage(
                document,
                page,
                pageInk: ink,
                rgba: format == NoteExportFormat.jpg,
              );
        // 允许上一页编码、写入与下一页渲染重叠，但不把
        // 整本书排入队列；上一张位图超过 8 MP 时也不重叠执行。
        await join();
        final target = targets[index];
        await target.parent.create(recursive: true);
        final temporary = File('${target.path}.$token.$index.tmp');
        temporaries.add(temporary);
        // 将本页已渲染字节写到目标文件，等待写入完成后才能声明该页导出成功。
        Future<void> write() async {
          if (copy) {
            await source.copy(temporary.path);
          } else if (format == NoteExportFormat.jpg) {
            await encoder!.writeJpeg(
              rendered!.bytes,
              rendered.width,
              rendered.height,
              temporary,
              quality,
            );
          } else {
            await temporary.writeAsBytes(rendered!.bytes, flush: true);
          }
          await temporary.rename(target.path);
          temporaries.remove(temporary);
          completed++;
          report(
            tr(
              '已导出图片：$completed / ${pages.length} 页',
              'Exported image: $completed / ${pages.length} pages',
            ),
          );
        }

        pending = write().then<void>(
          (_) {},
          onError: (Object error, StackTrace stack) {
            writeError = error;
            writeStack = stack;
          },
        );
        if (prefetch == 0 ||
            (rendered?.bytes.lengthInBytes ?? 0) > 32 * 1024 * 1024) {
          await join();
        }
      }
      await join();
    } finally {
      // 释放原生缓冲区或删除临时文件前，先等待本任务的
      // 写入结束；绝不删除已存在的目标文件。
      await pending;
      await encoder?.dispose();
      for (final file in temporaries) {
        if (await file.exists()) await file.delete();
      }
    }
  }

  /// 读取文件头判断是否真为 PNG，不仅依赖扩展名选择快速复制路径。
  Future<bool> _isPng(File file) async {
    final stream = await file.open();
    try {
      final bytes = await stream.read(8);
      const magic = [137, 80, 78, 71, 13, 10, 26, 10];
      return bytes.length == 8 &&
          List.generate(8, (i) => bytes[i] == magic[i]).every((v) => v);
    } finally {
      await stream.close();
    }
  }

  /// 合成当前页底图、文字、图片与笔迹为编码缓冲，原图与中间 Picture 在完成后释放。
  Future<_RenderedPage> _renderPage(
    NoteDocument document,
    NotePage page, {
    bool preserveSourceWhenUnannotated = false,
    PageInk? pageInk,
    bool rgba = false,
  }) async {
    await notes.ensurePageImage(document, page);
    final (Uint8List sourceBytes, PageInk ink) = await (
      File(page.path).readAsBytes(),
      pageInk != null
          ? Future.value(pageInk)
          : notes.loadPageInk(
              document,
              page,
              legacyWidthReference: _inkWidthReference,
              background: true,
            ),
    ).wait;
    if (preserveSourceWhenUnannotated && ink.strokes.isEmpty) {
      // PDF 直接嵌入原图时只需文件头；解码整张扫描页再丢掉像素没有意义。
      // 使用同一 PDF 图片提供器读取方向与尺寸，保留 JPEG EXIF 旋转语义。
      final metadata = pw.MemoryImage(sourceBytes);
      return _RenderedPage(sourceBytes, metadata.width!, metadata.height!);
    }
    final ui.Codec codec = await ui.instantiateImageCodec(sourceBytes);
    final ui.FrameInfo frame = await codec.getNextFrame();
    codec.dispose();
    final ui.Image source = frame.image;
    try {
      final ui.PictureRecorder recorder = ui.PictureRecorder();
      final ui.Canvas canvas = ui.Canvas(recorder);
      if (rgba) canvas.drawColor(const ui.Color(0xffffffff), ui.BlendMode.src);
      final ui.Size size = ui.Size(
        source.width.toDouble(),
        source.height.toDouble(),
      );
      canvas.drawImageRect(
        source,
        ui.Rect.fromLTWH(
          0,
          0,
          source.width.toDouble(),
          source.height.toDouble(),
        ),
        ui.Offset.zero & size,
        ui.Paint()..filterQuality = ui.FilterQuality.high,
      );
      // 页面内图片先合成，所有笔迹随后绘制，确保手写内容始终覆盖在图片上。
      for (final InkStroke stroke in ink.strokes) {
        if (stroke.kind == StrokeKind.image) {
          await _paintEmbeddedImage(canvas, size, document, stroke);
        }
      }
      final budget = Stopwatch()..start();
      for (final InkStroke stroke in ink.strokes) {
        if (stroke.kind == StrokeKind.image) continue;
        if (budget.elapsedMilliseconds >= 8) {
          await Future<void>.delayed(Duration.zero);
          budget.reset();
        }
        _paintStroke(canvas, size, stroke);
      }
      final picture = recorder.endRecording();
      final ui.Image flattened;
      try {
        flattened = await picture.toImage(source.width, source.height);
      } finally {
        picture.dispose();
      }
      try {
        final ByteData? data = await flattened.toByteData(
          format: rgba
              ? ui.ImageByteFormat.rawStraightRgba
              : ui.ImageByteFormat.png,
        );
        if (data == null) {
          throw StateError(
            tr('无法生成导出图片。', 'Could not create the exported image.'),
          );
        }
        return _RenderedPage(
          Uint8List.view(data.buffer, data.offsetInBytes, data.lengthInBytes),
          source.width,
          source.height,
        );
      } finally {
        flattened.dispose();
      }
    } finally {
      source.dispose();
    }
  }

  /// 按图片对象四角变换绘制嵌入资源，保持旋转/缩放并释放临时解码图像。
  Future<void> _paintEmbeddedImage(
    ui.Canvas canvas,
    ui.Size pageSize,
    NoteDocument document,
    InkStroke stroke,
  ) async {
    if (stroke.imageAsset == null || stroke.points.length < 4) return;
    final File file = File(
      notes.resolveEmbeddedImagePath(document, stroke.imageAsset!),
    );
    if (!await file.exists()) return;
    final ui.ImmutableBuffer buffer = await ui.ImmutableBuffer.fromFilePath(
      file.path,
    );
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    ui.Image? image;
    try {
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      codec = await descriptor.instantiateCodec();
      image = (await codec.getNextFrame()).image;
      final ui.Offset origin = ui.Offset(
        stroke.points[0].x * pageSize.width,
        stroke.points[0].y * pageSize.height,
      );
      final ui.Offset right = ui.Offset(
        stroke.points[1].x * pageSize.width,
        stroke.points[1].y * pageSize.height,
      );
      final ui.Offset bottom = ui.Offset(
        stroke.points[3].x * pageSize.width,
        stroke.points[3].y * pageSize.height,
      );
      final ui.Offset horizontal = right - origin;
      final ui.Offset vertical = bottom - origin;
      canvas
        ..save()
        ..translate(origin.dx, origin.dy)
        ..rotate(math.atan2(horizontal.dy, horizontal.dx));
      canvas.drawImageRect(
        image,
        ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        ui.Rect.fromLTWH(0, 0, horizontal.distance, vertical.distance),
        ui.Paint()..filterQuality = ui.FilterQuality.high,
      );
      canvas.restore();
    } finally {
      image?.dispose();
      codec?.dispose();
      descriptor?.dispose();
      buffer.dispose();
    }
  }
}
