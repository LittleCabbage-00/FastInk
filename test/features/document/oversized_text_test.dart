import 'package:fastink_flutter/src/engine/ink_canvas.dart';
import 'package:fastink_flutter/src/models/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('oversized text remains movable, scalable, editable and undoable', () {
    final ink = InkController(onCommitted: () {});
    const page = Size(800, 1000);
    final text = List.filled(300, 'large text').join('\n');
    ink.addText(
      const InkPoint(.1, .1, .5),
      page,
      text,
      Colors.black,
      80,
      boxWidth: 240,
    );
    expect(ink.selectionBounds!.bottom, greaterThan(1));
    final original = ink.strokes.single.copy();
    expect(
      ink.beginSelectionTransform(const InkPoint(.2, .4, .5), page),
      SelectionTransform.move,
    );
    ink.updateSelectionTransform(const InkPoint(.3, .2, .5), page);
    ink.finishSelectionTransform();
    expect(
      ink.strokes.single.points.first.y,
      lessThan(original.points.first.y),
    );
    ink.undo();
    ink.selectOnly(ink.strokes.single);
    final bounds = ink.selectionBounds!;
    expect(
      ink.beginSelectionTransform(
        InkPoint(bounds.right, bounds.bottom, .5),
        page,
      ),
      SelectionTransform.scale,
    );
    ink.updateSelectionTransform(const InkPoint(.2, .3, .5), page);
    ink.finishSelectionTransform();
    expect(ink.selectionBounds!.height, lessThanOrEqualTo(1));
    ink.updateText(
      ink.selectedTextStroke!,
      '$text\nedited',
      page,
      fontSize: 12.5,
      boxWidth: 600,
      textFontFamily: 'Consolas',
      anchor: const InkPoint(.04, .04, .5),
      rotation: 0,
    );
    expect(ink.strokes.single.text, endsWith('edited'));
    expect(ink.strokes.single.textFontFamily, 'Consolas');
    final updated = ink.strokes.single;
    final displayedScale =
        (updated.points[1].x - updated.points[0].x) / updated.textBoxWidth!;
    expect(
      updated.textSize * page.height * displayedScale,
      closeTo(12.5, .001),
    );

    ink.undo();
    expect(ink.strokes.single.text, text);
    ink.redo();
    expect(ink.strokes.single.text, endsWith('edited'));
    ink.dispose();
  });
}
