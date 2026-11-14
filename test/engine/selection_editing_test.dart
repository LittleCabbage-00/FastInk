import 'package:fastink_flutter/src/engine/ink_canvas.dart';
import 'package:fastink_flutter/src/models/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

InkStroke stroke(double x, {StrokeKind kind = StrokeKind.pen, String? text}) =>
    InkStroke(
      color: 0xff123456,
      width: 0.003,
      kind: kind,
      text: text,
      points: <InkPoint>[InkPoint(x, 0.4, 0.5), InkPoint(x + 0.1, 0.5, 0.7)],
    );

void main() {
  test('highlighter only eraser protects handwriting text and images', () {
    final InkController controller = InkController(onCommitted: () {});
    addTearDown(controller.dispose);
    final List<InkStroke> content = <InkStroke>[
      stroke(0.1),
      stroke(0.1, kind: StrokeKind.highlighter),
      stroke(0.1, text: 'Keep'),
      stroke(0.1, kind: StrokeKind.image),
    ];
    controller.replace(content);
    controller.eraseHighlighterOnly = true;
    controller.eraseAt(
      const InkPoint(0.1, 0.4, 0.5),
      const Size(1000, 1400),
      30,
      EraserMode.stroke,
    );
    expect(controller.strokes.length, 3);
    expect(
      controller.strokes.any((s) => s.kind == StrokeKind.highlighter),
      isFalse,
    );
    controller.undo();
    expect(controller.strokes.length, 4);
  });

  test(
    'copied ink survives source edits and pastes as one reversible action',
    () {
      final InkController source = InkController(onCommitted: () {});
      final InkController target = InkController(onCommitted: () {});
      addTearDown(source.dispose);
      addTearDown(target.dispose);
      source.replace(<InkStroke>[stroke(0.2), stroke(0.4)]);
      source.selectAll();
      final List<InkStroke> copied = source.copySelection();
      source.strokes.first.points.clear();
      source.deleteSelection();
      target.pasteStrokes(copied);
      expect(target.strokes.length, 2);
      expect(target.strokes.first.points.length, 2);
      expect(target.hasSelection, isTrue);
      target.undo();
      expect(target.strokes, isEmpty);
      target.redo();
      expect(target.strokes.length, 2);
      expect(copied.first.points.first.x, 0.2);
    },
  );

  test('pasting at page edge translates group without distorting objects', () {
    final InkController controller = InkController(onCommitted: () {});
    addTearDown(controller.dispose);
    controller.pasteStrokes(<InkStroke>[stroke(0.9), stroke(0.5)]);
    expect(controller.strokes.first.points.last.x, closeTo(1, 0.000001));
    expect(
      controller.strokes.first.points.last.x -
          controller.strokes.first.points.first.x,
      closeTo(0.1, 0.000001),
    );
    expect(controller.strokes.last.points.first.x, closeTo(0.5, 0.000001));
  });

  test(
    'recolor preserves image assets and text formatting through undo redo',
    () {
      final InkController controller = InkController(onCommitted: () {});
      addTearDown(controller.dispose);
      final InkStroke text = InkStroke(
        color: 0xff123456,
        width: 0.003,
        text: 'Hello',
        textItalic: true,
        textWeight: 700,
        points: <InkPoint>[const InkPoint(0.1, 0.1, 0.5)],
      );
      controller.replace(<InkStroke>[
        text,
        stroke(0.3),
        InkStroke(
          color: 0xffffffff,
          width: 0,
          kind: StrokeKind.image,
          imageAsset: 'assets/photo.png',
          points: <InkPoint>[const InkPoint(0.3, 0.3, 1)],
        ),
      ]);
      controller.selectAll();
      controller.recolorSelection(Colors.red.toARGB32());
      expect(controller.strokes.first.color, Colors.red.toARGB32());
      expect(controller.strokes.first.textItalic, isTrue);
      expect(controller.strokes.first.textWeight, 700);
      expect(controller.strokes.last.color, 0xffffffff);
      expect(controller.strokes.last.imageAsset, 'assets/photo.png');
      controller.undo();
      expect(controller.strokes.first.color, 0xff123456);
      controller.redo();
      expect(controller.strokes.first.color, Colors.red.toARGB32());
    },
  );

  test('lasso and select all respect content filters', () {
    final InkController controller = InkController(onCommitted: () {});
    addTearDown(controller.dispose);
    controller.replace(<InkStroke>[
      stroke(0.1),
      stroke(0.2, kind: StrokeKind.highlighter),
      stroke(0.3, text: 'Text'),
      stroke(0.4, kind: StrokeKind.image),
    ]);
    controller.selectHandwriting = false;
    controller.selectText = false;
    controller.selectImages = false;
    controller.selectAll();
    expect(controller.selectedStrokes.single.kind, StrokeKind.highlighter);
    controller.beginLasso(const InkPoint(0, 0, 1));
    controller.setRectangleLasso(
      const InkPoint(0, 0, 1),
      const InkPoint(1, 1, 1),
    );
    controller.finishLasso();
    expect(controller.selectedStrokes.single.kind, StrokeKind.highlighter);
  });
}
