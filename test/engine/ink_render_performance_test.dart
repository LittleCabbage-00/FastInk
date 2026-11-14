import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:fastink_flutter/src/engine/ink_canvas.dart';
import 'package:fastink_flutter/src/models/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as raster_image;

void main() {
  final input = Platform.environment['FASTINK_DENSE_INK'];
  testWidgets(
    'measure dense native ink painting without changing its source points',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final page = (await tester.runAsync(
        () async => PageInk.fromJson(
          jsonDecode(await File(input!).readAsString()) as Map<String, Object?>,
        ),
      ))!;
      final controller = InkController(onCommitted: () {})
        ..replace(page.strokes);
      final originalData = jsonEncode(
        page.strokes.map((s) => s.toJson()).toList(),
      );
      final originalPoints = page.strokes.fold<int>(
        0,
        (n, s) => n + s.points.length,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: InkLayer(
            controller: controller,
            retainCommittedLayers: false,
            tool: InkTool.pen,
            color: Colors.black,
            width: 3,
            eraserMode: EraserMode.stroke,
            eraserSize: 20,
            momentaryTool: null,
            enabled: true,
            onDrawingChanged: (_) {},
            onPenButtonChanged: (_, _) {},
            onTextRequested: (_, _) {},
          ),
        ),
      );
      await tester.pump();
      final painter = tester
          .widget<CustomPaint>(
            find
                .descendant(
                  of: find.byType(InkLayer),
                  matching: find.byType(CustomPaint),
                )
                .first,
          )
          .painter!;
      final record = <int>[];
      final raster = <int>[];
      final pictureBytes = <int>[];
      for (var frame = 0; frame < 9; frame++) {
        // Repeated pen-up redraws should not rebuild all pre-existing geometry.
        controller.begin(
          const InkPoint(.1, .9, .5),
          Colors.blue,
          .002,
          StrokeKind.pen,
        );
        controller.append(InkPoint(.15 + frame * .001, .91, .8));
        controller.finish();
        final recorder = ui.PictureRecorder();
        final watch = Stopwatch()..start();
        painter.paint(Canvas(recorder), const Size(800, 1100));
        final picture = recorder.endRecording();
        watch.stop();
        record.add(watch.elapsedMicroseconds);
        pictureBytes.add(picture.approximateBytesUsed);
        await tester.runAsync(() async {
          final timer = Stopwatch()..start();
          final image = await picture.toImage(800, 1100);
          try {
            await image.toByteData(format: ui.ImageByteFormat.rawRgba);
            timer.stop();
            raster.add(timer.elapsedMicroseconds);
            if (frame == 8) {
              final label =
                  Platform.environment['FASTINK_INK_BENCH_LABEL'] ?? 'current';
              final png = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              await File(
                'build/diagnostics/ink-dense-$label.png',
              ).writeAsBytes(png!.buffer.asUint8List());
            }
          } finally {
            image.dispose();
            picture.dispose();
          }
        });
      }
      int median(List<int> values) {
        final sorted = List<int>.of(values)..sort();
        return sorted[sorted.length ~/ 2];
      }

      final result = {
        'strokes': page.strokes.length,
        'points': originalPoints,
        'recordMedianUs': median(record),
        'rasterReadbackMedianUs': median(raster),
        'pictureBytesMedian': median(pictureBytes),
      };
      await tester.runAsync(
        () => File(
          'build/diagnostics/ink-render-${Platform.environment['FASTINK_INK_BENCH_LABEL'] ?? 'current'}.json',
        ).writeAsString(jsonEncode(result)),
      );
      // ignore: avoid_print
      print('DENSE_INK_BENCH ${jsonEncode(result)}');
      expect(
        page.strokes.fold<int>(0, (n, s) => n + s.points.length),
        originalPoints,
      );
      expect(controller.strokes.length, page.strokes.length + 9);
      await tester.pumpWidget(
        MaterialApp(
          home: InkLayer(
            controller: controller,
            tool: InkTool.pen,
            color: Colors.black,
            width: 3,
            eraserMode: EraserMode.stroke,
            eraserSize: 20,
            momentaryTool: null,
            enabled: true,
            onDrawingChanged: (_) {},
            onPenButtonChanged: (_, _) {},
            onTextRequested: (_, _) {},
          ),
        ),
      );
      await tester.pump();
      final retainedBefore = controller.debugCommittedPaintCount;
      final commitTimes = <int>[];
      for (var i = 0; i < 9; i++) {
        controller.begin(
          const InkPoint(.1, .95, .5),
          Colors.blue,
          .002,
          StrokeKind.pen,
        );
        controller.append(InkPoint(.2 + i * .001, .95, .8));
        controller.finish();
        final watch = Stopwatch()..start();
        await tester.pump();
        watch.stop();
        commitTimes.add(watch.elapsedMicroseconds);
      }
      result['commitUiMedianUs'] = median(commitTimes);
      result['retainedGroupsPaintedForNineStrokes'] =
          controller.debugCommittedPaintCount - retainedBefore;
      expect(result['retainedGroupsPaintedForNineStrokes'], lessThan(45));
      expect(
        jsonEncode(page.strokes.map((s) => s.toJson()).toList()),
        originalData,
      );
      await tester.runAsync(
        () => File(
          'build/diagnostics/ink-render-${Platform.environment['FASTINK_INK_BENCH_LABEL'] ?? 'current'}.json',
        ).writeAsString(jsonEncode(result)),
      );
      if (Platform.environment['FASTINK_INK_BENCH_LABEL'] == 'after' &&
          File('build/diagnostics/ink-dense-before.png').existsSync()) {
        final quality = (await tester.runAsync(() async {
          final a = raster_image.decodePng(
            await File('build/diagnostics/ink-dense-before.png').readAsBytes(),
          )!;
          final b = raster_image.decodePng(
            await File('build/diagnostics/ink-dense-after.png').readAsBytes(),
          )!;
          var union = 0, intersection = 0, alphaError = 0, inkPixels = 0;
          for (var y = 0; y < a.height; y++) {
            for (var x = 0; x < a.width; x++) {
              final old = a.getPixel(x, y).a.toInt(),
                  next = b.getPixel(x, y).a.toInt();
              if (old > 128 || next > 128) {
                union++;
              }
              if (old > 128 && next > 128) {
                intersection++;
              }
              if (old > 16 || next > 16) {
                alphaError += (old - next).abs();
                inkPixels++;
              }
            }
          }
          return {
            'inkPixelIou': intersection / union,
            'alphaMaeOnInk': alphaError / inkPixels,
          };
        }))!;
        await tester.runAsync(
          () => File(
            'build/diagnostics/ink-render-quality.json',
          ).writeAsString(jsonEncode(quality)),
        );
        expect(quality['inkPixelIou'], greaterThan(.92));
        expect(quality['alphaMaeOnInk'], lessThan(12));
      }
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    },
    skip: input == null,
  );
}
