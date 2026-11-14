import 'package:fastink_flutter/src/core/app_localizations.dart';
import 'package:fastink_flutter/src/storage/library_repository.dart';
import 'package:fastink_flutter/src/widgets/library_document_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => AppText.locale = const Locale('zh'));
  for (final dark in [false, true]) {
    testWidgets(
      'folder picker navigates, searches and selects at narrow size, dark=$dark',
      (tester) async {
        tester.view.physicalSize = const Size(640, 480);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final now = DateTime.now();
        LibraryDocument doc(
          String id,
          String title, {
          String? folder,
          bool trash = false,
          bool md = false,
        }) => LibraryDocument(
          id: id,
          title: title,
          sourcePath: '$id.${md ? 'md' : 'pdf'}',
          coverPath: '',
          pageCount: 1,
          importedAt: now,
          lastOpenedAt: now,
          folderId: folder,
          trashed: trash,
        );
        final chosen = doc('nested', 'Nested document', folder: 'child');
        final library = LibraryState(
          folders: [
            LibraryFolder(id: 'parent', name: 'Parent folder', createdAt: now),
            LibraryFolder(
              id: 'child',
              name: 'Child folder',
              parentId: 'parent',
              createdAt: now,
            ),
            LibraryFolder(
              id: 'markdown',
              name: 'Markdown folder',
              scope: LibraryScope.markdown,
              createdAt: now,
            ),
          ],
          documents: [
            chosen,
            doc('root', 'Root document'),
            doc('trash', 'Deleted document', trash: true),
            doc('md', 'Markdown document', md: true),
          ],
        );
        LibraryDocument? result;
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? ThemeData.dark() : ThemeData.light(),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () async =>
                      result = await showDialog<LibraryDocument>(
                        context: context,
                        builder: (_) => LibraryDocumentPicker(library: library),
                      ),
                  child: const Text('Open picker'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open picker'));
        await tester.pumpAndSettle();
        expect(find.text('Parent folder'), findsOneWidget);
        expect(find.text('Root document'), findsOneWidget);
        expect(find.text('Markdown folder'), findsNothing);
        expect(find.text('Deleted document'), findsNothing);
        await tester.tap(find.byKey(const ValueKey('pick-folder-parent')));
        await tester.pumpAndSettle();
        expect(find.text('Child folder'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('pick-folder-child')));
        await tester.pumpAndSettle();
        expect(find.text('Nested document'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('document-picker-up')));
        await tester.pumpAndSettle();
        expect(find.text('Child folder'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('document-picker-root')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('document-picker-search')),
          'Nested',
        );
        await tester.pumpAndSettle();
        expect(find.text('文稿 / Parent folder / Child folder'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('pick-document-nested')));
        await tester.pumpAndSettle();
        expect(result, same(chosen));
        expect(tester.takeException(), isNull);
      },
    );
  }
}
