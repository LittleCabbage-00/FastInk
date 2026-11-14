import 'dart:math' as math;

import 'package:fastink_flutter/src/core/document_viewport_layout.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';

void main() {
  DocumentViewportLayout layout({int pages = 4}) =>
      DocumentViewportLayout.build(
        viewport: const Size(1000, 700),
        aspectRatios: List<double>.filled(pages, 0.7),
        referenceAspectRatio: 0.7,
      );

  test('pages keep one continuous ordered coordinate system', () {
    final DocumentViewportLayout value = layout();
    for (int index = 1; index < value.pages.length; index++) {
      expect(
        value.pages[index].top,
        greaterThan(value.pages[index - 1].bottom),
      );
    }
  });

  test('landscape and portrait pages preserve one physical paper scale', () {
    final DocumentViewportLayout value = DocumentViewportLayout.build(
      viewport: const Size(1800, 1100),
      aspectRatios: const <double>[0.707, 1.414],
      referenceAspectRatio: 0.707,
    );
    final Rect portrait = value.pages[0];
    final Rect landscape = value.pages[1];
    expect(landscape.width / portrait.width, closeTo(math.sqrt(2), 0.002));
    expect(landscape.height, closeTo(portrait.width, 1));
    expect(
      landscape.width * landscape.height,
      closeTo(portrait.width * portrait.height, 2),
    );
    expect(portrait.center.dx, closeTo(900, 0.001));
    expect(landscape.center.dx, closeTo(900, 0.001));
  });

  test('binary lookup follows camera without page snapping', () {
    final DocumentViewportLayout value = layout();
    final Matrix4 camera = Matrix4.identity();
    camera[13] = -value.pages[1].center.dy + value.viewport.height / 2;
    expect(value.pageAtViewportCenter(camera), 1);

    camera[13] -= 37;
    expect(value.constrainCamera(camera)[13], closeTo(camera[13], 0.001));
  });

  test('horizontal movement is hard clamped when document fits', () {
    final DocumentViewportLayout value = layout();
    final Matrix4 camera = Matrix4.identity()..setTranslationRaw(900, 0, 0);
    final Matrix4 constrained = value.constrainCamera(camera);
    final Matrix4 elastic = value.elasticCamera(camera);
    expect(elastic[12], constrained[12]);
  });

  test('vertical elasticity exists only at true document edges', () {
    final DocumentViewportLayout value = layout();
    final Matrix4 middle = value.cameraForPage(Matrix4.identity(), 1);
    final Matrix4 middleElastic = value.elasticCamera(middle);
    expect(middleElastic[13], closeTo(middle[13], 0.001));

    final Matrix4 beyondTop = Matrix4.identity()..setTranslationRaw(0, 200, 0);
    final Matrix4 topLegal = value.constrainCamera(beyondTop);
    final Matrix4 topElastic = value.elasticCamera(beyondTop);
    expect(topElastic[13], greaterThan(topLegal[13]));
    expect(topElastic[13], lessThan(100));

    // 阻尼随距离平滑增强，不会在很短的拉动后突然像撞上硬边界。
    final Matrix4 shortPull = Matrix4.identity()..setTranslationRaw(0, 20, 0);
    final Matrix4 longPull = Matrix4.identity()..setTranslationRaw(0, 80, 0);
    final double shortElastic = value.elasticCamera(shortPull)[13];
    final double longElastic = value.elasticCamera(longPull)[13];
    expect(shortElastic, greaterThan(15));
    expect(longElastic, greaterThan(shortElastic * 2));
  });

  test('visible range stays bounded for a 3022 page document', () {
    final DocumentViewportLayout value = layout(pages: 3022);
    final Matrix4 camera = value.cameraForPage(Matrix4.identity(), 2400);
    final (int first, int last) = value.visibleRange(camera);
    expect(first, greaterThan(2390));
    expect(last - first, lessThan(8));
  });
}
