import 'dart:io';
import 'package:fastink_flutter/main.dart';
import 'package:fastink_flutter/src/core/app_localizations.dart';
import 'package:fastink_flutter/src/core/app_settings_controller.dart';
import 'package:fastink_flutter/src/core/settings_repository.dart';
import 'package:fastink_flutter/src/core/memory_policy_catalog.dart';
import 'package:fastink_flutter/src/engine/ink_canvas.dart';
import 'package:fastink_flutter/src/models/models.dart';
import 'package:fastink_flutter/src/storage/library_repository.dart';
import 'package:fastink_flutter/src/storage/note_repository.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as raster;
import '../document/window_usability_test.dart'
    show drainIO, waitForInk, preview;
import 'package:fastink_flutter/src/widgets/markdown_settings_panel.dart';

Finder keyed(String value) => find.byKey(ValueKey(value));
Finder settingSwitch(String text) => find.byWidgetPredicate(
  (w) =>
      w is SwitchListTile &&
      w.title is Text &&
      (w.title! as Text).data ==
          (AppText.locale.languageCode == 'en' && text == '显示工具提示'
              ? 'Show tooltips'
              : AppText.get(text)),
);

void main() {
  setUpAll(() async {
    for (final entry in {
      'Segoe UI Variable': r'C:\Windows\Fonts\segoeui.ttf',
      'Segoe UI': r'C:\Windows\Fonts\segoeui.ttf',
      'Microsoft YaHei UI': r'C:\Windows\Fonts\msyh.ttc',
      'MaterialIcons':
          'D:/ComputerProgram/path/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    }.entries) {
      final font = File(entry.value);
      if (await font.exists()) {
        await (FontLoader(entry.key)..addFont(
              Future.value(ByteData.sublistView(await font.readAsBytes())),
            ))
            .load();
      }
    }
  });

  testWidgets(
    'settings categories isolate handwriting, Markdown and shared preferences',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final temp = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('fastink-settings-categories-'),
      ))!;
      final repo = SettingsRepository(configRoot: '${temp.path}/config');
      final initial = AppSettings(
        dataRoot: '${temp.path}/data',
        language: 'zh',
        pressureEnabled: false,
        autoSaveDelayMs: 700,
        pdfPrefetchPages: 1,
        markdown: const MarkdownPreferences(
          autoSave: false,
          previewDelayMs: 600,
          jpgQuality: 80,
        ),
      );
      await tester.runAsync(() => repo.save(initial));
      await tester.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('usability-preview'),
          child: FastInkApp(settings: initial, settingsRepository: repo),
        ),
      );
      await drainIO(tester);
      await tester.tap(keyed('library-nav-settings'));
      await tester.pumpAndSettle();
      expect(settingSwitch('显示工具提示'), findsOneWidget);
      expect(settingSwitch('笔尖压感'), findsNothing);
      expect(find.byType(MarkdownSettingsPanel), findsNothing);
      await preview(tester, 'settings-general131');
      await tester.tap(keyed('settings-category-ink'));
      await tester.pumpAndSettle();
      expect(settingSwitch('笔尖压感'), findsOneWidget);
      expect(settingSwitch('显示工具提示'), findsNothing);
      expect(find.byType(MarkdownSettingsPanel), findsNothing);
      expect(keyed('autosave-delay'), findsNothing);
      for (final title in ['翻页动画', '首末页边界回弹']) {
        expect(find.text(title), findsNothing);
      }
      for (final title in ['最大缩放 ', '滚轮缩放速度 ', '页面侧栏宽度 ', 'JPG 导出质量 ']) {
        expect(find.textContaining(title), findsNothing);
      }
      expect(find.textContaining('Instance of'), findsNothing);

      expect(find.text('立即保存当前页'), findsNothing);
      // Scrolling the content never hides the category switch.
      final scroll = find
          .ancestor(
            of: keyed('settings-panel'),
            matching: find.byType(SingleChildScrollView),
          )
          .first;
      await tester.drag(scroll, const Offset(0, -450));
      await tester.pumpAndSettle();
      await tester.tap(keyed('settings-category-markdown'));
      await tester.pumpAndSettle();
      expect(find.byType(MarkdownSettingsPanel), findsOneWidget);
      expect(settingSwitch('笔尖压感'), findsNothing);
      expect(settingSwitch('自动保存'), findsNothing);
      expect(
        tester.widget<SwitchListTile>(keyed('markdown-setting-autoSave')).value,
        isFalse,
      );
      for (final field in [
        'autoSaveDelayMs',
        'previewDelayMs',
        'jpgQuality',
        'openOutline',
        'tabSize',
        'focusMode',
        'typewriter',
        'syncScroll',
        'hideCompletedTasks',
        'historyLimit',
      ]) {
        expect(keyed('markdown-setting-$field'), findsNothing);
      }
      await preview(tester, 'settings-markdown131');
      // Changing Markdown autosave must leave handwriting settings alone.
      tester
          .widget<SwitchListTile>(keyed('markdown-setting-autoSave'))
          .onChanged!(true);
      await drainIO(tester);
      // 先滚动再切换分类，覆盖滚动距离曾被误当作分组展开状态的回归场景。
      await tester.drag(
        find.byKey(const PageStorageKey('settings-panel-markdown')),
        const Offset(0, -300),
      );
      await tester.pumpAndSettle();
      await tester.tap(keyed('settings-category-ink'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<SwitchListTile>(settingSwitch('笔尖压感')).value,
        isFalse,
      );
      expect(
        tester.widget<SwitchListTile>(settingSwitch('自动保存')).value,
        isTrue,
      );
      await tester.tap(keyed('settings-category-markdown'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(ErrorWidget), findsNothing);
      expect(
        tester.widget<SwitchListTile>(keyed('markdown-setting-autoSave')).value,
        isTrue,
      );
      // Every category remains usable at the minimum window with larger text.
      tester.view.physicalSize = const Size(640, 480);
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      for (final category in ['general', 'markdown', 'ink']) {
        await tester.tap(keyed('settings-category-$category'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: category);
      }
      var saved = (await tester.runAsync(repo.load))!;
      // Disk replacement can briefly overlap a read; wait for the queued write.
      for (var i = 0; i < 30 && saved.dataRoot != initial.dataRoot; i++) {
        await drainIO(tester);
        saved = (await tester.runAsync(repo.load))!;
      }
      expect(saved.markdown.autoSave, isTrue);
      expect(saved.pressureEnabled, isFalse);
      expect(saved.autoSaveDelayMs, 700);
      expect(saved.pdfPrefetchPages, 1);
      expect(saved.markdown.previewDelayMs, 600);
      expect(saved.markdown.jpgQuality, 80);
      await tester.pumpWidget(const SizedBox.shrink());
      await drainIO(tester);
      await tester.runAsync(() => temp.delete(recursive: true));
    },
  );

  testWidgets('settings survive theme language rebuilds and persisted reload', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final temp = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('fastink-settings-ui-'),
    ))!;
    final repository = SettingsRepository(configRoot: '${temp.path}/config');
    final settings = AppSettings(
      dataRoot: '${temp.path}/data',
      language: 'en',
      defaultTool: 'highlighter',
    );
    await tester.runAsync(() => repository.save(settings));
    await tester.pumpWidget(
      FastInkApp(settings: settings, settingsRepository: repository),
    );
    await drainIO(tester);
    await tester.tap(keyed('library-nav-settings'));
    await tester.pumpAndSettle();
    tester.widget<SwitchListTile>(settingSwitch('显示工具提示')).onChanged!(false);
    await tester.pump();
    await tester.tap(keyed('settings-category-ink'));
    await tester.pumpAndSettle();
    for (final title in ['笔尖压感', '显示页码角标', '自动保存']) {
      final candidate = settingSwitch(title);
      expect(candidate, findsOneWidget, reason: title);
      tester.widget<SwitchListTile>(candidate).onChanged!(false);
      await tester.pump();
    }
    expect(keyed('settings-capture-button'), findsNothing);
    tester.widget<ListTile>(keyed('settings-default-pen-color')).onTap!();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(
      TooltipVisibility.of(tester.element(find.byType(AlertDialog))),
      isFalse,
    );
    final blue = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byWidgetPredicate(
        (w) =>
            w is Container &&
            w.decoration is BoxDecoration &&
            (w.decoration! as BoxDecoration).color == const Color(0xff1a73e8),
      ),
    );
    expect(blue, findsOneWidget);
    await tester.tap(find.ancestor(of: blue, matching: find.byType(InkWell)));
    await tester.pumpAndSettle();
    tester
        .widget<DropdownButton<LassoShape>>(
          find.descendant(
            of: keyed('settings-lasso-shape'),
            matching: find.byType(DropdownButton<LassoShape>),
          ),
        )
        .onChanged!(LassoShape.rectangle);
    await drainIO(tester);
    final initialSource = tester.widget<FastInkHome>(find.byType(FastInkHome));
    final controller = AppSettingsController(repository)
      ..syncFromWidget(initialSource);
    controller.penWidthPresets = [2, 4, 6];
    initialSource.onThemeModeChanged(ThemeMode.dark);
    await tester.pumpAndSettle();
    final rebuilt = tester.widget<FastInkHome>(find.byType(FastInkHome));
    controller.syncFromWidget(rebuilt, previous: initialSource);
    expect(controller.penWidthPresets, [2, 4, 6]);
    for (final title in ['笔尖压感', '显示页码角标', '自动保存']) {
      expect(
        tester.widget<SwitchListTile>(settingSwitch(title)).value,
        isFalse,
      );
    }
    rebuilt.onLanguageChanged(AppLanguage.zh);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(settingSwitch('自动保存')).value, isFalse);
    expect(
      tester
          .widget<DropdownButton<LassoShape>>(
            find.descendant(
              of: keyed('settings-lasso-shape'),
              matching: find.byType(DropdownButton<LassoShape>),
            ),
          )
          .value,
      LassoShape.rectangle,
    );
    await drainIO(tester);
    var saved = (await tester.runAsync(repository.load))!;
    for (
      var i = 0;
      i < 200 && (saved.language != 'zh' || saved.penColor != 0xff1a73e8);
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump(const Duration(milliseconds: 5));
      saved = (await tester.runAsync(repository.load))!;
    }
    expect(saved.pressureEnabled, isFalse);
    expect(saved.autoSaveEnabled, isFalse);
    expect(saved.tooltipsEnabled, isFalse);
    expect(saved.showPageNumber, isFalse);
    expect(saved.penColor, 0xff1a73e8);
    expect(saved.lassoShape, 'rectangle');
    expect(saved.themeMode, ThemeMode.dark);
    expect(saved.language, 'zh');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      FastInkApp(settings: saved, settingsRepository: repository),
    );
    await drainIO(tester);
    await tester.tap(keyed('library-nav-settings'));
    await tester.pumpAndSettle();
    await tester.tap(keyed('settings-category-ink'));
    await tester.pumpAndSettle();
    expect(keyed('settings-capture-button'), findsNothing);
    tester.view.physicalSize = const Size(640, 480);
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() => temp.delete(recursive: true));
  });

  testWidgets(
    'reenabling autosave flushes a pending page without another stroke',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final temp = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('fastink-autosave-'),
      ))!;
      final repo = SettingsRepository(configRoot: '${temp.path}/config');
      final notes = NoteRepository(dataRoot: '${temp.path}/data');
      late NoteDocument document;
      await tester.runAsync(() async {
        final source = File('${temp.path}/page.png');
        await source.writeAsBytes(
          raster.encodePng(raster.Image(width: 200, height: 280)),
        );
        document = await notes.indexFromSelectedPath(source.path);
        final library = LibraryRepository(root: '${temp.path}/data');
        await library.save(
          LibraryState(
            documents: [library.fromDocument(document)],
            folders: [],
          ),
        );
      });
      final settings = AppSettings(
        dataRoot: '${temp.path}/data',
        language: 'en',
        autoSaveEnabled: false,
        autoSaveDelayMs: 100,
        openSidebarByDefault: false,
      );
      await tester.runAsync(() => repo.save(settings));
      await tester.pumpWidget(
        FastInkApp(settings: settings, settingsRepository: repo),
      );
      await drainIO(tester);
      await tester.tap(keyed('library-nav-settings'));
      await tester.pumpAndSettle();
      await tester.tap(keyed('settings-category-ink'));
      await tester.pumpAndSettle();
      // Capture the actual settings binding while the same home State is alive.
      final enable = tester
          .widget<SwitchListTile>(settingSwitch('自动保存'))
          .onChanged!;
      await tester.tap(keyed('library-nav-documents'));
      await tester.pumpAndSettle();
      await tester.tap(keyed('document-${document.id}'));
      await waitForInk(tester);
      final ink = tester.widget<InkLayer>(find.byType(InkLayer)).controller;
      ink.begin(const InkPoint(.2, .2, .5), Colors.black, .003, StrokeKind.pen);
      ink.append(const InkPoint(.5, .3, .6));
      ink.finish();
      expect(ink.isInteracting, isFalse);
      await tester.pump(const Duration(milliseconds: 300));
      final before = (await tester.runAsync(
        () => notes.loadPageInk(document, document.pages.first),
      ))!;
      expect(before.strokes, isEmpty);
      enable(true);
      await tester.pump(const Duration(milliseconds: 150));
      await drainIO(tester);
      var after = (await tester.runAsync(
        () => notes.loadPageInk(document, document.pages.first),
      ))!;
      for (var i = 0; i < 30 && after.strokes.isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump(const Duration(milliseconds: 50));
        after = (await tester.runAsync(
          () => notes.loadPageInk(document, document.pages.first),
        ))!;
      }
      expect(after.strokes, hasLength(1));
      expect((await tester.runAsync(repo.load))!.autoSaveEnabled, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 300));
      await tester.runAsync(() => temp.delete(recursive: true));
    },
  );

  testWidgets('stylus-only mode permits mouse selection but blocks mouse ink', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(200, 200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final ink = InkController(onCommitted: () {});
    Widget canvas(InkTool tool) => MaterialApp(
      home: InkLayer(
        controller: ink,
        tool: tool,
        color: Colors.black,
        width: 3,
        eraserMode: EraserMode.stroke,
        eraserSize: 10,
        momentaryTool: null,
        enabled: true,
        stylusOnly: true,
        onDrawingChanged: (_) {},
        onPenButtonChanged: (_, _) {},
        onTextRequested: (_, _) {},
      ),
    );
    await tester.pumpWidget(canvas(InkTool.pen));
    final draw = await tester.startGesture(
      const Offset(20, 40),
      kind: PointerDeviceKind.mouse,
    );
    await draw.moveTo(const Offset(180, 80));
    await draw.up();
    expect(ink.strokes, isEmpty);
    ink.replace([
      InkStroke(
        color: 0xff000000,
        width: .002,
        points: [
          const InkPoint(.2, .2, .5),
          const InkPoint(.8, .2, .5),
          const InkPoint(.8, .8, .5),
          const InkPoint(.2, .8, .5),
        ],
      ),
    ]);
    await tester.pumpWidget(canvas(InkTool.lasso));
    final lasso = await tester.startGesture(
      const Offset(20, 20),
      kind: PointerDeviceKind.mouse,
    );
    for (final point in [
      const Offset(160, 20),
      const Offset(160, 140),
      const Offset(20, 140),
      const Offset(20, 20),
    ]) {
      await lasso.moveTo(point);
    }
    await lasso.up();
    await tester.pump();
    expect(ink.selectedStrokes, hasLength(1));
    final start = ink.strokes.single.points.first.x;
    await tester.pumpWidget(canvas(InkTool.pen));
    final move = await tester.startGesture(
      const Offset(100, 100),
      kind: PointerDeviceKind.mouse,
    );
    await move.moveBy(const Offset(10, 10));
    await move.up();
    await tester.pump();
    expect(ink.strokes.single.points.first.x, greaterThan(start));
    await tester.pumpWidget(const SizedBox.shrink());
    ink.dispose();
  });

  testWidgets(
    'barrel eraser can follow settings and does not change stored eraser mode',
    (tester) async {
      tester.view.physicalSize = const Size(200, 200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final ink = InkController(onCommitted: () {});
      final original = InkStroke(
        color: 0xff101010,
        width: .002,
        points: [const InkPoint(.1, .5, .5), const InkPoint(.9, .5, .5)],
      );
      Widget canvas(EraserMode buttonMode) => MaterialApp(
        home: InkLayer(
          controller: ink,
          tool: InkTool.pen,
          color: Colors.black,
          width: 3,
          eraserMode: EraserMode.stroke,
          eraserSize: 10,
          momentaryTool: null,
          enabled: true,
          primaryButtonTool: InkTool.eraser,
          primaryButtonEraserMode: buttonMode,
          onDrawingChanged: (_) {},
          onPenButtonChanged: (_, _) {},
          onTextRequested: (_, _) {},
        ),
      );
      for (final mode in EraserMode.values) {
        ink.replace([original]);
        await tester.pumpWidget(canvas(mode));
        final pen = await tester.startGesture(
          const Offset(100, 100),
          kind: PointerDeviceKind.stylus,
          buttons: kPrimaryStylusButton,
        );
        await pen.up();
        await tester.pump();
        expect(ink.strokes.length, mode == EraserMode.stroke ? 0 : 2);
        expect(
          tester.widget<InkLayer>(find.byType(InkLayer)).eraserMode,
          EraserMode.stroke,
        );
      }
      for (final profile in MemoryPolicyCatalog.profiles) {
        ink.rasterCacheMegabytes = profile.inkRasterCacheMegabytes;
        expect(ink.rasterCacheMegabytes, profile.inkRasterCacheMegabytes);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      ink.dispose();
    },
  );
}
