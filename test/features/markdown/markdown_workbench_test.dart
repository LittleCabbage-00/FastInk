import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:fastink_flutter/main.dart';
import 'package:fastink_flutter/src/features/markdown/markdown_editor.dart';
import 'package:fastink_flutter/src/core/app_localizations.dart';
import 'package:fastink_flutter/src/core/markdown_table_data.dart';
import 'package:fastink_flutter/src/core/settings_repository.dart';
import 'package:fastink_flutter/src/platform/markdown_diagrams.dart';
import 'package:fastink_flutter/src/platform/markdown_document_export.dart';
import 'package:fastink_flutter/src/platform/markdown_editor_service.dart';
import 'package:fastink_flutter/src/platform/markdown_encoding.dart';
import 'package:fastink_flutter/src/platform/markdown_history.dart';
import 'package:fastink_flutter/src/platform/markdown_workspace.dart';
import 'package:fastink_flutter/src/widgets/markdown_source_editor.dart';
import 'package:fastink_flutter/src/widgets/markdown_live_editor.dart';
import 'package:fastink_flutter/src/storage/library_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:fastink_flutter/src/widgets/markdown_settings_panel.dart';
import 'package:image/image.dart' as raster;
import 'package:xml/xml.dart';
import 'markdown_editor_test.dart' show drain;

Finder key(String value) => find.byKey(ValueKey(value));

void main() {
  setUp(() {
    AppText.locale = const Locale('zh');
    String clipboard = '';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard = (call.arguments as Map)['text'] as String;
            return null;
          }
          if (call.method == 'Clipboard.getData') return {'text': clipboard};
          if (call.method == 'Clipboard.hasStrings') {
            return {'value': clipboard.isNotEmpty};
          }
          return null;
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null),
  );
  setUpAll(() async {
    final bytes = await File(r'C:\Windows\Fonts\segoeui.ttf').readAsBytes();
    for (final name in [
      'Roboto',
      'Segoe UI',
      'Segoe UI Variable',
      'Microsoft YaHei UI',
      'Consolas',
    ]) {
      await (FontLoader(
        name,
      )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    }
  });

  test(
    'Markdown preferences persist separately and invalid values do not reset other settings',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'fastink-md-preferences-',
      );
      try {
        final repo = SettingsRepository(configRoot: temp.path);
        const value = MarkdownPreferences(
          defaultMode: 'read',
          openOutline: true,
          lineNumbers: false,
          syntaxHighlight: false,
          autoPair: false,
          continueLists: false,
          tabSize: 8,
          editorFont: 'Segoe UI',
          fontSize: 23,
          lineHeight: 2.1,
          previewFontSize: 22,
          previewWidth: 1150,
          syncScroll: false,
          previewDelayMs: 700,
          mathEnabled: false,
          remoteImages: false,
          autoSave: false,
          autoSaveDelayMs: 3200,
          typewriter: true,
          focusMode: true,
          exportFormat: 'docx',
          exportScale: 2,
          jpgQuality: 82,
          exportDark: true,
          historyEnabled: false,
          historyLimit: 90,
          diagramEnabled: false,
        );
        await repo.save(
          const AppSettings(
            dataRoot: 'test-data',
            markdown: value,
            pressureEnabled: false,
          ),
        );
        await repo.update(
          (current) => current.copyWith(themeMode: ThemeMode.dark),
        );
        final loaded = await repo.load();
        expect(loaded.markdown, value);
        expect(loaded.pressureEnabled, isFalse);
        expect(loaded.themeMode, ThemeMode.dark);
        final safe = MarkdownPreferences.fromJson({
          'fontSize': 999,
          'previewDelayMs': -100,
          'tabSize': 2.0,
          'autoPair': 'no',
          'defaultMode': 'bogus',
          'jpgQuality': double.nan,
          'historyLimit': 1000,
        });
        expect(safe.fontSize, 26);
        expect(safe.previewDelayMs, 100);
        expect(safe.tabSize, 2);
        expect(safe.autoPair, isTrue);
        expect(safe.defaultMode, 'split');
        expect(safe.jpgQuality, 94);
        expect(safe.historyLimit, 200);
      } finally {
        await temp.delete(recursive: true);
      }
    },
  );

  test(
    'input pairs, selected wrapping, backspace and list continuation preserve source and IME',
    () {
      const formatter = MarkdownInputFormatter(MarkdownPreferences());
      TextEditingValue value(String text, int offset) => TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: offset),
      );
      expect(
        formatter.formatEditUpdate(value('', 0), value('(', 1)),
        value('()', 1),
      );
      expect(
        formatter.formatEditUpdate(value('()', 1), value('())', 2)),
        value('()', 2),
      );
      expect(
        formatter.formatEditUpdate(value('()', 1), value(')', 0)),
        value('', 0),
      );
      final wrapped = formatter.formatEditUpdate(
        const TextEditingValue(
          text: 'word',
          selection: TextSelection(baseOffset: 0, extentOffset: 4),
        ),
        value('"', 1),
      );
      expect(wrapped.text, '"word"');
      expect(
        wrapped.selection,
        const TextSelection(baseOffset: 1, extentOffset: 5),
      );
      final composing = TextEditingValue(
        text: '你',
        selection: const TextSelection.collapsed(offset: 1),
        composing: const TextRange(start: 0, end: 1),
      );
      expect(formatter.formatEditUpdate(value('', 0), composing), composing);
      for (final entry in {
        '- task': '- task\n- ',
        '8. step': '8. step\n9. ',
        '- [x] done': '- [x] done\n- [ ] ',
        '> quote': '> quote\n> ',
        '  code': '  code\n  ',
        '- ': '',
        '> ': '',
      }.entries) {
        final result = formatter.formatEditUpdate(
          value(entry.key, entry.key.length),
          value('${entry.key}\n', entry.key.length + 1),
        );
        expect(result.text, entry.value, reason: entry.key);
      }
      expect(
        const MarkdownInputFormatter(
          MarkdownPreferences(autoPair: false),
        ).formatEditUpdate(value('', 0), value('(', 1)).text,
        '(',
      );
      expect(
        formatter.formatEditUpdate(value('can', 3), value("can'", 4)).text,
        "can'",
      );
    },
  );

  test(
    'table editor round trips escaped pipes, alignment and selected table range',
    () {
      const source =
          '# Heading\n\n| Name | Value |\n| :--- | ---: |\n| a\\|b | 12 |\n\nAfter';
      final table = MarkdownTableData.around(source, source.indexOf('a\\|b'))!;
      expect(table.$3.rows[1][0], 'a|b');
      expect(table.$3.alignments, ['left', 'right']);
      expect(table.$3.toMarkdown(), contains(r'a\|b'));
      expect(
        source.replaceRange(
          table.$1,
          table.$2,
          table.$3.withColumn().withRow().toMarkdown(),
        ),
        endsWith('\n\nAfter'),
      );
    },
  );

  test(
    'workspace resolves aliases, links, tags and preserves unrelated YAML properties',
    () async {
      const content =
          '---\ntitle: Project\naliases: [项目]\ntags: [work, 研究]\ncustom: "keep" # comment\n---\n# Heading\n[[Reading|Read]] #inline\n';
      final note = MarkdownWorkspace.inspect('D:/notes/project.md', content);
      expect(note.tags, containsAll(['work', '研究', 'inline']));
      expect(note.links, ['Reading']);
      final reading = MarkdownWorkspace.inspect(
        'D:/notes/reading.md',
        '---\ntitle: Reading\n---\nText',
      );
      expect(
        MarkdownWorkspace.resolve(
          [note, reading],
          '项目',
          reading.path,
        ).single.path,
        note.path,
      );
      expect(
        MarkdownWorkspace.resolve(
          [note, reading],
          './reading#Chapter',
          note.path,
        ).single.path,
        reading.path,
      );
      final updated = MarkdownWorkspace.updateProperties(content, {
        'tags': ['new'],
        'status': 'done',
      });
      expect(updated, contains('custom: "keep" # comment'));
      expect(MarkdownWorkspace.properties(updated)['status'], 'done');
      expect(MarkdownWorkspace.properties(updated)['tags'], ['new']);
      expect(MarkdownWorkspace.plainBody(updated), startsWith('# Heading'));
    },
  );

  test(
    'history keeps changed revisions, survives rename, and autosave off cancels a queued write',
    () async {
      final temp = await Directory.systemTemp.createTemp('fastink-md-history-');
      final service = MarkdownEditorService()
        ..autoSaveEnabled = false
        ..history = MarkdownHistory('${temp.path}/history');
      try {
        final state = service.createNew(temp.path);
        service.updateContent('first');
        await service.save();
        service.updateContent('second');
        await service.save();
        final list = await service.history!.list(state.path);
        expect(list, hasLength(1));
        expect(await list.single.readAsString(), 'first');
        final renamed = await service.rename('renamed');
        expect(await service.history!.list(renamed!), hasLength(1));
        service.autoSaveDelayMs = 100;
        service.autoSaveEnabled = true;
        service.updateContent('pending');
        service.autoSaveEnabled = false;
        await Future<void>.delayed(const Duration(milliseconds: 180));
        expect(await File(renamed).readAsString(), 'second');
        expect(service.state!.isDirty, isTrue);
        service.autoSaveEnabled = true;
        await Future<void>.delayed(const Duration(milliseconds: 250));
        expect(await File(renamed).readAsString(), 'pending');
      } finally {
        service.dispose();
        await temp.delete(recursive: true);
      }
    },
  );

  test(
    'UTF-8, UTF-16, GBK, Big5 and Shift-JIS load without requiring an encoding plugin',
    () {
      expect(
        MarkdownEncoding.decode(Uint8List.fromList(utf8.encode('中文'))).$1,
        '中文',
      );
      expect(
        MarkdownEncoding.decode(
          Uint8List.fromList([255, 254, 45, 78, 135, 101]),
        ).$1,
        '中文',
      );
      expect(
        MarkdownEncoding.decode(
          Uint8List.fromList([0xd6, 0xd0, 0xce, 0xc4, 0xb2, 0xe2, 0xca, 0xd4]),
        ).$1,
        '中文测试',
      );
      expect(
        MarkdownEncoding.decode(
          Uint8List.fromList([0xa4, 0xa4, 0xa4, 0xe5]),
          encoding: 'big5',
        ).$1,
        '中文',
      );
      expect(
        MarkdownEncoding.decode(
          Uint8List.fromList([0x82, 0xa0]),
          encoding: 'shift-jis',
        ).$1,
        'あ',
      );
    },
  );

  test(
    'DOCX contains editable headings, formatted text, tables and local image relationships',
    () async {
      final temp = await Directory.systemTemp.createTemp('fastink-md-docx-');
      try {
        await File(
          '${temp.path}/image.png',
        ).writeAsBytes(raster.encodePng(raster.Image(width: 40, height: 20)));
        final bytes = await MarkdownDocumentExport.docx(
          '# 中文标题\n\n**Bold** and *italic*\n\n| A | B |\n| --- | --- |\n| 1 | 2 |\n\n![](image.png)',
          sourcePath: '${temp.path}/note.md',
        );
        final archive = ZipDecoder().decodeBytes(bytes);
        String text(String path) =>
            utf8.decode(archive.findFile(path)!.content);
        for (final entry in archive.files.where(
          (entry) =>
              entry.name.endsWith('.xml') || entry.name.endsWith('.rels'),
        )) {
          XmlDocument.parse(utf8.decode(entry.content));
        }
        expect(text('word/document.xml'), contains('中文标题'));
        expect(text('word/document.xml'), contains('Heading1'));
        expect(text('word/document.xml'), contains('<w:tbl>'));
        expect(text('word/document.xml'), contains('<w:b/>'));
        expect(archive.findFile('word/media/image1.png'), isNotNull);
        expect(
          MarkdownDocumentExport.plainText('# Title\n\n**body**'),
          contains('body'),
        );
      } finally {
        await temp.delete(recursive: true);
      }
    },
  );

  testWidgets(
    'editor settings immediately change source appearance, persist through theme input and are shared with settings',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final temp = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('fastink-md-preferences-ui-'),
      ))!;
      final repo = SettingsRepository(configRoot: '${temp.path}/config');
      await tester.pumpWidget(
        FastInkApp(
          settings: AppSettings(dataRoot: temp.path, language: 'zh'),
          settingsRepository: repo,
        ),
      );
      await drain(tester);
      await tester.tap(find.text('Markdown').first);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('新建或导入'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('新建 Markdown'));
      await drain(tester);
      await tester.tap(find.byTooltip('更多操作'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Markdown 设置'));
      await tester.pumpAndSettle();
      final toggle = tester.widget<SwitchListTile>(
        key('markdown-setting-autoPair'),
      );
      toggle.onChanged!(false);
      await tester.pump();
      tester
          .widget<SwitchListTile>(key('markdown-setting-lineNumbers'))
          .onChanged!(false);
      await tester.pump();
      await tester.tap(find.byTooltip('关闭').first);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<MarkdownSourceEditor>(find.byType(MarkdownSourceEditor))
            .preferences
            .autoPair,
        isFalse,
      );
      expect(
        tester
            .widget<MarkdownSourceEditor>(find.byType(MarkdownSourceEditor))
            .preferences
            .lineNumbers,
        isFalse,
      );
      await tester.tap(find.byTooltip('返回'));
      await drain(tester);
      for (int i = 0; i < 50; i++) {
        final saved = (await tester.runAsync(repo.load))!;
        if (!saved.markdown.autoPair && !saved.markdown.lineNumbers) break;
        await drain(tester);
      }
      expect((await tester.runAsync(repo.load))!.markdown.autoPair, isFalse);
      await tester.tap(find.text('设置').first);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('settings-category-markdown')),
      );
      await tester.pumpAndSettle();
      tester
          .widget<FastInkHome>(find.byType(FastInkHome))
          .onThemeModeChanged(ThemeMode.dark);
      await drain(tester);
      expect(
        tester
            .widget<MarkdownSettingsPanel>(find.byType(MarkdownSettingsPanel))
            .value
            .autoPair,
        isFalse,
      );

      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() => temp.delete(recursive: true));
    },
  );

  testWidgets(
    'Tab, image paste, table dialog and templates change native source; focus mode can exit',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final temp = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('fastink-md-workbench-ui-'),
      ))!;
      final png = Uint8List.fromList(
        raster.encodePng(raster.Image(width: 8, height: 8)),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: MarkdownEditorView(
            dataRoot: temp.path,
            darkMode: false,
            onExit: () {},
            onThemeToggle: () {},
            readClipboardImage: () async => png,
          ),
        ),
      );
      await drain(tester);
      await tester.enterText(key('markdown-source'), 'one\ntwo');
      final controller = tester
          .widget<TextField>(key('markdown-source'))
          .controller!;
      controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 7,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(controller.text, '  one\n  two');
      await Clipboard.setData(const ClipboardData(text: ''));
      debugPrint('Markdown interactions: paste');
      controller.selection = TextSelection.collapsed(
        offset: controller.text.length,
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await drain(tester);
      expect(controller.text, contains('assets/paste-'));
      debugPrint('Markdown interactions: table');
      await tester.tap(find.byTooltip('插入表格'));
      await tester.pumpAndSettle();
      await tester.enterText(key('markdown-cell-0-0'), 'Header');
      await tester.enterText(key('markdown-cell-1-0'), 'Value');
      await tester.tap(find.text('应用表格'));
      await tester.pumpAndSettle();
      expect(controller.text, contains('| Header |'));
      expect(controller.text, contains('| Value |'));
      debugPrint('Markdown interactions: templates');
      await tester.tap(find.byTooltip('更多操作'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('从模板插入'));
      await tester.tap(find.text('从模板插入'));
      await drain(tester);
      await tester.tap(find.text('会议记录'));
      await tester.pumpAndSettle();
      expect(controller.text, contains('## 决议与行动'));
      debugPrint('Markdown interactions: focus');
      await tester.tap(find.byTooltip('更多操作'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('专注写作'));
      await tester.tap(
        find
            .ancestor(
              of: find.text('专注写作'),
              matching: find.byWidgetPredicate(
                (widget) => widget is PopupMenuEntry,
              ),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('插入表格'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byTooltip('插入表格'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await drain(tester);
      await tester.runAsync(() => temp.delete(recursive: true));
    },
  );

  test(
    'bundled Mermaid renders flowchart and sequence offline inside its resource job',
    () async {
      final first = await MarkdownDiagrams.render(
        'flowchart LR\n A[开始] --> B{选择}\n B -->|是| C[完成]\n B -->|否| A',
        dark: false,
      );
      final pixels = raster.decodePng(await first.readAsBytes())!;
      expect(pixels.width, greaterThan(100));
      expect(pixels.height, greaterThan(50));
      expect(
        await MarkdownDiagrams.render(
          'flowchart LR\n A[开始] --> B{选择}\n B -->|是| C[完成]\n B -->|否| A',
          dark: false,
        ),
        first,
      );
      final sequence = await MarkdownDiagrams.render(
        'sequenceDiagram\n Alice->>Bob: Hello\n Bob-->>Alice: Ready',
        dark: true,
      );
      expect(await sequence.length(), greaterThan(1000));
    },
    timeout: const Timeout(Duration(seconds: 90)),
  );

  testWidgets(
    'live block editing and task toggles preserve unrelated Markdown source',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final temp = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('fastink-md-live-'),
      ))!;
      final file = File('${temp.path}/live.md');
      const original =
          '---\ntitle: Keep\ncustom: "value" # comment\n---\n# Heading\n\nParagraph original\n\n- [ ] task\n\n| A | B |\n| --- | --- |\n| 1 | 2 |\n';
      await tester.runAsync(() => file.writeAsString(original));
      await tester.pumpWidget(
        MaterialApp(
          home: MarkdownEditorView(
            filePath: file.path,
            dataRoot: temp.path,
            darkMode: false,
            onExit: () {},
            onThemeToggle: () {},
            preferences: const MarkdownPreferences(
              defaultMode: 'live',
              autoSave: false,
            ),
          ),
        ),
      );
      await drain(tester);
      expect(key('markdown-live-editor'), findsOneWidget);
      expect(key('markdown-source'), findsNothing);
      final source = tester
          .widget<TextField>(
            find.byKey(const ValueKey('markdown-source'), skipOffstage: false),
          )
          .controller!;
      await tester.tap(key('markdown-live-block-2'));
      await tester.pumpAndSettle();
      await tester.enterText(
        key('markdown-live-block-input'),
        'Paragraph **changed**',
      );
      await tester.tap(find.byTooltip('完成此段'));
      await tester.pumpAndSettle();
      expect(
        source.text,
        original.replaceFirst('Paragraph original', 'Paragraph **changed**'),
      );
      await tester.tap(find.byIcon(Icons.check_box_outline_blank));
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        source.text,
        contains('- [x] task'),
        reason:
            'Live input visible: ${key('markdown-live-block-input').evaluate().length}; checkbox widgets: ${find.byIcon(Icons.check_box_outline_blank).evaluate().length}',
      );
      expect(source.text, contains('custom: "value" # comment'));
      expect(source.text, contains('| 1 | 2 |'));
      await tester.tap(find.text('添加段落'));
      await tester.pumpAndSettle();
      await tester.enterText(
        key('markdown-live-block-input'),
        'Last paragraph',
      );
      expect(source.text, endsWith('Last paragraph'));
      expect(MarkdownLiveEditor.ranges(source.text).length, greaterThan(4));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await drain(tester);
      await tester.runAsync(() => temp.delete(recursive: true));
    },
  );

  testWidgets(
    'workspace search saves the current note and opens real document tabs',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final temp = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('fastink-md-tabs-'),
      ))!;
      final alpha = File('${temp.path}/Alpha.md'),
          beta = File('${temp.path}/Beta.md');
      final library = LibraryRepository(root: temp.path);
      await tester.runAsync(() async {
        await alpha.writeAsString('# Alpha\n[[Beta|Related]]');
        await beta.writeAsString('# Beta\nUnique needle');
        final now = DateTime.now();
        await library.save(
          LibraryState(
            documents: [
              for (final entry in {'a': alpha, 'b': beta}.entries)
                LibraryDocument(
                  id: 'md-${entry.key}',
                  title: entry.key,
                  sourcePath: entry.value.path,
                  coverPath: '',
                  pageCount: 1,
                  importedAt: now,
                  lastOpenedAt: now,
                ),
            ],
            folders: [],
          ),
        );
      });
      await tester.pumpWidget(
        FastInkApp(
          settings: AppSettings(dataRoot: temp.path, language: 'zh'),
          settingsRepository: SettingsRepository(
            configRoot: '${temp.path}/config',
          ),
        ),
      );
      await drain(tester);
      await tester.tap(find.text('Markdown').first);
      await tester.pumpAndSettle();
      await tester.tap(key('document-md-a'));
      await drain(tester);
      await tester.enterText(
        key('markdown-source'),
        '# Alpha changed\n[[Beta|Related]]',
      );
      await tester.tap(find.byTooltip('更多操作'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('全文搜索与标签'));
      await drain(tester);
      expect(key('markdown-workspace-search'), findsOneWidget);
      await tester.enterText(key('markdown-workspace-search'), 'Unique needle');
      await tester.pump();
      await tester.tap(find.widgetWithText(ListTile, 'Beta'));
      await drain(tester);
      for (
        int i = 0;
        i < 10 &&
            tester
                    .widget<MarkdownEditorView>(find.byType(MarkdownEditorView))
                    .filePath !=
                beta.path;
        i++
      ) {
        await drain(tester);
      }
      expect(
        tester
            .widget<MarkdownEditorView>(find.byType(MarkdownEditorView))
            .filePath,
        beta.path,
      );
      expect(find.byType(InputChip), findsNWidgets(2));
      await tester.tap(find.text('Beta.md').first);
      await tester.pumpAndSettle();
      final renameField = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(renameField, 'Beta-renamed');
      await tester.tap(find.widgetWithText(FilledButton, '确定'));
      await drain(tester);
      expect(find.widgetWithText(InputChip, 'Beta-renamed.md'), findsOneWidget);
      expect(find.widgetWithText(InputChip, 'Beta.md'), findsNothing);
      expect(
        await tester.runAsync(alpha.readAsString),
        '# Alpha changed\n[[Beta|Related]]',
      );
      await tester.tap(find.widgetWithText(InputChip, 'Alpha.md'));
      await drain(tester);
      expect(
        tester.widget<TextField>(key('markdown-source')).controller!.text,
        contains('Alpha changed'),
      );
      tester
          .widget<MarkdownEditorView>(find.byType(MarkdownEditorView))
          .onOpenMarkdown!(
        File('${temp.path}/Beta-renamed.md').absolute.uri.toString(),
      );
      await drain(tester);
      await tester.tap(find.byTooltip('保存'));
      await drain(tester);
      expect(find.byType(InputChip), findsNWidgets(2));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await drain(tester);
      await tester.runAsync(() => temp.delete(recursive: true));
    },
  );

  test('diagram fences ignore examples inside other code blocks', () {
    const source =
        '```markdown\n```mermaid\nnot-a-diagram\n```\n\n~~~mermaid\nflowchart LR\n A-->B\n~~~';
    final blocks = MarkdownDiagrams.blocks(source);
    expect(blocks, hasLength(1));
    expect(blocks.single.$3, contains('flowchart LR'));
  });

  test(
    'queued diagram edits are superseded before a browser is started',
    () async {
      const slot = 'test-edit-slot';
      const old = 'flowchart LR\n A[obsolete edit] --> B';
      final outdated = MarkdownDiagrams.render(old, dark: false, slot: slot);
      final caught = expectLater(
        outdated,
        throwsA(isA<MarkdownDiagramSuperseded>()),
      );
      MarkdownDiagrams.release(slot, old, false);
      await caught;
    },
  );

  testWidgets(
    'regex capture replacement, invalid expressions and live preview settings take effect',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final temp = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('fastink-md-regex-'),
      ))!;
      await tester.pumpWidget(
        MaterialApp(
          home: MarkdownEditorView(
            dataRoot: temp.path,
            darkMode: false,
            onExit: () {},
            onThemeToggle: () {},
            preferences: const MarkdownPreferences(autoSave: false),
          ),
        ),
      );
      await drain(tester);
      await tester.enterText(
        key('markdown-source'),
        'Task 12\nTask 34\n\n\$x\$',
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(Math), findsOneWidget);
      await tester.tap(find.byTooltip('查找 / 替换'));
      await tester.pump();
      await tester.enterText(key('markdown-find'), r'Task (\d+)');
      await tester.tap(find.byTooltip('正则表达式'));
      await tester.pump();
      await tester.enterText(key('markdown-replace'), r'Done $1');
      await tester.tap(find.text('全部替换'));
      await tester.pump();
      final controller = tester
          .widget<TextField>(key('markdown-source'))
          .controller!;
      expect(controller.text, contains('Done 12\nDone 34'));
      await tester.enterText(key('markdown-find'), '[');
      await tester.pump();
      expect(find.text('正则表达式无效'), findsOneWidget);
      await tester.tap(find.byTooltip('关闭查找'));
      await tester.pump();
      await tester.tap(find.byTooltip('更多操作'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Markdown 设置'));
      await tester.pumpAndSettle();
      final previewSettings = find.byKey(
        const PageStorageKey<String>('markdown-settings-preview'),
      );
      await tester.ensureVisible(previewSettings);
      await tester.tap(previewSettings);
      await tester.pumpAndSettle();
      tester
          .widget<SwitchListTile>(key('markdown-setting-mathEnabled'))
          .onChanged!(false);
      await tester.pump();
      await tester.tap(find.byTooltip('关闭').first);
      await tester.pumpAndSettle();
      expect(find.byType(Math), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await drain(tester);
      await tester.runAsync(() => temp.delete(recursive: true));
    },
  );
}
