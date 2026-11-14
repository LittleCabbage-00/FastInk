import 'dart:io';
import 'dart:ui' as ui;
import 'package:fastink_flutter/src/features/markdown/markdown_editor.dart';
import 'package:fastink_flutter/src/core/app_localizations.dart';
import 'package:fastink_flutter/src/core/markdown_preferences.dart';
import 'package:fastink_flutter/src/core/markdown_writing_tools.dart';
import 'package:fastink_flutter/src/platform/markdown_templates.dart';
import 'package:fastink_flutter/src/widgets/markdown_item_picker.dart';
import 'package:fastink_flutter/src/widgets/markdown_source_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'markdown_editor_test.dart' show drain;

void main() {
  setUpAll(() async {
    for (final entry in {
      'Roboto': r'C:\Windows\Fonts\msyh.ttc',
      'Consolas': r'C:\Windows\Fonts\consola.ttf',
      'MaterialIcons':
          'D:/ComputerProgram/path/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    }.entries) {
      await (FontLoader(entry.key)..addFont(
            Future.value(
              ByteData.sublistView(await File(entry.value).readAsBytes()),
            ),
          ))
          .load();
    }
  });
  setUp(() => AppText.locale = const Locale('zh'));
  test(
    'tasks ignore metadata and longer fences; offsets preserve the source',
    () {
      const text =
          '---\r\n- [ ] metadata\r\n---\r\n# Today\r\n- [ ] 工作\r\n  - [X] nested\r\n````md\r\n```\r\n- [ ] example\r\n````\r\n1. [ ] final\r\n';
      final tasks = MarkdownTask.parse(text);
      expect(tasks.map((t) => t.label), ['工作', 'nested', 'final']);
      expect(tasks.map((t) => t.done), [false, true, false]);
      for (final task in tasks) {
        expect(text[task.marker], task.done ? 'X' : ' ');
      }
      final changed = editMarkdownLines(
        const TextEditingValue(
          text: text,
          selection: TextSelection(baseOffset: 0, extentOffset: text.length),
        ),
        MarkdownLineAction.toggleTask,
      );
      expect(
        changed.text,
        text
            .replaceFirst('[ ] 工作', '[x] 工作')
            .replaceFirst('[ ] final', '[x] final')
            .replaceFirst('[X] nested', '[x] nested'),
      );
    },
  );
  test(
    'line editing handles boundaries, multiline selection and composition',
    () {
      const value = TextEditingValue(
        text: 'one\ntwo\nthree',
        selection: TextSelection(baseOffset: 4, extentOffset: 8),
      );
      expect(
        editMarkdownLines(value, MarkdownLineAction.duplicate).text,
        'one\ntwo\ntwo\nthree',
      );
      expect(
        editMarkdownLines(value, MarkdownLineAction.moveUp).text,
        'two\none\nthree',
      );
      expect(
        editMarkdownLines(value, MarkdownLineAction.moveDown).text,
        'one\nthree\ntwo',
      );
      expect(
        editMarkdownLines(value, MarkdownLineAction.delete).text,
        'one\nthree',
      );
      const last = TextEditingValue(
        text: 'one\ntwo',
        selection: TextSelection.collapsed(offset: 6),
      );
      expect(editMarkdownLines(last, MarkdownLineAction.delete).text, 'one');
      expect(editMarkdownLines(last, MarkdownLineAction.moveDown), last);
      final composing = value.copyWith(
        composing: const TextRange(start: 4, end: 7),
      );
      expect(
        editMarkdownLines(composing, MarkdownLineAction.delete),
        composing,
      );
      expect(markdownWordCount('中文 hello world 123 !'), 5);
    },
  );
  test(
    'templates persist without overwrites; variables expand once; removal archives',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'fastink-templates-test-',
      );
      try {
        final store = MarkdownTemplates(temp.path);
        await store.save('../会议', '{{date}} {{time}} {{title}} {{unknown}}');
        await store.save('../会议', 'second');
        final items = await store.read();
        expect(items.length, 2);
        expect(items.map((t) => t.id).toSet().length, 2);
        expect(
          MarkdownTemplates.expand(
            items.firstWhere((t) => t.content != 'second').content,
            title: '{{date}}',
            date: DateTime(2026, 10, 28, 9, 5),
          ),
          '2026-10-28 09:05 {{date}} {{unknown}}',
        );
        await store.archive(items.first);
        expect((await store.read()).length, 1);
        expect(
          await store.directory
              .list()
              .where((file) => file.path.endsWith('.deleted'))
              .length,
          1,
        );
      } finally {
        await temp.delete(recursive: true);
      }
    },
  );
  test('new writing preferences round trip and retain safe defaults', () {
    const value = MarkdownPreferences(
      showWordCount: false,
      hideCompletedTasks: true,
    );
    expect(MarkdownPreferences.fromJson(value.toJson()), value);
    expect(MarkdownPreferences.fromJson({}).showWordCount, isTrue);
    expect(MarkdownPreferences.fromJson({}).hideCompletedTasks, isFalse);
  });

  testWidgets('picker supports arrow selection, Enter and empty results', (
    tester,
  ) async {
    String? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            child: const Text('open'),
            onPressed: () async {
              picked = await showDialog<String>(
                context: context,
                builder: (_) => const MarkdownItemPicker(
                  title: 'Search',
                  items: {'a': 'Alpha', 'b': 'Beta'},
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(picked, 'b');
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('markdown-command-search')),
      'no match',
    );
    await tester.pump();
    expect(find.text('没有匹配结果'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
  });

  testWidgets(
    'tasks update source, hide completed, navigate and save at 640px',
    (tester) async {
      tester.view.physicalSize = const Size(640, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final temp = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('fastink-task-ui-'),
      ))!;
      final file = File('${temp.path}/work.md');
      const content =
          '# 工作\n\n- [ ] Task one\n- [x] Task two\n\n```\n- [ ] example\n```\n';
      await tester.runAsync(() => file.writeAsString(content));
      MarkdownPreferences? settings;
      await tester.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('preview'),
          child: MaterialApp(
            home: MarkdownEditorView(
              filePath: file.path,
              dataRoot: temp.path,
              darkMode: false,
              onExit: () {},
              onThemeToggle: () {},
              preferences: const MarkdownPreferences(
                defaultMode: 'edit',
                autoSave: false,
              ),
              onPreferencesChanged: (p) => settings = p,
            ),
          ),
        ),
      );
      await drain(tester);
      await tester.tap(find.byTooltip('本文待办总览'));
      await tester.pumpAndSettle();
      expect(find.text('Task one'), findsOneWidget);
      expect(find.text('example'), findsNothing);
      await tester.tap(find.byType(Checkbox).first);
      await tester.pump();
      expect(find.text('本文待办 · 2 / 2'), findsOneWidget);
      await tester.tap(find.byType(SwitchListTile));
      await tester.pump();
      expect(settings!.hideCompletedTasks, isTrue);
      expect(find.text('没有匹配的待办'), findsOneWidget);
      await tester.tap(find.byType(SwitchListTile));
      await tester.pump();
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('preview')),
      );
      final image = (await tester.runAsync(() => boundary.toImage()))!;
      final bytes = await tester.runAsync(
        () => image.toByteData(format: ui.ImageByteFormat.png),
      );
      image.dispose();
      await tester.runAsync(
        () => File(
          'build/diagnostics/markdown134-editor.png',
        ).writeAsBytes(bytes!.buffer.asUint8List()),
      );
      await tester.tap(find.text('Task one'));
      await tester.pumpAndSettle();
      final source = tester.widget<MarkdownSourceEditor>(
        find.byType(MarkdownSourceEditor),
      );
      expect(
        source.controller.text,
        content.replaceFirst('[ ] Task one', '[x] Task one'),
      );
      expect(
        source.controller.selection.start,
        content.indexOf('- [ ] Task one'),
      );
      await tester.pump(const Duration(milliseconds: 600));
      expect(source.undo.value.canUndo, isTrue);
      source.undo.undo();
      await tester.pump();
      expect(source.controller.text, content);
      source.undo.redo();
      await tester.pump();
      await tester.tap(find.byTooltip('保存'));
      for (int attempt = 0; attempt < 10; attempt++) {
        await drain(tester);
        if (await tester.runAsync(file.readAsString) ==
            source.controller.text) {
          break;
        }
      }
      expect(await tester.runAsync(file.readAsString), source.controller.text);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await drain(tester);
      await tester.runAsync(() => temp.delete(recursive: true));
    },
  );

  testWidgets(
    'find adopts selection and custom templates insert without replacing the document',
    (tester) async {
      final temp = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('fastink-template-ui-'),
      ))!;
      final file = File('${temp.path}/work.md');
      await tester.runAsync(() => file.writeAsString('hello world'));
      await tester.runAsync(
        () => MarkdownTemplates(
          temp.path,
        ).save('Review', '## {{title}}\n- [ ] Review\n'),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: MarkdownEditorView(
            filePath: file.path,
            dataRoot: temp.path,
            darkMode: false,
            onExit: () {},
            onThemeToggle: () {},
            preferences: const MarkdownPreferences(
              defaultMode: 'edit',
              autoSave: false,
            ),
          ),
        ),
      );
      await drain(tester);
      final controller = tester
          .widget<MarkdownSourceEditor>(find.byType(MarkdownSourceEditor))
          .controller;
      controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 5,
      );
      await tester.tap(find.byTooltip('查找 / 替换'));
      await tester.pump();
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('markdown-find')))
            .controller!
            .text,
        'hello',
      );
      await tester.tap(find.byTooltip('关闭查找'));
      await tester.pump();
      controller.selection = TextSelection.collapsed(
        offset: controller.text.length,
      );
      await tester.tap(find.byTooltip('更多操作'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('从模板插入'));
      await drain(tester);
      await tester.enterText(
        find.byKey(const ValueKey('markdown-command-search')),
        'Review',
      );
      await tester.pump();
      await tester.tap(find.text('自定义 · Review'));
      await tester.pumpAndSettle();
      expect(controller.text, 'hello world\n\n## work\n- [ ] Review\n');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await drain(tester);
      await tester.runAsync(() => temp.delete(recursive: true));
    },
  );
}
