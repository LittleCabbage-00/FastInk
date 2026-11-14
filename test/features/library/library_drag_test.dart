import 'dart:io';
import 'dart:ui' as ui;
import 'package:fastink_flutter/main.dart';
import 'package:fastink_flutter/src/features/markdown/markdown_editor.dart';
import 'package:fastink_flutter/src/core/app_settings.dart';
import 'package:fastink_flutter/src/storage/library_repository.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as raster;

void main() {
  for (final kind in [
    PointerDeviceKind.mouse,
    PointerDeviceKind.stylus,
    PointerDeviceKind.touch,
  ]) {
    testWidgets(
      '${kind.name}: drag in, out, between nested folders; separate Markdown space',
      (tester) async {
        tester.view.physicalSize = const Size(1400, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final temp = (await tester.runAsync(
          () => Directory.systemTemp.createTemp('fastink-drag-'),
        ))!;
        final repo = LibraryRepository(root: temp.path);
        final now = DateTime.utc(2026);
        final image = File('${temp.path}/cover.png');
        final md = File('${temp.path}/memo.md');
        LibraryDocument doc(String id, String path) => LibraryDocument(
          id: id,
          title: id,
          sourcePath: path,
          coverPath: image.path,
          pageCount: 1,
          importedAt: now,
          lastOpenedAt: now,
        );
        await tester.runAsync(() async {
          for (final family in [
            'Segoe UI Variable',
            'Segoe UI',
            'Microsoft YaHei UI',
          ]) {
            if (!File(r'C:\Windows\Fonts\segoeui.ttf').existsSync()) continue;
            final font = FontLoader(family)
              ..addFont(
                Future.value(
                  ByteData.sublistView(
                    await File(r'C:\Windows\Fonts\segoeui.ttf').readAsBytes(),
                  ),
                ),
              );
            await font.load();
          }
          final icons = File(
            '${Directory.current.path}/build/windows-script/flutter_assets/fonts/MaterialIcons-Regular.otf',
          );
          if (await icons.exists()) {
            await (FontLoader('MaterialIcons')..addFont(
                  Future.value(ByteData.sublistView(await icons.readAsBytes())),
                ))
                .load();
          }
          await image.writeAsBytes(
            raster.encodePng(raster.Image(width: 80, height: 100)),
          );
          await md.writeAsString('# Memo');
          await repo.save(
            LibraryState(
              documents: [doc('note', image.path), doc('md', md.path)],
              folders: [
                LibraryFolder(id: 'a', name: 'Notes A', createdAt: now),
                LibraryFolder(
                  id: 'b',
                  name: 'Nested B',
                  createdAt: now,
                  parentId: 'a',
                ),
                LibraryFolder(
                  id: 'm',
                  name: 'Markdown Only',
                  createdAt: now,
                  scope: LibraryScope.markdown,
                ),
              ],
            ),
          );
          await tester.pumpWidget(
            RepaintBoundary(
              key: const ValueKey('library-preview'),
              child: FastInkApp(
                settings: AppSettings(dataRoot: temp.path, language: 'en'),
              ),
            ),
          );
        });
        Future<void> settleIO() async {
          for (var i = 0; i < 8; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 25)),
            );
            await tester.pump(const Duration(milliseconds: 40));
          }
        }

        await settleIO();
        Finder key(String value) => find.byKey(ValueKey(value));
        Future<void> drag(String from, Finder target) async {
          final start = tester.getCenter(key('document-$from'));
          final end = tester.getCenter(target);
          final isRootTarget =
              tester.widget(target).key == const ValueKey('library-root-drop');
          final gesture = await tester.startGesture(start, kind: kind);
          if (kind == PointerDeviceKind.touch) {
            await tester.pump(const Duration(milliseconds: 400));
          }
          for (var step = 1; step <= 10; step++) {
            await gesture.moveTo(Offset.lerp(start, end, step / 10)!);
            await tester.pump(const Duration(milliseconds: 20));
            if (isRootTarget && step == 10) {
              final hints = find.ancestor(
                of: key('library-root-drop'),
                matching: find.byType(AnimatedOpacity),
              );
              expect(tester.widget<AnimatedOpacity>(hints.first).opacity, 1);
            }
          }
          await gesture.up();
          await settleIO();
          if (isRootTarget) {
            final hints = find.ancestor(
              of: key('library-root-drop'),
              matching: find.byType(AnimatedOpacity),
            );
            expect(tester.widget<AnimatedOpacity>(hints.first).opacity, 0);
          }
          expect(tester.takeException(), isNull);
        }

        Future<String?> location(String id) async => (await tester.runAsync(
          repo.load,
        ))!.documents.firstWhere((d) => d.id == id).folderId;

        expect(key('folder-m'), findsNothing);
        await drag('note', key('folder-drop-a'));
        expect(await location('note'), 'a');
        expect(key('document-note'), findsNothing);
        await tester.tap(key('folder-a'));
        await tester.pumpAndSettle();
        expect(key('library-folder-panel'), findsOneWidget);
        expect(
          tester.getSize(key('library-folder-panel')).width,
          lessThan(700),
        );
        expect(key('folder-a'), findsOneWidget); // root remains accessible
        if (kind == PointerDeviceKind.mouse &&
            Platform.environment['FASTINK_LIBRARY_PREVIEW'] == '1') {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            key('library-preview'),
          );
          await tester.runAsync(() async {
            final preview = await boundary.toImage();
            try {
              final bytes = await preview.toByteData(
                format: ui.ImageByteFormat.png,
              );
              await File(
                'build/diagnostics/library-folder-preview.png',
              ).writeAsBytes(bytes!.buffer.asUint8List());
            } finally {
              preview.dispose();
            }
          });
        }
        await drag('note', key('folder-drop-b'));
        expect(await location('note'), 'b');
        await tester.tap(key('folder-b'));
        await tester.pumpAndSettle();
        await drag('note', key('library-parent-drop'));
        expect(await location('note'), 'a');
        await tester.tap(find.byTooltip('Go up one level'));
        await tester.pumpAndSettle();
        await drag('note', key('library-root-drop'));
        expect(await location('note'), isNull);
        await tester.tap(key('close-library-folder'));
        await tester.pumpAndSettle();
        await tester.tap(key('library-nav-markdown'));
        await tester.pumpAndSettle();
        expect(key('folder-a'), findsNothing);
        expect(key('folder-m'), findsOneWidget);
        await drag('md', key('folder-drop-m'));
        expect(await location('md'), 'm');
        expect(
          key('document-md'),
          findsNothing,
        ); // must not reappear via filesystem scan
        await tester.tap(key('folder-m'));
        await tester.pumpAndSettle();
        if (kind == PointerDeviceKind.mouse) {
          await tester.tap(key('document-md'));
          await settleIO();
          final editor = tester.widget<MarkdownEditorView>(
            find.byType(MarkdownEditorView),
          );
          editor.onFileSaved!(md.path);
          editor.onExit();
          await settleIO();
          final state = (await tester.runAsync(repo.load))!;
          expect(
            state.documents.where((d) => d.sourcePath == md.path).length,
            1,
          );
          expect(await location('md'), 'm');
        }
        await drag('md', key('library-root-drop'));
        expect(await location('md'), isNull);
        await tester.tap(key('close-library-folder'));
        await tester.pumpAndSettle();
        if (kind == PointerDeviceKind.mouse) {
          Future<void> createFolder(String section) async {
            await tester.tap(key('library-nav-$section'));
            await tester.pumpAndSettle();
            await tester.tap(key('library-new-menu-root'));
            await tester.pumpAndSettle();
            await tester.tap(find.text('New folder'));
            await tester.pumpAndSettle();
            await tester.enterText(key('library-folder-name'), 'Independent');
            await tester.tap(key('library-create-folder'));
            await settleIO();
          }

          await createFolder('markdown');
          await createFolder('documents');
          final state = (await tester.runAsync(repo.load))!;
          final independent = state.folders.where(
            (f) => f.name == 'Independent',
          );
          expect(independent.length, 2);
          expect(independent.map((f) => f.scope).toSet(), {
            LibraryScope.notes,
            LibraryScope.markdown,
          });
          expect(independent.every((f) => f.parentId == null), isTrue);
          final mdFolder = independent.firstWhere(
            (f) => f.scope == LibraryScope.markdown,
          );
          expect(key('folder-${mdFolder.id}'), findsNothing);
        }
        await tester.runAsync(() => tester.pumpWidget(const SizedBox.shrink()));
        await settleIO();
        imageCache.clear();
        imageCache.clearLiveImages();
        await tester.runAsync(() => temp.delete(recursive: true));
      },
    );
  }
}
