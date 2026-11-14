import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:fastink_flutter/src/capture/screenshot_document.dart';
import 'package:fastink_flutter/src/capture/screenshot_editor.dart';
import 'package:fastink_flutter/src/engine/ink_canvas.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _CaptureHarness {
  _CaptureHarness(this.tester, this.doc, this.buttons);
  final WidgetTester tester;
  final ScreenshotDocument doc;
  final ValueNotifier<int> buttons;
  int copies = 0, saves = 0;
  Offset at(double x, double y) {
    final r = tester.getRect(find.byKey(const ValueKey('capture-canvas')));
    final size = doc.displaySize;
    final scale = math
        .min((r.width - 32) / size.width, (r.height - 32) / size.height)
        .clamp(.001, 4.0);
    final origin = r.center - Offset(size.width, size.height) * scale / 2;
    return origin + doc.toDisplay(Offset(x, y)) * scale;
  }

  Future<void> tap(
    String id, {
    PointerDeviceKind kind = PointerDeviceKind.mouse,
  }) => tester.tap(find.byKey(ValueKey('capture-$id')), kind: kind);
  Future<void> drag(
    PointerDeviceKind kind, {
    int buttons = kPrimaryButton,
    int pointer = 1,
  }) async {
    final g = await tester.startGesture(
      at(40, 40),
      kind: kind,
      buttons: buttons,
      pointer: pointer,
    );
    await g.moveTo(at(260, 220));
    await g.up();
    await tester.pump();
  }

  Future<void> dispose() async {
    await tester.pumpWidget(const SizedBox.shrink());
    doc.dispose();
    buttons.dispose();
  }
}

Future<_CaptureHarness> _openCapture(
  WidgetTester tester, {
  bool momentary = true,
}) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final doc = (await tester.runAsync(() async {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(
      const Rect.fromLTWH(0, 0, 600, 400),
      Paint()..color = Colors.white,
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(600, 400);
    picture.dispose();
    return ScreenshotDocument.create(image);
  }))!;
  final h = _CaptureHarness(tester, doc, ValueNotifier(0));
  await tester.pumpWidget(
    MaterialApp(
      home: ScreenshotEditor(
        document: doc,
        nativePenButtons: h.buttons,
        penButtonMomentary: momentary,
        eraserSize: 12,
        penButtons: const {
          kPrimaryStylusButton: (tool: InkTool.lasso, eraser: null),
          kSecondaryStylusButton: (
            tool: InkTool.eraser,
            eraser: EraserMode.point,
          ),
        },
        onCopy: (_) async {
          h.copies++;
        },
        onSave: (_) async {
          h.saves++;
          return true;
        },
      ),
    ),
  );
  await tester.pump();
  return h;
}

void main() {
  testWidgets(
    'the dedicated crop tool accepts pen drag and preserves history on cancel',
    (tester) async {
      final h = await _openCapture(tester);
      await h.drag(PointerDeviceKind.stylus);
      expect(h.doc.crop!.left, closeTo(40, .001));
      expect(h.doc.crop!.right, closeTo(260, .001));
      final crop = h.doc.crop;
      h.doc.undo();
      expect(h.doc.canRedo, isTrue);
      final pen = await tester.startGesture(
        h.at(100, 80),
        kind: PointerDeviceKind.stylus,
      );
      await pen.moveTo(h.at(300, 200));
      await pen.cancel();
      await tester.pump();
      expect(h.doc.crop, isNull);
      expect(h.doc.canRedo, isTrue);
      h.doc.redo();
      expect(h.doc.crop, crop);
      await h.dispose();
    },
  );

  testWidgets('touch cannot crop or activate screenshot tools', (tester) async {
    final h = await _openCapture(tester);
    await h.tap('pen', kind: PointerDeviceKind.touch);
    await h.drag(PointerDeviceKind.touch);
    expect(h.doc.crop, isNull);
    expect(h.doc.canUndo, isFalse);
    await h.drag(PointerDeviceKind.stylus);
    expect(h.doc.crop, isNotNull);
    expect(h.doc.marks, isEmpty);
    expect(find.byKey(const ValueKey('capture-barrel-1')), findsNothing);
    await h.dispose();
  });

  testWidgets(
    'the note selection side button moves annotations and cannot crop',
    (tester) async {
      final h = await _openCapture(tester);
      await h.drag(
        PointerDeviceKind.stylus,
        buttons: kPrimaryButton | kPrimaryStylusButton,
      );
      expect(h.doc.crop, isNull);
      h.doc.crop = h.doc.imageRect;
      h.doc.add(
        const CaptureMark(
          tool: CaptureTool.rectangle,
          points: [Offset(30, 30), Offset(80, 80)],
        ),
      );
      await tester.pump();
      await h.tap('pen');
      await h.drag(
        PointerDeviceKind.stylus,
        buttons: kPrimaryButton | kPrimaryStylusButton,
        pointer: 51,
      );
      expect(h.doc.crop, h.doc.imageRect);
      expect(h.doc.marks.single.points.first.dx, closeTo(250, .001));
      await h.drag(PointerDeviceKind.stylus, pointer: 52);
      expect(h.doc.marks.last.tool, CaptureTool.pen);
      await h.dispose();
    },
  );

  testWidgets(
    'the native eraser side button cuts the stroke and undo restores it',
    (tester) async {
      final h = await _openCapture(tester);
      h.doc.crop = h.doc.imageRect;
      final original = CaptureMark(
        tool: CaptureTool.pen,
        points: const [Offset(20, 100), Offset(300, 100)],
      );
      h.doc.add(original);
      await tester.pump();
      await h.tap('pen');
      h.buttons.value = kSecondaryStylusButton;
      await tester.tapAt(h.at(140, 100), kind: PointerDeviceKind.stylus);
      h.buttons.value = 0;
      await tester.pump();
      expect(h.doc.marks, hasLength(2));
      expect(h.doc.marks.first.points.last.dx, lessThan(140));
      expect(h.doc.marks.last.points.first.dx, greaterThan(140));
      expect(h.doc.crop, h.doc.imageRect);
      h.doc.undo();
      expect(h.doc.marks.single, same(original));
      await h.dispose();
    },
  );

  testWidgets(
    'a late side button press switches the active gesture from writing to selecting',
    (tester) async {
      final h = await _openCapture(tester);
      h.doc.crop = h.doc.imageRect;
      h.doc.add(
        const CaptureMark(
          tool: CaptureTool.rectangle,
          points: [Offset(180, 100), Offset(220, 160)],
        ),
      );
      await tester.pump();
      await h.tap('pen');
      final pen = await tester.startGesture(
        h.at(60, 60),
        kind: PointerDeviceKind.stylus,
        pointer: 61,
      );
      await pen.moveTo(h.at(90, 75));
      for (final x in [200.0, 260.0]) {
        await pen.updateWithCustomEvent(
          PointerMoveEvent(
            pointer: 61,
            kind: PointerDeviceKind.stylus,
            buttons: kPrimaryButton | kPrimaryStylusButton,
            position: h.at(x, 130),
          ),
        );
      }
      await pen.up();
      await tester.pump();
      expect(h.doc.crop, h.doc.imageRect);
      expect(h.doc.marks.first.points.first.dx, closeTo(240, .001));
      expect(h.doc.marks.last.tool, CaptureTool.pen);
      await h.dispose();
    },
  );

  testWidgets(
    'toggle mode keeps the mapped tool after releasing the side button',
    (tester) async {
      final h = await _openCapture(tester, momentary: false);
      h.doc.crop = h.doc.imageRect;
      h.doc.add(
        const CaptureMark(
          tool: CaptureTool.pen,
          points: [Offset(20, 40), Offset(300, 40)],
        ),
      );
      await tester.pump();
      h.buttons.value = kSecondaryStylusButton;
      h.buttons.value = 0;
      await tester.tapAt(h.at(120, 40), kind: PointerDeviceKind.stylus);
      expect(h.doc.marks, hasLength(2));
      await h.tap('crop');
      await tester.pump();
      await h.drag(PointerDeviceKind.mouse);
      expect(h.doc.crop, isNotNull);
      await h.dispose();
    },
  );
}
