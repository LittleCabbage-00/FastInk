import 'dart:io';
import 'dart:ui' as ui;

import 'package:fastink_flutter/main.dart';
import 'package:fastink_flutter/src/features/markdown/markdown_editor.dart';
import 'package:fastink_flutter/src/core/app_localizations.dart';
import 'package:fastink_flutter/src/core/settings_repository.dart';
import 'package:fastink_flutter/src/platform/markdown_editor_service.dart';
import 'package:fastink_flutter/src/platform/markdown_render_export.dart';
import 'package:fastink_flutter/src/storage/library_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as raster;

Finder key(String value) => find.byKey(ValueKey(value));

Future<void> drain(WidgetTester tester) async {
  for (var i = 0; i < 15; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 15)),
    );
    await tester.pump(const Duration(milliseconds: 25));
  }
}

void main() {
  setUpAll(() async {
    for (final entry in {
      'Roboto': r'C:\Windows\Fonts\segoeui.ttf',
      'Microsoft YaHei UI': r'C:\Windows\Fonts\msyh.ttc',
      'Consolas': r'C:\Windows\Fonts\consola.ttf',
      'packages/flutter_math_fork/KaTeX_Main':
          'D:/ComputerProgram/path/flutter/pub-cache/hosted/pub.dev/flutter_math_fork-0.7.4/lib/katex_fonts/fonts/KaTeX_Main-Regular.ttf',
      'packages/flutter_math_fork/KaTeX_Math':
          'D:/ComputerProgram/path/flutter/pub-cache/hosted/pub.dev/flutter_math_fork-0.7.4/lib/katex_fonts/fonts/KaTeX_Math-Italic.ttf',
      'MaterialIcons':
          'D:/ComputerProgram/path/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    }.entries) {
      if (await File(entry.value).exists()) {
        await (FontLoader(entry.key)..addFont(
              Future.value(
                ByteData.sublistView(await File(entry.value).readAsBytes()),
              ),
            ))
            .load();
      }
    }
  });
  setUp(() => AppText.locale = const Locale('zh'));

  test('outline ignores fenced code, supports setext and closing hashes', () {
    const content =
        '# Chapter ###\n```md\n# not a heading\n```\nSection\n---\n~~~\n## neither\n~~~\n### End';
    final toc = MarkdownEditorService.extractToc(content);
    expect(toc.map((item) => item.title), ['Chapter', 'Section', 'End']);
    expect(toc.map((item) => item.level), [1, 2, 3]);
    expect(toc.last.offset, content.indexOf('### End'));
  });

  test(
    'autosave serializes writes and preserves edits made during saving',
    () async {
      final temp = await Directory.systemTemp.createTemp('fastink-md-save-');
      final service = MarkdownEditorService()..autoSaveEnabled = false;
      try {
        final state = service.createNew(temp.path);
        service.updateContent('before');
        final first = service.save();
        service.updateContent('during');
        expect(await first, isTrue);
        expect(state.isDirty, isTrue);
        expect(state.lastSavedContent, 'before');
        final second = service.save();
        service.updateContent('latest');
        final third = service.save();
        expect(await second, isTrue);
        expect(await third, isTrue);
        expect(await File(state.path).readAsString(), 'latest');
        expect(state.isDirty, isFalse);
        expect(await service.rename('../unsafe'), isNull);
        final existing = File('${File(state.path).parent.path}/existing.md');
        await existing.writeAsString('keep');
        expect(await service.rename('existing'), isNull);
        expect(await existing.readAsString(), 'keep');
      } finally {
        service.dispose();
        await temp.delete(recursive: true);
      }
    },
  );

  test(
    'opened plain files accept image assets; external temp names cannot collide',
    () async {
      final temp = await Directory.systemTemp.createTemp('fastink-md-assets-');
      final first = MarkdownEditorService();
      final second = MarkdownEditorService();
      try {
        final a = await Directory('${temp.path}/a').create();
        final b = await Directory('${temp.path}/b').create();
        final fileA = File('${a.path}/same.md');
        final fileB = File('${b.path}/same.md');
        await fileA.writeAsString('a');
        await fileB.writeAsString('b');
        final sa = await first.openExternalAsTemp(fileA.path);
        final sb = await second.openExternalAsTemp(fileB.path);
        expect(sa.path, isNot(sb.path));
        expect(sa.content, 'a');
        expect(sb.content, 'b');
        final library = await Directory('${temp.path}/library').create();
        await File('${library.path}/same.md').writeAsString('existing');
        final imported = await first.importToLibrary(library.path);
        expect(imported, endsWith('same-2.md'));
        expect(
          await File('${library.path}/same.md').readAsString(),
          'existing',
        );
        await second.openFile(imported!);
        final image = File('${temp.path}/sample.png');
        await image.writeAsBytes(
          raster.encodePng(raster.Image(width: 4, height: 4)),
        );
        expect(await second.insertImage(image), 'assets/sample.png');
        expect(
          await File('${library.path}/assets/sample.png').exists(),
          isTrue,
        );
      } finally {
        first.dispose();
        second.dispose();
        await temp.delete(recursive: true);
      }
    },
  );

  testWidgets(
    'formatting targets selected lines, find replace is literal, undo works; narrow layout fits',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final temp = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('fastink-md-ui-'),
      ))!;
      await tester.pumpWidget(
        MaterialApp(
          home: MarkdownEditorView(
            dataRoot: temp.path,
            darkMode: false,
            onExit: () {},
            onThemeToggle: () {},
          ),
        ),
      );
      await drain(tester);
      await tester.enterText(key('markdown-source'), 'one\ntwo\nlast');
      final source = tester
          .widget<TextField>(key('markdown-source'))
          .controller!;
      source.selection = const TextSelection(baseOffset: 0, extentOffset: 7);
      await tester.tap(find.byTooltip('无序列表'));
      await tester.pump();
      expect(source.text, '- one\n- two\nlast');
      await tester.enterText(key('markdown-source'), 'a.* A.* a.*');
      await tester.pump(const Duration(milliseconds: 600));
      await tester.tap(find.byTooltip('查找 / 替换'));
      await tester.pump();
      await tester.enterText(key('markdown-find'), 'a.*');
      await tester.enterText(key('markdown-replace'), r'$1');
      await tester.tap(find.text('全部替换'));
      await tester.pump();
      expect(source.text, r'$1 $1 $1');
      await tester.pump(const Duration(milliseconds: 600));
      final undo = tester
          .widget<TextField>(key('markdown-source'))
          .undoController!;
      expect(undo.value.canUndo, isTrue);
      undo.undo();
      await tester.pump();
      expect(source.text, isNot(r'$1 $1 $1'));
      tester.view.physicalSize = const Size(640, 640);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('关闭查找'));
      await tester.pump();
      await tester.tap(find.byTooltip('编辑 / 分栏 / 阅读'));
      await tester.pumpAndSettle();
      await tester.tap(
        find
            .ancestor(
              of: find.text('仅阅读'),
              matching: find.byWidgetPredicate(
                (widget) => widget is PopupMenuEntry,
              ),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(key('markdown-source'), findsNothing);
      expect(key('markdown-preview'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() => temp.delete(recursive: true));
    },
  );

  testWidgets(
    'preview shows local images, tasks and outline jumps to rendered heading',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final temp = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('fastink-md-preview-'),
      ))!;
      final file = File('${temp.path}/memo.md');
      await tester.runAsync(() async {
        await File(
          '${temp.path}/sample.png',
        ).writeAsBytes(raster.encodePng(raster.Image(width: 80, height: 50)));
        await file.writeAsString(
          '# Start\n\n![](sample.png)\n\n- [x] done\n\n${List.filled(60, 'Paragraph\n').join('\n')}\n## End\nLast',
        );
      });
      await tester.pumpWidget(
        MaterialApp(
          home: MarkdownEditorView(
            filePath: file.path,
            dataRoot: temp.path,
            darkMode: false,
            onExit: () {},
            onThemeToggle: () {},
          ),
        ),
      );
      await drain(tester);
      expect(find.byType(Image), findsOneWidget);
      expect(find.byIcon(Icons.check_box_outlined), findsOneWidget);
      await tester.tap(find.byIcon(Icons.check_box_outlined));
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        tester.widget<TextField>(key('markdown-source')).controller!.text,
        contains('- [ ] done'),
      );
      await tester.tap(find.byTooltip('目录'));
      await tester.pump();
      await tester.tap(find.widgetWithText(ListTile, 'End'));
      await tester.pumpAndSettle();
      final scroll = tester
          .widget<SingleChildScrollView>(key('markdown-preview'))
          .controller!;
      expect(scroll.offset, greaterThan(800));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() => temp.delete(recursive: true));
    },
  );

  testWidgets(
    'raster PDF and long images include content below the screen; JPEG really is JPEG',
    (tester) async {
      final temp = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('fastink-md-export-'),
      ))!;
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: Stack(
            children: [
              Positioned(
                left: 0,
                top: 0,
                width: 794,
                child: MarkdownExportBoundary(
                  key: boundaryKey,
                  child: Column(
                    children: [
                      Container(height: 1300, color: Colors.white),
                      Container(height: 300, color: Color(0xffff0000)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      await tester.pump();
      final boundary =
          boundaryKey.currentContext!.findRenderObject()!
              as MarkdownExportRenderBoundary;
      final counts = <int>[];
      await tester.runAsync(() async {
        for (final format in ['png', 'jpg', 'pdf']) {
          final target = File('${temp.path}/export.$format');
          await MarkdownRenderExport.write(
            boundary: boundary,
            target: target,
            format: format,
            onProgress: (done, total) {
              if (done == total) counts.add(total);
            },
          );
          final bytes = await target.readAsBytes();
          if (format == 'pdf') {
            expect(String.fromCharCodes(bytes.take(4)), '%PDF');
          } else {
            final decoded = raster.decodeImage(bytes)!;
            expect(decoded.height, greaterThan(1600));
            expect(
              decoded.getPixel(10, decoded.height - 10).r,
              greaterThan(240),
            );
            expect(decoded.getPixel(10, decoded.height - 10).g, lessThan(20));
            if (format == 'jpg') expect(bytes.take(2), [255, 216]);
          }
        }
      });
      expect(counts, [1, 1, 2]);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() => temp.delete(recursive: true));
    },
  );

  for (final width in [1280.0, 640.0]) {
    testWidgets(
      'trash has no create/import at width $width, normal library retains it',
      (tester) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final temp = (await tester.runAsync(
          () => Directory.systemTemp.createTemp('fastink-trash-ui-'),
        ))!;
        final settings = SettingsRepository(configRoot: '${temp.path}/config');
        await tester.pumpWidget(
          FastInkApp(
            settings: AppSettings(dataRoot: temp.path, language: 'zh'),
            settingsRepository: settings,
          ),
        );
        await drain(tester);
        if (width < 900) {
          await tester.tap(find.byTooltip('打开资料库导航'));
          await tester.pumpAndSettle();
        }
        await tester.tap(find.text('废纸篓').first);
        await tester.pumpAndSettle();
        expect(find.byTooltip('新建或导入'), findsNothing);
        expect(find.byIcon(Icons.delete_forever_outlined), findsWidgets);
        if (width < 900) {
          await tester.tap(find.byTooltip('打开资料库导航'));
          await tester.pumpAndSettle();
        }
        await tester.tap(find.text('文稿').first);
        await tester.pumpAndSettle();
        expect(find.byTooltip('新建或导入'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(() => temp.delete(recursive: true));
      },
    );
  }

  testWidgets(
    'external edits save to original on exit and never register the temp copy',
    (tester) async {
      final temp = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('fastink-md-external-'),
      ))!;
      final source = File('${temp.path}/original.md');
      await tester.runAsync(() => source.writeAsString('original'));
      var exited = false;
      final registered = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: MarkdownEditorView(
            externalSourcePath: source.path,
            dataRoot: temp.path,
            darkMode: false,
            onExit: () => exited = true,
            onThemeToggle: () {},
            onFileSaved: registered.add,
          ),
        ),
      );
      await drain(tester);
      await tester.tap(find.text('编辑原文件'));
      await tester.pump();
      await tester.enterText(key('markdown-source'), '# Edited original');
      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await drain(tester);
      for (int attempt = 0; attempt < 30 && !exited; attempt++) {
        await drain(tester);
      }
      expect(exited, isTrue);
      expect(registered, isEmpty);
      expect(await tester.runAsync(source.readAsString), '# Edited original');
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() => temp.delete(recursive: true));
    },
  );

  testWidgets(
    'renaming Markdown inside editor retains library identity, folder and favorite',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final temp = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('fastink-md-rename-'),
      ))!;
      final file = File('${temp.path}/before.md');
      final library = LibraryRepository(root: temp.path);
      await tester.runAsync(() async {
        await file.writeAsString('# Heading');
        await library.save(
          LibraryState(
            documents: [
              LibraryDocument(
                id: 'md-retained',
                title: 'before',
                sourcePath: file.path,
                coverPath: '',
                pageCount: 1,
                importedAt: DateTime.utc(2026),
                lastOpenedAt: DateTime.utc(2026),
                folderId: 'folder',
                favorite: true,
              ),
            ],
            folders: [
              LibraryFolder(
                id: 'folder',
                name: 'Markdown Folder',
                createdAt: DateTime.utc(2026),
                scope: LibraryScope.markdown,
              ),
            ],
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
      await tester.tap(key('folder-folder'));
      await tester.pumpAndSettle();
      await tester.tap(key('document-md-retained'));
      await drain(tester);
      await tester.tap(find.text('before.md'));
      await tester.pumpAndSettle();
      final nameField = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(nameField, 'after');
      await tester.tap(find.widgetWithText(FilledButton, '确定'));
      await drain(tester);
      await tester.tap(find.byTooltip('返回'));
      await drain(tester);
      final saved = (await tester.runAsync(library.load))!;
      expect(saved.documents, hasLength(1));
      expect(saved.documents.single.id, 'md-retained');
      expect(saved.documents.single.folderId, 'folder');
      expect(saved.documents.single.favorite, isTrue);
      expect(saved.documents.single.title, 'after');
      expect(saved.documents.single.sourcePath, endsWith('after.md'));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() => temp.delete(recursive: true));
    },
  );

  testWidgets(
    'Markdown menu exports rendered document with progress and portable local image references',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final temp = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('fastink-md-export-menu-'),
      ))!;
      final source = File('${temp.path}/source.md');
      final out = Directory('${temp.path}/output');
      await tester.runAsync(() async {
        await out.create();
        await File(
          '${temp.path}/picture.png',
        ).writeAsBytes(raster.encodePng(raster.Image(width: 20, height: 20)));
        await source.writeAsString(
          '# Markdown 工作台\n\n## 记录与计划\n\n- [x] 完成的事项\n- [ ] 下一步计划\n\n> 支持文字、公式和图片\n\n| 名称 | 数量 |\n| --- | --- |\n| 笔记 | 12 |\n\n行内公式：\$x^2 + y^2\$\n\n![](picture.png)\n\n```dart\nfinal message = "Hello FastInk";\n```',
        );
      });
      final screenshotKey = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            fontFamily: 'Microsoft YaHei UI',
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xff595a99),
              surface: const Color(0xfffbfbfd),
            ),
          ),
          home: RepaintBoundary(
            key: screenshotKey,
            child: MarkdownEditorView(
              filePath: source.path,
              dataRoot: temp.path,
              darkMode: false,
              onExit: () {},
              onThemeToggle: () {},
              pickExportDestination: (format) async =>
                  File('${out.path}/note.$format'),
            ),
          ),
        ),
      );
      await drain(tester);
      if (Platform.environment['FASTINK_UI_PREVIEW'] == '1') {
        final boundary =
            screenshotKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          try {
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File(
              'build/diagnostics/ui-markdown1218.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
          } finally {
            image.dispose();
          }
        });
      }
      for (final entry in {
        'png': '导出 PNG 长图',
        'pdf': '导出 PDF',
        'md': '导出 Markdown 源文件',
      }.entries) {
        await tester.tap(find.byTooltip('导出'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(entry.value));
        await tester.pump();
        bool finished = false;
        for (int i = 0; i < 150; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump(const Duration(milliseconds: 25));
          finished = (await tester.runAsync(
            () => File('${out.path}/note.${entry.key}').exists(),
          ))!;
          if (finished &&
              find.byType(AlertDialog).evaluate().isEmpty &&
              find.byType(LinearProgressIndicator).evaluate().isEmpty) {
            break;
          }
        }
        expect(
          finished,
          isTrue,
          reason:
              '${entry.key}: ${tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).join(' | ')}',
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      await tester.runAsync(() async {
        final exported = await File('${out.path}/note.md').readAsString();
        final ref = RegExp(r'!\[\]\(<([^>]+)>\)').firstMatch(exported)!;
        expect(await File('${out.path}/${ref.group(1)}').exists(), isTrue);
        final png = raster.decodePng(
          await File('${out.path}/note.png').readAsBytes(),
        )!;
        expect(png.width, 1191);
        expect(png.height, greaterThan(500));
        expect(await source.readAsString(), contains('![](picture.png)'));
      });
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() => temp.delete(recursive: true));
    },
  );
}
