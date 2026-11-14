import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:fastink_flutter/src/engine/ink_canvas.dart';
import 'package:fastink_flutter/src/models/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'ink_render_cache_test.dart' show surface;

void main() {
  testWidgets(
    'selection release commits the last queued transform and one undo',
    (tester) async {
      tester.view.physicalSize = const Size(200, 200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = InkController(onCommitted: () {})
        ..replace([
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
      controller.selectAll();
      await tester.pumpWidget(surface(controller, retained: true));
      final gesture = await tester.startGesture(
        const Offset(100, 100),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveTo(const Offset(105, 105));
      await gesture.moveTo(const Offset(110, 110));
      // Release before a display frame: the final queued position must survive.
      await gesture.up();
      await tester.pump();
      expect(controller.strokes.single.points.first.x, closeTo(.25, 1e-8));
      controller.undo();
      expect(controller.strokes.single.points.first.x, .2);
      expect(controller.canUndo, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    },
  );

  testWidgets(
    'panning retains existing tiles and creates only visible regions',
    (tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = InkController(onCommitted: () {})
        ..replace([
          for (var y = 0; y < 20; y++)
            for (var x = 0; x < 20; x++)
              InkStroke(
                color: 0xff202020,
                width: .002,
                points: [
                  InkPoint(.02 + x * .045, .02 + y * .045, .5),
                  InkPoint(.04 + x * .045, .03 + y * .045, .7),
                ],
              ),
        ]);
      controller.updateView(
        visibleRect: const Rect.fromLTWH(5, 5, 180, 180),
        scale: 1,
      );
      await tester.pumpWidget(surface(controller, retained: true));
      final initial = controller.debugCommittedPaintCount;
      expect(initial, inInclusiveRange(1, 9));
      for (var i = 1; i < 20; i++) {
        controller.updateView(
          visibleRect: Rect.fromLTWH(5 + i * .1, 5, 180, 180),
          scale: 1,
        );
        await tester.pump();
      }
      expect(
        controller.debugCommittedPaintCount,
        initial,
        reason: 'Small camera changes must not rebuild ink geometry',
      );
      controller.updateView(
        visibleRect: const Rect.fromLTWH(400, 300, 180, 180),
        scale: 2,
      );
      await tester.pump();
      expect(
        controller.debugCommittedPaintCount - initial,
        inInclusiveRange(1, 16),
      );
      controller.updateView(
        visibleRect: const Rect.fromLTWH(400, 300, 50, 30),
        scale: 8,
        pixelRatio: 3,
      );
      await tester.pump();
      for (var i = 0; i < 20 && controller.debugRasterTileCount == 0; i++) {
        await tester.pump(const Duration(milliseconds: 65));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 15)),
        );
        await tester.pump();
      }
      expect(
        controller.debugRasterTileCount,
        greaterThan(0),
        reason: 'High DPI and high zoom must still produce bounded image tiles',
      );
      expect(controller.debugRasterBytes, lessThanOrEqualTo(48 * 1024 * 1024));
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    },
  );

  testWidgets('raster tiles preserve editable ink through erase and undo', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(200, 200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = InkController(onCommitted: () {})
      ..replace([
        InkStroke(
          color: 0xffff0000,
          width: .02,
          points: [const InkPoint(.1, .5, .3), const InkPoint(.9, .5, .8)],
        ),
      ]);
    final key = GlobalKey();
    Future<void> mount(bool retained) => tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: surface(controller, retained: retained),
      ),
    );
    Future<List<int>> pixels() async => (await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage();
      try {
        return (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!.buffer.asUint8List();
      } finally {
        image.dispose();
      }
    }))!;
    await mount(true);
    final original = await pixels();
    for (var i = 0; i < 20 && controller.debugRasterTileCount < 2; i++) {
      await tester.pump(const Duration(milliseconds: 65));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 15)),
      );
      await tester.pump();
    }
    expect(controller.debugRasterTileCount, greaterThan(0));
    expect(controller.debugRasterBytes, lessThanOrEqualTo(48 * 1024 * 1024));
    final raster = await pixels();
    double error(List<int> a, List<int> b) {
      var sum = 0;
      for (var i = 0; i < a.length; i++) {
        sum += (a[i] - b[i]).abs();
      }
      return sum / a.length;
    }

    expect(error(raster, original), lessThan(.5));
    controller.eraseAt(
      const InkPoint(.5, .5, .5),
      const Size(200, 200),
      20,
      EraserMode.point,
    );
    await tester.pump();
    final edited = await pixels();
    expect(edited, isNot(orderedEquals(original)));
    await mount(false);
    expect(error(await pixels(), edited), lessThan(.5));
    controller.undo();
    await mount(true);
    expect(error(await pixels(), original), lessThan(.5));
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  final dense = Platform.environment['FASTINK_DENSE_INK'];
  test(
    'dense native page supports the full editing sequence without data loss',
    () async {
      final page = PageInk.fromJson(
        jsonDecode(await File(dense!).readAsString()) as Map<String, Object?>,
      );
      final controller = InkController(onCommitted: () {})
        ..replace(page.strokes.map((s) => s.copy()).toList());
      final original = jsonEncode(
        controller.strokes.map((s) => s.toJson()).toList(),
      );
      final timings = <String, int>{};
      void measure(String name, void Function() run) {
        final watch = Stopwatch()..start();
        run();
        timings[name] = watch.elapsedMicroseconds;
      }

      measure('selectAllAndBoundsUs', () {
        controller.selectAll();
        controller.selectionBounds;
      });
      measure('copyPasteUs', () {
        controller.pasteStrokes(controller.copySelection());
      });
      measure('undoPasteUs', controller.undo);
      controller.selectAll();
      measure('recolorUs', () => controller.recolorSelection(0xff123456));
      measure('undoRecolorUs', controller.undo);
      controller.selectAll();
      measure('rotateUs', () => controller.rotateSelection(.05));
      measure('undoRotateUs', controller.undo);
      measure('redoRotateUs', controller.redo);
      controller.undo();
      measure('freeLassoUs', () {
        controller.beginLasso(const InkPoint(0, 0, .5));
        controller.appendLasso(const InkPoint(1, 0, .5));
        controller.appendLasso(const InkPoint(1, 1, .5));
        controller.appendLasso(const InkPoint(0, 1, .5));
        controller.finishLasso();
      });
      final first = controller.strokes.first.points.first;
      measure(
        'pointEraseUs',
        () => controller.eraseAt(
          first,
          const Size(800, 1100),
          5,
          EraserMode.point,
        ),
      );
      controller.undo();
      measure(
        'strokeEraseUs',
        () => controller.eraseAt(
          first,
          const Size(800, 1100),
          5,
          EraserMode.stroke,
        ),
      );
      controller.undo();
      measure('saveSnapshotUs', controller.snapshot);
      expect(
        jsonEncode(controller.strokes.map((s) => s.toJson()).toList()),
        original,
      );
      await File(
        'build/diagnostics/ink-interactions-after.json',
      ).writeAsString(jsonEncode(timings));
      // ignore: avoid_print
      print('DENSE_INTERACTIONS ${jsonEncode(timings)}');
      controller.dispose();
    },
    skip: dense == null,
  );
}
