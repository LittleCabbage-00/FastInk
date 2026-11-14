import 'dart:io';
import 'package:fastink_flutter/main.dart';
import 'package:fastink_flutter/src/core/app_settings.dart';
import 'package:fastink_flutter/src/core/app_localizations.dart';
import 'package:fastink_flutter/src/models/paper_template.dart';
import 'package:image/image.dart' as raster;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('tablet opens a notebook without overflowing navigation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final Directory folder = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('fastink_mobile_layout_'),
    ))!;
    final File image = File('${folder.path}/Phone.png');
    await tester.runAsync(
      () => image.writeAsBytes(
        raster.encodePng(raster.Image(width: 200, height: 280)),
      ),
    );
    final previousHandler = FlutterError.onError!;
    FlutterError.onError = (details) {
      debugPrint(details.toString());
      previousHandler(details);
    };
    addTearDown(() => FlutterError.onError = previousHandler);
    await tester.runAsync(() async {
      await tester.pumpWidget(
        FastInkApp(
          settings: AppSettings(
            dataRoot: folder.path,
            language: 'en',
            showPerformance: false,
          ),
          initialPath: image.path,
        ),
      );
    });
    for (int i = 0; i < 80; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(milliseconds: 100));
      if (find
          .byTooltip(RegExp('搜索本文稿|Search this document'))
          .evaluate()
          .isNotEmpty) {
        break;
      }
    }
    expect(tester.takeException(), isNull);
    expect(
      find.byTooltip(RegExp('搜索本文稿|Search this document')),
      findsOneWidget,
    );
    tester.view.physicalSize = const Size(800, 1280);
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);
    await tester.tap(find.byIcon(Icons.arrow_back_rounded).first);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byTooltip(tr('新建或导入')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byWidgetPredicate(
        (widget) => widget is PopupMenuItem<String> && widget.value == 'note',
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('paper-category-planning')));
    await tester.pump();
    final monthly = find.byKey(const ValueKey<String>('paper-monthly'));
    expect(monthly, findsOneWidget);
    await tester.ensureVisible(monthly);
    await tester.tap(monthly);
    await tester.pump();
    final painters = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((widget) => widget.painter)
        .whereType<PaperTemplatePainter>();
    expect(
      painters
          .where((painter) => painter.template.pattern == PaperPattern.monthly)
          .length,
      2,
    );
    expect(tester.takeException(), isNull);
    await tester.tap(find.text(tr('取消')));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      imageCache.clear();
      imageCache.clearLiveImages();
      for (int attempt = 0; attempt < 5; attempt++) {
        try {
          await folder.delete(recursive: true);
          break;
        } on FileSystemException {
          // Windows image decoders and virus scanners may hold temp files
          // briefly after the widget is disposed; cleanup is best effort.
          await Future<void>.delayed(const Duration(milliseconds: 300));
        }
      }
    });
  });
}
