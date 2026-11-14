import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:fastink_flutter/src/engine/ink_canvas.dart';
import 'package:fastink_flutter/src/models/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'ink_render_cache_test.dart' show surface;

void main() {
  testWidgets(
    'text motion renders intermediate positions without changing saved data or adding undo records',
    (tester) async {
      tester.view.physicalSize = const Size(400, 500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var commits = 0;
      final ink = InkController(onCommitted: () => commits++);
      const size = Size(400, 500);
      ink.addText(
        const InkPoint(.08, .08, .5),
        size,
        'Move this text',
        Colors.black,
        20,
        boxWidth: 200,
      );
      final original = ink.selectedTextStroke!;
      final before = jsonEncode(original.toJson());
      ink.updateText(
        original,
        original.text!,
        size,
        fontSize: 14,
        boxWidth: 260,
        anchor: const InkPoint(.25, .65, .5),
        rotation: 0,
        resetScale: true,
      );
      final saved = jsonEncode(ink.snapshot().map((s) => s.toJson()).toList());
      final committed = commits;
      ink.startTextRelocation(ink.selectedTextStroke!, original.points);
      final capture = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(key: capture, child: surface(ink, retained: true)),
      );
      Future<Uint8List> pixels() async => (await tester.runAsync(() async {
        final boundary =
            capture.currentContext!.findRenderObject() as RenderRepaintBoundary;
        final image = await boundary.toImage();
        try {
          return (await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!.buffer.asUint8List();
        } finally {
          image.dispose();
        }
      }))!;
      final start = await pixels();
      final paints = ink.debugCommittedPaintCount;
      ink.updateTextRelocation(.5);
      await tester.pump();
      final middle = await pixels();
      expect(middle, isNot(orderedEquals(start)));
      expect(ink.debugCommittedPaintCount, paints);
      expect(jsonEncode(ink.snapshot().map((s) => s.toJson()).toList()), saved);
      ink.updateTextRelocation(1);
      await tester.pump();
      expect(await pixels(), isNot(orderedEquals(middle)));
      ink.finishTextRelocation();
      expect(commits, committed);
      ink.undo();
      expect(jsonEncode(ink.strokes.single.toJson()), before);
      ink.redo();
      ink.startTextRelocation(ink.strokes.single, original.points);
      ink.updateTextRelocation(.4);
      ink.undo();
      expect(ink.isTextRelocating, isFalse);
      expect(jsonEncode(ink.strokes.single.toJson()), before);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
      ink.dispose();
    },
  );
}
