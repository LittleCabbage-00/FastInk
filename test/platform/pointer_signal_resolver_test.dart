import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('document listener wins and resolves one wheel event', (
    WidgetTester tester,
  ) async {
    int resolved = 0;
    Offset? delta;
    await tester.pumpWidget(
      MaterialApp(
        home: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerSignal: (PointerSignalEvent event) {
            GestureBinding.instance.pointerSignalResolver.register(event, (
              PointerSignalEvent accepted,
            ) {
              resolved++;
              delta = (accepted as PointerScrollEvent).scrollDelta;
            });
          },
          child: const SizedBox.expand(),
        ),
      ),
    );

    tester.binding.handlePointerEvent(
      const PointerScrollEvent(
        position: Offset(100, 100),
        scrollDelta: Offset(0, 120),
      ),
    );
    await tester.pump();

    expect(resolved, 1);
    expect(delta, const Offset(0, 120));
  });
}
