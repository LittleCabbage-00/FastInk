import 'dart:convert';
import 'dart:io';
import 'package:fastink_flutter/src/export/export_repository.dart';
import 'package:fastink_flutter/src/models/models.dart';
import 'package:fastink_flutter/src/storage/note_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as raster;

String tool(String name) =>
    '${Directory.current.path}/windows/tools/poppler/$name.exe';

Future<raster.Image> render(File pdf, int page, String output) async {
  final result = await Process.run(tool('pdftoppm'), [
    '-f',
    '$page',
    '-l',
    '$page',
    '-singlefile',
    '-scale-to',
    '500',
    '-png',
    pdf.path,
    output,
  ]);
  expect(result.exitCode, 0, reason: '${result.stderr}');
  return raster.decodePng(await File('$output.png').readAsBytes())!;
}

List<int> fixturePdf() {
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Count 3 /Kids [3 0 R 5 0 R 7 0 R] >>',
  ];
  for (var i = 0; i < 3; i++) {
    final content =
        '1 1 1 rg 0 0 200 300 re f 0 0 1 rg 35 50 15 15 re f '
        '0 0 0 rg BT /F1 12 Tf 40 190 Td (ORIGINAL ${i + 1}) Tj ET';
    objects.add(
      '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 300] '
      '${i == 1 ? '/CropBox [20 30 180 270]' : ''} /Rotate ${i == 1
          ? 90
          : i == 2
          ? 270
          : 0} '
      '/Resources << /Font << /F1 9 0 R >> >> /Contents ${4 + i * 2} 0 R >>',
    );
    objects.add('<< /Length ${content.length} >>\nstream\n$content\nendstream');
  }
  objects.add('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>');
  final buffer = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[0];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(buffer.length);
    buffer.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
  }
  final start = buffer.length;
  buffer.write('xref\n0 ${objects.length + 1}\n0000000000 65535 f \n');
  for (final offset in offsets.skip(1)) {
    buffer.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  buffer.write(
    'trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n$start\n%%EOF',
  );
  return ascii.encode(buffer.toString());
}

InkStroke redInk() => InkStroke(
  color: 0xffff0000,
  width: .025,
  penStyle: PenStyle.ball,
  points: const [InkPoint(.2, .2, 1), InkPoint(.8, .2, 1)],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late NoteRepository notes;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('fastink-export-');
    notes = NoteRepository(dataRoot: '${temp.path}/data');
  });
  tearDown(() async {
    await temp.delete(recursive: true);
  });

  Future<NoteDocument> fixture() async {
    final file = File('${temp.path}/input.pdf');
    await file.writeAsBytes(fixturePdf());
    return notes.importPdf(file, onProgress: (_) {});
  }

  test(
    'vector ink aligns on cropped and rotated original PDF pages and preserves text',
    () async {
      final doc = await fixture();
      for (final page in doc.pages) {
        await notes.savePageInk(doc, page, PageInk(strokes: [redInk()]));
      }
      final output = File('${temp.path}/export.pdf');
      await output.writeAsString(
        'Previous export must be replaced only on success',
      );
      final progress = <ExportProgress>[];
      await ExportRepository(
        notes,
        pdfPagesPerPart: 2,
      ).exportPdf(doc, output, onUpdate: progress.add);
      expect(progress.first.value, 0);
      expect(progress.last.value, 1);
      final values = progress.map((e) => e.value!).toList();
      expect(values, orderedEquals([...values]..sort()));
      for (var i = 1; i <= 3; i++) {
        final image = await render(output, i, '${temp.path}/page$i');
        final pixel = image.getPixel(
          (image.width * .5).round(),
          (image.height * .2).round(),
        );
        expect(
          pixel.r,
          greaterThan(220),
          reason: 'red line on rotated page $i',
        );
        expect(
          pixel.g,
          lessThan(50),
          reason: 'line y position on rotated page $i',
        );
        final outside = image.getPixel(
          (image.width * .5).round(),
          (image.height * .1).round(),
        );
        expect(outside.r, greaterThan(220));
        expect(outside.g, greaterThan(220));
      }
      final text = await Process.run(tool('pdftotext'), [output.path, '-']);
      expect(text.stdout, contains('ORIGINAL 1'));
      expect(text.stdout, contains('ORIGINAL 3'));
      expect(File(doc.pages[2].path).existsSync(), isFalse);
      if (Platform.environment['FASTINK_EXPORT_PREVIEW'] == '1') {
        await File(
          '${temp.path}/page2.png',
        ).copy('build/diagnostics/pdf-export-rotated-preview.png');
      }
    },
  );

  test(
    'reorder, remove and inserted image pages export in requested order without rendering originals',
    () async {
      var doc = await fixture();
      final added = File('${temp.path}/added.png');
      final green = raster.Image(width: 80, height: 100);
      raster.fill(green, color: raster.ColorRgb8(0, 255, 0));
      await added.writeAsBytes(raster.encodePng(green));
      doc = await notes.insertImagePages(doc, 1, [added]);
      await notes.savePageInk(doc, doc.pages[3], PageInk(strokes: [redInk()]));
      final output = File('${temp.path}/subset.pdf');
      await ExportRepository(
        notes,
      ).exportPdf(doc, output, pageIndexes: [3, 1, 0]);
      final info = await Process.run(tool('pdfinfo'), [output.path]);
      expect(info.stdout, contains(RegExp(r'Pages:\s+3')));
      final text = await Process.run(tool('pdftotext'), [output.path, '-']);
      expect(
        text.stdout.toString().indexOf('ORIGINAL 3'),
        lessThan(text.stdout.toString().indexOf('ORIGINAL 1')),
      );
      expect(text.stdout, isNot(contains('ORIGINAL 2')));
      final image = await render(output, 2, '${temp.path}/inserted');
      final pixel = image.getPixel(20, 20);
      expect(pixel.g, greaterThan(230));
      expect(pixel.r, lessThan(20));
      expect(File(doc.pages[3].path).existsSync(), isFalse);
    },
  );

  test(
    'failed export preserves existing destination and does not overwrite original source',
    () async {
      final doc = await fixture();
      final original = (await notes.originalPdfSource(doc))!;
      final before = await original.readAsBytes();
      await notes.savePageInk(
        doc,
        doc.pages.first,
        PageInk(strokes: [redInk()]),
      );
      await expectLater(
        ExportRepository(notes).exportPdf(doc, original),
        throwsStateError,
      );
      expect(await original.readAsBytes(), before);
      await notes.savePageInk(
        doc,
        doc.pages.first,
        PageInk(
          strokes: [
            InkStroke(
              color: 0xff000000,
              width: .01,
              kind: StrokeKind.image,
              imageAsset: 'assets/missing.png',
              points: const [
                InkPoint(.1, .1, 1),
                InkPoint(.5, .1, 1),
                InkPoint(.5, .5, 1),
                InkPoint(.1, .5, 1),
              ],
            ),
          ],
        ),
      );
      final output = File('${temp.path}/existing.pdf');
      await output.writeAsString('existing file');
      await expectLater(
        ExportRepository(notes).exportPdf(doc, output),
        throwsA(isA<FileSystemException>()),
      );
      expect(await output.readAsString(), 'existing file');
      expect(
        temp.listSync().where((f) => f.path.contains('.fastink-export-')),
        isEmpty,
      );
    },
  );

  test(
    'image and text annotations compose with multiply highlighter without hiding the PDF',
    () async {
      final doc = await fixture();
      final asset = File('${temp.path}/blue.png');
      final blue = raster.Image(width: 20, height: 20);
      raster.fill(blue, color: raster.ColorRgb8(0, 0, 255));
      await asset.writeAsBytes(raster.encodePng(blue));
      final relative = await notes.importEmbeddedImage(doc, asset);
      await notes.savePageInk(
        doc,
        doc.pages.first,
        PageInk(
          strokes: [
            InkStroke(
              color: 0xff000000,
              width: .01,
              kind: StrokeKind.image,
              imageAsset: relative,
              points: const [
                InkPoint(.2, .3, 1),
                InkPoint(.4, .3, 1),
                InkPoint(.4, .5, 1),
                InkPoint(.2, .5, 1),
              ],
            ),
            InkStroke(
              color: 0xffffff00,
              width: .04,
              kind: StrokeKind.highlighter,
              points: const [InkPoint(.2, .4, 1), InkPoint(.4, .4, 1)],
            ),
            InkStroke(
              color: 0xff000000,
              width: .01,
              text: 'TEXT',
              textSize: .06,
              points: const [
                InkPoint(.5, .3, 1),
                InkPoint(.9, .3, 1),
                InkPoint(.9, .6, 1),
                InkPoint(.5, .6, 1),
              ],
            ),
          ],
        ),
      );
      final output = File('${temp.path}/mixed.pdf');
      await ExportRepository(notes).exportPdf(doc, output);
      final image = await render(output, 1, '${temp.path}/mixed');
      final pixel = image.getPixel(
        (image.width * .3).round(),
        (image.height * .4).round(),
      );
      expect(pixel.r, lessThan(20));
      expect(pixel.g, lessThan(20));
      expect(pixel.b, inInclusiveRange(150, 185)); // yellow multiply over blue
      final content = await Process.run(tool('pdftotext'), [output.path, '-']);
      expect(content.stdout, contains('ORIGINAL 1'));
    },
  );

  test(
    'background ink reads wait for pending saves and recover the previous snapshot',
    () async {
      final doc = await fixture();
      final page = doc.pages.first;
      await notes.savePageInk(doc, page, PageInk(strokes: [redInk()]));
      final latest = redInk().copy(color: 0xff00ff00);
      final pending = notes.savePageInk(doc, page, PageInk(strokes: [latest]));
      final read = await notes.loadPageInk(doc, page, background: true);
      await pending;
      expect(read.strokes.single.color, 0xff00ff00);
      final primary = File(
        '${notes.dataRoot}/documents/${doc.id}/pages/${page.originalPage.toString().padLeft(6, '0')}.json',
      );
      await File(
        '${primary.path}.previous',
      ).writeAsString(jsonEncode(PageInk(strokes: [redInk()]).toJson()));
      await primary.writeAsString('{invalid');
      final recovered = await notes.loadPageInk(doc, page, background: true);
      expect(recovered.strokes.single.color, 0xffff0000);
    },
  );

  test(
    'consecutive text uses one layer per run and keeps the ink stacking order',
    () async {
      final doc = await fixture();
      InkStroke text(double x) => InkStroke(
        color: 0xffff0000,
        width: .01,
        text: 'MM',
        textSize: .1,
        textBoxWidth: .4,
        points: [
          InkPoint(x, .2, .5),
          InkPoint(x + .4, .2, .5),
          InkPoint(x + .4, .34, .5),
          InkPoint(x, .34, .5),
        ],
      );
      final blue = InkStroke(
        color: 0xff0000ff,
        width: .025,
        penStyle: PenStyle.ball,
        points: const [InkPoint(.1, .26, 1), InkPoint(.9, .26, 1)],
      );
      await notes.savePageInk(
        doc,
        doc.pages.first,
        PageInk(
          strokes: [
            for (var i = 0; i < 6; i++) text(.1),
            blue,
            for (var i = 0; i < 6; i++) text(.55),
          ],
        ),
      );
      final pdf = File('${temp.path}/text-runs.pdf');
      await ExportRepository(notes).exportPdf(doc, pdf);
      final image = await render(pdf, 1, '${temp.path}/text-runs');
      final first = image.getPixel(
        (image.width * .25).round(),
        (image.height * .26).round(),
      );
      final second = image.getPixel(
        (image.width * .65).round(),
        (image.height * .26).round(),
      );
      expect(first.b, greaterThan(220));
      expect(first.r, lessThan(50));
      expect(second.r, greaterThan(220));
      expect(second.b, lessThan(50));
      final info = await Process.run(
        '${Directory.current.path}/windows/tools/qpdf/qpdf.exe',
        ['--json', '--json-key=qpdf', pdf.path],
      );
      expect(info.exitCode, 0);
      final data = jsonDecode(info.stdout as String) as Map;
      int countImages(Object? node) {
        if (node is List) {
          return node.fold<int>(0, (n, child) => n + countImages(child));
        }
        if (node is Map) {
          // 透明图还有灰度蒙版，这里只统计彩色主图。
          return (node['/Subtype'] == '/Image' &&
                      node['/ColorSpace'] == '/DeviceRGB'
                  ? 1
                  : 0) +
              node.values.fold<int>(0, (n, child) => n + countImages(child));
        }
        return 0;
      }

      expect(countImages(data), 2);
    },
  );

  test(
    'plain duplicate pages reuse resources while distinct and annotated pages keep their order',
    () async {
      var doc = await fixture();
      final red = raster.Image(width: 80, height: 100);
      raster.fill(red, color: raster.ColorRgb8(255, 0, 0));
      final blue = raster.Image(width: 80, height: 100);
      raster.fill(blue, color: raster.ColorRgb8(0, 0, 255));
      final redBytes = raster.encodePng(red, level: 0);
      final blueBytes = raster.encodePng(blue, level: 0);
      expect(redBytes.length, blueBytes.length);
      final a = await File('${temp.path}/a.png').writeAsBytes(redBytes);
      final copy = await File('${temp.path}/copy.png').writeAsBytes(redBytes);
      final different = await File(
        '${temp.path}/different.png',
      ).writeAsBytes(blueBytes);
      doc = await notes.insertImagePages(doc, 1, [a, copy, different, a]);
      await notes.savePageInk(
        doc,
        doc.pages[2],
        PageInk(strokes: [redInk().copy(color: 0xff00ff00)]),
      );
      final pdf = File('${temp.path}/duplicates.pdf');
      final updates = <ExportProgress>[];
      await ExportRepository(notes, pdfPagesPerPart: 2).exportPdf(
        doc,
        pdf,
        pageIndexes: [4, 1, 2, 3, 1, 0],
        onUpdate: updates.add,
      );
      final info = await Process.run(tool('pdfinfo'), [pdf.path]);
      expect(info.stdout, contains(RegExp(r'Pages:\s+6')));
      for (final i in [1, 2, 5]) {
        final image = await render(pdf, i, '${temp.path}/duplicate$i');
        final p = image.getPixel(image.width ~/ 2, image.height ~/ 2);
        expect(p.r, greaterThan(240));
        expect(p.b, lessThan(15));
      }
      final annotated = await render(pdf, 3, '${temp.path}/annotated');
      final mark = annotated.getPixel(
        annotated.width ~/ 2,
        (annotated.height * .2).round(),
      );
      expect(mark.g, greaterThan(220));
      final other = await render(pdf, 4, '${temp.path}/blue');
      expect(
        other.getPixel(other.width ~/ 2, other.height ~/ 2).b,
        greaterThan(240),
      );
      final values = updates.map((p) => p.value!).toList();
      expect(values, orderedEquals([...values]..sort()));
      expect(values.last, 1);
    },
  );

  test(
    'unannotated JPEG exports with its EXIF orientation and matching page ratio',
    () async {
      final image = raster.Image(width: 40, height: 80);
      raster.fill(image, color: raster.ColorRgb8(0, 0, 255));
      raster.fillRect(
        image,
        x1: 0,
        y1: 0,
        x2: 39,
        y2: 39,
        color: raster.ColorRgb8(255, 0, 0),
      );
      image.exif.imageIfd.orientation = 6;
      final source = await File(
        '${temp.path}/rotated.jpg',
      ).writeAsBytes(raster.encodeJpg(image, quality: 100));
      final doc = await notes.importImages([source], onProgress: (_) {});
      final pdf = File('${temp.path}/oriented.pdf');
      await ExportRepository(notes).exportPdf(doc, pdf);
      final output = await render(pdf, 1, '${temp.path}/oriented');
      expect(output.width / output.height, closeTo(2, .02));
      final left = output.getPixel(output.width ~/ 4, output.height ~/ 2);
      final right = output.getPixel(output.width * 3 ~/ 4, output.height ~/ 2);
      expect(left.b, greaterThan(220));
      expect(right.r, greaterThan(220));
    },
  );

  final sample = Platform.environment['FASTINK_OUTLINE_SAMPLE'];
  test(
    'real Capital PDF with 66 added pages exports 3088 pages under one minute',
    () async {
      final source = File(sample!);
      final directory = await Directory('${temp.path}/book').create();
      await File('${directory.path}/.fastink-pdf.json').writeAsString(
        jsonEncode({
          'version': 1,
          'source': source.path,
          'pageCount': 3022,
          'dpi': 132,
        }),
      );
      final extra = File('${temp.path}/extra.png');
      final paper = raster.Image(width: 1200, height: 1700);
      raster.fill(paper, color: raster.ColorRgb8(255, 255, 255));
      await extra.writeAsBytes(raster.encodePng(paper));
      final doc = NoteDocument(
        id: 'benchmark',
        title: 'Capital',
        directory: directory.path,
        initialIndex: 0,
        pages: [
          for (var i = 1; i <= 3088; i++)
            NotePage(
              index: i - 1,
              originalPage: i,
              name: 'Book #$i.jpg',
              path: i <= 3022 ? '${directory.path}/Book #$i.jpg' : extra.path,
            ),
        ],
      );
      for (final i in [0, 1, 25, 100, 999, 2000, 3021, 3030]) {
        await notes.savePageInk(
          doc,
          doc.pages[i],
          PageInk(strokes: [redInk()]),
        );
      }
      final output = File('${temp.path}/capital-3088.pdf');
      final progress = <ExportProgress>[];
      final stages = <String, int>{};
      final timer = Stopwatch()..start();
      await ExportRepository(
        notes,
        onTiming: (name, duration) => stages[name] = duration.inMilliseconds,
      ).exportPdf(doc, output, onUpdate: progress.add);
      timer.stop();
      // ignore: avoid_print
      print(
        'CAPITAL_BENCHMARK pages=3088 elapsed_ms=${timer.elapsedMilliseconds} bytes=${await output.length()} stages=${jsonEncode(stages)}',
      );
      expect(timer.elapsed, lessThan(const Duration(minutes: 1)));
      expect(
        directory.listSync().whereType<File>().where(
          (f) => f.path.endsWith('.jpg'),
        ),
        isEmpty,
      );
      expect(progress.last.value, 1);
      final info = await Process.run(tool('pdfinfo'), [output.path]);
      expect(info.stdout, contains(RegExp(r'Pages:\s+3088')));
      final outline = await Process.run(tool('pdftohtml'), [
        '-xml',
        '-i',
        '-f',
        '1',
        '-l',
        '1',
        '-stdout',
        output.path,
      ]);
      expect(
        RegExp(r'<item page=').allMatches(outline.stdout.toString()).length,
        218,
      );
      final image = await render(output, 26, '${temp.path}/capital26');
      final pixel = image.getPixel(
        (image.width * .5).round(),
        (image.height * .2).round(),
      );
      expect(pixel.r, greaterThan(220));
      expect(pixel.g, lessThan(50));
      if (Platform.environment['FASTINK_EXPORT_PREVIEW'] == '1') {
        await File(
          '${temp.path}/capital26.png',
        ).copy('build/diagnostics/pdf-export-capital-preview.png');
      }
      if (Platform.environment['FASTINK_CAPITAL_DENSE'] == '1') {
        final dense = PageInk.fromJson(
          jsonDecode(
                await File(
                  Platform.environment['FASTINK_DENSE_EXPORT_INPUT']!,
                ).readAsString(),
              )
              as Map<String, Object?>,
        );
        final locations = [0, 1, 25, 100, 999, 2000, 3021, 3030];
        for (final i in locations) {
          await notes.savePageInk(doc, doc.pages[i], dense);
        }
        final denseOutput = File('${temp.path}/capital-dense.pdf');
        final watch = Stopwatch()..start();
        final updates = <ExportProgress>[];
        final denseStages = <String, int>{};
        await ExportRepository(
          notes,
          onTiming: (name, duration) =>
              denseStages[name] = duration.inMilliseconds,
        ).exportPdf(doc, denseOutput, onUpdate: updates.add);
        watch.stop();
        expect(watch.elapsed, lessThan(const Duration(minutes: 1)));
        expect(updates.last.value, 1);
        final values = updates.map((u) => u.value!).toList();
        expect(values, orderedEquals([...values]..sort()));
        // ignore: avoid_print
        print(
          'CAPITAL_DENSE pages=3088 annotated=${locations.length} points=${locations.length * dense.strokes.fold<int>(0, (n, s) => n + s.points.length)} elapsed_ms=${watch.elapsedMilliseconds} bytes=${await denseOutput.length()} stages=${jsonEncode(denseStages)}',
        );
      }
      if (Platform.environment['FASTINK_EXPORT_STRESS'] == '1') {
        for (var i = 0; i < 3022; i++) {
          await notes.savePageInk(
            doc,
            doc.pages[i],
            PageInk(strokes: [redInk()]),
          );
        }
        final stress = File('${temp.path}/capital-3088-all-annotated.pdf');
        final stressTimer = Stopwatch()..start();
        await ExportRepository(notes).exportPdf(doc, stress);
        stressTimer.stop();
        // ignore: avoid_print
        print(
          'CAPITAL_STRESS pages=3088 annotated=3022 elapsed_ms=${stressTimer.elapsedMilliseconds} bytes=${await stress.length()}',
        );
        expect(stressTimer.elapsed, lessThan(const Duration(minutes: 1)));
      }
    },
    timeout: const Timeout(Duration(minutes: 5)),
    skip: sample == null || !File(sample).existsSync(),
  );
}
