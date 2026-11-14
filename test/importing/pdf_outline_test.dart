import 'dart:convert';
import 'dart:io';
import 'package:fastink_flutter/src/importing/pdf_outline_parser.dart';
import 'package:fastink_flutter/main.dart';
import 'package:fastink_flutter/src/core/app_settings.dart';
import 'package:fastink_flutter/src/models/models.dart';
import 'package:fastink_flutter/src/storage/library_repository.dart';
import 'package:fastink_flutter/src/storage/note_repository.dart';
import 'package:fastink_flutter/src/widgets/pdf_outline_tree.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;

const sampleXml = '''<?xml version="1.0"?><pdf2xml><page number="1"/>
<outline><item page="1">第一卷</item><outline><item page="1">序言 &amp; 说明</item>
<item page="2">第一章</item><outline><item page="3">第一节</item></outline></outline>
<item page="4">第二卷</item></outline></pdf2xml>''';

void main() {
  test(
    'preserves Unicode, sibling outline nesting and duplicate page targets',
    () {
      final entries = parsePdfOutlineXml(sampleXml);
      expect(entries.map((entry) => entry.title), ['第一卷', '第二卷']);
      expect(entries.first.children.first.title, '序言 & 说明');
      expect(entries.first.children.first.originalPage, 1);
      expect(entries.first.children[1].children.single.originalPage, 3);
      expect(entries.fold<int>(0, (sum, entry) => sum + entry.count), 5);
      final now = DateTime.now();
      final item = LibraryDocument(
        id: 'pdf',
        title: 'PDF',
        sourcePath: '',
        coverPath: '',
        pageCount: 4,
        importedAt: now,
        lastOpenedAt: now,
        pdfOutline: entries,
        pdfOutlineVersion: 1,
        pageTitles: {0: 'Manual title'},
      );
      final reopened = LibraryDocument.fromJson(
        jsonDecode(jsonEncode(item.toJson())) as Map<String, Object?>,
      );
      expect(
        reopened
            .copyWith(favorite: true)
            .pdfOutline
            .first
            .children[1]
            .children
            .single
            .title,
        '第一节',
      );
      expect(reopened.pageTitles, {0: 'Manual title'});
      expect(reopened.pdfOutlineVersion, 1);
      expect(parsePdfOutlineXml('<pdf2xml><page/></pdf2xml>'), isEmpty);
    },
  );

  test(
    'Poppler reads compressed Unicode bookmarks and named destinations',
    () async {
      final temp = await Directory.systemTemp.createTemp('fastink_outline_');
      try {
        final pdf = pw.Document(compress: true);
        pdf.addPage(
          pw.Page(
            build: (_) => pw.Column(
              children: [
                pw.Outline(
                  name: 'vol-1',
                  title: '第一卷',
                  child: pw.Text('Volume'),
                ),
                pw.Outline(
                  name: 'preface',
                  title: '序言',
                  level: 1,
                  child: pw.Text('Preface'),
                ),
              ],
            ),
          ),
        );
        pdf.addPage(
          pw.Page(
            build: (_) => pw.Outline(
              name: 'chapter',
              title: '第一章',
              level: 1,
              child: pw.Text('Chapter'),
            ),
          ),
        );
        final input = File('${temp.path}/source.pdf');
        await input.writeAsBytes(await pdf.save());
        final repo = NoteRepository(dataRoot: '${temp.path}/data');
        final doc = await repo.importPdf(input, onProgress: (_) {});
        final entries = await repo.readPdfOutline(doc);
        expect(entries.single.title, '第一卷');
        expect(entries.single.children.map((entry) => entry.title), [
          '序言',
          '第一章',
        ]);
        expect(entries.single.children.last.originalPage, 2);
        expect(await File(doc.pages[1].path).exists(), isFalse);
        expect(repo.originalPdfPageIndexes(doc), {1: 0, 2: 1});
        final reordered = await repo.reorderPages(doc, 0, 1);
        expect(repo.originalPdfPageIndexes(reordered), {2: 0, 1: 1});
      } finally {
        await temp.delete(recursive: true);
      }
    },
  );

  testWidgets('outline expands and follows mapped page order', (tester) async {
    int? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PdfOutlineTree(
              entries: parsePdfOutlineXml(sampleXml),
              pageIndexes: const {1: 3, 2: 0, 3: 1, 4: 2},
              currentIndex: 0,
              onSelected: (index) => selected = index,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byIcon(Icons.expand_more).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('序言 & 说明'));
    expect(selected, 3);
    await tester.tap(find.text('第一章'));
    expect(selected, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'opening an already imported PDF backfills bookmarks without replacing manual titles',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final temp = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('fastink_outline_migration_'),
      ))!;
      final repo = NoteRepository(dataRoot: '${temp.path}/data');
      final library = LibraryRepository(root: repo.dataRoot);
      final doc = (await tester.runAsync(() async {
        final pdf = pw.Document()
          ..addPage(
            pw.Page(
              build: (_) => pw.Outline(
                name: 'volume',
                title: '第一卷',
                child: pw.Text('Volume'),
              ),
            ),
          );
        final input = File('${temp.path}/old.pdf');
        await input.writeAsBytes(await pdf.save());
        final imported = await repo.importPdf(input, onProgress: (_) {});
        await library.save(
          LibraryState(
            documents: [
              library
                  .fromDocument(imported)
                  .copyWith(pageTitles: {0: 'My manual title'}),
            ],
            folders: [],
          ),
        );
        return imported;
      }))!;
      await tester.runAsync(
        () => tester.pumpWidget(
          FastInkApp(
            settings: AppSettings(
              dataRoot: repo.dataRoot,
              language: 'en',
              openSidebarByDefault: true,
              defaultSidebarTab: 1,
            ),
            initialPath: doc.pages.first.path,
          ),
        ),
      );
      for (int i = 0; i < 100; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump(const Duration(milliseconds: 50));
        if (find.text('第一卷').evaluate().isNotEmpty &&
            find.byType(CircularProgressIndicator).evaluate().isEmpty) {
          break;
        }
      }
      expect(find.text('第一卷'), findsOneWidget);
      expect(find.text('My manual title'), findsOneWidget);
      final saved = (await tester.runAsync(library.load))!.documents.single;
      expect(saved.pdfOutlineVersion, 1);
      expect(saved.pdfOutline.single.originalPage, 1);
      expect(saved.pageTitles, {0: 'My manual title'});
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 300));
      imageCache.clear();
      imageCache.clearLiveImages();
      await tester.runAsync(() async {
        for (int attempt = 0; attempt < 5; attempt++) {
          try {
            await temp.delete(recursive: true);
            break;
          } on FileSystemException {
            await Future<void>.delayed(const Duration(milliseconds: 250));
          }
        }
      });
    },
  );

  test('PDF without bookmarks returns an empty outline', () async {
    final temp = await Directory.systemTemp.createTemp('fastink_no_outline_');
    try {
      final pdf = pw.Document()
        ..addPage(pw.Page(build: (_) => pw.Text('No bookmarks')));
      final input = File('${temp.path}/source.pdf');
      await input.writeAsBytes(await pdf.save());
      await File(
        '${temp.path}/.fastink-pdf.json',
      ).writeAsString(jsonEncode({'source': input.path, 'dpi': 96}));
      final entries = await NoteRepository(dataRoot: '${temp.path}/data')
          .readPdfOutline(
            NoteDocument(
              id: 'no-outline',
              title: 'No outline',
              directory: temp.path,
              pages: const [],
              initialIndex: 0,
            ),
          );
      expect(entries, isEmpty);
    } finally {
      await temp.delete(recursive: true);
    }
  });

  final realSample = Platform.environment['FASTINK_OUTLINE_SAMPLE'];
  if (realSample != null) {
    test('user PDF keeps all 218 bookmarks and three volume roots', () async {
      final temp = await Directory.systemTemp.createTemp(
        'fastink_outline_sample_',
      );
      try {
        await File(
          '${temp.path}/.fastink-pdf.json',
        ).writeAsString(jsonEncode({'source': realSample, 'dpi': 96}));
        final entries = await NoteRepository(dataRoot: '${temp.path}/data')
            .readPdfOutline(
              NoteDocument(
                id: 'sample',
                title: 'Sample',
                directory: temp.path,
                pages: const [],
                initialIndex: 0,
              ),
            );
        expect(entries.map((entry) => entry.title), ['第一卷', '第二卷', '第三卷']);
        expect(entries.fold<int>(0, (sum, entry) => sum + entry.count), 218);
        expect(entries.first.originalPage, 1);
        expect(entries.first.children.first.originalPage, 2);
        expect(entries.every((entry) => entry.children.isNotEmpty), isTrue);
        await File('${temp.path}/outline.json').writeAsString(
          jsonEncode(entries.map((entry) => entry.toJson()).toList()),
        );
      } finally {
        await temp.delete(recursive: true);
      }
    });
  }
}
