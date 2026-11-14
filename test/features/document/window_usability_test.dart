import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:fastink_flutter/main.dart';
import 'package:fastink_flutter/src/core/app_localizations.dart';
import 'package:fastink_flutter/src/core/app_settings.dart';
import 'package:fastink_flutter/src/engine/ink_canvas.dart';
import 'package:fastink_flutter/src/models/models.dart';
import 'package:fastink_flutter/src/storage/library_repository.dart';
import 'package:fastink_flutter/src/storage/note_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as raster;

Finder key(String value) => find.byKey(ValueKey(value));

Future<void> drainIO(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> waitForInk(WidgetTester tester) async {
  for (var i = 0; i < 100; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 50));
    if (find.byType(InkLayer).evaluate().isNotEmpty &&
        key('library-header').evaluate().isEmpty) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 200));
      return;
    }
  }
  fail(
    'Editor did not load: ${tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).join(" | ")}',
  );
}

Future<void> preview(WidgetTester tester, String name) async {
  if (Platform.environment['FASTINK_UI_PREVIEW'] != '1') return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    key('usability-preview'),
  );
  final shadows = debugDisableShadows;
  void repaint(RenderObject object) {
    object.markNeedsPaint();
    object.visitChildren(repaint);
  }

  debugDisableShadows = false;
  try {
    repaint(boundary);
    await tester.pump();
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      try {
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(
          'build/diagnostics/ui-$name.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
      } finally {
        image.dispose();
      }
    });
  } finally {
    debugDisableShadows = shadows;
    repaint(boundary);
    await tester.pump();
  }
}

void main() {
  setUpAll(() async {
    final font = File(r'C:\Windows\Fonts\segoeui.ttf');
    if (await font.exists()) {
      final bytes = ByteData.sublistView(await font.readAsBytes());
      for (final family in [
        'Segoe UI Variable',
        'Segoe UI',
        'Microsoft YaHei UI',
        'Roboto',
      ]) {
        await (FontLoader(family)..addFont(Future.value(bytes))).load();
      }
    }
    final icons = File(
      'D:/ComputerProgram/path/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
    if (await icons.exists()) {
      await (FontLoader('MaterialIcons')..addFont(
            Future.value(ByteData.sublistView(await icons.readAsBytes())),
          ))
          .load();
    }
  });

  testWidgets('failed page save preserves current ink and allows a retry', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final temp = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('fastink-save-retry-'),
    ))!;
    final repository = NoteRepository(dataRoot: '${temp.path}/data');
    final note = (await tester.runAsync(() async {
      final created = await repository.createBlankNote('Save retry');
      return repository.addBlankPage(created, insertIndex: 1);
    }))!;
    await tester.runAsync(
      () => tester.pumpWidget(
        FastInkApp(
          settings: AppSettings(
            dataRoot: repository.dataRoot,
            language: 'en',
            autoSaveEnabled: false,
            openSidebarByDefault: false,
            defaultPageFit: 'page',
          ),
          initialPath: note.pages.first.path,
        ),
      ),
    );
    await waitForInk(tester);
    final controller = tester
        .widget<InkLayer>(find.byType(InkLayer).first)
        .controller;
    controller.pasteStrokes([
      InkStroke(
        color: 0xff202124,
        width: .01,
        points: [const InkPoint(.2, .4, .7), const InkPoint(.5, .5, .7)],
      ),
    ]);
    final expected = controller.strokes.single.toJson();
    await tester.pump();
    // 暂时将笔迹目录替换为同名文件，模拟磁盘写入失败。
    final pages = Directory(
      '${repository.dataRoot}/documents/${note.id}/pages',
    );
    final backup = '${pages.path}.test-backup';
    final blocker = File(pages.path);
    await tester.runAsync(() async {
      await pages.rename(backup);
      await blocker.writeAsString('blocked');
    });
    final pageInput = key('page-number-input');
    tester.widget<TextField>(pageInput).onSubmitted!('2');
    await drainIO(tester);
    expect(controller.strokes.single.toJson(), expected);
    expect(controller.canUndo, isTrue);
    expect(tester.widget<TextField>(pageInput).controller!.text, '1');
    await tester.runAsync(() async {
      await blocker.delete();
      await Directory(backup).rename(pages.path);
    });
    tester.widget<TextField>(pageInput).onSubmitted!('2');
    await drainIO(tester);
    await waitForInk(tester);
    expect(tester.widget<TextField>(pageInput).controller!.text, '2');
    expect(controller.strokes, isEmpty);
    final stored = (await tester.runAsync(
      () => repository.loadPageInk(note, note.pages.first),
    ))!;
    expect(stored.strokes.single.toJson(), expected);
    await tester.pumpWidget(const SizedBox.shrink());
    await drainIO(tester);
    imageCache.clear();
    imageCache.clearLiveImages();
    await tester.runAsync(() => temp.delete(recursive: true));
  });

  testWidgets('changing template paper refreshes both views and existing ink', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final temp = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('fastink-paper-switch-'),
    ))!;
    final repository = NoteRepository(dataRoot: '${temp.path}/data');
    final note = (await tester.runAsync(
      () => repository.createBlankNote(
        'Paper contrast',
        template: const PaperTemplate(pattern: PaperPattern.blank),
      ),
    ))!;
    final root = key('paper-pixel-preview');
    await tester.runAsync(
      () => tester.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('paper-pixel-preview'),
          child: FastInkApp(
            settings: AppSettings(
              dataRoot: repository.dataRoot,
              language: 'en',
              themeMode: ThemeMode.dark,
              defaultPageFit: 'page',
              openSidebarByDefault: true,
              autoSaveEnabled: false,
            ),
            initialPath: note.pages.single.path,
          ),
        ),
      ),
    );
    await waitForInk(tester);
    final ink = tester.widget<InkLayer>(find.byType(InkLayer).first).controller;
    ink.pasteStrokes([
      InkStroke(
        color: 0xff202124,
        width: .018,
        points: [const InkPoint(.28, .30, .72), const InkPoint(.72, .30, .72)],
      ),
      InkStroke(
        color: 0xff123456,
        width: .018,
        points: [const InkPoint(.28, .52, .72), const InkPoint(.72, .52, .72)],
      ),
    ]);
    ink.clearSelection();
    await drainIO(tester);
    final savedInk = ink.strokes.map((stroke) => stroke.toJson()).toList();

    /// 取主画布和缩略图上对应的背景、黑白墨和深蓝墨像素。
    Future<List<Color>> sample() async {
      final canvas = tester.renderObject<RenderBox>(
        find.byType(InkLayer).first,
      );
      final thumbFinder = find.byType(InkPreview).first;
      final previewWidget = tester.widget<InkPreview>(thumbFinder);
      final thumb = tester.getRect(thumbFinder);
      final fitted = Alignment.center.inscribe(
        applyBoxFit(
          BoxFit.contain,
          previewWidget.sourceSize!,
          thumb.size,
        ).destination,
        thumb,
      );
      final locations = [
        for (final y in [
          .2,
          ink.strokes[0].points.first.y,
          ink.strokes[1].points.first.y,
        ])
          canvas.localToGlobal(
            Offset(canvas.size.width * .5, canvas.size.height * y),
          ),
        for (final y in [
          .2,
          ink.strokes[0].points.first.y,
          ink.strokes[1].points.first.y,
        ])
          fitted.topLeft + Offset(fitted.width * .5, fitted.height * y),
      ];
      final boundary = tester.renderObject<RenderRepaintBoundary>(root);
      return (await tester.runAsync(() async {
        final screenshot = await boundary.toImage();
        try {
          final rgba = (await screenshot.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!;
          return locations.map((point) {
            final index =
                (point.dy.round() * screenshot.width + point.dx.round()) * 4;
            return Color.fromARGB(
              255,
              rgba.getUint8(index),
              rgba.getUint8(index + 1),
              rgba.getUint8(index + 2),
            );
          }).toList();
        } finally {
          screenshot.dispose();
        }
      }))!;
    }

    Future<void> changePaper(int index, bool dark) async {
      await tester.tap(find.byTooltip(AppText.get('更多')));
      await tester.pumpAndSettle();
      final action = find.byWidgetPredicate(
        (w) => w is PopupMenuItem<String> && w.value == 'paper',
      );
      await tester.ensureVisible(action);
      await tester.runAsync(() => tester.tap(action));
      for (
        var i = 0;
        i < 30 && key('paper-color-$index').evaluate().isEmpty;
        i++
      ) {
        await drainIO(tester);
      }
      await tester.ensureVisible(key('paper-color-$index'));
      await tester.tap(key('paper-color-$index'));
      await tester.runAsync(() => tester.tap(key('paper-template-submit')));
      for (var i = 0; i < 20; i++) {
        await drainIO(tester);
        final layer = tester.widget<InkLayer>(find.byType(InkLayer).first);
        if (layer.paperDark == dark) {
          final colors = await sample();
          if ((colors.first.computeLuminance() < .1) == dark &&
              (colors[3].computeLuminance() < .1) == dark) {
            return;
          }
        }
      }
      fail('Paper and sidebar failed to switch to dark=$dark');
    }

    final initial = await sample();
    expect(initial[0].computeLuminance(), greaterThan(.85));
    expect(initial[1].computeLuminance(), lessThan(.1));
    await changePaper(4, true);
    final dark = await sample();
    for (final offset in [0, 3]) {
      expect(dark[offset].computeLuminance(), lessThan(.1));
      expect(dark[offset + 1].computeLuminance(), greaterThan(.8));
      expect(dark[offset + 2].toARGB32(), 0xff123456);
    }
    expect(ink.strokes.map((stroke) => stroke.toJson()).toList(), savedInk);
    expect(ink.canUndo, isTrue);
    await changePaper(0, false);
    final restored = await sample();
    expect(restored[0].computeLuminance(), greaterThan(.85));
    expect(restored[1].computeLuminance(), lessThan(.1));
    expect(restored[4].computeLuminance(), lessThan(.1));
    await tester.pumpWidget(const SizedBox.shrink());
    await drainIO(tester);
    imageCache.clear();
    imageCache.clearLiveImages();
    await tester.runAsync(() => temp.delete(recursive: true));
  });

  testWidgets(
    'library scales without overflow, closes drawer and searches inside folders',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      final temp = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('fastink-usability-library-'),
      ))!;
      final now = DateTime.utc(2026);
      final cover = File('${temp.path}/preview.png');
      await tester.runAsync(() async {
        final page = raster.Image(width: 180, height: 250);
        raster.fill(page, color: raster.ColorRgb8(255, 255, 255));
        for (var y = 35; y < 225; y += 15) {
          raster.drawLine(
            page,
            x1: 20,
            y1: y,
            x2: 160,
            y2: y,
            color: raster.ColorRgb8(185, 197, 220),
          );
        }
        await cover.writeAsBytes(raster.encodePng(page));
        LibraryDocument doc(String id, String title, {String? folder}) =>
            LibraryDocument(
              id: id,
              title: title,
              sourcePath: cover.path,
              coverPath: cover.path,
              pageCount: 8,
              importedAt: now,
              lastOpenedAt: now,
              folderId: folder,
            );
        await LibraryRepository(root: temp.path).save(
          LibraryState(
            folders: [
              LibraryFolder(
                id: 'work',
                name: 'Work and reference materials with a long folder name',
                createdAt: now,
              ),
            ],
            documents: [
              doc('root', 'A notebook with a long descriptive title'),
              doc('nested', 'Hidden research notebook', folder: 'work'),
            ],
          ),
        );
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('usability-preview'),
            child: FastInkApp(
              settings: AppSettings(dataRoot: temp.path, language: 'en'),
            ),
          ),
        );
      });
      await drainIO(tester);
      await tester.tap(key('document-menu-root'));
      await tester.pumpAndSettle();
      for (final item in tester.widgetList<PopupMenuItem<String>>(
        find.byType(PopupMenuItem<String>),
      )) {
        expect(item.height, 44);
        expect(
          find.descendant(of: find.byWidget(item), matching: find.byType(Icon)),
          findsOneWidget,
        );
      }
      expect(find.text('Export'), findsOneWidget);
      await preview(tester, 'library-document-menu');
      await tester.tap(find.text('Export'));
      await drainIO(tester);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        tester.widget<Text>(key('export-document-title')).data,
        'A notebook with a long descriptive title',
      );
      expect(find.text('PDF'), findsOneWidget);
      expect(find.text('PNG'), findsOneWidget);
      expect(find.text('JPG'), findsOneWidget);
      expect(key('export-current-page'), findsNothing);
      expect(find.byType(RadioGroup<bool>), findsNothing);
      expect(key('export-library-scope'), findsOneWidget);
      await tester.tap(find.text('PNG'));
      await tester.pumpAndSettle();
      expect(find.text('1 numbered images saved to a folder'), findsOneWidget);
      expect(key('export-current-page'), findsNothing);
      expect(find.byType(InkLayer), findsNothing);
      await tester.tap(find.text(AppText.get('取消')));
      await tester.pumpAndSettle();
      expect(key('document-root'), findsOneWidget);
      await tester.tap(key('folder-menu-work'));
      await tester.pumpAndSettle();
      for (final item in tester.widgetList<PopupMenuItem<String>>(
        find.byType(PopupMenuItem<String>),
      )) {
        expect(item.height, 44);
        expect(
          find.descendant(of: find.byWidget(item), matching: find.byType(Icon)),
          findsOneWidget,
        );
      }
      await tester.tapAt(const Offset(1200, 750));
      await tester.pumpAndSettle();
      for (final (size, scale) in [
        (const Size(1600, 900), 1.0),
        (const Size(1280, 800), 1.3),
        (const Size(800, 600), 1.0),
        (const Size(640, 480), 1.3),
      ]) {
        tester.view.physicalSize = size;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        await tester.pumpAndSettle();
        expect(
          tester.getSize(key('library-header')).height,
          lessThanOrEqualTo(120),
        );
        final card = tester.getSize(key('document-root'));
        expect(card.width, greaterThanOrEqualTo(170));
        expect(card.height, lessThanOrEqualTo(300));
        expect(tester.takeException(), isNull, reason: '$size scale=$scale');
        if (size.width == 1600) await preview(tester, 'library-1600');
      }
      final rootCardBounds = tester.getRect(key('document-root'));
      final newMenuBounds = tester.getRect(key('library-new-menu-root'));
      await tester.tap(key('folder-work'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      final transition = find.byKey(
        const ValueKey('library-folder-transition'),
      );
      final fade = tester.widget<FadeTransition>(
        find
            .descendant(of: transition, matching: find.byType(FadeTransition))
            .last,
      );
      expect(fade.opacity.value, inExclusiveRange(0, 1));
      expect(tester.getRect(key('document-root')), rootCardBounds);
      final openingRootWidth = tester.getSize(key('document-root')).width;
      await tester.pumpAndSettle();
      expect(
        tester.getSize(key('document-root')).width,
        closeTo(openingRootWidth, .1),
      );
      expect(key('library-folder-panel'), findsOneWidget);
      expect(tester.getSize(key('library-folder-panel')).width, lessThan(320));
      expect(key('document-nested'), findsOneWidget);
      expect(tester.getRect(key('library-new-menu-work')), newMenuBounds);
      final dropHint = find
          .ancestor(
            of: key('library-root-drop'),
            matching: find.byType(AnimatedOpacity),
          )
          .first;
      expect(tester.widget<AnimatedOpacity>(dropHint).opacity, 0);
      await tester.tap(key('library-new-menu-work'));
      await tester.pumpAndSettle();
      expect(find.text('New note'), findsOneWidget);
      expect(find.text(AppText.get('导入笔记文件夹')), findsNothing);
      expect(find.text(AppText.get('导入 PDF / 图片')), findsOneWidget);
      await tester.tapAt(const Offset(20, 250));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await preview(tester, 'library-640-folder');
      await tester.tap(key('close-library-folder'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(
        key('library-folder-panel'),
        findsOneWidget,
        reason: 'Closing panel should animate out instead of disappearing',
      );
      await tester.pumpAndSettle();
      expect(key('library-folder-panel'), findsNothing);
      await tester.tap(key('folder-work'));
      await tester.pumpAndSettle();
      await tester.enterText(key('library-search'), 'Hidden');
      await tester.pumpAndSettle();
      expect(key('library-folder-panel'), findsNothing);
      expect(key('document-nested'), findsOneWidget);
      expect(key('document-root'), findsNothing);
      await tester.tap(key('clear-library-search'));
      await tester.pumpAndSettle();
      expect(key('document-root'), findsOneWidget);
      expect(key('document-nested'), findsNothing);
      await tester.tap(find.byIcon(Icons.menu_rounded));
      await tester.pumpAndSettle();
      await tester.tap(key('library-nav-markdown'));
      await tester.pumpAndSettle();
      final scaffold = tester.state<ScaffoldState>(find.byType(Scaffold).first);
      expect(scaffold.isDrawerOpen, isFalse);
      expect(key('folder-work'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await drainIO(tester);
      imageCache.clear();
      imageCache.clearLiveImages();
      await tester.runAsync(() => temp.delete(recursive: true));
    },
  );

  testWidgets(
    'editor keeps history reachable and switches documents in a narrow window',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final temp = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('fastink-usability-editor-'),
      ))!;
      final notes = NoteRepository(dataRoot: '${temp.path}/data');
      final docs = <NoteDocument>[];
      await tester.runAsync(() async {
        for (final title in [
          'A long research notebook with annotated pages',
          'Second working notebook',
        ]) {
          final image = File('${temp.path}/$title.png');
          final page = raster.Image(width: 200, height: 280);
          raster.fill(page, color: raster.ColorRgb8(255, 255, 255));
          await image.writeAsBytes(raster.encodePng(page));
          docs.add(await notes.importImages([image], onProgress: (_) {}));
        }
        final now = DateTime.utc(2026);
        await LibraryRepository(root: notes.dataRoot).save(
          LibraryState(
            documents: [
              for (final doc in docs)
                LibraryDocument(
                  id: doc.id,
                  title: doc.title,
                  sourcePath: doc.pages.first.path,
                  coverPath: doc.pages.first.path,
                  pageCount: 1,
                  importedAt: now,
                  lastOpenedAt: now,
                ),
            ],
          ),
        );
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('usability-preview'),
            child: FastInkApp(
              settings: AppSettings(
                dataRoot: notes.dataRoot,
                language: 'en',
                autoSaveEnabled: false,
                openSidebarByDefault: false,
              ),
            ),
          ),
        );
      });
      await drainIO(tester);
      await tester.tap(key('document-${docs.first.id}'));
      await waitForInk(tester);
      expect(find.byType(InkLayer), findsWidgets);
      await tester.tap(find.byTooltip(AppText.get('更多')));
      await tester.pumpAndSettle();
      final editorExport = find.byWidgetPredicate(
        (w) => w is PopupMenuItem<String> && w.value == 'export',
      );
      await tester.ensureVisible(editorExport);
      await tester.tap(editorExport);
      await tester.pumpAndSettle();
      expect(key('export-current-page'), findsOneWidget);
      expect(key('export-library-scope'), findsNothing);
      await tester.tap(key('export-current-page'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<RadioGroup<bool>>(find.byType(RadioGroup<bool>))
            .groupValue,
        isFalse,
      );
      await tester.tap(find.text(AppText.get('取消')));
      await tester.pumpAndSettle();
      await tester.tap(key('page-sidebar-toggle'));
      await tester.pumpAndSettle();
      for (final mode in ['dark', 'light', 'system']) {
        await tester.tap(find.byTooltip(AppText.get('更多')));
        await tester.pumpAndSettle();
        final item = find.byWidgetPredicate(
          (w) => w is PopupMenuItem<String> && w.value == 'theme-$mode',
        );
        await tester.ensureVisible(item);
        await tester.tap(item);
        await drainIO(tester);
        if (mode != 'system') {
          final canvas = tester.widget<InkLayer>(find.byType(InkLayer).first);
          final thumbnail = tester.widget<InkPreview>(find.byType(InkPreview));
          expect(canvas.displayFilter, mode == 'dark' ? isNotNull : isNull);
          expect(thumbnail.displayFilter, canvas.displayFilter);
          await preview(tester, 'paper-$mode');
        }
        await tester.tap(find.byTooltip(AppText.get('更多')));
        await tester.pumpAndSettle();
        final current = find.byWidgetPredicate(
          (w) => w is PopupMenuItem<String> && w.value == 'theme-$mode',
        );
        final tile = tester.widget<ListTile>(
          find.descendant(of: current, matching: find.byType(ListTile)),
        );
        expect(tile.selected, isTrue);
        expect(tile.trailing, isA<Icon>());
        expect(
          find.byWidgetPredicate(
            (w) => w is ListTile && w.selected && w.trailing is Icon,
          ),
          findsOneWidget,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
      }
      await tester.tap(key('page-sidebar-toggle'));
      await tester.pumpAndSettle();
      final ink = tester
          .widget<InkLayer>(find.byType(InkLayer).first)
          .controller;
      ink.pasteStrokes([
        InkStroke(
          color: 0xff123456,
          width: .002,
          points: [const InkPoint(.2, .3, .8), const InkPoint(.4, .5, .7)],
        ),
      ]);
      await tester.pump();
      for (final (size, scale) in [
        (const Size(1600, 900), 1.0),
        (const Size(1280, 800), 1.3),
        (const Size(800, 600), 1.3),
        (const Size(640, 480), 1.0),
      ]) {
        tester.view.physicalSize = size;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        await tester.pump(const Duration(milliseconds: 500));
        expect(tester.takeException(), isNull, reason: '$size scale=$scale');
        final history = tester.getRect(key('ink-history-controls'));
        expect(history.right, lessThanOrEqualTo(size.width));
        expect(history.top, greaterThanOrEqualTo(0));
        final undo = find.byWidgetPredicate(
          (widget) =>
              widget is IconButton && widget.tooltip == AppText.get('撤销'),
        );
        expect(tester.widget<IconButton>(undo).onPressed, isNotNull);
        final scroll = find.descendant(
          of: key('tool-options-scrollbar'),
          matching: find.byType(SingleChildScrollView),
        );
        await tester.drag(scroll, const Offset(-1400, 0));
        await tester.pumpAndSettle();
        expect(tester.getRect(key('ink-history-controls')), history);
      }
      await tester.tap(find.byTooltip(AppText.get('撤销')));
      await tester.pump();
      expect(ink.strokes, isEmpty);
      await tester.tap(find.byTooltip(AppText.get('重做')));
      await tester.pump();
      expect(ink.strokes, hasLength(1));
      final zoom =
          tester
                  .widget<ValueListenableBuilder<Matrix4>>(
                    find.byType(ValueListenableBuilder<Matrix4>),
                  )
                  .valueListenable
              as TransformationController;
      zoom.value = Matrix4.identity();
      await tester.pumpAndSettle();
      final layerFinder = find.byType(InkLayer).first;
      final layerSize = tester.getSize(layerFinder);
      final pageOrigin = tester.getTopLeft(layerFinder);
      final bodyTop = tester.getBottomLeft(find.byType(AppBar)).dy;
      final anchor =
          pageOrigin +
          Offset(layerSize.width * .3, layerSize.height * .4) -
          Offset(0, bodyTop);
      void zoomTo(double scale) {
        zoom.value = Matrix4.identity()
          ..translateByDouble(
            -anchor.dx * (scale - 1),
            -anchor.dy * (scale - 1),
            0,
            1,
          )
          ..scaleByDouble(scale, scale, 1, 1);
      }

      Size screenSize(Finder finder) {
        final box = tester.renderObject<RenderBox>(finder);
        final rect = Rect.fromPoints(
          box.localToGlobal(Offset.zero),
          box.localToGlobal(box.size.bottomRight(Offset.zero)),
        );
        return rect.size;
      }

      ink.selectAll();
      await tester.pumpAndSettle();
      for (final scale in [1.0, 2.0, 4.0]) {
        zoomTo(scale);
        await tester.pumpAndSettle();
        final size = screenSize(key('selection-actions'));
        expect(size.width, closeTo(124, .1));
        expect(size.height, closeTo(34, .1));
        expect(
          tester.getTopLeft(key('selection-actions')).dy,
          greaterThanOrEqualTo(bodyTop),
        );
        expect(
          tester.getBottomRight(key('selection-actions')).dy,
          lessThanOrEqualTo(tester.view.physicalSize.height),
        );
        expect(tester.takeException(), isNull);
      }
      await preview(tester, 'selection-zoom-400');
      zoomTo(1);
      await tester.pumpAndSettle();
      tester
          .widget<InkLayer>(layerFinder)
          .onTextRequested(const InkPoint(.3, .4, 1), layerSize);
      await tester.pumpAndSettle();
      await tester.enterText(key('inline-text-input'), 'Memo');
      for (final brightness in [Brightness.dark, Brightness.light]) {
        tester.platformDispatcher.platformBrightnessTestValue = brightness;
        await tester.pumpAndSettle();
        final input = tester.widget<TextField>(key('inline-text-input'));
        expect(
          Theme.of(tester.element(key('inline-text-input'))).brightness,
          brightness,
        );
        final material = tester.widget<Material>(key('inline-text-editor'));
        final foreground = input.style!.color!;
        final background = Color.alphaBlend(material.color!, Colors.white);
        final a = foreground.computeLuminance(),
            b = background.computeLuminance();
        final contrast = (math.max(a, b) + .05) / (math.min(a, b) + .05);
        expect(contrast, greaterThanOrEqualTo(4.5), reason: '$brightness');
        expect(input.cursorColor, isNotNull);
        await preview(tester, 'inline-text-${brightness.name}');
      }
      await tester.pumpAndSettle();
      final editorSize = screenSize(key('inline-text-editor'));
      expect(editorSize.width, inInclusiveRange(128, 224));
      expect(editorSize.height, lessThanOrEqualTo(50));
      for (final scale in [1.0, 2.0, 4.0]) {
        zoomTo(scale);
        await tester.pumpAndSettle();
        final size = screenSize(key('inline-text-editor'));
        expect(size.width, closeTo(editorSize.width, .1));
        expect(size.height, closeTo(editorSize.height, .1));
        expect(tester.takeException(), isNull);
      }
      await preview(tester, 'text-editor-zoom-400');
      tester.view.physicalSize = const Size(800, 600);
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      await tester.pumpAndSettle();
      expect(
        screenSize(key('inline-text-editor')).width,
        closeTo(editorSize.width, .1),
      );
      expect(
        screenSize(key('inline-text-editor')).height,
        closeTo(editorSize.height, .1),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(key('inline-text-editor'), findsNothing);
      expect(ink.strokes, hasLength(1));
      tester.view.physicalSize = const Size(640, 480);
      tester.platformDispatcher.textScaleFactorTestValue = 1;
      await tester.pumpAndSettle();
      zoomTo(1);
      await tester.pumpAndSettle();
      tester
          .widget<InkLayer>(layerFinder)
          .onTextRequested(const InkPoint(.3, .4, 1), layerSize);
      await tester.pumpAndSettle();
      await tester.enterText(key('inline-text-input'), 'Saved memo');
      await tester.tap(find.byTooltip(AppText.get('完成（Ctrl+Enter）')));
      await tester.pumpAndSettle();
      final referenceText = ink.strokes.last;
      expect(referenceText.color, 0xff202124, reason: '输入面板的主题颜色不改变落字颜色');
      ink.undo();
      tester
          .widget<InkLayer>(layerFinder)
          .onTextRequested(const InkPoint(.3, .4, 1), layerSize);
      await tester.pumpAndSettle();
      await tester.enterText(key('inline-text-input'), 'Saved memo');
      zoomTo(2);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(AppText.get('完成（Ctrl+Enter）')));
      await tester.pumpAndSettle();
      expect(ink.strokes.last.text, 'Saved memo');
      expect(ink.strokes.last.textSize, closeTo(12 / layerSize.height, .0001));
      expect(
        ink.strokes.last.textBoxWidth,
        closeTo(referenceText.textBoxWidth!, .0001),
      );
      ink.undo();
      zoomTo(1);
      await tester.pumpAndSettle();
      final longText = List.filled(160, 'Long editable text 中文段落').join('\n');
      ink.addText(
        const InkPoint(.1, .1, .5),
        layerSize,
        longText,
        Colors.black,
        80,
        boxWidth: 200,
      );
      await tester.pumpAndSettle();
      final beforeMove = ink.selectionBounds!;
      final cameraBeforeMove = List<double>.of(zoom.value.storage);
      await tester.drag(
        find.byTooltip(
          AppText.get('拖动这里移动文本框', 'Drag here to move the text box'),
        ),
        const Offset(40, 12),
      );
      await tester.pumpAndSettle();
      expect(ink.selectionBounds!.left, greaterThan(beforeMove.left));
      expect(
        zoom.value.storage,
        orderedEquals(cameraBeforeMove),
        reason: 'Dragging text controls must not pan the page',
      );
      ink.undo();
      ink.selectOnly(ink.strokes.last);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(AppText.get('编辑文字')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(key('text-properties-content'))
            .controller!
            .text,
        longText,
      );
      await tester.enterText(key('text-properties-size'), 'NaN');
      await tester.tap(key('text-properties-apply'));
      await tester.pump();
      expect(key('text-properties-content'), findsOneWidget);
      await tester.enterText(key('text-properties-size'), '24.5');
      await tester.enterText(
        key('text-properties-width'),
        (layerSize.width * .8).toStringAsFixed(1),
      );
      await preview(tester, 'text-properties-640');
      await tester.tap(key('text-properties-apply'));
      await tester.pumpAndSettle();
      expect(ink.selectedTextStroke!.text, longText);
      expect(
        ink.selectedTextStroke!.textSize * layerSize.height,
        closeTo(24.5, .01),
      );
      await tester.tap(find.byTooltip(AppText.get('编辑文字')));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      await preview(tester, 'text-properties-reopen');
      await tester.tap(key('text-properties-fit'));
      await drainIO(tester);
      await tester.tap(key('text-properties-apply'));
      await tester.pumpAndSettle();
      expect(ink.selectionBounds!.bottom, lessThanOrEqualTo(1.01));
      expect(ink.selectedTextStroke!.text, longText);
      ink.undo();
      ink.undo();
      ink.undo();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await preview(tester, 'editor-640');
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(AppText.get('更多')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(editorExport);
      await tester.tap(editorExport);
      await tester.pumpAndSettle();
      expect(key('export-current-page'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await preview(tester, 'export-editor-640');
      await tester.tap(find.text(AppText.get('取消')));
      await tester.pumpAndSettle();
      tester.platformDispatcher.textScaleFactorTestValue = 1;
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.byTooltip(AppText.get('返回资料库')));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      for (
        var i = 0;
        i < 100 && key('document-${docs.last.id}').evaluate().isEmpty;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(
        key('document-${docs.last.id}'),
        findsOneWidget,
        reason: tester
            .widgetList<Text>(find.byType(Text))
            .map((w) => w.data)
            .join(' | '),
      );
      await tester.tap(key('document-${docs.last.id}'));
      await waitForInk(tester);
      await tester.tap(key('document-switcher'));
      await tester.pumpAndSettle();
      expect(find.text(docs.first.title), findsOneWidget);
      await tester.tap(find.text(docs.first.title));
      for (var i = 0; i < 100; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump(const Duration(milliseconds: 50));
        if (find.byType(InkLayer).evaluate().isNotEmpty &&
            tester
                    .widget<InkLayer>(find.byType(InkLayer).first)
                    .controller
                    .strokes
                    .length ==
                1) {
          break;
        }
      }
      expect(
        tester.widget<InkLayer>(find.byType(InkLayer).first).controller.strokes,
        hasLength(1),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await drainIO(tester);
      imageCache.clear();
      imageCache.clearLiveImages();
      await tester.runAsync(() => temp.delete(recursive: true));
    },
  );
}
