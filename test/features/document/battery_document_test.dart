import 'dart:io';
import 'package:fastink_flutter/main.dart';
import 'package:fastink_flutter/src/widgets/embedded_image_layer.dart';
import 'package:fastink_flutter/src/core/app_settings.dart';
import 'package:fastink_flutter/src/engine/ink_canvas.dart';
import 'package:fastink_flutter/src/models/models.dart';
import 'package:fastink_flutter/src/platform/render_power_policy.dart';
import 'package:fastink_flutter/src/storage/library_repository.dart';
import 'package:fastink_flutter/src/storage/note_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as raster;
import 'window_usability_test.dart' show drainIO, waitForInk;

void main() {
  testWidgets(
    'power switching refreshes only display images and preserves editing history',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      RenderPowerMonitor.instance.value = const RenderPowerPolicy(
        onBattery: true,
      );
      final temp = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('fastink-battery-doc-'),
      ))!;
      final notes = NoteRepository(dataRoot: '${temp.path}/data');
      late NoteDocument doc;
      await tester.runAsync(() async {
        final file = File('${temp.path}/page.png');
        await file.writeAsBytes(
          raster.encodePng(raster.Image(width: 1800, height: 2600)),
        );
        doc = await notes.importImages([file], onProgress: (_) {});
        final asset = await notes.importEmbeddedImage(doc, file);
        await notes.savePageInk(
          doc,
          doc.pages.first,
          PageInk(
            strokes: [
              InkStroke(
                color: 0xff000000,
                width: .002,
                kind: StrokeKind.image,
                imageAsset: asset,
                points: const [
                  InkPoint(.1, .1, 1),
                  InkPoint(.4, .1, 1),
                  InkPoint(.4, .4, 1),
                  InkPoint(.1, .4, 1),
                ],
              ),
            ],
          ),
        );
        final now = DateTime.utc(2026);
        await LibraryRepository(root: notes.dataRoot).save(
          LibraryState(
            documents: [
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
          FastInkApp(
            settings: AppSettings(
              dataRoot: notes.dataRoot,
              language: 'en',
              autoSaveEnabled: false,
              openSidebarByDefault: false,
            ),
          ),
        );
      });
      await drainIO(tester);
      await tester.tap(find.byKey(ValueKey('document-${doc.id}')));
      await waitForInk(tester);
      final pageSize = tester.getSize(find.byType(InkLayer).first);
      expect(pageSize.width / pageSize.height, closeTo(1800 / 2600, 1e-8));
      final controller = tester
          .widget<InkLayer>(find.byType(InkLayer).first)
          .controller;
      controller.begin(
        const InkPoint(.2, .8, .3),
        Colors.blue,
        .002,
        StrokeKind.pen,
      );
      controller.append(const InkPoint(.3, .8, .8));
      controller.finish();
      await tester.pump();
      expect(controller.canUndo, isTrue);
      final written = controller.strokes.last;
      final camera = tester
          .widgetList<AnimatedBuilder>(find.byType(AnimatedBuilder))
          .map((w) => w.animation)
          .whereType<TransformationController>()
          .first;
      final beforeCamera = List<double>.of(camera.value.storage);

      // 包括快速反复插拔：过期解码不能覆盖当前策略，不能重载笔迹清空历史。
      for (final battery in [false, true, false, true]) {
        RenderPowerMonitor.instance.value = RenderPowerPolicy(
          onBattery: battery,
        );
        await tester.pump();
      }
      for (var i = 0; i < 30; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 25)),
        );
        await tester.pump(const Duration(milliseconds: 30));
      }
      final embedded = tester.widget<EmbeddedImageLayer>(
        find.byType(EmbeddedImageLayer).first,
      );
      expect((embedded.cacheWidth, embedded.cacheHeight), (1600, 2400));
      expect(embedded.filterQuality, FilterQuality.low);
      expect(
        tester.widget<InkLayer>(find.byType(InkLayer).first).controller,
        same(controller),
      );
      expect(controller.strokes.last, same(written));
      expect(controller.canUndo, isTrue);
      expect(camera.value.storage, orderedEquals(beforeCamera));
      final imageWidths = tester
          .widgetList<RawImage>(find.byType(RawImage))
          .where((w) => w.image != null)
          .map((w) => w.image!.width)
          .toList();
      expect(imageWidths, contains(1600));
      expect(imageWidths.every((w) => w <= 1600), isTrue);
      controller.undo();
      expect(controller.strokes.length, 1);
      expect(controller.strokes.single.kind, StrokeKind.image);
      controller.redo();
      expect(controller.strokes.last.points.last.pressure, .8);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
      RenderPowerMonitor.instance.value = const RenderPowerPolicy();
      await tester.runAsync(() => temp.delete(recursive: true));
    },
  );
}
