import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:fastink_flutter/src/models/models.dart';
import 'package:fastink_flutter/src/platform/note_cover_cache.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as raster;

void main() {
  testWidgets(
    'dense editable ink becomes bounded reusable preview without touching source',
    (tester) async {
      await tester.runAsync(() async {
        final root = await Directory.systemTemp.createTemp(
          'fastink-dense-cover-',
        );
        try {
          final pages = await Directory(
            '${root.path}/documents/dense/pages',
          ).create(recursive: true);
          await File(
            '${root.path}/documents/dense/manifest.json',
          ).writeAsString(
            jsonEncode({
              'pages': [
                {'originalPage': 1},
              ],
            }),
          );
          final supplied = Platform.environment['FASTINK_COVER_BENCH_INPUT'];
          final ink = supplied == null
              ? PageInk(
                  strokes: List.generate(
                    1000,
                    (line) => InkStroke(
                      color: 0xff202020,
                      width: .001,
                      points: List.generate(
                        50,
                        (i) => InkPoint(
                          .05 + i / 55,
                          .05 + (line % 100) * .009 + math.sin(i * .3) * .003,
                          .3 + (i % 5) / 10,
                        ),
                      ),
                    ),
                  ),
                )
              : PageInk.fromJson(
                  jsonDecode(await File(supplied).readAsString())
                      as Map<String, Object?>,
                );
          final inkFile = File('${pages.path}/000001.json');
          final source = jsonEncode(ink.toJson());
          await inkFile.writeAsString(source);
          final paper = raster.Image(width: 800, height: 1120);
          raster.fill(paper, color: raster.ColorRgb8(255, 255, 255));
          final background = File('${root.path}/paper.png');
          await background.writeAsBytes(raster.encodePng(paper));
          final rawCount = ink.strokes.fold<int>(
            0,
            (n, s) => n + s.points.length,
          );
          final previewCount = ink.strokes
              .map(simplifyCoverStroke)
              .fold<int>(0, (n, s) => n + s.points.length);
          final cold = Stopwatch()..start();
          final first = (await NoteCoverCache.load(
            root.path,
            'dense',
            background.path,
          ))!;
          cold.stop();
          final count = NoteCoverCache.renderCount;
          final warm = Stopwatch()..start();
          final second = (await NoteCoverCache.load(
            root.path,
            'dense',
            background.path,
          ))!;
          warm.stop();
          expect(first.path, second.path);
          expect(NoteCoverCache.renderCount, count);
          expect(await inkFile.readAsString(), source);
          final preview = raster.decodePng(await first.readAsBytes())!;
          expect(
            math.max(preview.width, preview.height),
            lessThanOrEqualTo(512),
          );
          debugPrint(
            'Dense cover: ${ink.strokes.length} strokes, $rawCount -> $previewCount preview points; cold ${cold.elapsedMilliseconds} ms; warm ${warm.elapsedMilliseconds} ms; ${preview.width} x ${preview.height}',
          );
        } finally {
          await root.delete(recursive: true);
        }
      });
    },
  );
}
