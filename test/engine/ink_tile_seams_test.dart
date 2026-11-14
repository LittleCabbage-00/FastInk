import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:fastink_flutter/src/engine/ink_canvas.dart';
import 'package:fastink_flutter/src/models/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'fractional zoom keeps solid ink continuous across cached tile edges',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final ink = InkController(onCommitted: () {})
        ..replace([
          InkStroke(
            color: 0xff000000,
            width: .0071,
            penStyle: PenStyle.ball,
            points: const [InkPoint(.05, .16, .5), InkPoint(.95, .16, .5)],
          ),
          InkStroke(
            color: 0xff000000,
            width: .0071,
            penStyle: PenStyle.ball,
            points: const [InkPoint(.32, .04, .5), InkPoint(.32, .95, .5)],
          ),
        ]);
      ink.addText(
        const InkPoint(.04, .22, .5),
        const Size(400, 800),
        List.filled(20, 'Continuous editable text').join('\n'),
        Colors.black,
        20.2,
        boxWidth: 360,
      );
      ink.clearSelection();
      ink.updateView(visibleRect: null, scale: 1.25);
      final key = GlobalKey();
      Future<void> show(bool retained) => tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: MaterialApp(
            home: ColoredBox(
              color: Colors.white,
              child: Align(
                alignment: Alignment.topLeft,
                child: Transform.translate(
                  offset: const Offset(.3, .6),
                  child: Transform.scale(
                    scale: 1.25,
                    alignment: Alignment.topLeft,
                    child: SizedBox(
                      width: 400,
                      height: 800,
                      child: InkLayer(
                        controller: ink,
                        retainCommittedLayers: retained,
                        tool: InkTool.pen,
                        color: Colors.black,
                        width: 3,
                        eraserMode: EraserMode.stroke,
                        eraserSize: 10,
                        momentaryTool: null,
                        enabled: true,
                        onDrawingChanged: (_) {},
                        onPenButtonChanged: (_, _) {},
                        onTextRequested: (_, _) {},
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      Future<Uint8List> pixels() async => (await tester.runAsync(() async {
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
      await show(false);
      final vector = await pixels();
      final before = ink.debugCommittedPaintCount;
      await show(true);
      final tiles = ink.debugCommittedPaintCount - before;
      for (var i = 0; i < 50 && ink.debugRasterTileCount < tiles; i++) {
        await tester.pump(const Duration(milliseconds: 65));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 15)),
        );
        await tester.pump();
      }
      expect(ink.debugRasterTileCount, greaterThanOrEqualTo(tiles));
      final cached = await pixels();
      int red(Uint8List bytes, int x, int y) => bytes[(y * 800 + x) * 4];
      // 穿过缓存边界的粗实线应持续为黑色，不因分块裁切变成浅色细缝。
      for (var x = 35; x < 470; x++) {
        expect(red(vector, x, 161), lessThan(32));
        expect(
          red(cached, x, 161),
          lessThan(64),
          reason: 'Horizontal tile seam at x=$x',
        );
      }
      for (var y = 45; y < 940; y++) {
        expect(red(vector, 160, y), lessThan(32));
        expect(
          red(cached, 160, y),
          lessThan(64),
          reason: 'Vertical tile seam at y=$y',
        );
      }
      await tester.pumpWidget(const SizedBox.shrink());
      ink.dispose();
    },
  );
}
