import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:fastink_flutter/src/importing/onenote_page_parser.dart';
import 'package:fastink_flutter/src/export/export_repository.dart';
import 'package:fastink_flutter/src/platform/onenote_reader.dart';
import 'package:fastink_flutter/src/storage/note_repository.dart';
import 'package:fastink_flutter/src/models/models.dart';
import 'package:fastink_flutter/src/engine/ink_canvas.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as raster;

Uint8List cabinet(Uint8List content, String name) {
  final fileName = utf8.encode(name);
  final fileOffset = 44;
  final blocks = (content.length / 32768).ceil();
  final dataOffset = fileOffset + 16 + fileName.length + 1;
  final output = Uint8List(dataOffset + content.length + blocks * 8);
  final data = ByteData.sublistView(output);
  data.setUint32(0, 0x4643534d, Endian.little);
  data.setUint32(8, output.length, Endian.little);
  data.setUint32(16, fileOffset, Endian.little);
  output[24] = 3;
  output[25] = 1;
  data.setUint16(26, 1, Endian.little);
  data.setUint16(28, 1, Endian.little);
  data.setUint32(36, dataOffset, Endian.little);
  data.setUint16(40, blocks, Endian.little);
  data.setUint32(fileOffset, content.length, Endian.little);
  data.setUint16(fileOffset + 14, 0x20, Endian.little);
  output.setRange(fileOffset + 16, fileOffset + 16 + fileName.length, fileName);
  var offset = dataOffset;
  for (var start = 0; start < content.length; start += 32768) {
    final end = (start + 32768).clamp(0, content.length);
    data.setUint16(offset + 4, end - start, Endian.little);
    data.setUint16(offset + 6, end - start, Endian.little);
    output.setRange(offset + 8, offset + 8 + end - start, content, start);
    offset += 8 + end - start;
  }
  return output;
}

void main() {
  setUpAll(() async {
    for (final (path, families) in [
      (r'C:\Windows\Fonts\segoeui.ttf', ['Segoe UI Variable', 'Segoe UI']),
      (r'C:\Windows\Fonts\calibri.ttf', ['Calibri']),
      (r'C:\Windows\Fonts\calibril.ttf', ['Calibri Light']),
      (r'C:\Windows\Fonts\msyh.ttc', ['Microsoft YaHei UI', 'Microsoft YaHei']),
    ]) {
      final file = File(path);
      if (await file.exists()) {
        final bytes = ByteData.sublistView(await file.readAsBytes());
        for (final family in families) {
          await (FontLoader(family)..addFont(Future.value(bytes))).load();
        }
      }
    }
  });
  testWidgets(
    'OneNote paragraphs, image and pressure strokes remain separate and editable',
    (tester) async {
      final png = base64Encode(
        raster.encodePng(raster.Image(width: 10, height: 10)),
      );
      final page = parseOneNotePage(
        '''<one:Page xmlns:one="http://schemas.microsoft.com/office/onenote/2013/onenote" name="Demo">
<one:QuickStyleDef index="0" font="Segoe UI" fontSize="14" fontColor="#224488"/>
<one:Title><one:OE><one:T>Title</one:T></one:OE></one:Title>
<one:Outline><one:Position x="36" y="90"/><one:Size width="300" height="200"/><one:OEChildren><one:OE quickStyleIndex="0"><one:T><![CDATA[Text &amp; 中文<br>next line]]></one:T></one:OE></one:OEChildren></one:Outline>
<one:Image><one:Position x="36" y="180"/><one:Size width="120" height="80"/><one:Data>$png</one:Data></one:Image>
<one:InkDrawing><one:Position x="54" y="280"/><one:Size width="160" height="80"/><one:Data>AA==</one:Data></one:InkDrawing></one:Page>''',
        [
          {
            'index': 0,
            'bounds': [0, 0, 160, 80],
            'strokes': [
              {
                'color': 0xff123456,
                'width': 3,
                'height': 3,
                'highlighter': false,
                'ignorePressure': false,
                'points': [
                  [0, 0, .3],
                  [80, 40, .9],
                  [160, 80, .5],
                ],
              },
            ],
          },
        ],
      );
      expect(page.strokes.where((s) => s.text != null), hasLength(2));
      final text = page.strokes.firstWhere(
        (s) => s.text?.startsWith('Text') ?? false,
      );
      expect(text.text, 'Text & 中文\nnext line');
      expect(text.color, 0xff224488);
      expect(text.textSize * page.size.height, 14);
      expect(page.images, hasLength(1));
      expect(
        page.strokes.where((s) => s.kind == StrokeKind.image),
        hasLength(1),
      );
      final ink = page.strokes.last;
      expect(ink.points.map((p) => p.pressure), [.3, .9, .5]);
      expect(ink.points.first.x * page.size.width, 54);
      final controller = InkController(onCommitted: () {})
        ..replace(page.strokes);
      controller.updateText(text, 'Changed after import', page.size);
      expect(
        controller.strokes.any((s) => s.text == 'Changed after import'),
        isTrue,
      );
      controller.undo();
      expect(controller.strokes.any((s) => s.text == text.text), isTrue);
      controller.selectAll();
      controller.deleteSelection();
      expect(controller.strokes, isEmpty);
      controller.undo();
      expect(controller.strokes, hasLength(4));
      controller.dispose();
      expect(page.warnings, isEmpty);
    },
  );

  test('OneNote extensions and invalid package rejection', () async {
    for (final extension in ['one', 'onex', 'onepkg', 'ONE']) {
      expect(OneNoteReader.supports('测试.$extension'), isTrue);
    }
    expect(OneNoteReader.supports('note.one.exe'), isFalse);
    final temp = await Directory.systemTemp.createTemp('fastink-cab-check-');
    try {
      final fake = File('${temp.path}/fake.onepkg');
      await fake.writeAsString('not a cabinet');
      await expectLater(
        OneNoteReader.validatePackage(fake),
        throwsFormatException,
      );
      await fake.writeAsBytes(
        cabinet(Uint8List.fromList([1, 2, 3]), '../outside.one'),
      );
      await expectLater(
        OneNoteReader.validatePackage(fake),
        throwsFormatException,
      );
      await fake.writeAsBytes(
        cabinet(Uint8List.fromList([1, 2, 3]), 'Notebook/Section.one'),
      );
      await OneNoteReader.validatePackage(fake);
    } finally {
      await temp.delete(recursive: true);
    }
  });

  final sample = Platform.environment['FASTINK_ONENOTE_SAMPLE'];
  testWidgets(
    'real OneNote file imports native content without changing the source',
    (tester) async {
      final temp = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('fastink-one-integration-'),
      ))!;
      final source = File(sample!);
      final before = await tester.runAsync(
        () async => sha256.convert(await source.readAsBytes()),
      );
      final repo = NoteRepository(dataRoot: '${temp.path}/data');
      final batch = (await tester.runAsync(
        () => repo.importOneNote(source, onProgress: (_) {}),
      ))!;
      expect(batch.documents, isNotEmpty);
      final doc = batch.documents.first.document;
      final ink = (await tester.runAsync(
        () => repo.loadPageInk(doc, doc.pages.first),
      ))!;
      expect(
        ink.strokes.where((s) => s.kind == StrokeKind.pen && s.text == null),
        isNotEmpty,
      );
      expect(ink.strokes.where((s) => s.text != null), isNotEmpty);
      final original = (await tester.runAsync(source.readAsBytes))!;
      for (final extension in ['onex', 'onepkg']) {
        final variant = File('${temp.path}/sample.$extension');
        await tester.runAsync(
          () => variant.writeAsBytes(
            extension == 'onepkg'
                ? cabinet(original, 'Notebook/Section.one')
                : original,
          ),
        );
        final converted = (await tester.runAsync(
          () => repo.importOneNote(variant, onProgress: (_) {}),
        ))!;
        final importedDoc = converted.documents.single.document;
        final content = (await tester.runAsync(
          () => repo.loadPageInk(importedDoc, importedDoc.pages.first),
        ))!;
        expect(content.strokes.length, ink.strokes.length, reason: extension);
      }
      // Confirm the background contains no baked-in content, then render the
      // imported editable objects for visual QA with real Windows fonts.
      final blank = (await tester.runAsync(
        () async =>
            raster.decodePng(await File(doc.pages.first.path).readAsBytes()),
      ))!;
      expect(blank.getPixel(blank.width ~/ 2, blank.height ~/ 2).r, 255);
      await tester.runAsync(
        () => ExportRepository(repo).exportImage(
          doc,
          doc.pages.first,
          File('build/diagnostics/onenote-editable-import.png'),
          NoteExportFormat.png,
        ),
      );
      final after = await tester.runAsync(
        () async => sha256.convert(await source.readAsBytes()),
      );
      expect(after.toString(), before.toString());
      final imageSample = Platform.environment['FASTINK_ONENOTE_IMAGE_SAMPLE'];
      if (imageSample != null) {
        final converted = (await tester.runAsync(
          () => repo.importOneNote(File(imageSample), onProgress: (_) {}),
        ))!;
        final imageDoc = converted.documents.single.document;
        final content = (await tester.runAsync(
          () => repo.loadPageInk(imageDoc, imageDoc.pages.first),
        ))!;
        final images = content.strokes
            .where((s) => s.kind == StrokeKind.image)
            .toList();
        expect(images, isNotEmpty);
        for (final image in images) {
          expect(
            await tester.runAsync(
              () => File(
                repo.resolveEmbeddedImagePath(imageDoc, image.imageAsset!),
              ).exists(),
            ),
            isTrue,
          );
        }
      }
      await tester.runAsync(() async {
        await File(
          'build/diagnostics/onenote-integration-result.json',
        ).writeAsString(
          jsonEncode({
            'documents': batch.documents.length,
            'pages': doc.pages.length,
            'textObjects': ink.strokes.where((s) => s.text != null).length,
            'inkStrokes': ink.strokes
                .where((s) => s.kind == StrokeKind.pen && s.text == null)
                .length,
            'warnings': batch.warnings.length,
            'sourceUnchanged': true,
          }),
        );
        await temp.delete(recursive: true);
      });
    },
    skip: sample == null,
  );
}
