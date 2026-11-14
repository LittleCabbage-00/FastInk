import 'dart:math' as math;

import 'package:fastink_flutter/src/engine/ink_canvas.dart';
import 'package:fastink_flutter/src/models/models.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'point eraser clips sparse lines exactly without adding untouched samples',
    () {
      final controller = InkController(onCommitted: () {});
      final original = InkStroke(
        color: 0xff101010,
        width: .003,
        points: [const InkPoint(.1, .5, .2), const InkPoint(.9, .5, .8)],
      );
      controller.replace([original]);
      expect(
        controller.eraseAt(
          const InkPoint(.5, .5, .5),
          const Size(1000, 1000),
          30,
          EraserMode.point,
        ),
        isTrue,
      );
      expect(controller.strokes.map((s) => s.points.length), [2, 2]);
      expect(controller.strokes.first.points.last.x, closeTo(.47, 1e-9));
      expect(controller.strokes.last.points.first.x, closeTo(.53, 1e-9));
      expect(
        controller.strokes.first.points.last.pressure,
        closeTo(.4775, 1e-9),
      );
      expect(
        controller.eraseAt(
          const InkPoint(.5, .5, .5),
          const Size(1000, 1000),
          30,
          EraserMode.point,
        ),
        isFalse,
      );
      controller.undo();
      expect(controller.strokes.single.points.length, 2);
      expect(controller.strokes.single, same(original));
      controller.redo();
      expect(controller.strokes.map((s) => s.points.length), [2, 2]);
      controller.replace([
        original.copy(
          points: [
            const InkPoint(.1, .5, .1),
            const InkPoint(.1, .5, .2),
            const InkPoint(.9, .5, .8),
          ],
        ),
      ]);
      controller.eraseAt(
        const InkPoint(.5, .5, .5),
        const Size(1000, 1000),
        30,
        EraserMode.point,
      );
      expect(controller.strokes.first.points.take(2).map((p) => p.pressure), [
        .1,
        .2,
      ]);
      controller.dispose();
    },
  );
  test('pressure curves distinguish light and firm pen contact', () {
    final double linear = mapPenPressure(0.25, PressureCurve.linear, 1);
    expect(mapPenPressure(0.25, PressureCurve.gentle, 1), greaterThan(linear));
    expect(mapPenPressure(0.25, PressureCurve.firm, 1), lessThan(linear));
    expect(mapPenPressure(1, PressureCurve.firm, 1), 1);
  });

  test('old saved strokes remain compatible and default to pen', () {
    final InkStroke stroke = InkStroke.fromJson(<String, Object?>{
      'color': 0xff000000,
      'width': 3,
      'points': <Object?>[
        <String, Object?>{'x': 0.1, 'y': 0.2, 'p': 0.5},
      ],
    });

    expect(stroke.kind, StrokeKind.pen);
  });

  test('embedded image is persisted and reuses selection transforms', () {
    int commits = 0;
    final InkController controller = InkController(
      onCommitted: () => commits++,
    );
    controller.addImage(
      'assets/photo.webp',
      2,
      const Size(1000, 1400),
      placementBounds: const Rect.fromLTWH(100, 160, 280, 220),
    );
    expect(controller.selectedStrokes.single.kind, StrokeKind.image);
    expect(
      InkStroke.fromJson(controller.strokes.single.toJson()).imageAsset,
      'assets/photo.webp',
    );
    final Rect before = controller.selectionBounds!;
    expect(before.center.dx, closeTo(.24, .0001));
    expect(before.center.dy, closeTo(270 / 1400, .0001));
    final SelectionTransform? transform = controller.beginSelectionTransform(
      InkPoint(before.center.dx, before.center.dy, 0.5),
      const Size(1000, 1400),
    );
    expect(transform, SelectionTransform.move);
    controller.updateSelectionTransform(
      InkPoint(before.center.dx + 0.05, before.center.dy + 0.05, 0.5),
      const Size(1000, 1400),
    );
    controller.finishSelectionTransform();
    expect(controller.selectionBounds!.left, greaterThan(before.left));
    expect(commits, greaterThanOrEqualTo(2));
  });

  test('point eraser removes only the touched part of a stroke', () {
    int commits = 0;
    final InkController controller = InkController(
      onCommitted: () {
        commits++;
      },
    );
    controller.begin(
      const InkPoint(0.1, 0.5, 0.5),
      Colors.black,
      3,
      StrokeKind.pen,
    );
    controller.append(const InkPoint(0.9, 0.5, 0.5));
    controller.finish();

    final bool erased = controller.eraseAt(
      const InkPoint(0.5, 0.5, 0.5),
      const Size(1000, 1000),
      30,
      EraserMode.point,
    );

    expect(erased, isTrue);
    expect(controller.strokes, hasLength(2));
    expect(commits, 2);
    controller.dispose();
  });

  test('held pen stroke straightens and keeps an adjustable endpoint', () {
    final InkController controller = InkController(onCommitted: () {});
    controller.begin(
      const InkPoint(0.1, 0.2, 0.5),
      Colors.black,
      3,
      StrokeKind.pen,
    );
    controller
      ..append(const InkPoint(0.3, 0.28, 0.6))
      ..append(const InkPoint(0.55, 0.42, 0.7));
    expect(controller.straightenActiveStroke(const Size(1000, 1400)), isTrue);
    expect(controller.activeStroke!.points, hasLength(2));
    controller.updateStraightenedStroke(const InkPoint(0.8, 0.5, 0.8));
    expect(controller.activeStroke!.points.last.x, 0.8);
    controller.finish();
    expect(controller.strokes.single.points.last.y, 0.5);
  });

  test('eraser bounds stay correct across samples and separate gestures', () {
    int commits = 0;
    final InkController controller = InkController(
      onCommitted: () => commits++,
    );
    for (final double x in <double>[0.2, 0.8]) {
      controller.begin(InkPoint(x, 0.3, 0.5), Colors.black, 3, StrokeKind.pen);
      controller.append(InkPoint(x, 0.7, 0.5));
      controller.finish();
    }
    expect(commits, 2);

    controller.beginHistoryTransaction(deferSnapshot: true);
    expect(
      controller.eraseAt(
        const InkPoint(0.5, 0.5, 0.5),
        const Size(1000, 1000),
        25,
        EraserMode.stroke,
      ),
      isFalse,
    );
    expect(
      controller.eraseAt(
        const InkPoint(0.2, 0.5, 0.5),
        const Size(1000, 1000),
        25,
        EraserMode.stroke,
      ),
      isTrue,
    );
    expect(
      controller.eraseAt(
        const InkPoint(0.8, 0.5, 0.5),
        const Size(1000, 1000),
        25,
        EraserMode.stroke,
      ),
      isTrue,
    );
    controller.finishEraseGesture();
    expect(controller.strokes, isEmpty);
    expect(commits, 3);

    controller.undo();
    expect(controller.strokes, hasLength(2));
    expect(commits, 4);
    controller.beginHistoryTransaction(deferSnapshot: true);
    expect(
      controller.eraseAt(
        const InkPoint(0.8, 0.5, 0.5),
        const Size(1000, 1000),
        25,
        EraserMode.stroke,
      ),
      isTrue,
    );
    controller.finishEraseGesture();
    expect(controller.strokes, hasLength(1));
    expect(commits, 5);
    controller.dispose();
  });

  test('lasso selection can move, scale and delete selected ink', () {
    int commits = 0;
    final InkController controller = InkController(
      onCommitted: () {
        commits++;
      },
    );
    controller.begin(
      const InkPoint(0.10, 0.10, 0.5),
      Colors.black,
      3,
      StrokeKind.pen,
    );
    controller.append(const InkPoint(0.20, 0.20, 0.5));
    controller.finish();
    controller.begin(
      const InkPoint(0.70, 0.70, 0.5),
      Colors.red,
      3,
      StrokeKind.pen,
    );
    controller.append(const InkPoint(0.80, 0.80, 0.5));
    controller.finish();

    controller.beginLasso(const InkPoint(0.05, 0.05, 0.5));
    controller.appendLasso(const InkPoint(0.30, 0.05, 0.5));
    controller.appendLasso(const InkPoint(0.30, 0.30, 0.5));
    controller.appendLasso(const InkPoint(0.05, 0.30, 0.5));
    controller.finishLasso();
    expect(controller.selectedStrokes, hasLength(1));

    expect(
      controller.beginSelectionTransform(
        const InkPoint(0.15, 0.15, 0.5),
        const Size(1000, 1000),
      ),
      SelectionTransform.move,
    );
    controller.updateSelectionTransform(
      const InkPoint(0.25, 0.25, 0.5),
      const Size(1000, 1000),
    );
    controller.finishSelectionTransform();
    expect(controller.selectionBounds!.left, closeTo(0.20, 0.001));

    final Rect bounds = controller.selectionBounds!;
    expect(
      controller.beginSelectionTransform(
        InkPoint(bounds.right, bounds.bottom, 0.5),
        const Size(1000, 1000),
      ),
      SelectionTransform.scale,
    );
    controller.updateSelectionTransform(
      InkPoint(bounds.right + 0.1, bounds.bottom + 0.1, 0.5),
      const Size(1000, 1000),
    );
    controller.finishSelectionTransform();
    expect(controller.selectionBounds!.width, greaterThan(bounds.width));

    final InkPoint beforeRotation =
        controller.selectedStrokes.first.points.first;
    controller.rotateSelection(math.pi / 2);
    final InkPoint afterRotation =
        controller.selectedStrokes.first.points.first;
    expect(afterRotation.x, isNot(closeTo(beforeRotation.x, 0.001)));

    controller.deleteSelection();
    expect(controller.strokes, hasLength(1));
    expect(commits, 6);
    controller.dispose();
  });

  test(
    'rectangular lasso works when dragged from bottom right to top left',
    () {
      final InkController controller = InkController(onCommitted: () {});
      controller.begin(
        const InkPoint(0.20, 0.20, 0.5),
        Colors.black,
        3,
        StrokeKind.pen,
      );
      controller.append(const InkPoint(0.25, 0.25, 0.5));
      controller.finish();
      controller.begin(
        const InkPoint(0.70, 0.70, 0.5),
        Colors.red,
        3,
        StrokeKind.pen,
      );
      controller.append(const InkPoint(0.75, 0.75, 0.5));
      controller.finish();

      const InkPoint start = InkPoint(0.4, 0.4, 0.5);
      controller.beginLasso(start);
      controller.setRectangleLasso(start, const InkPoint(0.1, 0.1, 0.5));
      expect(controller.lassoPoints, hasLength(5));
      controller.finishLasso();
      expect(controller.selectedStrokes, hasLength(1));
      expect(controller.selectedStrokes.single.color, Colors.black.toARGB32());
      controller.dispose();
    },
  );

  test('rectangular lasso selects a sparse stroke crossing the box', () {
    final InkController controller = InkController(onCommitted: () {});
    controller.begin(
      const InkPoint(0.10, 0.25, 0.5),
      Colors.black,
      3,
      StrokeKind.pen,
    );
    controller.append(const InkPoint(0.90, 0.25, 0.5));
    controller.finish();
    const InkPoint start = InkPoint(0.4, 0.2, 0.5);
    controller.beginLasso(start);
    controller.setRectangleLasso(start, const InkPoint(0.6, 0.3, 0.5));
    controller.finishLasso();
    expect(controller.selectedStrokes, hasLength(1));
    controller.dispose();
  });

  test(
    'shape tool creates regular geometry and selection can duplicate it',
    () {
      final InkController controller = InkController(onCommitted: () {});
      controller.beginShape(
        const InkPoint(0.2, 0.2, 0.5),
        Colors.blue,
        4,
        ShapeType.rectangle,
      );
      controller.updateShape(
        const InkPoint(0.6, 0.5, 0.5),
        ShapeType.rectangle,
      );
      controller.finish();
      expect(controller.strokes.single.points, hasLength(5));

      controller.selectAll();
      controller.duplicateSelection();
      expect(controller.strokes, hasLength(2));
      expect(
        controller.selectedStrokes.single.points.first.x,
        closeTo(0.225, 0.001),
      );
      controller.dispose();
    },
  );

  test('free rotation preserves physical ink size on a portrait page', () {
    final InkController controller = InkController(onCommitted: () {});
    controller.begin(
      const InkPoint(0.40, 0.40, 0.5),
      Colors.black,
      6,
      StrokeKind.pen,
    );
    controller.append(const InkPoint(0.60, 0.40, 0.5));
    controller.finish();
    controller.selectAll();

    const Size portraitPage = Size(800, 1200);
    expect(
      controller.beginSelectionTransform(
        const InkPoint(0.50, 0.375, 0.5),
        portraitPage,
      ),
      SelectionTransform.rotate,
    );
    controller.updateSelectionTransform(
      const InkPoint(0.60, 0.40, 0.5),
      portraitPage,
    );
    controller.finishSelectionTransform();

    final List<InkPoint> points = controller.strokes.single.points;
    final double physicalLength = math.sqrt(
      math.pow((points.last.x - points.first.x) * portraitPage.width, 2) +
          math.pow((points.last.y - points.first.y) * portraitPage.height, 2),
    );
    expect(physicalLength, closeTo(160, 0.01));
    expect(controller.strokes.single.width, 6);
    controller.dispose();
  });

  test(
    'selection handles accept a generous touch target near the visual dot',
    () {
      final InkController controller = InkController(onCommitted: () {});
      controller.begin(
        const InkPoint(0.40, 0.40, 0.5),
        Colors.black,
        6,
        StrokeKind.pen,
      );
      controller.append(const InkPoint(0.60, 0.40, 0.5));
      controller.finish();
      controller.selectAll();

      expect(
        controller.beginSelectionTransform(
          const InkPoint(0.63, 0.42, 0.5),
          const Size(800, 1200),
        ),
        SelectionTransform.scale,
      );
      controller.finishSelectionTransform();
      expect(
        controller.beginSelectionTransform(
          const InkPoint(0.50, 0.50, 0.5),
          const Size(800, 1200),
          includeInterior: false,
        ),
        isNull,
      );
      controller.dispose();
    },
  );

  test('selection handle geometry stays screen-sized while zoomed', () {
    final InkController controller = InkController(onCommitted: () {});
    controller.begin(
      const InkPoint(0.40, 0.40, 0.5),
      Colors.black,
      6,
      StrokeKind.pen,
    );
    controller.append(const InkPoint(0.60, 0.40, 0.5));
    controller.finish();
    controller.selectAll();
    controller.selectionViewScale = 4;

    const Size page = Size(800, 1200);
    const double handleX = 481;
    const double handleY = 481;
    expect(
      controller.beginSelectionTransform(
        const InkPoint((handleX + 15) / 800, handleY / 1200, 0.5),
        page,
        includeInterior: false,
      ),
      SelectionTransform.scale,
    );
    controller.finishSelectionTransform();
    expect(
      controller.beginSelectionTransform(
        const InkPoint((handleX + 17) / 800, handleY / 1200, 0.5),
        page,
        includeInterior: false,
      ),
      isNull,
    );
    controller.dispose();
  });

  test('undo restores destructive and transformed selection edits', () {
    final InkController controller = InkController(onCommitted: () {});
    controller.begin(
      const InkPoint(0.25, 0.30, 0.5),
      Colors.black,
      5,
      StrokeKind.pen,
    );
    controller.append(const InkPoint(0.45, 0.50, 0.5));
    controller.finish();
    controller.selectAll();
    final List<InkPoint> original = List<InkPoint>.of(
      controller.strokes.single.points,
    );

    expect(
      controller.beginSelectionTransform(
        const InkPoint(0.35, 0.40, 0.5),
        const Size(800, 1200),
      ),
      SelectionTransform.move,
    );
    controller.updateSelectionTransform(
      const InkPoint(0.45, 0.50, 0.5),
      const Size(800, 1200),
    );
    controller.finishSelectionTransform();
    expect(controller.strokes.single.points.first.x, closeTo(0.35, 0.001));

    controller.undo();
    expect(controller.strokes.single.points.first.x, original.first.x);
    controller.redo();
    expect(controller.strokes.single.points.first.x, closeTo(0.35, 0.001));

    controller.selectAll();
    controller.deleteSelection();
    expect(controller.strokes, isEmpty);
    controller.undo();
    expect(controller.strokes, hasLength(1));
    controller.clear();
    expect(controller.strokes, isEmpty);
    controller.undo();
    expect(controller.strokes, hasLength(1));
    controller.dispose();
  });

  testWidgets('selected handles do not fall through to pen input', (
    WidgetTester tester,
  ) async {
    final InkController controller = InkController(onCommitted: () {});
    controller.begin(
      const InkPoint(0.30, 0.30, 0.5),
      Colors.black,
      4,
      StrokeKind.pen,
    );
    controller.append(const InkPoint(0.50, 0.30, 0.5));
    controller.finish();
    controller.selectAll();

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 600,
          height: 600,
          child: InkLayer(
            controller: controller,
            tool: InkTool.pen,
            color: Colors.black,
            width: 4,
            eraserMode: EraserMode.stroke,
            eraserSize: 30,
            momentaryTool: null,
            enabled: true,
            onDrawingChanged: (_) {},
            onPenButtonChanged: (_, _) {},
            onTextRequested: (_, _) {},
          ),
        ),
      ),
    );
    expect(tester.getSize(find.byType(InkLayer)), const Size(800, 600));
    final TestGesture gesture = await tester.startGesture(
      const Offset(418, 192),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveTo(const Offset(450, 230));
    await gesture.up();
    await tester.pump();

    expect(controller.strokes, hasLength(1));
    expect(controller.activeStroke, isNull);
    controller.dispose();
  });

  test('system-font text is persisted and participates in selection', () {
    final InkController controller = InkController(onCommitted: () {});
    controller.addText(
      const InkPoint(0.2, 0.2, 0.5),
      const Size(800, 1200),
      'FastInk 文本',
      Colors.blue,
      32,
      boxWidth: 240,
      textWeight: 700,
      textItalic: true,
      textUnderline: true,
      textAlign: TextAlign.center,
      textFontFamily: 'Microsoft YaHei UI',
    );

    expect(controller.strokes, hasLength(1));
    expect(controller.hasSelection, isTrue);
    final InkStroke restored = InkStroke.fromJson(
      controller.strokes.single.toJson(),
    );
    expect(restored.text, 'FastInk 文本');
    expect(restored.textSize, closeTo(32 / 1200, 0.0001));
    expect(restored.textBoxWidth, closeTo(240 / 800, 0.0001));
    expect(restored.textWeight, 700);
    expect(restored.textItalic, isTrue);
    expect(restored.textUnderline, isTrue);
    expect(restored.textAlign, TextAlign.center);
    expect(restored.textFontFamily, 'Microsoft YaHei UI');
    expect(restored.points, hasLength(4));
    expect(controller.textStrokeAt(const InkPoint(0.3, 0.21, 0.5)), isNotNull);
    controller.duplicateSelection();
    expect(controller.strokes, hasLength(2));
    controller.dispose();
  });

  test('narrow text near the page edge saves and reopens without widening', () {
    final controller = InkController(onCommitted: () {});
    const canvas = Size(800, 1200);
    controller.addText(
      const InkPoint(.92, .3, .5),
      canvas,
      'A',
      Colors.black,
      20,
      boxWidth: 50,
    );
    final original = controller.strokes.single;
    expect(original.textBoxWidth, closeTo(50 / 800, .0001));
    controller.updateText(original, 'B', canvas, boxWidth: 50);
    expect(controller.strokes.single.textBoxWidth, original.textBoxWidth);
    expect(controller.strokes.single.points[1].x, lessThanOrEqualTo(1));
    controller.undo();
    expect(controller.strokes.single.text, 'A');
    controller.dispose();
  });

  test('selected text reflows without unexpectedly widening its box', () {
    int commits = 0;
    final InkController controller = InkController(
      onCommitted: () => commits++,
    );
    const Size pageSize = Size(800, 1200);
    controller.addText(
      const InkPoint(0.2, 0.2, 0.5),
      pageSize,
      '旧文字',
      Colors.blue,
      32,
    );
    final InkStroke original = controller.selectedTextStroke!;
    final InkPoint origin = original.points.first;

    controller.updateText(original, '这是一段明显超过原始文本框宽度并且应该自动换行的较长文字内容', pageSize);

    expect(controller.strokes, hasLength(1));
    expect(controller.selectedTextStroke?.text, contains('自动换行'));
    expect(controller.selectedTextStroke?.points.first.x, origin.x);
    expect(controller.selectedTextStroke?.points.first.y, origin.y);
    expect(controller.selectedTextStroke!.points[1].x, original.points[1].x);
    expect(
      controller.selectedTextStroke!.points[3].y,
      greaterThan(original.points[3].y),
    );
    expect(commits, 2);
    controller.dispose();
  });

  testWidgets('laser trail stays out of saved ink and fades independently', (
    WidgetTester tester,
  ) async {
    final InkController controller = InkController(onCommitted: () {});
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 800,
          height: 600,
          child: InkLayer(
            controller: controller,
            tool: InkTool.laser,
            color: Colors.black,
            width: 3,
            eraserMode: EraserMode.stroke,
            eraserSize: 30,
            momentaryTool: null,
            enabled: true,
            laserMode: LaserMode.trail,
            laserColor: Colors.red,
            laserWidth: 7,
            laserFadeMs: 100,
            onDrawingChanged: (_) {},
            onPenButtonChanged: (_, _) {},
            onTextRequested: (_, _) {},
          ),
        ),
      ),
    );
    final TestGesture gesture = await tester.startGesture(
      const Offset(100, 100),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveTo(const Offset(260, 180));
    await gesture.up();
    await tester.pump();

    expect(controller.strokes, isEmpty);
    expect(controller.canUndo, isFalse);
    await tester.pump(const Duration(milliseconds: 150));
    expect(controller.strokes, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('late side-button event converts the first contact to eraser', (
    WidgetTester tester,
  ) async {
    final InkController controller = InkController(onCommitted: () {});
    controller.begin(
      const InkPoint(0.1, 0.5, 0.5),
      Colors.black,
      3,
      StrokeKind.pen,
    );
    controller.append(const InkPoint(0.9, 0.5, 0.5));
    controller.finish();

    InkTool? momentaryTool;
    late void Function(InkTool? value) setMomentaryTool;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            setMomentaryTool = (InkTool? value) => setState(() {
              momentaryTool = value;
            });
            return InkLayer(
              controller: controller,
              tool: InkTool.pen,
              color: Colors.black,
              width: 3,
              eraserMode: EraserMode.point,
              eraserSize: 30,
              momentaryTool: momentaryTool,
              enabled: true,
              onDrawingChanged: (_) {},
              onPenButtonChanged: (_, _) {},
              onTextRequested: (_, _) {},
            );
          },
        ),
      ),
    );

    final TestGesture gesture = await tester.createGesture(
      kind: PointerDeviceKind.stylus,
    );
    await gesture.down(tester.getCenter(find.byType(InkLayer)));
    await tester.pump();
    expect(controller.activeStroke, isNotNull);

    setMomentaryTool(InkTool.eraser);
    await tester.pump();
    expect(controller.activeStroke, isNull);
    expect(controller.strokes.length, greaterThanOrEqualTo(2));

    await gesture.up();
    await tester.pump();
    controller.dispose();
  });
}
