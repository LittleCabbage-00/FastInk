import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:fastink_flutter/src/core/app_localizations.dart';
import 'package:fastink_flutter/src/storage/note_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;

void main() {
  test(
    'PDF worker preserves original, ordered lazy pages, DPI and Chinese progress',
    () async {
      final root = await Directory.systemTemp.createTemp('fastink-pdf-worker-');
      final previousLocale = AppText.locale;
      AppText.locale = const Locale('zh');
      try {
        final pdf = pw.Document(compress: true);
        for (var page = 0; page < 3; page++) {
          pdf.addPage(
            pw.Page(
              build: (_) => pw.Outline(
                name: 'page-$page',
                title: '章节 ${page + 1}',
                child: pw.Text('Page ${page + 1}'),
              ),
            ),
          );
        }
        final original = File('${root.path}/test source.pdf');
        final bytes = await pdf.save();
        await original.writeAsBytes(bytes);
        final repository = NoteRepository(
          dataRoot: '${root.path}/library',
          pdfImportDpi: 108,
        );
        final parent = Isolate.current.controlPort;
        final messages = <String>[];
        final document = await repository.importPdf(
          original,
          onProgress: (message) {
            expect(Isolate.current.controlPort, parent);
            messages.add(message);
          },
        );
        expect(messages.first, '正在读取 PDF 页数…');
        expect(messages.last, contains('共 3 页'));
        expect(document.title, 'test source');
        expect(document.pages.map((page) => page.originalPage), [1, 2, 3]);
        expect(await File(document.pages.first.path).exists(), isTrue);
        for (final page in document.pages.skip(1)) {
          expect(await File(page.path).exists(), isFalse);
        }
        final metadata =
            jsonDecode(
                  await File(
                    '${document.directory}/.fastink-pdf.json',
                  ).readAsString(),
                )
                as Map;
        expect(metadata['dpi'], 108);
        expect(await File(metadata['source'] as String).readAsBytes(), bytes);
        expect(await original.readAsBytes(), bytes);
        final reopened = await repository.indexFromSelectedPath(
          document.pages.first.path,
          documentId: document.id,
        );
        expect(
          reopened.pages.map((page) => page.path),
          document.pages.map((page) => page.path),
        );
        final outline = await repository.readPdfOutline(document);
        expect(outline.map((entry) => entry.title), ['章节 1', '章节 2', '章节 3']);
        expect(outline.map((entry) => entry.originalPage), [1, 2, 3]);
      } finally {
        AppText.locale = previousLocale;
        await root.delete(recursive: true);
      }
    },
  );

  test('worker failure returns promptly and a later import succeeds', () async {
    final root = await Directory.systemTemp.createTemp(
      'fastink-pdf-worker-error-',
    );
    try {
      final broken = File('${root.path}/invalid.pdf');
      await broken.writeAsString('This is not a PDF');
      final repository = NoteRepository(dataRoot: '${root.path}/library');
      await expectLater(
        repository.importPdf(broken, onProgress: (_) {}),
        throwsA(isA<StateError>()),
      );
      final pdf = pw.Document()
        ..addPage(pw.Page(build: (_) => pw.Text('Recovery')));
      final valid = File('${root.path}/valid.pdf');
      await valid.writeAsBytes(await pdf.save());
      final imported = await repository.importPdf(valid, onProgress: (_) {});
      expect(imported.pages, hasLength(1));
      expect(await File(imported.pages.first.path).exists(), isTrue);
    } finally {
      await root.delete(recursive: true);
    }
  });
}
