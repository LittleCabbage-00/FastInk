import 'dart:io';
import 'package:fastink_flutter/main.dart';
import 'package:fastink_flutter/src/core/app_localizations.dart';
import 'package:fastink_flutter/src/core/settings_repository.dart';
import 'package:fastink_flutter/src/engine/ink_canvas.dart';
import 'package:fastink_flutter/src/features/markdown/markdown_editor.dart';
import 'package:fastink_flutter/src/models/models.dart';
import 'package:fastink_flutter/src/platform/render_power_policy.dart';
import 'package:fastink_flutter/src/storage/library_repository.dart';
import 'package:fastink_flutter/src/storage/note_repository.dart';
import 'package:fastink_flutter/src/widgets/app_screen_transition.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as raster;
import 'window_usability_test.dart' show drainIO, waitForInk;

double displacement(WidgetTester tester) => tester
    .widget<Transform>(find.byKey(const ValueKey('screen-transition-offset')))
    .transform
    .storage[12];

void main() {
  tearDown(() => RenderPowerMonitor.instance.value = const RenderPowerPolicy());

  testWidgets(
    'enter and return animate without retaining or rebuilding old screens',
    (tester) async {
      final builds = <String, int>{};
      final disposed = <String>[];
      var taps = 0;
      Future<void> show(String id) => tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(),
            child: AppScreenTransition(
              destination: id,
              returning: id == 'library',
              child: _Probe(
                key: ValueKey(id),
                label: id,
                onBuild: () => builds[id] = (builds[id] ?? 0) + 1,
                onDispose: () => disposed.add(id),
                onTap: () => taps++,
              ),
            ),
          ),
        ),
      );
      await show('library');
      expect(displacement(tester), 0);
      await show('document');
      expect(displacement(tester), 20);
      expect(disposed, ['library']);
      expect(find.byType(_Probe), findsOneWidget);
      final documentBuilds = builds['document'];
      await tester.pump(const Duration(milliseconds: 50));
      expect(displacement(tester), allOf(greaterThan(0), lessThan(20)));
      expect(builds['document'], documentBuilds);
      // 平移动画中的按钮仍按实际位置命中，不阻塞用户操作。
      await tester.tap(find.text('document'));
      expect(taps, 1);
      await tester.pumpAndSettle();
      expect(displacement(tester), 0);
      await show('library');
      expect(displacement(tester), -20);
      expect(disposed, ['library', 'document']);
      await tester.pump(const Duration(milliseconds: 40));
      expect(displacement(tester), allOf(greaterThan(-20), lessThan(0)));
      // 快速反向切换不会残留旧画布、重复控制器或等待前一次动画结束。
      await show('markdown');
      expect(displacement(tester), 20);
      expect(find.byType(_Probe), findsOneWidget);
      await tester.pumpAndSettle();
      await show('markdown');
      expect(displacement(tester), 0, reason: '同一编辑器的状态更新不重播动画');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'battery keeps shorter navigation and system reduced motion stops it',
    (tester) async {
      RenderPowerMonitor.instance.value = const RenderPowerPolicy(
        onBattery: true,
      );
      Future<void> show(String id, {bool reduced = false}) => tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: reduced),
            child: AppScreenTransition(
              destination: id,
              returning: id == 'library',
              child: const SizedBox.expand(),
            ),
          ),
        ),
      );
      await show('library');
      await show('document');
      expect(displacement(tester), 12);
      await tester.pump(const Duration(milliseconds: 60));
      expect(displacement(tester), allOf(greaterThan(0), lessThan(12)));
      await tester.pump(const Duration(milliseconds: 61));
      expect(displacement(tester), 0);
      await show('library');
      expect(displacement(tester), -12);
      await show('library', reduced: true);
      expect(displacement(tester), 0);
      await show('markdown', reduced: true);
      expect(displacement(tester), 0);
      expect(tester.hasRunningAnimations, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'real handwriting and Markdown enter and exit with animation and saved ink',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final temp = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('fastink-navigation-'),
      ))!;
      final notes = NoteRepository(dataRoot: '${temp.path}/data');
      late NoteDocument note;
      await tester.runAsync(() async {
        final image = File('${temp.path}/page.png');
        await image.writeAsBytes(
          raster.encodePng(raster.Image(width: 200, height: 280)),
        );
        note = await notes.importImages([image], onProgress: (_) {});
        final md = File('${temp.path}/example.md');
        await md.writeAsString('# Example\n\nLocal Markdown.');
        final now = DateTime.now();
        await LibraryRepository(root: notes.dataRoot).save(
          LibraryState(
            folders: [
              LibraryFolder(
                id: 'folder',
                name: 'Folder sample',
                createdAt: now,
              ),
            ],
            documents: [
              for (var i = 0; i < 30; i++)
                LibraryDocument(
                  id: 'other-$i',
                  title: 'Other $i',
                  sourcePath: note.pages.first.path,
                  coverPath: note.pages.first.path,
                  pageCount: 1,
                  importedAt: now,
                  lastOpenedAt: now,
                ),
              for (final (id, path) in [
                (note.id, note.pages.first.path),
                ('md', md.path),
              ])
                LibraryDocument(
                  id: id,
                  title: id == 'md' ? 'Markdown sample' : 'Handwritten sample',
                  sourcePath: path,
                  coverPath: path,
                  pageCount: 1,
                  importedAt: now,
                  lastOpenedAt: now.subtract(const Duration(days: 1)),
                ),
            ],
          ),
        );
      });
      await tester.pumpWidget(
        FastInkApp(
          settings: AppSettings(
            dataRoot: notes.dataRoot,
            language: 'en',
            autoSaveEnabled: false,
            openSidebarByDefault: false,
          ),
          settingsRepository: SettingsRepository(
            configRoot: '${temp.path}/config',
          ),
        ),
      );
      await drainIO(tester);
      final search = find.byKey(const ValueKey('library-search'));
      final browser = find.byKey(const ValueKey('library-browser-documents'));
      final browserElement = tester.element(browser);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(tester.widget<TextField>(search).focusNode!.hasFocus, isTrue);
      await tester.enterText(search, 'Hand');
      await tester.pump();
      await tester.enterText(search, 'Handwritten');
      await tester.pump();
      expect(tester.element(browser), same(browserElement));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(search).controller!.text, isEmpty);
      // 文件夹可用 Esc 关闭，搜索框获得焦点也不妨碍此操作。
      await tester.tap(find.byKey(const ValueKey('folder-folder')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('library-folder-panel')),
        findsOneWidget,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('library-folder-panel')), findsNothing);
      final grid = find.byKey(
        const PageStorageKey('library-grid-documents-root-browse'),
      );
      final scroll = tester.state<ScrollableState>(
        find.descendant(of: grid, matching: find.byType(Scrollable)).first,
      );
      scroll.position.jumpTo(scroll.position.maxScrollExtent);
      await tester.pumpAndSettle();
      final previousOffset = scroll.position.pixels;
      expect(previousOffset, greaterThan(0));
      Future<void> destination(String expected) async {
        for (var i = 0; i < 100; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump();
          if (tester
                  .widget<AppScreenTransition>(find.byType(AppScreenTransition))
                  .destination ==
              expected) {
            return;
          }
        }
        fail('Navigation did not reach $expected');
      }

      await tester.tap(find.byKey(ValueKey('document-${note.id}')));
      await destination('document');
      expect(displacement(tester), greaterThan(0));
      await waitForInk(tester);
      final pageField = find.byKey(const ValueKey('page-number-input'));
      await tester.tap(pageField);
      expect(
        tester
            .widget<TextField>(pageField)
            .controller!
            .selection
            .textInside('1'),
        '1',
      );
      await tester.enterText(pageField, '');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(pageField).controller!.text, '1');
      await tester.enterText(pageField, '9999');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(pageField).controller!.text, '1');
      final ink = tester
          .widget<InkLayer>(find.byType(InkLayer).first)
          .controller;
      ink.begin(const InkPoint(.2, .2, .4), Colors.black, .002, StrokeKind.pen);
      ink.append(const InkPoint(.4, .3, .8));
      ink.finish();
      await tester.pumpAndSettle();
      Future<void> historyKey(
        LogicalKeyboardKey key, {
        bool shift = false,
      }) async {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyEvent(key);
        if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pump();
      }

      // 在工具栏上获得键盘焦点，验证不依赖画布焦点且每次只撤销一次。
      final historyButton = find.byTooltip(AppText.get('撤销'));
      final buttonFocus = Focus.of(
        tester.element(
          find.descendant(of: historyButton, matching: find.byType(Icon)).first,
        ),
      );
      buttonFocus.requestFocus();
      await tester.pump();
      await historyKey(LogicalKeyboardKey.keyZ);
      expect(ink.strokes, isEmpty);
      await historyKey(LogicalKeyboardKey.keyY);
      expect(ink.strokes, hasLength(1));
      await historyKey(LogicalKeyboardKey.keyZ);
      await historyKey(LogicalKeyboardKey.keyZ, shift: true);
      expect(ink.strokes, hasLength(1));
      // 文本输入获得焦点时，Ctrl+Z 不得更改画布笔迹。
      await tester.tap(pageField);
      await tester.enterText(pageField, '123');
      await historyKey(LogicalKeyboardKey.keyZ);
      expect(ink.strokes, hasLength(1));
      await tester.tap(find.byKey(const ValueKey('page-number-total')));
      await tester.tap(find.byTooltip(AppText.get('返回资料库')));
      await destination('library');
      expect(displacement(tester), lessThan(0));
      expect(find.byType(InkLayer), findsNothing);
      final saved = (await tester.runAsync(
        () => notes.loadPageInk(note, note.pages.first),
      ))!;
      expect(saved.strokes, hasLength(1));
      await tester.pumpAndSettle();
      final returnedScroll = tester.state<ScrollableState>(
        find.descendant(of: grid, matching: find.byType(Scrollable)).first,
      );
      expect(returnedScroll.position.pixels, closeTo(previousOffset, .01));
      await tester.tap(find.byKey(const ValueKey('library-nav-markdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('document-md')));
      await destination('markdown');
      expect(displacement(tester), greaterThan(0));
      await drainIO(tester);
      expect(find.byType(MarkdownEditorView), findsOneWidget);
      await tester.tap(find.byTooltip(AppText.get('返回')));
      await destination('library');
      expect(displacement(tester), lessThan(0));
      expect(find.byType(MarkdownEditorView), findsNothing);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await drainIO(tester);
      await tester.runAsync(() => temp.delete(recursive: true));
    },
  );
}

class _Probe extends StatefulWidget {
  const _Probe({
    super.key,
    required this.label,
    required this.onBuild,
    required this.onDispose,
    required this.onTap,
  });
  final String label;
  final VoidCallback onBuild, onDispose, onTap;
  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  @override
  void dispose() {
    widget.onDispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    widget.onBuild();
    return Scaffold(
      body: Center(
        child: TextButton(onPressed: widget.onTap, child: Text(widget.label)),
      ),
    );
  }
}
