import 'dart:io';
import 'package:fastink_flutter/main.dart';
import 'package:fastink_flutter/src/models/export_progress.dart';
import 'package:fastink_flutter/src/core/app_settings.dart';
import 'package:fastink_flutter/src/engine/ink_canvas.dart';
import 'package:fastink_flutter/src/models/models.dart';
import 'package:fastink_flutter/src/storage/note_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as raster;

void main() {
  testWidgets(
    'fullscreen keeps drawing tools and ink, restores sidebar and exits on return',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final temp = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('fastink_fullscreen_'),
      ))!;
      final repo = NoteRepository(dataRoot: '${temp.path}/data');
      final doc = (await tester.runAsync(() async {
        final image = File('${temp.path}/page.png');
        await image.writeAsBytes(
          raster.encodePng(raster.Image(width: 200, height: 280)),
        );
        final doc = await repo.importImages([image], onProgress: (_) {});
        await repo.savePageInk(
          doc,
          doc.pages.first,
          PageInk(
            strokes: [
              InkStroke(
                color: 0xff123456,
                width: .002,
                points: [
                  const InkPoint(.2, .3, .8),
                  const InkPoint(.4, .5, .7),
                ],
              ),
            ],
          ),
        );
        return doc;
      }))!;
      await tester.runAsync(
        () => tester.pumpWidget(
          FastInkApp(
            settings: AppSettings(
              dataRoot: repo.dataRoot,
              language: 'en',
              openSidebarByDefault: true,
            ),
            initialPath: doc.pages.first.path,
          ),
        ),
      );
      Future<void> drain(bool Function() ready) async {
        for (int i = 0; i < 100; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)),
          );
          await tester.pump(const Duration(milliseconds: 50));
          if (ready()) return;
        }
        fail('Window did not settle');
      }

      await drain(() => find.byType(InkLayer).evaluate().isNotEmpty);
      expect(find.byKey(const ValueKey('manage-pages')), findsOneWidget);
      final controller = tester
          .widget<InkLayer>(find.byType(InkLayer).first)
          .controller;
      final inkBefore = controller.strokes.single.toJson();
      final sidebarToggle = find.byKey(const ValueKey('page-sidebar-toggle'));
      for (final width in [1280.0, 640.0]) {
        tester.view.physicalSize = Size(width, 800);
        await tester.pumpAndSettle();
        final buttonBounds = tester.getRect(sidebarToggle);
        expect(
          find.byTooltip('Hide pages, outline and bookmarks'),
          findsOneWidget,
        );
        expect(
          find.descendant(of: sidebarToggle, matching: find.byType(Text)),
          findsOneWidget,
        );
        final tabs = find.byType(SegmentedButton<int>);
        tester.widget<SegmentedButton<int>>(tabs).onSelectionChanged!({1});
        await tester.pumpAndSettle();
        await tester.tap(sidebarToggle);
        await tester.pumpAndSettle();
        expect(find.byType(SegmentedButton<int>), findsNothing);
        expect(tester.getRect(sidebarToggle), buttonBounds);
        expect(
          find.byTooltip('Show pages, outline and bookmarks'),
          findsOneWidget,
        );
        expect(sidebarToggle.hitTestable(), findsOneWidget);
        expect(controller.strokes.single.toJson(), inkBefore);
        await tester.tap(sidebarToggle);
        await tester.pumpAndSettle();
        expect(tester.widget<SegmentedButton<int>>(tabs).selected, {1});
        expect(tester.getRect(sidebarToggle), buttonBounds);
        expect(
          find.byTooltip('Hide pages, outline and bookmarks'),
          findsOneWidget,
        );
        tester.widget<SegmentedButton<int>>(tabs).onSelectionChanged!({0});
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('manage-pages')), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      tester.view.physicalSize = const Size(1280, 800);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('enter-fullscreen')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const ValueKey('immersive-toolbar')), findsOneWidget);
      expect(find.byKey(const ValueKey('manage-pages')), findsNothing);
      expect(sidebarToggle, findsNothing);
      expect(find.byTooltip('Search this document · Ctrl+F'), findsNothing);
      expect(controller.strokes.single.toJson(), inkBefore);
      expect(tester.widget<AppBar>(find.byType(AppBar)).toolbarHeight, 64);
      final progressHost = find.byWidgetPredicate(
        (widget) => widget is ValueListenableBuilder<ExportProgress?>,
      );
      final progress =
          tester
                  .widget<ValueListenableBuilder<ExportProgress?>>(progressHost)
                  .valueListenable
              as ValueNotifier<ExportProgress?>;
      progress.value = const ExportProgress(
        'Writing PDF: 3088 pages',
        value: .72,
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey('export-progress-panel')),
        findsOneWidget,
      );
      expect(find.text('72%'), findsOneWidget);
      // Shrinking a Windows window must not overflow the compact tool strip.
      tester.view.physicalSize = const Size(640, 700);
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const ValueKey('enter-fullscreen')), findsOneWidget);
      expect(find.byKey(const ValueKey('manage-pages')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('export-progress-panel')),
        findsOneWidget,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.f11);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const ValueKey('exit-fullscreen')), findsOneWidget);
      progress.value = null;
      await tester.pump();
      expect(find.byKey(const ValueKey('export-progress-panel')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('fullscreen-back')));
      await drain(
        () =>
            find
                .byKey(const ValueKey('immersive-toolbar'))
                .evaluate()
                .isEmpty &&
            find.byType(InkLayer).evaluate().isEmpty,
      );
      expect(
        (await tester.runAsync(
          () => repo.loadPageInk(doc, doc.pages.first),
        ))!.strokes.single.toJson(),
        inkBefore,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 300));
      imageCache.clear();
      imageCache.clearLiveImages();
      await tester.runAsync(() async {
        for (int i = 0; i < 5; i++) {
          try {
            await temp.delete(recursive: true);
            break;
          } on FileSystemException {
            await Future<void>.delayed(const Duration(milliseconds: 200));
          }
        }
      });
    },
  );
}
