import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:fastink_flutter/src/export/export_repository.dart';
import 'package:fastink_flutter/src/models/models.dart';
import 'package:fastink_flutter/src/storage/note_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('PDF cache limit is configurable and clamped safely', () {
    final NoteRepository repository = NoteRepository(maximumCachedPdfPages: 80);
    expect(repository.maximumCachedPdfPages, 80);
    repository.maximumCachedPdfPages = 10;
    expect(repository.maximumCachedPdfPages, 40);
    repository.maximumCachedPdfPages = 999;
    expect(repository.maximumCachedPdfPages, 320);
  });

  TestWidgetsFlutterBinding.ensureInitialized();

  test('normalized stroke width keeps a page-relative thickness', () {
    // 归一化粗细在任何尺度下占页面的比例都一样：以前屏幕按布局像素、导出
    // 按图片像素画，同一笔在导出里细了一截。
    const double width = 0.012;
    const ui.Size canvas = ui.Size(566, 800);
    // 同一页在 2× 尺度下的画布（导出图就是这个量级），宽高比严格相同。
    const ui.Size export = ui.Size(1132, 1600);
    expect(
      inkPixelWidth(width, canvas) / canvas.width,
      closeTo(inkPixelWidth(width, export) / export.width, 1e-9),
    );
    // 基准是几何平均，所以 90° 旋转（宽高互换）后像素粗细不变，
    // 旋转只换点列、原样 copy() 字段就是对的。
    expect(
      inkPixelWidth(width, const ui.Size(800, 566)),
      closeTo(inkPixelWidth(width, canvas), 1e-9),
    );
    expect(
      inkPixelWidth(width, canvas),
      closeTo(width * math.sqrt(566 * 800), 1e-9),
    );
  });

  test('legacy pixel widths migrate to page-relative widths on load', () async {
    final Directory directory = await Directory.systemTemp.createTemp(
      'fastink_ink_migration_test_',
    );
    try {
      final NoteRepository repository = NoteRepository(
        dataRoot: '${directory.path}\\data',
      );
      final NoteDocument document = await repository.createBlankNote('旧版笔迹');
      final NotePage page = document.pages.first;
      // 手工写一份 v2 文件：那时 width 是绘制时的页面布局像素。
      final File ink = File(
        '${directory.path}\\data\\documents\\${document.id}\\pages\\'
        '${page.originalPage.toString().padLeft(6, '0')}.json',
      );
      await ink.parent.create(recursive: true);
      await ink.writeAsString(
        jsonEncode(<String, Object?>{
          'version': 2,
          'updatedAt': DateTime.now().toUtc().toIso8601String(),
          'strokes': <Object?>[
            <String, Object?>{
              'color': 0xff202124,
              'width': 6,
              'points': <Object?>[
                <String, Object?>{'x': 0.5, 'y': 0.5, 'p': 0.5},
              ],
            },
          ],
        }),
      );

      final PageInk migrated = await repository.loadPageInk(
        document,
        page,
        legacyWidthReference: 600,
      );
      expect(migrated.strokes.single.width, closeTo(0.01, 1e-9));
      // 用当时的页面尺度画回来还是 6 像素：迁移不改屏幕上的样子。
      expect(
        inkPixelWidth(migrated.strokes.single.width, const ui.Size(600, 600)),
        closeTo(6, 1e-9),
      );

      // 存回去就固化成当前版本，之后无论拿什么基准读都不再换算。
      await repository.savePageInk(document, page, migrated);
      final PageInk persisted = await repository.loadPageInk(
        document,
        page,
        legacyWidthReference: 1200,
      );
      expect(persisted.version, PageInk.currentVersion);
      expect(persisted.strokes.single.width, closeTo(0.01, 1e-9));
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test('indexes one Scrble note and sorts its pages numerically', () async {
    final Directory directory = await Directory.systemTemp.createTemp(
      'fastink_test_',
    );
    try {
      for (final String name in <String>[
        '资本论 #100.png',
        '资本论 #02.png',
        '资本论 #10.png',
        '别的笔记 #01.png',
      ]) {
        await File('${directory.path}\\$name').writeAsBytes(<int>[1, 2, 3]);
      }

      final document = await NoteRepository().indexFromSelectedPath(
        '${directory.path}\\资本论 #10.png',
      );

      expect(document.title, '资本论');
      expect(document.pages.map((page) => page.originalPage), <int>[
        2,
        10,
        100,
      ]);
      expect(document.initialIndex, 1);
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test('imports a PDF into numbered image pages', () async {
    final Directory directory = await Directory.systemTemp.createTemp(
      'fastink_pdf_test_',
    );
    try {
      final File pdf = File('${directory.path}\\sample.pdf');
      await pdf.writeAsBytes(_onePagePdf());
      final NoteRepository repository = NoteRepository(
        dataRoot: '${directory.path}\\data',
        pdfImportDpi: 96,
      );

      final document = await repository.importPdf(pdf, onProgress: (_) {});

      expect(document.title, 'sample');
      expect(document.pages, hasLength(1));
      expect(await File(document.pages.single.path).exists(), isTrue);
      final Map<String, Object?> metadata =
          jsonDecode(
                await File(
                  '${document.directory}\\.fastink-pdf.json',
                ).readAsString(),
              )
              as Map<String, Object?>;
      expect(metadata['dpi'], 96);
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test('unannotated PDF export uses the lossless original fast path', () async {
    final Directory directory = await Directory.systemTemp.createTemp(
      'fastink_pdf_fast_export_test_',
    );
    try {
      final File source = File('${directory.path}\\source.pdf');
      final List<int> originalBytes = _onePagePdf();
      await source.writeAsBytes(originalBytes);
      final NoteRepository notes = NoteRepository(
        dataRoot: '${directory.path}\\data',
      );
      final NoteDocument document = await notes.importPdf(
        source,
        onProgress: (_) {},
      );
      final File destination = File('${directory.path}\\export.pdf');

      await ExportRepository(notes).exportPdf(document, destination);

      expect(await destination.readAsBytes(), originalBytes);
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test(
    '3022-page PDF renders only cover and random pages on demand',
    () async {
      final Directory directory = await Directory.systemTemp.createTemp(
        'fastink_lazy_pdf_test_',
      );
      try {
        final File pdf = File('${directory.path}\\large.pdf');
        await pdf.writeAsBytes(_multiPagePdf(3022));
        final NoteRepository repository = NoteRepository(
          dataRoot: '${directory.path}\\data',
        );

        final document = await repository.importPdf(pdf, onProgress: (_) {});

        expect(document.pages, hasLength(3022));
        expect(await File(document.pages[0].path).exists(), isTrue);
        expect(await File(document.pages[1].path).exists(), isFalse);
        expect(await File(document.pages[3021].path).exists(), isFalse);
        await repository.ensurePageImage(document, document.pages[3021]);
        expect(await File(document.pages[3021].path).exists(), isTrue);
        final reopened = await repository.indexFromSelectedPath(
          document.pages.first.path,
          documentId: document.id,
        );
        expect(reopened.pages, hasLength(3022));
      } finally {
        await directory.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test('creates ruled landscape paper and persists page order', () async {
    final Directory directory = await Directory.systemTemp.createTemp(
      'fastink_pages_test_',
    );
    try {
      final NoteRepository repository = NoteRepository(
        dataRoot: '${directory.path}\\data',
      );
      NoteDocument document = await repository.createBlankNote(
        '课堂笔记',
        template: const PaperTemplate(
          pattern: PaperPattern.ruled,
          size: PaperSizePreset.letter,
          landscape: true,
        ),
      );
      final ui.Codec codec = await ui.instantiateImageCodec(
        await File(document.pages.first.path).readAsBytes(),
      );
      final ui.FrameInfo frame = await codec.getNextFrame();
      expect(frame.image.width, 1650);
      expect(frame.image.height, 1275);
      frame.image.dispose();
      codec.dispose();

      document = await repository.addBlankPage(
        document,
        insertIndex: 1,
        template: const PaperTemplate(pattern: PaperPattern.grid),
      );
      document = await repository.duplicatePage(document, 0);
      final int duplicatedOriginal = document.pages[1].originalPage;
      document = await repository.reorderPages(document, 1, 3);
      expect(document.pages.last.originalPage, duplicatedOriginal);

      final NoteDocument reopened = await repository.indexFromSelectedPath(
        document.pages.first.path,
        documentId: document.id,
      );
      expect(
        reopened.pages.map((page) => page.originalPage),
        document.pages.map((page) => page.originalPage),
      );
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test('exports flattened handwriting to PNG and PDF', () async {
    final Directory directory = await Directory.systemTemp.createTemp(
      'fastink_export_test_',
    );
    try {
      final NoteRepository notes = NoteRepository(
        dataRoot: '${directory.path}\\data',
      );
      final NoteDocument document = await notes.createBlankNote('导出测试');
      final String embeddedAsset = await notes.importEmbeddedImage(
        document,
        File(document.pages.first.path),
      );
      await notes.savePageInk(
        document,
        document.pages.first,
        PageInk(
          strokes: <InkStroke>[
            InkStroke(
              color: 0,
              width: 0.01,
              kind: StrokeKind.image,
              imageAsset: embeddedAsset,
              points: const <InkPoint>[
                InkPoint(0.25, 0.3, 0.5),
                InkPoint(0.75, 0.3, 0.5),
                InkPoint(0.75, 0.55, 0.5),
                InkPoint(0.25, 0.55, 0.5),
              ],
            ),
            InkStroke(
              color: 0xffe53935,
              width: 0.012,
              points: const <InkPoint>[
                InkPoint(0.1, 0.1, 0.5),
                InkPoint(0.9, 0.9, 0.8),
              ],
            ),
            InkStroke(
              color: 0xff1a73e8,
              width: 0.01,
              text: '导出文本',
              textSize: 0.04,
              points: const <InkPoint>[
                InkPoint(0.1, 0.2, 0.5),
                InkPoint(0.35, 0.2, 0.5),
                InkPoint(0.35, 0.26, 0.5),
                InkPoint(0.1, 0.26, 0.5),
              ],
            ),
          ],
        ),
      );
      final ExportRepository exporter = ExportRepository(notes);
      final File png = File('${directory.path}\\page.png');
      final File pdf = File('${directory.path}\\note.pdf');
      final Directory jpgPages = Directory('${directory.path}\\jpg-pages');
      await exporter.exportImage(
        document,
        document.pages.first,
        png,
        NoteExportFormat.png,
      );
      await exporter.exportPdf(document, pdf);
      await exporter.exportImages(document, jpgPages, NoteExportFormat.jpg);
      final File lowQuality = File('${directory.path}\\low.jpg');
      final File highQuality = File('${directory.path}\\high.jpg');
      exporter.jpgQuality = 70;
      await exporter.exportImage(
        document,
        document.pages.first,
        lowQuality,
        NoteExportFormat.jpg,
      );
      exporter.jpgQuality = 100;
      await exporter.exportImage(
        document,
        document.pages.first,
        highQuality,
        NoteExportFormat.jpg,
      );
      expect(await png.length(), greaterThan(1000));
      expect((await pdf.readAsBytes()).take(4), '%PDF'.codeUnits);
      expect(
        await File('${jpgPages.path}\\导出测试-001.jpg').length(),
        greaterThan(1000),
      );
      expect(
        await highQuality.readAsBytes(),
        isNot(orderedEquals(await lowQuality.readAsBytes())),
      );
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test(
    'rotates a page and its ink together without changing stroke width',
    () async {
      final Directory directory = await Directory.systemTemp.createTemp(
        'fastink_rotate_test_',
      );
      try {
        final NoteRepository repository = NoteRepository(
          dataRoot: '${directory.path}\\data',
        );
        NoteDocument document = await repository.createBlankNote(
          '旋转测试',
          template: const PaperTemplate(landscape: true),
        );
        await repository.savePageInk(
          document,
          document.pages.first,
          PageInk(
            strokes: <InkStroke>[
              InkStroke(
                color: 0xff202124,
                // 按页面几何平均归一化的粗细（0.012 × 约 670 ≈ 8 像素）。
                width: 0.012,
                points: const <InkPoint>[
                  InkPoint(0.2, 0.3, 0.5),
                  InkPoint(0.8, 0.6, 0.7),
                ],
              ),
              InkStroke(
                color: 0,
                width: 0.01,
                kind: StrokeKind.image,
                imageAsset: 'assets/pic.png',
                points: const <InkPoint>[
                  InkPoint(0.1, 0.1, 0.5),
                  InkPoint(0.4, 0.1, 0.5),
                  InkPoint(0.4, 0.4, 0.5),
                  InkPoint(0.1, 0.4, 0.5),
                ],
              ),
            ],
          ),
        );

        document = await repository.rotatePage(document, 0);
        final PageInk rotated = await repository.loadPageInk(
          document,
          document.pages.first,
        );
        final InkStroke pen = rotated.strokes.firstWhere(
          (stroke) => stroke.kind == StrokeKind.pen,
        );
        // 粗细原样保留：归一化基准是几何平均，旋转换掉宽高也不改像素粗细。
        expect(pen.width, 0.012);
        expect(pen.points.first.x, closeTo(0.7, 0.001));
        expect(pen.points.first.y, closeTo(0.2, 0.001));
        expect(pen.points.last.x, closeTo(0.4, 0.001));
        expect(pen.points.last.y, closeTo(0.8, 0.001));
        // 旋转换点列必须走 copy() 保留全部字段——imageAsset 丢过一次，
        // 图片页一旋转就整页没图。
        final InkStroke image = rotated.strokes.firstWhere(
          (stroke) => stroke.kind == StrokeKind.image,
        );
        expect(image.imageAsset, 'assets/pic.png');
        expect(image.points.first.x, closeTo(0.9, 0.001));
        expect(image.points.first.y, closeTo(0.1, 0.001));

        final ui.Codec codec = await ui.instantiateImageCodec(
          await File(document.pages.first.path).readAsBytes(),
        );
        final ui.FrameInfo frame = await codec.getNextFrame();
        expect(frame.image.height, greaterThan(frame.image.width));
        frame.image.dispose();
        codec.dispose();
      } finally {
        await directory.delete(recursive: true);
      }
    },
  );
}

List<int> _onePagePdf() {
  return _multiPagePdf(1);
}

List<int> _multiPagePdf(int pageCount) {
  const String content =
      'BT /F1 24 Tf 72 720 Td (FastInk PDF import test) Tj ET';
  final int fontObject = 3 + pageCount * 2;
  final List<int> pageObjects = <int>[
    for (int page = 0; page < pageCount; page++) 3 + page * 2,
  ];
  final List<String> objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [${pageObjects.map((id) => '$id 0 R').join(' ')}] /Count $pageCount >>',
    for (int page = 0; page < pageCount; page++) ...<String>[
      '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
          '/Resources << /Font << /F1 $fontObject 0 R >> >> '
          '/Contents ${4 + page * 2} 0 R >>',
      '<< /Length ${content.length} >>\nstream\n$content\nendstream',
    ],
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
  ];
  final StringBuffer buffer = StringBuffer('%PDF-1.4\n');
  final List<int> offsets = <int>[0];
  for (int i = 0; i < objects.length; i++) {
    offsets.add(utf8.encode(buffer.toString()).length);
    buffer.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
  }
  final int xrefOffset = utf8.encode(buffer.toString()).length;
  buffer.write('xref\n0 ${objects.length + 1}\n');
  buffer.write('0000000000 65535 f \n');
  for (final int offset in offsets.skip(1)) {
    buffer.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  buffer.write(
    'trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\n'
    'startxref\n$xrefOffset\n%%EOF\n',
  );
  return utf8.encode(buffer.toString());
}
