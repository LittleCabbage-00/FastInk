import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:fastink_flutter/src/export/export_repository.dart';
import 'package:fastink_flutter/src/models/models.dart';
import 'package:fastink_flutter/src/storage/image_export_encoder.dart';
import 'package:fastink_flutter/src/storage/note_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as raster;

List<int> jpegSampling(Uint8List bytes) {
  var offset = 2;
  while (offset + 8 < bytes.length) {
    if (bytes[offset] != 255) {
      offset++;
      continue;
    }
    final marker = bytes[offset + 1];
    offset += 2;
    final length = (bytes[offset] << 8) | bytes[offset + 1];
    if (marker == 0xc0 || marker == 0xc1 || marker == 0xc2) {
      final count = bytes[offset + 7];
      return [for (var i = 0; i < count; i++) bytes[offset + 9 + i * 3]];
    }
    offset += length;
  }
  throw StateError('JPEG frame header missing');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late NoteRepository notes;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('fastink-image-export-');
    notes = NoteRepository(dataRoot: '${temp.path}/data');
  });
  tearDown(() async {
    await temp.delete(recursive: true);
  });

  Future<NoteDocument> fixture({int count = 2, bool jpegSource = false}) async {
    final image = raster.Image(width: 120, height: 180, numChannels: 4);
    raster.fill(image, color: raster.ColorRgba8(255, 255, 255, 255));
    raster.fillRect(
      image,
      x1: 10,
      y1: 20,
      x2: 50,
      y2: 65,
      color: raster.ColorRgba8(240, 15, 25, 255),
    );
    raster.fillRect(
      image,
      x1: 65,
      y1: 100,
      x2: 110,
      y2: 160,
      color: raster.ColorRgba8(20, 35, 240, 255),
    );
    final source = File('${temp.path}/source.png');
    // A lazy PDF cache also uses a .png filename for JPEG contents. Detect
    // signatures rather than extensions before copying PNG pages unchanged.
    await source.writeAsBytes(
      jpegSource ? raster.encodeJpg(image) : raster.encodePng(image),
    );
    return notes.importImages(List.filled(count, source), onProgress: (_) {});
  }

  test(
    'unannotated PNG is copied byte-for-byte; numeric progress completes after writing',
    () async {
      final doc = await fixture();
      final repo = ExportRepository(notes);
      final progress = <ExportProgress>[];
      final output = Directory('${temp.path}/png');
      await repo.exportImages(
        doc,
        output,
        NoteExportFormat.png,
        onUpdate: progress.add,
      );
      final files =
          (await output.list().where((e) => e is File).cast<File>().toList())
            ..sort((a, b) => a.path.compareTo(b.path));
      expect(files, hasLength(2));
      expect(
        await files.first.readAsBytes(),
        await File(doc.pages.first.path).readAsBytes(),
      );
      expect(progress.last.value, 1);
      for (var i = 1; i < progress.length; i++) {
        expect(
          progress[i].value!,
          greaterThanOrEqualTo(progress[i - 1].value!),
        );
      }
      expect(files.every((f) => !f.path.endsWith('.tmp')), isTrue);
    },
  );

  test('JPEG source with a PNG filename is converted to actual PNG', () async {
    final doc = await fixture(count: 1, jpegSource: true);
    final output = File('${temp.path}/actual.png');
    await ExportRepository(
      notes,
    ).exportImage(doc, doc.pages.first, output, NoteExportFormat.png);
    final bytes = await output.readAsBytes();
    expect(bytes.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
    final image = raster.decodePng(bytes)!;
    expect(image.width, 120);
    expect(image.height, 180);
    expect(image.getPixel(25, 40).r, greaterThan(210));
  });

  test(
    'annotations compose before native JPG encoding with correct colors and dimensions',
    () async {
      final doc = await fixture(count: 1);
      await notes.savePageInk(
        doc,
        doc.pages.first,
        PageInk(
          strokes: [
            InkStroke(
              color: 0xff00aa00,
              width: .06,
              penStyle: PenStyle.ball,
              points: const [InkPoint(.1, .5, 1), InkPoint(.9, .5, 1)],
            ),
          ],
        ),
      );
      final output = File('${temp.path}/批注页面.jpg');
      final progress = <ExportProgress>[];
      await ExportRepository(notes).exportImage(
        doc,
        doc.pages.first,
        output,
        NoteExportFormat.jpg,
        onUpdate: progress.add,
      );
      final image = raster.decodeJpg(await output.readAsBytes())!;
      expect(
        jpegSampling(await output.readAsBytes()),
        [0x11, 0x11, 0x11],
        reason: 'Keep 4:4:4 color detail for colored handwriting.',
      );
      expect(image.width, 120);
      expect(image.height, 180);
      expect(image.getPixel(25, 40).r, greaterThan(210));
      expect(image.getPixel(85, 130).b, greaterThan(210));
      expect(image.getPixel(60, 90).g, greaterThan(120));
      expect(image.getPixel(60, 90).r, lessThan(45));
      expect(progress.last.value, 1);
    },
  );

  test(
    'JPEG transparency becomes white; PNG preserves original transparency',
    () async {
      final image = raster.Image(width: 120, height: 180, numChannels: 4);
      raster.fill(image, color: raster.ColorRgba8(0, 0, 0, 0));
      raster.fillRect(
        image,
        x1: 20,
        y1: 20,
        x2: 70,
        y2: 70,
        color: raster.ColorRgba8(255, 0, 0, 255),
      );
      final source = File('${temp.path}/transparent.png');
      await source.writeAsBytes(raster.encodePng(image));
      final doc = await notes.importImages([source], onProgress: (_) {});
      final repo = ExportRepository(notes);
      final jpeg = File('${temp.path}/white.jpg');
      final png = File('${temp.path}/transparent-export.png');
      await repo.exportImage(doc, doc.pages.first, jpeg, NoteExportFormat.jpg);
      await repo.exportImage(doc, doc.pages.first, png, NoteExportFormat.png);
      final color = raster
          .decodeJpg(await jpeg.readAsBytes())!
          .getPixel(100, 150);
      expect(color.r, greaterThan(245));
      expect(color.g, greaterThan(245));
      expect(color.b, greaterThan(245));
      expect(
        raster.decodePng(await png.readAsBytes())!.getPixel(100, 150).a,
        0,
      );
    },
  );

  test(
    'source overwrite is rejected; failure preserves an existing destination and removes temporaries',
    () async {
      final doc = await fixture(count: 1);
      final repo = ExportRepository(notes);
      final source = File(doc.pages.first.path);
      final original = await source.readAsBytes();
      await expectLater(
        repo.exportImage(doc, doc.pages.first, source, NoteExportFormat.png),
        throwsArgumentError,
      );
      expect(await source.readAsBytes(), original);
      final output = File('${temp.path}/keep.jpg');
      await output.writeAsBytes([1, 2, 3]);
      await source.writeAsBytes([0, 1, 2, 3]);
      await expectLater(
        repo.exportImage(doc, doc.pages.first, output, NoteExportFormat.jpg),
        throwsA(anything),
      );
      expect(await output.readAsBytes(), [1, 2, 3]);
      expect(await temp.list().where((e) => e.path.endsWith('.tmp')).length, 0);
    },
  );

  test(
    'background encoder is reusable, bounded and closes after a failed write',
    () async {
      final worker = await ImageExportEncoder.start();
      final rgba = Uint8List(32 * 32 * 4);
      for (var i = 0; i < rgba.length; i += 4) {
        rgba[i] = 255;
        rgba[i + 3] = 255;
      }
      try {
        final first = worker.writeJpeg(
          rgba,
          32,
          32,
          File('${temp.path}/red.jpg'),
          94,
        );
        expect(
          () =>
              worker.writeJpeg(rgba, 32, 32, File('${temp.path}/busy.jpg'), 94),
          throwsStateError,
        );
        await first;
        await expectLater(
          worker.writeJpeg(
            rgba,
            32,
            32,
            File('${temp.path}/missing/output.jpg'),
            94,
          ),
          throwsStateError,
        );
        await worker.writeJpeg(
          rgba,
          32,
          32,
          File('${temp.path}/recovered.jpg'),
          94,
        );
        final image = raster.decodeJpg(
          await File('${temp.path}/recovered.jpg').readAsBytes(),
        )!;
        expect(image.getPixel(15, 15).r, greaterThan(245));
        expect(image.getPixel(15, 15).b, lessThan(10));
        final odd = Uint8List(31 * 29 * 4);
        for (var i = 0; i < odd.length; i += 4) {
          odd[i + 2] = 255;
          odd[i + 3] = 255;
        }
        final oddFile = File('${temp.path}/odd.jpg');
        await worker.writeJpeg(odd, 31, 29, oddFile, 94);
        final oddImage = raster.decodeJpg(await oddFile.readAsBytes())!;
        expect(oddImage.width, 31);
        expect(oddImage.height, 29);
        expect(oddImage.getPixel(20, 20).b, greaterThan(245));
        final padding =
            250 - File('${temp.path}/fallback.jpg').absolute.path.length - 1;
        final folder = await Directory(
          '${temp.path}/${List.filled(padding, 'x').join()}',
        ).create();
        final longFile = File('${folder.path}/fallback.jpg');
        expect(longFile.absolute.path.length, greaterThanOrEqualTo(248));
        await worker.writeJpeg(rgba, 32, 32, longFile, 94);
        expect(
          raster.decodeJpg(await longFile.readAsBytes())!.getPixel(15, 15).r,
          greaterThan(245),
        );
      } finally {
        await worker.dispose();
      }
      expect(
        () =>
            worker.writeJpeg(rgba, 32, 32, File('${temp.path}/closed.jpg'), 94),
        throwsStateError,
      );
    },
  );

  test(
    'a junction alias cannot replace a source page or notebook metadata',
    () async {
      final doc = await fixture(count: 1);
      final source = File(doc.pages.first.path);
      final original = await source.readAsBytes();
      if (Platform.isWindows) {
        final alias = '${temp.path}/source-alias';
        final link = await Process.run('cmd.exe', [
          '/c',
          'mklink',
          '/J',
          alias.replaceAll('/', '\\'),
          source.parent.path.replaceAll('/', '\\'),
        ]);
        expect(link.exitCode, 0, reason: '${link.stderr}');
        final target = File('$alias/${source.uri.pathSegments.last}');
        await expectLater(
          ExportRepository(
            notes,
          ).exportImage(doc, doc.pages.first, target, NoteExportFormat.jpg),
          throwsArgumentError,
        );
        expect(await source.readAsBytes(), original);
      }
      final metadata = File(
        '${notes.dataRoot}/documents/${doc.id}/pages/keep.json',
      );
      await metadata.parent.create(recursive: true);
      await metadata.writeAsString('keep');
      await expectLater(
        ExportRepository(
          notes,
        ).exportImage(doc, doc.pages.first, metadata, NoteExportFormat.png),
        throwsArgumentError,
      );
      expect(await metadata.readAsString(), 'keep');
    },
  );

  test(
    'atomic replacement works and a failed replacement preserves the old target',
    () async {
      final doc = await fixture(count: 1);
      final repo = ExportRepository(notes);
      final target = File('${temp.path}/replace.png');
      await target.writeAsBytes([1, 2, 3]);
      await repo.exportImage(
        doc,
        doc.pages.first,
        target,
        NoteExportFormat.png,
      );
      expect(
        await target.readAsBytes(),
        await File(doc.pages.first.path).readAsBytes(),
      );
      final occupied = await Directory('${temp.path}/occupied.jpg').create();
      final marker = File('${occupied.path}/keep.txt');
      await marker.writeAsString('keep');
      final updates = <ExportProgress>[];
      await expectLater(
        repo.exportImage(
          doc,
          doc.pages.first,
          File(occupied.path),
          NoteExportFormat.jpg,
          onUpdate: updates.add,
        ),
        throwsA(anything),
      );
      expect(await marker.readAsString(), 'keep');
      expect(updates.last.value, lessThan(1));
      expect(await temp.list().where((f) => f.path.endsWith('.tmp')).length, 0);
    },
  );

  test(
    'encoding benchmark on the same full-resolution page',
    () async {
      const width = 1200, height = 1700, count = 12;
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.drawColor(const ui.Color(0xffffffff), ui.BlendMode.src);
      for (var i = 0; i < 120; i++) {
        canvas.drawRect(
          ui.Rect.fromLTWH((i % 10) * 120, (i ~/ 10) * 140, 110, 130),
          ui.Paint()..color = ui.Color(0xff000000 | ((i * 19873) & 0xffffff)),
        );
        canvas.drawLine(
          ui.Offset(20, i * 14),
          ui.Offset(1180, i * 14 + 8),
          ui.Paint()
            ..color = const ui.Color(0xff223344)
            ..strokeWidth = 2,
        );
      }
      final picture = recorder.endRecording();
      final page = await picture.toImage(width, height);
      picture.dispose();
      final worker = await ImageExportEncoder.start();
      final old = Stopwatch(), fast = Stopwatch();
      try {
        // Warm both codecs once; compare the old PNG -> decode -> JPEG chain
        // against raw pixels -> native JPEG at the same quality, including I/O.
        final warm = await page.toByteData(format: ui.ImageByteFormat.png);
        raster.encodeJpg(
          raster.decodePng(warm!.buffer.asUint8List())!,
          quality: 94,
        );
        final raw = await page.toByteData(
          format: ui.ImageByteFormat.rawStraightRgba,
        );
        await worker.writeJpeg(
          raw!.buffer.asUint8List(),
          width,
          height,
          File('${temp.path}/warm.jpg'),
          94,
        );
        old.start();
        for (var i = 0; i < count; i++) {
          final png = await page.toByteData(format: ui.ImageByteFormat.png);
          final decoded = raster.decodePng(png!.buffer.asUint8List())!;
          await File(
            '${temp.path}/old-$i.jpg',
          ).writeAsBytes(raster.encodeJpg(decoded, quality: 94), flush: true);
        }
        old.stop();
        fast.start();
        for (var i = 0; i < count; i++) {
          final bytes = await page.toByteData(
            format: ui.ImageByteFormat.rawStraightRgba,
          );
          await worker.writeJpeg(
            bytes!.buffer.asUint8List(),
            width,
            height,
            File('${temp.path}/new-$i.jpg'),
            94,
          );
        }
        fast.stop();
        final result =
            'JPEG_ENCODE_BENCH pages=$count pixels=${width}x$height old_ms=${old.elapsedMilliseconds} new_ms=${fast.elapsedMilliseconds} speedup=${(old.elapsedMicroseconds / fast.elapsedMicroseconds).toStringAsFixed(2)}';
        stdout.writeln(result);
        await Directory('build/diagnostics').create(recursive: true);
        await File(
          'build/diagnostics/image-export-benchmark.txt',
        ).writeAsString('$result\n');
        await File(
          '${temp.path}/new-0.jpg',
        ).copy('build/diagnostics/image-export-native-preview.jpg');
        final source = File('${temp.path}/benchmark-source.png');
        await source.writeAsBytes(warm.buffer.asUint8List());
        final doc = await notes.importImages(
          List.filled(count, source),
          onProgress: (_) {},
        );
        old.reset();
        old.start();
        for (var i = 0; i < count; i++) {
          await notes.loadPageInk(doc, doc.pages[i]);
          final codec = await ui.instantiateImageCodec(
            await File(doc.pages[i].path).readAsBytes(),
          );
          final frame = await codec.getNextFrame();
          codec.dispose();
          final recorder = ui.PictureRecorder();
          ui.Canvas(recorder).drawImageRect(
            frame.image,
            ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
            ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
            ui.Paint()..filterQuality = ui.FilterQuality.high,
          );
          final picture = recorder.endRecording();
          final flattened = await picture.toImage(width, height);
          picture.dispose();
          try {
            final data = await flattened.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File(
              '${temp.path}/old-$i.png',
            ).writeAsBytes(data!.buffer.asUint8List(), flush: true);
          } finally {
            flattened.dispose();
            frame.image.dispose();
          }
        }
        old.stop();
        fast.reset();
        fast.start();
        final pngOutput = Directory('${temp.path}/fast-png');
        await ExportRepository(
          notes,
        ).exportImages(doc, pngOutput, NoteExportFormat.png);
        fast.stop();
        final pngResult =
            'PNG_EXPORT_BENCH pages=$count pixels=${width}x$height old_ms=${old.elapsedMilliseconds} new_ms=${fast.elapsedMilliseconds} speedup=${(old.elapsedMicroseconds / fast.elapsedMicroseconds).toStringAsFixed(2)}';
        stdout.writeln(pngResult);
        await File(
          'build/diagnostics/image-export-benchmark.txt',
        ).writeAsString('$pngResult\n', mode: FileMode.append);
        await source.copy('build/diagnostics/image-export-source-preview.png');
      } finally {
        page.dispose();
        await worker.dispose();
      }
    },
    skip: Platform.environment['FASTINK_IMAGE_BENCH'] != '1',
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
