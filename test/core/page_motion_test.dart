import 'package:fastink_flutter/src/core/page_motion.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('plain wheel remains vertical and modifiers have isolated meanings', () {
    expect(
      documentWheelIntent(controlPressed: false, shiftPressed: false),
      DocumentWheelIntent.verticalScroll,
    );
    expect(
      documentWheelIntent(controlPressed: false, shiftPressed: true),
      DocumentWheelIntent.horizontalPan,
    );
    expect(
      documentWheelIntent(controlPressed: true, shiftPressed: true),
      DocumentWheelIntent.zoom,
    );
  });

  test('inertia strength changes distance and remains bounded', () {
    expect(touchPanCoastDistance(1000, 0), 0);
    expect(touchPanCoastDistance(1000, 1), 320);
    expect(touchPanCoastDistance(9000, 2), 1800);
    expect(touchPanCoastDuration(1000, 1), const Duration(milliseconds: 503));
  });

  test('touch inertia only uses a recent movement sample', () {
    expect(
      hasFreshTouchVelocity(
        lastMove: const Duration(milliseconds: 100),
        releaseTime: const Duration(milliseconds: 175),
      ),
      isTrue,
    );
    expect(
      hasFreshTouchVelocity(
        lastMove: const Duration(milliseconds: 100),
        releaseTime: const Duration(milliseconds: 250),
      ),
      isFalse,
    );
  });
}
