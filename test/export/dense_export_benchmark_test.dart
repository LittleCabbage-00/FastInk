import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:fastink_flutter/src/export/export_repository.dart';
import 'package:fastink_flutter/src/models/models.dart';
import 'package:fastink_flutter/src/storage/note_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'pdf_fast_export_test.dart' as fixture;

void main() {
  testWidgets('dense export keeps source editable and reports completion', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final root = await Directory.systemTemp.createTemp(
        'fastink-dense-export-',
      );
      final label =
          Platform.environment['FASTINK_EXPORT_BENCH_LABEL'] ?? 'test';
      final input = Platform.environment['FASTINK_DENSE_EXPORT_INPUT'];
      try {
        final notes = NoteRepository(dataRoot: '${root.path}/data');
        final source = File('${root.path}/source.pdf');
        await source.writeAsBytes(fixture.fixturePdf());
        final document = await notes.importPdf(source, onProgress: (_) {});
        final ink = input == null
            ? PageInk(
                strokes: List.generate(
                  1200,
                  (line) => InkStroke(
                    color: 0xff202020,
                    width: .001,
                    penStyle: PenStyle.ball,
                    points: List.generate(
                      42,
                      (i) => InkPoint(
                        .05 + i / 50,
                        .05 + (line % 100) * .009 + math.sin(i * .3) * .003,
                        .3 + (i % 5) / 10,
                      ),
                    ),
                  ),
                ),
              )
            : PageInk.fromJson(
                jsonDecode(await File(input).readAsString())
                    as Map<String, Object?>,
              );
        await notes.savePageInk(document, document.pages.first, ink);
        final reference = jsonEncode(
          (await notes.loadPageInk(document, document.pages.first)).toJson(),
        );
        final exporter = ExportRepository(notes);
        final updates = <ExportProgress>[];
        final clock = Stopwatch()..start();
        var lastTick = 0, maxGap = 0, ticks = 0;
        final timer = Timer.periodic(const Duration(milliseconds: 16), (_) {
          final now = clock.elapsedMilliseconds;
          maxGap = math.max(maxGap, now - lastTick);
          lastTick = now;
          ticks++;
        });
        try {
          final pdf = File('${root.path}/export.pdf');
          final watch = Stopwatch()..start();
          await exporter.exportPdf(document, pdf, onUpdate: updates.add);
          final pdfMs = watch.elapsedMilliseconds;
          final pdfGap = math.max(maxGap, clock.elapsedMilliseconds - lastTick);
          maxGap = 0;
          lastTick = clock.elapsedMilliseconds;
          expect(updates.last.value, 1);
          watch.reset();
          final png = File('${root.path}/export.png');
          await exporter.exportImage(
            document,
            document.pages.first,
            png,
            NoteExportFormat.png,
          );
          final pngMs = watch.elapsedMilliseconds;
          final pngGap = math.max(maxGap, clock.elapsedMilliseconds - lastTick);
          timer.cancel();
          expect(
            jsonEncode(
              (await notes.loadPageInk(
                document,
                document.pages.first,
              )).toJson(),
            ),
            reference,
          );
          expect(await pdf.length(), greaterThan(1000));
          expect(await png.length(), greaterThan(1000));
          final result = {
            'strokes': ink.strokes.length,
            'points': ink.strokes.fold<int>(0, (n, s) => n + s.points.length),
            'pdfMs': pdfMs,
            'pngMs': pngMs,
            'pdfBytes': await pdf.length(),
            'pngBytes': await png.length(),
            'maxEventLoopGapMs': math.max(pdfGap, pngGap),
            'pdfEventLoopGapMs': pdfGap,
            'pngEventLoopGapMs': pngGap,
            'heartbeatTicks': ticks,
          };
          debugPrint('Dense export $label: ${jsonEncode(result)}');
          if (Platform.environment['FASTINK_EXPORT_BENCH_LABEL'] != null) {
            await pdf.copy('build/diagnostics/dense-export-$label.pdf');
            await png.copy('build/diagnostics/dense-export-$label.png');
            await File(
              'build/diagnostics/dense-export-$label.json',
            ).writeAsString(jsonEncode(result));
          }
        } finally {
          timer.cancel();
        }
      } finally {
        await root.delete(recursive: true);
      }
    });
  });
}
