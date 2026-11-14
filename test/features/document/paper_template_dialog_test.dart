import 'dart:io';
import 'dart:ui' as ui;
import 'package:fastink_flutter/src/core/app_localizations.dart';
import 'package:fastink_flutter/src/models/paper_template.dart';
import 'package:fastink_flutter/src/widgets/paper_template_dialog.dart';
import 'package:fastink_flutter/src/widgets/paper_template_preview.dart';
import 'package:flutter/material.dart';
import 'package:fastink_flutter/src/storage/template_library.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() async {
    // Actual system fonts make the captured UI useful for visual review.
    final font = File('C:/Windows/Fonts/msyh.ttc');
    if (await font.exists()) {
      final loader = FontLoader('PreviewTest');
      loader.addFont(
        font.readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
      );
      await loader.load();
      final canvasFont = FontLoader('sans-serif');
      canvasFont.addFont(
        font.readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
      );
      await canvasFont.load();
    }
    final icons = File(
      'D:/ComputerProgram/path/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
    if (await icons.exists()) {
      final loader = FontLoader('MaterialIcons');
      loader.addFont(
        icons.readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
      );
      await loader.load();
    }
  });

  testWidgets('categories filter cards; preview stays visible and enlarges', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    AppText.locale = const Locale('zh');
    final capture = GlobalKey();
    PaperTemplateSelection? selection;
    await tester.pumpWidget(
      RepaintBoundary(
        key: capture,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            useMaterial3: true,
            fontFamily: 'PreviewTest',
            dialogTheme: const DialogThemeData(
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.transparent,
            ),
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xff5965df),
            ),
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () async {
                    selection = await showDialog<PaperTemplateSelection>(
                      context: context,
                      builder: (_) => PaperTemplateDialog(
                        creating: true,
                        library: _PreviewTemplateLibrary(),
                      ),
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('paper-grid')), findsOneWidget);
    expect(find.byKey(const ValueKey('paper-monthly')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('paper-category-planning')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('paper-grid')), findsNothing);
    final monthly = find.byKey(const ValueKey('paper-monthly'));
    await tester.ensureVisible(monthly);
    await tester.tap(monthly);
    await tester.pumpAndSettle();
    final preview = find.byKey(const ValueKey('paper-preview-panel'));
    final before = tester.getRect(preview);
    final panel = tester.widget<PaperTemplatePreviewPanel>(
      find.byType(PaperTemplatePreviewPanel),
    );
    expect(panel.template.pattern, PaperPattern.monthly);
    await _capture(tester, capture, 'landscape');
    final color = find.byKey(const ValueKey('paper-color-3'));
    await tester.ensureVisible(color);
    await tester.tap(color);
    await tester.pumpAndSettle();
    expect(tester.getRect(preview), before);
    expect(
      tester
          .widget<PaperTemplatePreviewPanel>(
            find.byType(PaperTemplatePreviewPanel),
          )
          .template
          .color,
      const Color(0xffeaf2ff),
    );
    await tester.tap(find.byKey(const ValueKey('paper-preview-enlarge')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('paper-preview-zoom')), findsOneWidget);
    await _capture(tester, capture, 'enlarged');
    await tester.tap(find.byKey(const ValueKey('paper-preview-close')));
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(800, 1280);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<PaperTemplatePreviewPanel>(
            find.byType(PaperTemplatePreviewPanel),
          )
          .compact,
      isTrue,
    );
    expect(tester.getRect(preview).top, greaterThan(0));
    await _capture(tester, capture, 'portrait');
    // Filtering must retain the selected paper and all its settings.
    await tester.tap(find.byKey(const ValueKey('paper-category-basic')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<PaperTemplatePreviewPanel>(
            find.byType(PaperTemplatePreviewPanel),
          )
          .template
          .pattern,
      PaperPattern.monthly,
    );
    // Keyboard should leave the name field and confirmation accessible.
    tester.view.viewInsets = const FakeViewPadding(bottom: 420);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    tester.view.resetViewInsets();
    await tester.pumpAndSettle();
    for (final size in <Size>[Size(960, 600), Size(600, 960)]) {
      tester.view.physicalSize = size;
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const ValueKey('paper-template-submit')).hitTestable(),
        findsOneWidget,
      );
    }
    await tester.tap(find.byKey(const ValueKey('paper-template-submit')));
    await tester.pumpAndSettle();
    expect(selection!.template.pattern, PaperPattern.monthly);
    expect(selection!.template.color, const Color(0xffeaf2ff));
    expect(tester.takeException(), isNull);
  });

  test(
    'small previews keep patterns visible without darkening saved paper',
    () async {
      for (final pattern in <PaperPattern>[
        PaperPattern.ruled,
        PaperPattern.grid,
        PaperPattern.dotted,
        PaperPattern.music,
      ]) {
        final counts = <int>[];
        for (final mode in <PaperRenderMode>[
          PaperRenderMode.page,
          PaperRenderMode.thumbnail,
        ]) {
          final recorder = ui.PictureRecorder();
          paintPaperTemplate(
            ui.Canvas(recorder),
            const Size(76, 108),
            PaperTemplate(pattern: pattern),
            mode: mode,
          );
          final picture = recorder.endRecording();
          final image = await picture.toImage(76, 108);
          final bytes = (await image.toByteData())!.buffer.asUint8List();
          int visible = 0;
          for (int i = 0; i < bytes.length; i += 4) {
            if (bytes[i] < 220 && bytes[i + 1] < 220 && bytes[i + 2] < 220) {
              visible++;
            }
          }
          counts.add(visible);
          image.dispose();
          picture.dispose();
        }
        expect(
          counts[1],
          greaterThan(150),
          reason: '${pattern.name} must be visible',
        );
        expect(
          counts[1],
          greaterThan(counts[0]),
          reason: 'preview must compensate for subpixel guides',
        );
      }
    },
  );
}

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('build/diagnostics/template-picker-$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

class _PreviewTemplateLibrary extends TemplateLibrary {
  _PreviewTemplateLibrary() : super('');
  @override
  Future<List<PaperTemplate>> load() async => const [];
}
