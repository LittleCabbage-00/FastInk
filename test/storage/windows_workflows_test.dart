import 'dart:convert';
import 'dart:io';
import 'package:fastink_flutter/src/models/models.dart';
import 'package:fastink_flutter/src/storage/library_backup.dart';
import 'package:fastink_flutter/src/storage/library_repository.dart';
import 'package:fastink_flutter/src/storage/note_repository.dart';
import 'package:fastink_flutter/src/storage/template_library.dart';
import 'package:fastink_flutter/src/widgets/page_batch_dialog.dart';
import 'package:fastink_flutter/src/widgets/paper_template_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'package:image/image.dart' as raster;

void main() {
  Future<Directory> sandbox() async {
    final dir = await Directory.systemTemp.createTemp(
      'fastink_windows_workflows_',
    );
    addTearDown(() async {
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    });
    return dir;
  }

  test(
    'PDF template import uses only the first page and keeps its layout',
    () async {
      final temp = await sandbox();
      final pdf = pw.Document();
      pdf.addPage(
        pw.Page(
          pageFormat: const PdfPageFormat(300, 200),
          margin: pw.EdgeInsets.zero,
          build: (_) => pw.Container(color: PdfColors.blue),
        ),
      );
      pdf.addPage(pw.Page(build: (_) => pw.Container(color: PdfColors.red)));
      final input = File('${temp.path}/TwoPages.pdf');
      await input.writeAsBytes(await pdf.save());
      final template = await TemplateLibrary(
        '${temp.path}/library',
      ).importFile(input);
      expect(template.pixelSize.aspectRatio, closeTo(1.5, .01));
      final image = raster.decodePng(
        await File(template.backgroundAsset!).readAsBytes(),
      )!;
      final pixel = image.getPixel(image.width ~/ 2, image.height ~/ 2);
      expect(pixel.b, greaterThan(220));
      expect(pixel.r, lessThan(80));
      expect(pixel.b - pixel.r, greaterThan(150));
    },
  );

  test(
    'editable backup survives relocation and loss of original external files',
    () async {
      final temp = await sandbox();
      final root = '${temp.path}/library';
      final repo = NoteRepository(dataRoot: root);
      final note = await repo.createBlankNote(
        'Notebook',
        template: const PaperTemplate(pattern: PaperPattern.weekly),
      );
      final literalText = '$root/this is written text';
      final asset = await repo.importEmbeddedImage(
        note,
        File(note.pages.first.path),
      );
      await repo.savePageInk(
        note,
        note.pages.first,
        PageInk(
          strokes: [
            InkStroke(
              color: 0xff000000,
              width: .002,
              text: literalText,
              points: [const InkPoint(.1, .2, .8), const InkPoint(.3, .4, .8)],
            ),
            InkStroke(
              color: 0xff000000,
              width: .002,
              kind: StrokeKind.image,
              imageAsset: asset,
              points: [const InkPoint(.2, .2, 1)],
            ),
          ],
        ),
      );
      final outside = await Directory('${temp.path}/outside').create();
      await File(note.pages.first.path).copy('${outside.path}/External.png');
      final external = await repo.indexFromDirectory(outside.path);
      final library = LibraryRepository(root: root);
      await library.save(
        LibraryState(
          documents: [
            library
                .fromDocument(note)
                .copyWith(bookmarkedPages: [0], pageTitles: {0: 'Chapter'}),
            library.fromDocument(external),
          ],
        ),
      );
      final previewCache = await Directory('$root/.preview-cache').create();
      await File('${previewCache.path}/throwaway.png').writeAsBytes([1, 2, 3]);
      await LibraryBackup.create(root, '${temp.path}/backup');
      expect(
        Directory('${temp.path}/backup/.preview-cache').existsSync(),
        isFalse,
      );
      await Directory('${temp.path}/backup').rename('${temp.path}/moved');
      await Directory(root).rename('${temp.path}/old-library');
      await outside.rename('${temp.path}/old-outside');
      final restored = '${temp.path}/restored';
      await LibraryBackup.restore('${temp.path}/moved', restored);
      final loaded = await LibraryRepository(root: restored).load();
      expect(loaded.documents, hasLength(2));
      expect(loaded.documents.first.bookmarkedPages, [0]);
      expect(loaded.documents.first.pageTitles[0], 'Chapter');
      final restoredRepo = NoteRepository(dataRoot: restored);
      for (final item in loaded.documents) {
        expect(File(item.sourcePath).existsSync(), isTrue);
        final document = await restoredRepo.indexFromSelectedPath(
          item.sourcePath,
          documentId: item.id,
        );
        expect(File(document.pages.first.path).existsSync(), isTrue);
      }
      final document = await restoredRepo.indexFromSelectedPath(
        loaded.documents.first.sourcePath,
        documentId: loaded.documents.first.id,
      );
      final ink = await restoredRepo.loadPageInk(
        document,
        document.pages.first,
      );
      expect(
        ink.strokes.first.text,
        literalText,
      ); // Never rewrite text that resembles a path.
      expect(ink.strokes.first.points.first.pressure, .8);
      expect(
        File(
          restoredRepo.resolveEmbeddedImagePath(
            document,
            ink.strokes.last.imageAsset!,
          ),
        ).existsSync(),
        isTrue,
      );
      expect(
        (await restoredRepo.loadPaperTemplate(document.pages.first))!.pattern,
        PaperPattern.weekly,
      );
      await restoredRepo.savePageInk(
        document,
        document.pages.first,
        const PageInk(strokes: []),
      );
      expect(
        (await restoredRepo.loadPageInk(
          document,
          document.pages.first,
        )).strokes,
        isEmpty,
      );
    },
  );

  test(
    'backup refuses changed files, traversal and overwriting existing library',
    () async {
      final temp = await sandbox();
      final root = '${temp.path}/library';
      await LibraryRepository(root: root).save(const LibraryState());
      final backup = '${temp.path}/backup';
      await LibraryBackup.create(root, backup);
      await expectLater(
        LibraryBackup.restore(backup, root),
        throwsA(isA<FileSystemException>()),
      );
      await File('$backup/library.json').writeAsString('{}');
      await expectLater(
        LibraryBackup.restore(backup, '${temp.path}/bad'),
        throwsFormatException,
      );
      expect(Directory('${temp.path}/bad').existsSync(), isFalse);
      final marker = File('$backup/${LibraryBackup.marker}');
      final meta =
          jsonDecode(await marker.readAsString()) as Map<String, dynamic>;
      meta['files'] = {'../escape.json': 'fake', 'library.json': 'fake'};
      await marker.writeAsString(jsonEncode(meta));
      await expectLater(
        LibraryBackup.restore(backup, '${temp.path}/escape'),
        throwsFormatException,
      );
      expect(Directory('${temp.path}/escape').existsSync(), isFalse);
    },
  );

  test(
    'batch pages preserve copied ink and paper, reject deleting all, and reuse clean pages',
    () async {
      final temp = await sandbox();
      final repo = NoteRepository(dataRoot: '${temp.path}/library');
      var note = await repo.createBlankNote('Batch');
      note = await repo.addBlankPage(
        note,
        insertIndex: 1,
        template: const PaperTemplate(pattern: PaperPattern.cornell),
      );
      await repo.savePageInk(
        note,
        note.pages[1],
        PageInk(
          strokes: [
            InkStroke(
              color: 0xff000000,
              width: .002,
              points: [const InkPoint(.1, .3, .6)],
            ),
          ],
        ),
      );
      note = await repo.batchPages(note, [0, 1], duplicate: true);
      expect(note.pages.map((p) => p.originalPage).toSet(), hasLength(4));
      expect(
        (await repo.loadPageInk(note, note.pages[3])).strokes,
        hasLength(1),
      );
      expect(
        (await repo.loadPaperTemplate(note.pages[3]))!.pattern,
        PaperPattern.cornell,
      );
      await expectLater(
        repo.batchPages(note, [0, 1, 2, 3], duplicate: false),
        throwsStateError,
      );
      note = await repo.batchPages(note, [1, 2, 3], duplicate: false);
      expect(note.pages, hasLength(1));
      note = await repo.addBlankPage(note, insertIndex: 1);
      expect((await repo.loadPageInk(note, note.pages[1])).strokes, isEmpty);
      await expectLater(
        repo.batchPages(note, [-1], duplicate: true),
        throwsArgumentError,
      );
    },
  );

  test(
    'custom paper and covers persist, generate identical backgrounds and survive backup',
    () async {
      final temp = await sandbox();
      final root = '${temp.path}/library';
      final repo = NoteRepository(dataRoot: root);
      final original = await repo.createBlankNote(
        'Source',
        template: const PaperTemplate(pattern: PaperPattern.grid),
      );
      final library = TemplateLibrary(root);
      final paper = await library.importFile(File(original.pages.first.path));
      final cover = await library.importFile(
        File(original.pages.first.path),
        cover: true,
      );
      await library.save(
        const PaperTemplate(pattern: PaperPattern.dotted, spacing: 1.4),
        'Large dots',
      );
      expect((await TemplateLibrary(root).load()).length, 3);
      expect((await library.load()).where((p) => p.isCover).length, 1);
      var document = await repo.createBlankNote('Custom', template: paper);
      expect(
        await File(document.pages.first.path).readAsBytes(),
        await File(paper.backgroundAsset!).readAsBytes(),
      );
      document = await repo.addBlankPage(
        document,
        insertIndex: 0,
        template: cover,
      );
      expect(
        (await repo.loadPaperTemplate(document.pages.first))!.isCover,
        isTrue,
      );
      document = await repo.rotatePage(document, 0);
      expect(
        (await repo.loadPaperTemplate(document.pages.first))!.pixelSize,
        Size(cover.pixelSize.height, cover.pixelSize.width),
      );
      final notes = LibraryRepository(root: root);
      await notes.save(LibraryState(documents: [notes.fromDocument(document)]));
      await LibraryBackup.create(root, '${temp.path}/backup');
      await LibraryBackup.restore(
        '${temp.path}/backup',
        '${temp.path}/restored',
      );
      final templates = await TemplateLibrary('${temp.path}/restored').load();
      expect(templates.first.backgroundAsset, contains('/restored/'));
      expect(File(templates.first.backgroundAsset!).existsSync(), isTrue);
    },
  );

  testWidgets(
    'page management protects last page and returns selected copies',
    (tester) async {
      PageBatchChoice? result;
      final doc = NoteDocument(
        id: 'test',
        title: 'Test',
        directory: '',
        initialIndex: 0,
        pages: List.generate(
          3,
          (i) => NotePage(
            index: i,
            originalPage: i + 1,
            path: '',
            name: 'Page $i',
          ),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await showDialog<PageBatchChoice>(
                    context: context,
                    builder: (_) =>
                        PageBatchDialog(document: doc, currentIndex: 0),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('batch-page-2')));
      await tester.pump();
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      expect(result!.indexes, {0, 2});
      expect(result!.duplicate, isTrue);
    },
  );

  testWidgets('new notebook can choose cover independently of paper', (
    tester,
  ) async {
    final temp = (await tester.runAsync(sandbox))!;
    final library = TemplateLibrary(temp.path);
    await tester.runAsync(() async {
      await library.save(
        const PaperTemplate(pattern: PaperPattern.weekly),
        'Weekly paper',
      );
      await library.save(
        const PaperTemplate(pattern: PaperPattern.grid),
        'Grid cover',
        cover: true,
      );
    });
    PaperTemplateSelection? result;
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showDialog<PaperTemplateSelection>(
                  context: context,
                  builder: (_) =>
                      PaperTemplateDialog(creating: true, library: library),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    for (int attempt = 0; attempt < 20; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await tester.pump();
      if (find.textContaining('17').evaluate().isNotEmpty) break;
    }
    await tester.tap(find.byKey(const ValueKey('paper-category-mine')));
    await tester.pump();
    await tester.ensureVisible(find.text('Weekly paper'));
    await tester.tap(find.text('Weekly paper'));
    await tester.pump();
    await tester.tap(
      find
          .byWidgetPredicate(
            (w) => w is Text && (w.data == '封面' || w.data == 'Covers'),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Grid cover'));
    await tester.tap(find.text('Grid cover'));
    await tester.pump();
    for (final size in <Size>[Size(960, 600), Size(600, 960)]) {
      tester.view.physicalSize = size;
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    tester.view.viewInsets = const FakeViewPadding(bottom: 480);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    tester.view.resetViewInsets();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('paper-template-submit')));
    await tester.pumpAndSettle();
    expect(result!.template.pattern, PaperPattern.weekly);
    expect(result!.cover!.isCover, isTrue);
    expect(result!.cover!.pattern, PaperPattern.grid);
    expect(tester.takeException(), isNull);
  });
}
