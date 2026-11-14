import 'dart:io';
import 'package:fastink_flutter/main.dart';
import 'package:fastink_flutter/src/core/app_settings.dart';
import 'package:fastink_flutter/src/engine/ink_canvas.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as raster;

void main() {
  testWidgets(
    'touch and trackpad follow fingers on both axes, pinch stays cumulative and wheel stays conventional',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final temp = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('fastink-gestures-'),
      ))!;
      final source = File('${temp.path}/page.png');
      await tester.runAsync(() async {
        await source.writeAsBytes(
          raster.encodePng(raster.Image(width: 200, height: 280)),
        );
        await tester.pumpWidget(
          FastInkApp(
            settings: AppSettings(
              dataRoot: '${temp.path}/data',
              language: 'en',
              openSidebarByDefault: false,
              edgeBounceEnabled: false,
            ),
            initialPath: source.path,
          ),
        );
      });
      for (var i = 0; i < 100; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 40)),
        );
        await tester.pump(const Duration(milliseconds: 40));
        if (find.byType(InkLayer).evaluate().isNotEmpty) break;
      }
      await tester.pumpAndSettle();
      expect(find.byType(InkLayer), findsWidgets);
      final camera =
          tester
                  .widget<ValueListenableBuilder<Matrix4>>(
                    find.byType(ValueListenableBuilder<Matrix4>),
                  )
                  .valueListenable
              as TransformationController;
      final surface = find.byWidgetPredicate(
        (w) => w is Listener && w.onPointerPanZoomUpdate != null,
      );
      final focal = tester.getCenter(surface);
      final localFocal = focal - tester.getTopLeft(surface);
      Future<void> reset() async {
        camera.value = Matrix4.identity()
          ..setEntry(0, 0, 3)
          ..setEntry(1, 1, 3)
          ..setEntry(0, 3, -localFocal.dx * 2)
          ..setEntry(1, 3, -localFocal.dy * 2);
        await tester.pump();
      }

      for (final delta in [const Offset(-40, -60), const Offset(40, 60)]) {
        await reset();
        final before = Matrix4.copy(camera.value);
        final touch = await tester.startGesture(
          focal,
          kind: PointerDeviceKind.touch,
        );
        await touch.moveBy(delta, timeStamp: const Duration(milliseconds: 16));
        expect(
          camera.value[12] - before[12],
          closeTo(delta.dx, .01),
          reason: 'touch before=$before after=${camera.value} focal=$focal',
        );
        expect(camera.value[13] - before[13], closeTo(delta.dy, .01));
        await touch.up(timeStamp: const Duration(milliseconds: 200));
        await tester.pumpAndSettle();

        await reset();
        final trackpad = await tester.createGesture(
          kind: PointerDeviceKind.trackpad,
        );
        await trackpad.panZoomStart(focal);
        await trackpad.panZoomUpdate(focal, pan: delta);
        expect(camera.value[12] - before[12], closeTo(delta.dx, .01));
        expect(camera.value[13] - before[13], closeTo(delta.dy, .01));
        await trackpad.panZoomEnd();
        await tester.pumpAndSettle();
      }

      await reset();
      final scene = camera.toScene(localFocal);
      final trackpad = await tester.createGesture(
        kind: PointerDeviceKind.trackpad,
      );
      await trackpad.panZoomStart(focal);
      for (final scale in [1.1, 1.2, 1.3]) {
        await trackpad.panZoomUpdate(focal, scale: scale);
        expect(camera.value.getMaxScaleOnAxis(), closeTo(3 * scale, .001));
        expect((camera.toScene(localFocal) - scene).distance, lessThan(.01));
      }
      await trackpad.panZoomEnd();
      await reset();
      final beforeWheel = camera.value[13];
      tester.binding.handlePointerEvent(
        PointerScrollEvent(position: focal, scrollDelta: const Offset(0, 60)),
      );
      expect(camera.value[13], closeTo(beforeWheel - 60, .01));
      await tester.tap(find.byIcon(Icons.arrow_back_rounded));
      for (var i = 0; i < 12; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 300));
      imageCache.clear();
      imageCache.clearLiveImages();
      await tester.runAsync(() async {
        for (var attempt = 0; attempt < 10; attempt++) {
          try {
            await temp.delete(recursive: true);
            return;
          } on FileSystemException {
            if (attempt == 9) rethrow;
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
        }
      });
      expect(tester.takeException(), isNull);
    },
  );
}
