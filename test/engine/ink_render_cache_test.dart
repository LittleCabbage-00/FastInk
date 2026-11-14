import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:fastink_flutter/src/engine/ink_canvas.dart';
import 'package:fastink_flutter/src/models/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

Widget surface(
  InkController controller, {
  bool retained = false,
  InkTool tool = InkTool.pen,
}) => MaterialApp(
  home: InkLayer(
    controller: controller,
    retainCommittedLayers: retained,
    tool: tool,
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
);

void main() {
  testWidgets('mixed highlighter ink updates and preserves compositing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(200, 200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = InkController(onCommitted: () {})
      ..replace([
        InkStroke(
          color: 0xff101010,
          width: .02,
          points: [const InkPoint(.1, .5, .5), const InkPoint(.9, .5, .5)],
        ),
        InkStroke(
          color: 0xffffff00,
          width: .08,
          kind: StrokeKind.highlighter,
          points: [const InkPoint(.5, .1, .5), const InkPoint(.5, .9, .5)],
        ),
      ]);
    final captureKey = GlobalKey();
    Future<void> mount(bool retained) => tester.pumpWidget(
      RepaintBoundary(
        key: captureKey,
        child: surface(controller, retained: retained),
      ),
    );
    Future<Uint8List> capture() async {
      final boundary =
          captureKey.currentContext!.findRenderObject()
              as RenderRepaintBoundary;
      return (await tester.runAsync(() async {
        final result = await boundary.toImage();
        try {
          return (await result.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!.buffer.asUint8List();
        } finally {
          result.dispose();
        }
      }))!;
    }

    await mount(true);
    final before = await capture();
    await mount(false);
    expect(await capture(), orderedEquals(before));
    await mount(true);
    controller.begin(
      const InkPoint(.2, .8, .5),
      Colors.red,
      .02,
      StrokeKind.pen,
    );
    controller.append(const InkPoint(.8, .8, .5));
    controller.finish();
    await tester.pump();
    expect(await capture(), isNot(orderedEquals(before)));
    controller.undo();
    await tester.pump();
    expect(await capture(), orderedEquals(before));
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets(
    'cached ink remains editable through append, move, recolor, erase, undo and resize',
    (tester) async {
      tester.view.physicalSize = const Size(200, 200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final red = InkStroke(
        color: 0xffff0000,
        width: .02,
        penStyle: PenStyle.ball,
        points: [const InkPoint(.2, .2, .5), const InkPoint(.8, .3, .5)],
      );
      final controller = InkController(onCommitted: () {})..replace([red]);
      await tester.pumpWidget(surface(controller));
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
      Future<Uint8List> image([int side = 200]) async {
        final recorder = ui.PictureRecorder();
        painter.paint(Canvas(recorder), Size(side.toDouble(), side.toDouble()));
        final picture = recorder.endRecording();
        return (await tester.runAsync(() async {
          final result = await picture.toImage(side, side);
          try {
            return (await result.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            ))!.buffer.asUint8List();
          } finally {
            result.dispose();
            picture.dispose();
          }
        }))!;
      }

      int channel(
        Uint8List bytes,
        int x,
        int y,
        int channel, [
        int side = 200,
      ]) => bytes[(y * side + x) * 4 + channel];
      expect(channel(await image(), 100, 50, 0), 255);
      controller.begin(
        const InkPoint(.2, .8, .5),
        const Color(0xff0000ff),
        .02,
        StrokeKind.pen,
        PenStyle.ball,
      );
      controller.append(const InkPoint(.8, .8, .5));
      controller.finish();
      final appended = await image();
      expect(channel(appended, 100, 50, 0), 255);
      expect(channel(appended, 100, 160, 2), 255);
      controller.selectOnly(red);
      expect(
        controller.beginSelectionTransform(
          const InkPoint(.5, .25, .5),
          const Size(200, 200),
          hitRadius: 4,
        ),
        SelectionTransform.move,
      );
      controller.updateSelectionTransform(
        const InkPoint(.5, .65, .5),
        const Size(200, 200),
      );
      controller.finishSelectionTransform();
      final moved = await image();
      expect(channel(moved, 100, 50, 3), 0);
      expect(channel(moved, 100, 130, 0), 255);
      controller.undo();
      expect(channel(await image(), 100, 50, 0), 255);
      controller.selectOnly(red);
      controller.recolorSelection(0xff00ff00);
      expect(channel(await image(), 100, 50, 1), 255);
      controller.eraseAt(
        const InkPoint(.5, .25, .5),
        const Size(200, 200),
        8,
        EraserMode.stroke,
      );
      expect(channel(await image(), 100, 50, 3), 0);
      controller.undo();
      expect(channel(await image(), 100, 50, 1), 255);
      expect(channel(await image(300), 150, 75, 1, 300), 255);
      controller.clear();
      expect(channel(await image(), 100, 50, 3), 0);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    },
  );

  testWidgets('new and erased strokes repaint only nearby regions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = InkController(onCommitted: () {});
    controller.replace(
      List.generate(
        320,
        (i) => InkStroke(
          color: 0xff202124,
          width: .002,
          points: [
            InkPoint(.1, .1 + i * .002, .5),
            InkPoint(.7, .11 + i * .002, .7),
          ],
        ),
      ),
    );
    await tester.pumpWidget(surface(controller, retained: true));
    await tester.pump();
    final before = controller.debugCommittedPaintCount;
    controller.begin(
      const InkPoint(.1, .9, .5),
      Colors.red,
      .002,
      StrokeKind.pen,
    );
    controller.append(const InkPoint(.8, .9, .8));
    await tester.pump();
    expect(
      controller.debugCommittedPaintCount,
      before,
      reason: 'Live writing must not repaint any completed group',
    );
    controller.finish();
    await tester.pump();
    expect(
      controller.debugCommittedPaintCount - before,
      lessThan(before),
      reason: 'A new stroke must not invalidate the rest of the page',
    );
    final tailBefore = controller.debugCommittedPaintCount;
    controller.begin(
      const InkPoint(.1, .92, .5),
      Colors.red,
      .002,
      StrokeKind.pen,
    );
    controller.append(const InkPoint(.8, .92, .8));
    controller.finish();
    await tester.pump();
    expect(controller.debugCommittedPaintCount - tailBefore, lessThan(before));
    final eraseBefore = controller.debugCommittedPaintCount;
    controller.beginHistoryTransaction(deferSnapshot: true);
    controller.eraseAt(
      const InkPoint(.13, .1, .5),
      const Size(800, 600),
      5,
      EraserMode.point,
    );
    await tester.pump();
    expect(
      controller.debugCommittedPaintCount - eraseBefore,
      lessThan(before / 2),
      reason: 'Erasing the first strokes must not shift every later layer',
    );
    controller.finishEraseGesture();
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
}
