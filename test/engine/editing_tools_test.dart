import 'package:fastink_flutter/src/engine/ink_canvas.dart';
import 'package:fastink_flutter/src/models/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('new shapes remain editable saved ink with one-step undo', () {
    for (final type in <ShapeType>[
      ShapeType.arrow,
      ShapeType.triangle,
      ShapeType.diamond,
    ]) {
      final controller = InkController(onCommitted: () {});
      controller.beginShape(
        const InkPoint(.2, .2, .5),
        Colors.black,
        .003,
        type,
        canvasSize: const Size(1000, 1600),
      );
      controller.updateShape(const InkPoint(.7, .6, .5), type);
      controller.finish();
      final stroke = InkStroke.fromJson(controller.strokes.single.toJson());
      expect(stroke.points.length, greaterThanOrEqualTo(4));
      expect(stroke.points.every((p) => p.x.isFinite && p.y.isFinite), isTrue);
      controller.undo();
      expect(controller.strokes, isEmpty);
      controller.redo();
      expect(controller.strokes, hasLength(1));
      controller.dispose();
    }
  });
  test('layer move preserves selection group order and is reversible', () {
    final controller = InkController(onCommitted: () {});
    addTearDown(controller.dispose);
    final strokes = List<InkStroke>.generate(
      4,
      (i) => InkStroke(
        color: i,
        width: .003,
        points: <InkPoint>[InkPoint(i * .1, .1, .5)],
      ),
    );
    controller.replace(strokes);
    controller.selectedStrokes.addAll(<InkStroke>[strokes[2], strokes[0]]);
    controller.reorderSelection(toFront: true);
    expect(controller.strokes, <InkStroke>[
      strokes[1],
      strokes[3],
      strokes[0],
      strokes[2],
    ]);
    controller.undo();
    expect(controller.strokes, strokes);
    controller.redo();
    expect(controller.strokes.last, strokes[2]);
  });
}
