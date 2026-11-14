import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:fastink_flutter/src/widgets/library_note_preview.dart';
import 'package:fastink_flutter/src/platform/note_cover_cache.dart';
import 'package:fastink_flutter/src/models/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as raster;

void main() {
  testWidgets(
    'library cover paints saved text and handwriting, including a reordered first page',
    (tester) async {
      final temp = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('fastink-cover137-'),
      ))!;
      final cover = File('${temp.path}/white.png');
      await tester.runAsync(() async {
        final directory = await Directory(
          '${temp.path}/documents/test/pages',
        ).create(recursive: true);
        await File('${temp.path}/documents/test/manifest.json').writeAsString(
          jsonEncode({
            'pages': [
              {'originalPage': 7},
            ],
          }),
        );
        final background = raster.Image(width: 200, height: 280);
        raster.fill(background, color: raster.ColorRgb8(255, 255, 255));
        await cover.writeAsBytes(raster.encodePng(background));
        final ink = PageInk(
          strokes: [
            InkStroke(
              color: 0xff000000,
              width: .02,
              points: [const InkPoint(.1, .2, .7), const InkPoint(.9, .8, .7)],
            ),
            InkStroke(
              color: 0xff000000,
              width: 1,
              text: 'Cover text',
              textSize: .08,
              textBoxWidth: .8,
              points: [
                const InkPoint(.1, .1, .5),
                const InkPoint(.9, .1, .5),
                const InkPoint(.9, .3, .5),
                const InkPoint(.1, .3, .5),
              ],
            ),
          ],
        );
        await File(
          '${directory.path}/000007.json',
        ).writeAsString(jsonEncode(ink.toJson()));
        final loaded = await readLibraryCoverInk(temp.path, 'test');
        expect(loaded.strokes.length, 2);
        await tester.pumpWidget(
          MaterialApp(
            home: Center(
              child: RepaintBoundary(
                key: const ValueKey('cover-preview'),
                child: SizedBox(
                  width: 200,
                  height: 280,
                  child: LibraryNotePreview(
                    root: temp.path,
                    documentId: 'test',
                    coverPath: cover.path,
                  ),
                ),
              ),
            ),
          ),
        );
      });
      for (int i = 0; i < 30; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 25)),
        );
        await tester.pump(const Duration(milliseconds: 30));
        if (NoteCoverCache.peek(temp.path, 'test') != null) {
          break;
        }
      }
      expect(NoteCoverCache.peek(temp.path, 'test'), isNotNull);
      final first = NoteCoverCache.peek(temp.path, 'test')!;
      final renders = NoteCoverCache.renderCount;
      // 重开封面必须命中磁盘缓存，不能重复排版原始笔迹。
      await tester.runAsync(() async {
        final watch = Stopwatch()..start();
        final cached = await NoteCoverCache.load(temp.path, 'test', cover.path);
        expect(cached!.path, first.path);
        expect(NoteCoverCache.renderCount, renders);
        debugPrint(
          'Warm cover cache: ${watch.elapsedMilliseconds} ms, no repaint',
        );
      });
      // 图像解码跨越真实 IO 与测试时钟；分轮推进，避免等待假时钟中的 pending image。
      for (int i = 0; i < 20; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 25)),
        );
        await tester.pump(const Duration(milliseconds: 30));
      }
      await tester.pumpAndSettle();
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('cover-preview')),
      );
      final image = (await tester.runAsync(boundary.toImage))!;
      final rgba = (await tester.runAsync(
        () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
      ))!;
      final png = (await tester.runAsync(
        () => image.toByteData(format: ui.ImageByteFormat.png),
      ))!;
      image.dispose();
      final bytes = rgba.buffer.asUint8List();
      int dark = 0;
      for (int i = 0; i < bytes.length; i += 4) {
        if (bytes[i] < 100 &&
            bytes[i + 1] < 100 &&
            bytes[i + 2] < 100 &&
            bytes[i + 3] > 200) {
          dark++;
        }
      }
      expect(
        dark,
        greaterThan(100),
        reason: 'The cover must contain rendered content, not just white paper',
      );
      await tester.runAsync(
        () => File(
          'build/diagnostics/library-cover138.png',
        ).writeAsBytes(png.buffer.asUint8List()),
      );
      // 首页内容改变后，缓存路径改变，避免 Flutter 继续显示旧 FileImage。
      await tester.runAsync(() async {
        final path = File('${temp.path}/documents/test/pages/000007.json');
        final ink = PageInk.fromJson(
          jsonDecode(await path.readAsString()) as Map<String, Object?>,
        );
        await path.writeAsString(
          jsonEncode(PageInk(strokes: [ink.strokes.first]).toJson()),
        );
        final fresh = await NoteCoverCache.load(temp.path, 'test', cover.path);
        expect(fresh!.path, isNot(first.path));
        expect(NoteCoverCache.renderCount, renders + 1);
      });
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() => temp.delete(recursive: true));
    },
  );

  test(
    'dense thumbnail simplification preserves source and visible geometry',
    () {
      final points = List.generate(
        5000,
        (i) => InkPoint(i / 5000, .3 + i / 100000, .2 + (i % 7) / 10),
      );
      final original = InkStroke(
        color: 0xff000000,
        width: .002,
        points: points,
      );
      final simplified = simplifyCoverStroke(original);
      expect(original.points.length, 5000);
      expect(simplified.points.length, 2);
      expect(simplified.points.first, same(points.first));
      expect(simplified.points.last, same(points.last));
      final corner = original.copy(
        points: [
          points.first,
          const InkPoint(.2, .8, .8),
          const InkPoint(.4, .2, .3),
          points.last,
        ],
      );
      expect(simplifyCoverStroke(corner).points.length, 4);
    },
  );
}
