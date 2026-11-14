import 'dart:convert';
import 'dart:io';
import 'package:fastink_flutter/src/models/models.dart';
import 'package:fastink_flutter/src/storage/library_repository.dart';
import 'package:fastink_flutter/src/storage/note_repository.dart';
import 'package:fastink_flutter/src/widgets/page_batch_dialog.dart';
import 'package:fastink_flutter/src/export/export_repository.dart';
import 'package:fastink_flutter/main.dart';
import 'package:fastink_flutter/src/core/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as raster;
import 'package:pdf/widgets.dart' as pw;

void main() {
  late Directory temp;
  late NoteRepository repo;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('fastink_page_copy_');
    repo = NoteRepository(dataRoot: '${temp.path}/library');
  });
  tearDown(() async {
    for (int attempt = 0; attempt < 5; attempt++) {
      try {
        if (await temp.exists()) await temp.delete(recursive: true);
        return;
      } on FileSystemException catch (error) {
        // Windows image decoders can retain files briefly after disposal.
        if (error.osError?.errorCode != 32) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
    }
  });

  Future<NoteDocument> note(String name, int count) async {
    final dir = await Directory('${temp.path}/$name').create();
    final files = <File>[];
    for (int i = 0; i < count; i++) {
      final file = File('${dir.path}/$name-$i.png');
      await file.writeAsBytes(
        raster.encodePng(raster.Image(width: 40 + i, height: 60)),
      );
      files.add(file);
    }
    final document = await repo.importImages(files, onProgress: (_) {});
    await repo.saveDocumentManifest(document);
    return document;
  }

  test(
    'copies in source order with independent ink, images and custom paper',
    () async {
      final source = await note('Source', 3);
      final target = await note('Target', 2);
      final oldManifest = await File(
        '${repo.dataRoot}/documents/${source.id}/manifest.json',
      ).readAsString();
      final asset = await repo.importEmbeddedImage(
        source,
        File(source.pages[0].path),
      );
      final strokes = [
        InkStroke(
          color: 0xff123456,
          width: .002,
          penStyle: PenStyle.brush,
          text: 'Chapter',
          textWeight: 700,
          textItalic: true,
          textUnderline: true,
          textAlign: TextAlign.center,
          textBoxWidth: .4,
          points: [const InkPoint(.1, .2, .8), const InkPoint(.3, .4, .5)],
        ),
        InkStroke(
          color: 0xff000000,
          width: 0,
          kind: StrokeKind.image,
          imageAsset: asset,
          points: [const InkPoint(.2, .3, 1), const InkPoint(.7, .8, 1)],
        ),
      ];
      for (final index in [0, 2]) {
        await repo.savePageInk(
          source,
          source.pages[index],
          PageInk(strokes: strokes),
        );
      }
      final paper = PaperTemplate(
        backgroundAsset: source.pages[0].path,
        customName: 'My cover',
        customWidth: 40,
        customHeight: 60,
        isCover: true,
      );
      await File(
        '${source.pages[0].path}.paper.json',
      ).writeAsString(jsonEncode(paper.toJson()));
      final targetInk = PageInk(
        strokes: [strokes.first.copy(color: 0xffabcdef)],
      );
      await repo.savePageInk(target, target.pages.first, targetInk);

      final updated = await repo.copyPagesToDocument(source, target, [2, 0, 2]);
      expect(updated.pages.map((p) => p.name), [
        ...target.pages.map((p) => p.name),
        source.pages[0].name,
        source.pages[2].name,
      ]);
      expect(updated.pages.map((p) => p.index), [0, 1, 2, 3]);
      expect(updated.pages.map((p) => p.originalPage).toSet(), hasLength(4));
      final firstInk = await repo.loadPageInk(updated, updated.pages[2]);
      final secondInk = await repo.loadPageInk(updated, updated.pages[3]);
      expect(firstInk.strokes.first.toJson(), strokes.first.toJson());
      expect(
        firstInk.strokes.last.imageAsset,
        secondInk.strokes.last.imageAsset,
      );
      final copiedAsset = repo.resolveEmbeddedImagePath(
        updated,
        firstInk.strokes.last.imageAsset!,
      );
      expect(copiedAsset, contains(target.id));
      expect(
        await File(copiedAsset).readAsBytes(),
        await File(repo.resolveEmbeddedImagePath(source, asset)).readAsBytes(),
      );
      final copiedPaper = (await repo.loadPaperTemplate(updated.pages[2]))!;
      expect(copiedPaper.backgroundAsset, updated.pages[2].path);
      expect(copiedPaper.label, 'My cover');
      expect(copiedPaper.isCover, isTrue);
      expect(
        (await repo.loadPageInk(
          updated,
          updated.pages.first,
        )).strokes.first.color,
        0xffabcdef,
      );
      expect(
        await File(
          '${repo.dataRoot}/documents/${source.id}/manifest.json',
        ).readAsString(),
        oldManifest,
      );
      expect(target.pages, hasLength(2));
      await repo.deleteDocumentStorage(source.id, source.pages.first.path);
      expect(await File(copiedAsset).exists(), isTrue);
      expect(await File(copiedPaper.backgroundAsset!).exists(), isTrue);
      final reopened = await repo.indexFromSelectedPath(
        updated.pages.first.path,
        documentId: updated.id,
      );
      expect(reopened.pages, hasLength(4));
      expect(
        (await repo.loadPageInk(reopened, reopened.pages[2])).strokes,
        hasLength(2),
      );
    },
  );

  test(
    'a missing embedded image rolls back copied pages and leaves the target intact',
    () async {
      final source = await note('Broken', 2);
      final target = await note('Target', 1);
      await repo.savePageInk(
        source,
        source.pages[1],
        PageInk(
          strokes: [
            InkStroke(
              color: 0,
              width: 0,
              kind: StrokeKind.image,
              imageAsset: 'assets/missing.png',
              points: [],
            ),
          ],
        ),
      );
      final manifest = File(
        '${repo.dataRoot}/documents/${target.id}/manifest.json',
      );
      final before = await manifest.readAsString();
      await expectLater(
        repo.copyPagesToDocument(source, target, [0, 1]),
        throwsA(isA<FileSystemException>()),
      );
      expect(await manifest.readAsString(), before);
      final dir = Directory('${repo.dataRoot}/documents/${target.id}');
      final leftovers = await dir
          .list(recursive: true)
          .where(
            (entry) =>
                entry is File &&
                entry.absolute.path.replaceAll('\\', '/') !=
                    manifest.absolute.path.replaceAll('\\', '/'),
          )
          .toList();
      expect(leftovers, isEmpty);
    },
  );

  test('empty source ink never revives a removed target page ink id', () async {
    final source = await note('Empty', 1);
    final target = await note('Target', 1);
    final retainedPage = NotePage(
      index: 1,
      originalPage: target.pages.first.originalPage + 1,
      path: '',
      name: 'Removed',
    );
    await repo.savePageInk(
      target,
      retainedPage,
      PageInk(strokes: [InkStroke(color: 42, width: .01, points: [])]),
    );
    final updated = await repo.copyPagesToDocument(source, target, [0]);
    expect(
      updated.pages.last.originalPage,
      greaterThan(retainedPage.originalPage),
    );
    expect(
      (await repo.loadPageInk(updated, updated.pages.last)).strokes,
      isEmpty,
    );
    expect(
      (await repo.loadPageInk(target, retainedPage)).strokes.single.color,
      42,
    );
    for (final indexes in [
      <int>[],
      [-1],
      [1],
    ]) {
      await expectLater(
        repo.copyPagesToDocument(source, target, indexes),
        throwsArgumentError,
      );
    }
    await expectLater(
      repo.copyPagesToDocument(source, source, [0]),
      throwsArgumentError,
    );
  });

  test(
    'copies an unrendered PDF page into an independent bitmap page',
    () async {
      final pdf = pw.Document();
      pdf.addPage(pw.Page(build: (_) => pw.Text('First')));
      pdf.addPage(pw.Page(build: (_) => pw.Text('Second')));
      final input = File('${temp.path}/source.pdf');
      await input.writeAsBytes(await pdf.save());
      final source = await repo.importPdf(input, onProgress: (_) {});
      expect(await File(source.pages[1].path).exists(), isFalse);
      final target = await note('Target', 1);
      final updated = await repo.copyPagesToDocument(source, target, [1]);
      expect(
        raster.decodeImage(await File(updated.pages.last.path).readAsBytes()),
        isNotNull,
      );
      await repo.deleteDocumentStorage(source.id, source.pages.first.path);
      expect(
        await (await repo.ensurePageImage(
          updated,
          updated.pages.last,
        )).exists(),
        isTrue,
      );
    },
  );

  test(
    'PDF targets retain copied backgrounds through cache eviction and export all pages',
    () async {
      repo.maximumCachedPdfPages = 40;
      final pdf = pw.Document()
        ..addPage(pw.Page(build: (_) => pw.Text('Original')));
      final input = File('${temp.path}/target.pdf');
      await input.writeAsBytes(await pdf.save());
      final target = await repo.importPdf(input, onProgress: (_) {});
      expect(await repo.canExportOriginalPdf(target), isTrue);
      final source = await note('Extra', 41);
      final updated = await repo.copyPagesToDocument(
        source,
        target,
        List.generate(41, (i) => i),
      );
      expect(await repo.canExportOriginalPdf(updated), isFalse);
      for (final page in updated.pages) {
        await repo.ensurePageImage(updated, page);
      }
      repo.updatePdfCacheWindow(updated, [0]);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      for (final page in updated.pages.skip(1)) {
        expect(
          await File(page.path).exists(),
          isTrue,
          reason: 'Copied backgrounds are permanent',
        );
        expect(repo.isOriginalPdfPage(updated, page), isFalse);
      }
      final output = File('${temp.path}/export.pdf');
      await ExportRepository(repo).exportPdf(updated, output);
      final exported = await repo.importPdf(output, onProgress: (_) {});
      expect(exported.pages, hasLength(42));
    },
  );

  testWidgets(
    'batch dialog passes the chosen pages to cross-document copying',
    (tester) async {
      const doc = NoteDocument(
        id: 'source',
        title: 'Source',
        directory: '',
        pages: [
          NotePage(index: 0, originalPage: 1, path: '', name: 'One'),
          NotePage(index: 1, originalPage: 2, path: '', name: 'Two'),
        ],
        initialIndex: 0,
      );
      PageBatchChoice? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async =>
                    result = await showDialog<PageBatchChoice>(
                      context: context,
                      builder: (_) =>
                          const PageBatchDialog(document: doc, currentIndex: 0),
                    ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('batch-page-1')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('copy-pages-to-document')));
      await tester.pumpAndSettle();
      expect(result!.indexes, {0, 1});
      expect(result!.toOtherDocument, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'complete app workflow opens appended page and persists bookmarks and outline',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final documents = (await tester.runAsync(
        () async => [await note('Source', 2), await note('Target', 1)],
      ))!;
      final source = documents[0], target = documents[1];
      final library = LibraryRepository(root: repo.dataRoot);
      await tester.runAsync(
        () => library.save(
          LibraryState(
            documents: [
              library
                  .fromDocument(source)
                  .copyWith(
                    title: 'Source',
                    bookmarkedPages: [0],
                    pageTitles: {0: 'Chapter'},
                  ),
              library
                  .fromDocument(target)
                  .copyWith(
                    title: 'Target',
                    bookmarkedPages: [0],
                    pageTitles: {0: 'Existing'},
                  ),
            ],
            folders: [],
          ),
        ),
      );
      await tester.runAsync(
        () => tester.pumpWidget(
          FastInkApp(
            settings: AppSettings(
              dataRoot: repo.dataRoot,
              language: 'en',
              openSidebarByDefault: true,
            ),
            initialPath: source.pages.first.path,
          ),
        ),
      );
      Future<void> drainUntil(bool Function() condition) async {
        for (int i = 0; i < 80; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)),
          );
          await tester.pump(const Duration(milliseconds: 50));
          if (condition()) return;
        }
        fail(
          'App workflow did not finish: ${tester.widgetList<Text>(find.byType(Text)).map((w) => w.data).join(' | ')}',
        );
      }

      await drainUntil(
        () =>
            find.byKey(const ValueKey('manage-pages')).evaluate().isNotEmpty &&
            find.byType(CircularProgressIndicator).evaluate().isEmpty,
      );
      await tester.runAsync(
        () => tester.tap(find.byKey(const ValueKey('manage-pages'))),
      );
      await drainUntil(
        () => find.byType(PageBatchDialog).evaluate().isNotEmpty,
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const ValueKey('copy-pages-to-document')));
      await drainUntil(
        () => find.byType(PageCopyTargetDialog).evaluate().isNotEmpty,
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.byKey(ValueKey('page-copy-target-${source.id}')),
        findsNothing,
      );
      await tester.tap(find.byKey(ValueKey('page-copy-target-${target.id}')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('page-copy-confirm')));
      await drainUntil(
        () =>
            find
                .textContaining('Copied 1 pages to Target')
                .evaluate()
                .isNotEmpty &&
            find.byType(CircularProgressIndicator).evaluate().isEmpty,
      );
      final saved = (await tester.runAsync(library.load))!;
      final savedTarget = saved.documents.firstWhere(
        (item) => item.id == target.id,
      );
      expect(savedTarget.pageCount, 2);
      expect(savedTarget.bookmarkedPages, [0, 1]);
      expect(savedTarget.pageTitles, {0: 'Existing', 1: 'Chapter'});
      expect(savedTarget.lastPageIndex, 1);
      expect(
        saved.documents.firstWhere((item) => item.id == source.id).pageCount,
        2,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 300));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 250)),
      );
      imageCache.clear();
      imageCache.clearLiveImages();
    },
  );

  testWidgets(
    'target chooser searches, requires a choice and returns the selected document',
    (tester) async {
      final now = DateTime(2026);
      LibraryDocument item(String id) => LibraryDocument(
        id: id,
        title: id,
        sourcePath: '',
        coverPath: '',
        pageCount: 2,
        importedAt: now,
        lastOpenedAt: now,
      );
      LibraryDocument? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async =>
                    result = await showDialog<LibraryDocument>(
                      context: context,
                      builder: (_) => PageCopyTargetDialog(
                        documents: [item('Math'), item('Work')],
                        pageCount: 2,
                      ),
                    ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('page-copy-confirm')),
            )
            .onPressed,
        isNull,
      );
      await tester.enterText(
        find.byKey(const ValueKey('page-copy-target-search')),
        'work',
      );
      await tester.pump();
      expect(find.text('Math'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('page-copy-target-Work')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('page-copy-confirm')));
      await tester.pumpAndSettle();
      expect(result!.id, 'Work');
      expect(tester.takeException(), isNull);
    },
  );
}
