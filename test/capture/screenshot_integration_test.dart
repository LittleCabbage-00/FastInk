import 'dart:io';
import 'package:fastink_flutter/main.dart';
import 'package:fastink_flutter/src/capture/screenshot_document.dart';
import 'package:fastink_flutter/src/capture/screenshot_editor.dart';
import 'package:fastink_flutter/src/core/app_settings.dart';
import 'package:fastink_flutter/src/engine/ink_canvas.dart';
import 'package:fastink_flutter/src/models/models.dart';
import 'package:fastink_flutter/src/storage/note_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as raster;

void main() {
  testWidgets(
    'fullscreen note capture inserts an independent annotated crop and preserves existing ink',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final temp = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('fastink_capture_flow_'),
      ))!;
      final repo = NoteRepository(dataRoot: '${temp.path}/data');
      final doc = (await tester.runAsync(() async {
        final file = File('${temp.path}/page.png');
        await file.writeAsBytes(
          raster.encodePng(
            raster.Image(width: 240, height: 320)
              ..clear(raster.ColorRgb8(240, 240, 240)),
          ),
        );
        final doc = await repo.importImages([file], onProgress: (_) {});
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
              swapPenButtons: true,
            ),
            initialPath: doc.pages.first.path,
          ),
        ),
      );
      Future<void> drain(bool Function() ready) async {
        for (var i = 0; i < 120; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)),
          );
          await tester.pump(const Duration(milliseconds: 50));
          if (ready()) return;
        }
        fail('Capture flow did not complete');
      }

      await drain(() => find.byType(InkLayer).evaluate().isNotEmpty);
      final controller = tester
          .widget<InkLayer>(find.byType(InkLayer).first)
          .controller;
      final before = controller.strokes.single.toJson();
      final toolBefore = tester
          .widget<InkLayer>(find.byType(InkLayer).first)
          .tool;
      final momentaryBefore = tester
          .widget<InkLayer>(find.byType(InkLayer).first)
          .momentaryTool;
      final eraserBefore = tester
          .widget<InkLayer>(find.byType(InkLayer).first)
          .eraserMode;
      await tester.tap(find.byKey(const ValueKey('enter-fullscreen')));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const ValueKey('screenshot-menu')));
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => tester.tap(find.text('Capture note / PDF region')),
      );
      await drain(() => find.byType(ScreenshotEditor).evaluate().isNotEmpty);
      final capture = tester
          .widget<ScreenshotEditor>(find.byType(ScreenshotEditor))
          .document;
      final captureWidget = tester.widget<ScreenshotEditor>(
        find.byType(ScreenshotEditor),
      );
      expect(
        captureWidget.penButtons[kSecondaryStylusButton]!.tool,
        InkTool.lasso,
      );
      expect(
        captureWidget.penButtons[kPrimaryStylusButton]!.tool,
        InkTool.eraser,
      );
      expect(
        captureWidget.penButtons[kPrimaryStylusButton]!.eraser,
        EraserMode.point,
      );
      for (final pressed in [true, false]) {
        await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
          'fastink/pen',
          const StandardMethodCodec().encodeMethodCall(
            MethodCall('button', {
              'button': 1,
              'pressed': pressed,
              'source': 'windows-ink',
            }),
          ),
          (_) {},
        );
        await tester.pump();
        expect(
          captureWidget.nativePenButtons!.value & kPrimaryStylusButton != 0,
          pressed,
        );
        final underlying = tester.widget<InkLayer>(find.byType(InkLayer).first);
        expect(underlying.momentaryTool, momentaryBefore);
        expect(underlying.eraserMode, eraserBefore);
      }
      expect(
        tester.widget<InkLayer>(find.byType(InkLayer).first).tool,
        toolBefore,
      );
      capture.checkpoint();
      capture.crop = const Rect.fromLTRB(24, 32, 192, 256);
      capture.add(
        const CaptureMark(
          tool: CaptureTool.rectangle,
          points: [Offset(40, 60), Offset(140, 150)],
          color: Colors.red,
          width: 4,
        ),
      );
      await tester.pump();
      await tester.runAsync(
        () => tester.tap(
          find.byKey(const ValueKey('capture-insert')),
          kind: PointerDeviceKind.stylus,
        ),
      );
      await drain(
        () =>
            controller.strokes.length == 2 &&
            find.byType(ScreenshotEditor).evaluate().isEmpty,
      );
      await drain(
        () => find
            .text('Screenshot inserted; move, resize or rotate it')
            .evaluate()
            .isNotEmpty,
      );
      expect(controller.strokes.first.toJson(), before);
      final inserted = controller.strokes.last;
      expect(inserted.kind, StrokeKind.image);
      expect(controller.selectedStrokes, contains(inserted));
      expect(find.byKey(const ValueKey('immersive-toolbar')), findsOneWidget);
      final asset = File(
        repo.resolveEmbeddedImagePath(doc, inserted.imageAsset!),
      );
      final saved = (await tester.runAsync(() async {
        final png = raster.decodePng(await asset.readAsBytes())!;
        expect(png.width, 168);
        expect(png.height, 224);
        expect(png.getPixel(16, 28).r, greaterThan(240));
        return repo.loadPageInk(doc, doc.pages.first);
      }))!;
      expect(saved.strokes.length, 2);
      expect(saved.strokes.first.toJson(), before);
      for (final device in [PointerDeviceKind.mouse, PointerDeviceKind.touch]) {
        final center = controller.selectionBounds!.center;
        final box = tester.renderObject<RenderBox>(find.byType(InkLayer).first);
        final position = box.localToGlobal(
          Offset(center.dx * box.size.width, center.dy * box.size.height),
        );
        final gesture = await tester.startGesture(position, kind: device);
        expect(
          controller.isInteracting,
          isTrue,
          reason: 'Drag started with $device',
        );
        await gesture.moveBy(const Offset(30, 22));
        await tester.pump();
        await gesture.up();
        await tester.pump();
        expect(
          controller.selectionBounds!.center.dx,
          greaterThan(center.dx),
          reason: 'Moved with $device',
        );
        expect(
          controller.selectionBounds!.center.dy,
          greaterThan(center.dy),
          reason: 'Moved with $device',
        );
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 400));
      imageCache.clear();
      imageCache.clearLiveImages();
      await tester.runAsync(() async {
        for (var i = 0; i < 15; i++) {
          try {
            await temp.delete(recursive: true);
            return;
          } on FileSystemException {
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
        }
      });
    },
  );
}
