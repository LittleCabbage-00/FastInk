import 'dart:convert';
import 'dart:io';
import 'package:fastink_flutter/src/engine/ink_canvas.dart';
import 'package:fastink_flutter/src/models/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../engine/ink_render_cache_test.dart' show surface;

void main() {
  testWidgets(
    'battery tiles yield to navigation and writing, then resume and stay editable',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = InkController(onCommitted: () {})
        ..replace([
          for (var y = 0; y < 24; y++)
            for (var x = 0; x < 18; x++)
              InkStroke(
                color: 0xff202020,
                width: .002,
                points: [
                  InkPoint(.015 + x * .054, .015 + y * .04, .3),
                  InkPoint(.045 + x * .054, .035 + y * .04, .8),
                ],
              ),
        ]);
      final original = jsonEncode(
        controller.strokes.map((s) => s.toJson()).toList(),
      );
      void view(bool battery, [double left = 0]) => controller.updateView(
        visibleRect: Rect.fromLTWH(left, 0, 800, 1100),
        scale: 1,
        pixelRatio: 2,
        maxRasterDensity: battery ? 2 : double.infinity,
        economical: battery,
      );
      view(false);
      await tester.pumpWidget(surface(controller, retained: true));
      final pluggedTiles = controller.debugCommittedPaintCount;
      view(true);
      final before = controller.debugCommittedPaintCount;
      await tester.pump();
      final batteryTiles = controller.debugCommittedPaintCount - before;
      expect(batteryTiles, lessThan(pluggedTiles * .4));

      // 连续相机事件不能触发一串离屏缓存生成；不把输入频率降到显示帧率。
      for (var i = 0; i < 8; i++) {
        view(true, i * .1);
        await tester.pump(const Duration(milliseconds: 16));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 16)),
        );
      }
      expect(controller.debugRasterPrepareCount, 0);
      controller.begin(
        const InkPoint(.1, .9, .4),
        Colors.blue,
        .002,
        StrokeKind.pen,
      );
      controller.append(const InkPoint(.2, .9, .8));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 140)),
      );
      expect(controller.debugRasterPrepareCount, 0);
      controller.finish();
      await tester.pump();
      for (
        var i = 0;
        i < 50 && controller.debugRasterTileCount < batteryTiles;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(controller.debugRasterTileCount, greaterThan(0));
      expect(controller.debugRasterBytes, lessThanOrEqualTo(48 * 1024 * 1024));
      final painted = controller.debugCommittedPaintCount;
      for (var i = 0; i < 30; i++) {
        view(true, .1 + i * .01);
        await tester.pump();
      }
      expect(controller.debugCommittedPaintCount, painted);
      controller.undo();
      expect(
        jsonEncode(controller.strokes.map((s) => s.toJson()).toList()),
        original,
      );
      controller.eraseAt(
        const InkPoint(.03, .025, .5),
        const Size(800, 1100),
        12,
        EraserMode.point,
      );
      controller.undo();
      expect(
        jsonEncode(controller.strokes.map((s) => s.toJson()).toList()),
        original,
      );
      view(false);
      await tester.pump();
      expect(tester.takeException(), isNull);
      // ignore: avoid_print
      print(
        'BATTERY_TILE_BENCH ${jsonEncode({'pluggedTiles': pluggedTiles, 'batteryTiles': batteryTiles})}',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    },
  );

  final dense = Platform.environment['FASTINK_DENSE_INK'];
  testWidgets(
    'measure dense page tile work in both power policies without changing ink',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final page = (await tester.runAsync(
        () async => PageInk.fromJson(
          jsonDecode(await File(dense!).readAsString()) as Map<String, Object?>,
        ),
      ))!;
      final original = jsonEncode(page.strokes.map((s) => s.toJson()).toList());
      final results = <String, Object>{};
      for (final battery in [false, true]) {
        final controller = InkController(onCommitted: () {})
          ..replace(page.strokes);
        controller.updateView(
          visibleRect: const Rect.fromLTWH(0, 0, 800, 1100),
          scale: 1,
          pixelRatio: 2,
          maxRasterDensity: 2,
          economical: battery,
        );
        final watch = Stopwatch()..start();
        await tester.pumpWidget(surface(controller, retained: true));
        watch.stop();
        results[battery ? 'battery' : 'plugged'] = {
          'tilesPainted': controller.debugCommittedPaintCount,
          'coldPumpUs': watch.elapsedMicroseconds,
        };
        expect(
          jsonEncode(page.strokes.map((s) => s.toJson()).toList()),
          original,
        );
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
      }
      await tester.runAsync(
        () => File(
          'build/diagnostics/battery-render1311.json',
        ).writeAsString(jsonEncode(results)),
      );
      // ignore: avoid_print
      print('DENSE_BATTERY_BENCH ${jsonEncode(results)}');
    },
    skip: dense == null,
  );
}
