import 'package:fastink_flutter/src/engine/ink_canvas.dart';
import 'package:fastink_flutter/src/models/models.dart' show PenStyle;
import 'package:fastink_flutter/src/platform/native_pen_pressure.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sensitivity exposes a clear width difference at middle pressure', () {
    double width(double sensitivity) => penPressureWidthFactor(
      PenStyle.fountain,
      mapPenPressure(.5, PressureCurve.linear, sensitivity),
    );
    expect(width(2) / width(.5), greaterThan(4));
    expect(mapPenPressure(.5, PressureCurve.linear, 1), .5);
    expect(mapPenPressure(1, PressureCurve.firm, .5), 1);
    expect(penPressureWidthFactor(PenStyle.ball, .05), 1);
  });

  test(
    'native pressure expires and mouse contact clears the old pen sample',
    () {
      Duration now = Duration.zero;
      final native = NativePenPressure(now: () => now);
      const pen = PointerDownEvent(pointer: 93, kind: PointerDeviceKind.stylus);
      native.update(.3);
      expect(native.forEvent(pen), .3);
      now += NativePenPressure.maxAge + const Duration(microseconds: 1);
      expect(native.forEvent(pen), isNull);
      native.update(.7);
      expect(
        native.forEvent(const PointerDownEvent(kind: PointerDeviceKind.mouse)),
        isNull,
      );
      expect(native.forEvent(pen), isNull);
      native.update(.4);
      expect(native.forEvent(pen), .4);
      expect(
        native.forEvent(const PointerMoveEvent(kind: PointerDeviceKind.touch)),
        isNull,
      );
    },
  );

  test('invalid native samples cannot replace a valid sample', () {
    final native = NativePenPressure(now: () => Duration.zero)..update(.4);
    for (final value in [double.nan, double.infinity, -1.0, 0.0, 2.0]) {
      native.update(value);
    }
    expect(
      native.forEvent(const PointerDownEvent(kind: PointerDeviceKind.stylus)),
      .4,
    );
  });

  for (final useNative in [false, true]) {
    testWidgets('two mouse strokes then repeated pen switches preserve '
        '${useNative ? 'legacy Windows' : 'Flutter'} pressure', (tester) async {
      final controller = InkController(onCommitted: () {});
      final native = NativePenPressure(now: () => Duration.zero);
      await _mount(tester, controller, native.forEvent);

      int pointer = 1;
      Future<void> mouseStroke() async {
        await _stroke(
          tester,
          pointer++,
          PointerDeviceKind.mouse,
          [1, 1, 1],
          beforeSample: (_) => native.update(.2),
        );
        expect(
          controller.strokes.last.points.map((p) => p.pressure),
          everyElement(.72),
        );
      }

      await mouseStroke();
      await mouseStroke();
      for (int contact = 0; contact < 4; contact++) {
        // Flutter contact IDs keep increasing; the Windows pen ID remains
        // independent. Real events or fresh native samples must both work.
        await _stroke(
          tester,
          pointer++,
          PointerDeviceKind.stylus,
          useNative ? [1, 1, 1] : [.15, .85, .3],
          beforeSample: (index) {
            if (useNative) native.update([.15, .85, .3][index]);
          },
        );
        final pressures = controller.strokes.last.points.map((p) => p.pressure);
        expect(pressures, orderedEquals([.15, .85, .3]));
        await mouseStroke();
      }
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    });
  }

  testWidgets('current stylus pressure wins over a conflicting native sample', (
    tester,
  ) async {
    final controller = InkController(onCommitted: () {});
    final native = NativePenPressure(now: () => Duration.zero)..update(.1);
    await _mount(tester, controller, native.forEvent);
    await _stroke(tester, 71, PointerDeviceKind.stylus, [.2, .9, .4]);
    expect(
      controller.strokes.single.points.map((p) => p.pressure),
      orderedEquals([.2, .9, .4]),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('expired native pressure cannot flatten a later pen stroke', (
    tester,
  ) async {
    Duration now = Duration.zero;
    final controller = InkController(onCommitted: () {});
    final native = NativePenPressure(now: () => now)..update(.1);
    now = const Duration(seconds: 1);
    await _mount(tester, controller, native.forEvent);
    await _stroke(tester, 42, PointerDeviceKind.stylus, [.2, 1, .3]);
    expect(
      controller.strokes.single.points.map((p) => p.pressure),
      orderedEquals([.2, 1.0, .3]),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets(
    'Windows raw pressure range normalizes before applying the curve',
    (tester) async {
      final controller = InkController(onCommitted: () {});
      final native = NativePenPressure(now: () => Duration.zero)..update(.7);
      await _mount(tester, controller, native.forEvent);
      await _stroke(tester, 20, PointerDeviceKind.stylus, [
        1,
        1024,
        512,
      ], pressureMax: 1024);
      expect(
        controller.strokes.single.points.map((p) => p.pressure),
        orderedEquals([.05, 1.0, .5]),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    },
  );

  testWidgets('pressure switch and curve still apply after device changes', (
    tester,
  ) async {
    final controller = InkController(onCommitted: () {});
    final native = NativePenPressure(now: () => Duration.zero)..update(.5);
    await _mount(tester, controller, native.forEvent, pressureEnabled: false);
    await _stroke(tester, 1, PointerDeviceKind.mouse, [1, 1, 1]);
    await _stroke(tester, 2, PointerDeviceKind.stylus, [.2, .9, .3]);
    expect(
      controller.strokes.last.points.map((p) => p.pressure),
      everyElement(.72),
    );
    await _mount(
      tester,
      controller,
      native.forEvent,
      curve: PressureCurve.firm,
      sensitivity: .8,
    );
    await _stroke(tester, 3, PointerDeviceKind.stylus, [.2, .9, .3]);
    expect(
      controller.strokes.last.points.map((p) => p.pressure),
      orderedEquals(
        [.2, .9, .3].map((p) => mapPenPressure(p, PressureCurve.firm, .8)),
      ),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
}

Future<void> _mount(
  WidgetTester tester,
  InkController controller,
  double? Function(PointerEvent) pressure, {
  bool pressureEnabled = true,
  PressureCurve curve = PressureCurve.linear,
  double sensitivity = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: InkLayer(
        controller: controller,
        tool: InkTool.pen,
        color: Colors.black,
        width: 3,
        eraserMode: EraserMode.stroke,
        eraserSize: 30,
        momentaryTool: null,
        enabled: true,
        pressureEnabled: pressureEnabled,
        pressureCurve: curve,
        pressureSensitivity: sensitivity,
        pressureForEvent: pressure,
        onDrawingChanged: (_) {},
        onPenButtonChanged: (_, _) {},
        onTextRequested: (_, _) {},
      ),
    ),
  );
}

Future<void> _stroke(
  WidgetTester tester,
  int pointer,
  PointerDeviceKind kind,
  List<double> pressure, {
  void Function(int)? beforeSample,
  double pressureMax = 1,
}) async {
  final int device = kind == PointerDeviceKind.mouse ? 0 : 0x20000000;
  beforeSample?.call(0);
  await tester.sendEventToBinding(
    PointerDownEvent(
      pointer: pointer,
      device: device,
      kind: kind,
      buttons: kPrimaryButton,
      position: const Offset(100, 100),
      pressure: pressure.first,
      pressureMin: 0,
      pressureMax: pressureMax,
    ),
  );
  for (int index = 1; index < pressure.length; index++) {
    beforeSample?.call(index);
    await tester.sendEventToBinding(
      PointerMoveEvent(
        pointer: pointer,
        device: device,
        kind: kind,
        buttons: kPrimaryButton,
        position: Offset(100 + index * 50, 100 + index * 20),
        delta: const Offset(50, 20),
        pressure: pressure[index],
        pressureMin: 0,
        pressureMax: pressureMax,
      ),
    );
  }
  await tester.sendEventToBinding(
    PointerUpEvent(
      pointer: pointer,
      device: device,
      kind: kind,
      position: const Offset(200, 140),
    ),
  );
}
