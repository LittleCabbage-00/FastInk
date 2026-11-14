import 'dart:convert';
import 'dart:io';
import 'package:fastink_flutter/src/core/text_box_placement.dart';
import 'package:fastink_flutter/src/core/settings_repository.dart';
import 'package:fastink_flutter/src/engine/ink_canvas.dart';
import 'package:fastink_flutter/src/models/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('fit reflows long text into blank space below handwriting', () async {
    const page = Size(800, 1000);
    final occupied = [const Rect.fromLTWH(20, 30, 760, 420)];
    final text = List.filled(15, 'Stream 的数据依次经过过滤和转换，如何处理？').join('\n');
    final fitted = await fitTextBoxToPage(
      text: text,
      style: const TextStyle(fontSize: 36),
      textAlign: TextAlign.left,
      preferred: const Rect.fromLTWH(32, 40, 736, 800),
      pageSize: page,
      occupied: occupied,
    );
    expect(fitted, isNotNull);
    expect(fitted!.bounds.top, greaterThan(450));
    expect(occupied.any(fitted.bounds.overlaps), isFalse);
    expect(fitted.bounds.bottom, lessThanOrEqualTo(960));
    expect(fitted.fontSize, inInclusiveRange(1, 36));
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(fontSize: fitted.fontSize),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: fitted.bounds.width);
    expect(painter.height, closeTo(fitted.bounds.height, .01));
    painter.dispose();
  });

  test(
    'fit changes width for a side gap and keeps a small chosen font',
    () async {
      final occupied = [const Rect.fromLTWH(0, 0, 560, 1000)];
      final fitted = await fitTextBoxToPage(
        text: List.filled(8, 'Editable notes').join('\n'),
        style: const TextStyle(fontSize: 12),
        textAlign: TextAlign.center,
        preferred: const Rect.fromLTWH(32, 40, 736, 800),
        pageSize: const Size(800, 1000),
        occupied: occupied,
      );
      expect(fitted, isNotNull);
      expect(fitted!.bounds.left, greaterThan(560));
      expect(fitted.bounds.width, lessThan(220));
      expect(fitted.fontSize, 12);
      expect(fitted.hardToRead, isFalse);
      expect(occupied.any(fitted.bounds.overlaps), isFalse);
    },
  );

  test(
    'no blank space returns failure instead of a least-overlapping position',
    () async {
      expect(
        await fitTextBoxToPage(
          text: 'Keep all content',
          style: const TextStyle(fontSize: 12),
          textAlign: TextAlign.left,
          preferred: const Rect.fromLTWH(32, 40, 736, 200),
          pageSize: const Size(800, 1000),
          occupied: [const Rect.fromLTWH(0, 0, 800, 1000)],
        ),
        isNull,
      );
    },
  );

  test(
    'fitting transformed text excludes itself, preserves other objects and is one undo',
    () async {
      const page = Size(800, 1000);
      final ink = InkController(onCommitted: () {});
      ink.begin(const InkPoint(.1, .1, .3), Colors.black, .008, StrokeKind.pen);
      ink.append(const InkPoint(.8, .45, .8));
      ink.finish();
      final handwriting = ink.strokes.first;
      final originalInk = jsonEncode(handwriting.toJson());
      final text = List.filled(15, 'Long editable text').join('\n');
      ink.addText(
        const InkPoint(.04, .04, .5),
        page,
        text,
        Colors.black,
        50,
        boxWidth: 300,
      );
      final unscaled = ink.selectedTextStroke!;
      final anchor = unscaled.points.first;
      ink.replace([
        handwriting,
        unscaled.copy(
          points: unscaled.points
              .map(
                (p) => InkPoint(
                  anchor.x + (p.x - anchor.x) * 1.5,
                  anchor.y + (p.y - anchor.y) * 1.5,
                  p.pressure,
                ),
              )
              .toList(),
        ),
      ]);
      ink.selectOnly(ink.strokes.last);
      ink.rotateSelection(.1);
      final original = ink.selectedTextStroke!;
      final before = jsonEncode(original.toJson());
      final obstacles = ink.contentBounds(page, excluding: original);
      expect(obstacles, hasLength(1));
      final fitted = (await fitTextBoxToPage(
        text: text,
        style: const TextStyle(
          fontSize: 40,
          fontFamily: 'Segoe UI Variable',
          fontFamilyFallback: ['Microsoft YaHei UI'],
        ),
        textAlign: TextAlign.left,
        preferred: const Rect.fromLTWH(32, 40, 736, 800),
        pageSize: page,
        occupied: obstacles,
      ))!;
      ink.updateText(
        original,
        text,
        page,
        fontSize: fitted.fontSize,
        boxWidth: fitted.bounds.width,
        anchor: InkPoint(
          fitted.bounds.left / page.width,
          fitted.bounds.top / page.height,
          .5,
        ),
        rotation: 0,
        resetScale: true,
      );
      final result = ink.selectedTextStroke!;
      final actual = Rect.fromLTRB(
        result.points[0].x * page.width,
        result.points[0].y * page.height,
        result.points[2].x * page.width,
        result.points[2].y * page.height,
      );
      expect(actual.left, closeTo(fitted.bounds.left, .001));
      expect(actual.height, closeTo(fitted.bounds.height, .01));
      expect(obstacles.any(actual.overlaps), isFalse);
      expect(result.text, text);
      expect(jsonEncode(handwriting.toJson()), originalInk);
      ink.undo();
      expect(
        jsonEncode(
          ink.selectedTextStroke?.toJson() ?? ink.strokes.last.toJson(),
        ),
        before,
      );
      ink.redo();
      expect(ink.strokes.last.text, text);
      expect(jsonEncode(handwriting.toJson()), originalInk);
      ink.dispose();
    },
  );
  test(
    'nearest empty space avoids writing and stays stable when already clear',
    () {
      const area = Rect.fromLTWH(8, 8, 784, 984);
      const preferred = Rect.fromLTWH(100, 100, 180, 50);
      final writing = [const Rect.fromLTWH(80, 80, 250, 100)];
      final placed = placeTextBox(preferred, area, writing);
      expect(placed.overlaps(writing.single), isFalse);
      expect(area.contains(placed.topLeft), isTrue);
      expect(placeTextBox(placed, area, writing), placed);
      expect(placeTextBox(preferred, area, [area]).isFinite, isTrue);
    },
  );
  test('text grows with content and wraps at the available width', () {
    const style = TextStyle(fontSize: 12);
    final short = measureAdaptiveText('Short', style, 300);
    final longer = measureAdaptiveText(
      'A much longer line of text for the box',
      style,
      300,
    );
    final paragraph = measureAdaptiveText(
      List.filled(30, 'A much longer line').join('\n'),
      style,
      300,
    );
    expect(longer.width, greaterThan(short.width));
    expect(paragraph.height, greaterThan(longer.height));
    expect(paragraph.width, lessThanOrEqualTo(300));
  });

  test(
    'small blank space shrinks all text before requesting a readability warning',
    () async {
      final fitted = await fitTextBoxToPage(
        text: List.filled(12, 'Every line stays editable').join('\n'),
        style: const TextStyle(fontSize: 12),
        textAlign: TextAlign.left,
        preferred: const Rect.fromLTWH(32, 40, 736, 800),
        pageSize: const Size(800, 1000),
        occupied: [const Rect.fromLTWH(0, 0, 800, 880)],
      );
      expect(fitted, isNotNull);
      expect(fitted!.fontSize, lessThan(8));
      expect(fitted.hardToRead, isTrue);
      expect(fitted.bounds.top, greaterThan(880));
      expect(fitted.bounds.bottom, lessThanOrEqualTo(960));
    },
  );
  test('text and image bounds do not inherit handwriting thickness', () {
    final ink = InkController(onCommitted: () {});
    ink.addText(
      const InkPoint(.3, .4, .5),
      const Size(800, 1000),
      'Memo',
      Colors.black,
      12,
    );
    expect(
      ink.contentBounds(const Size(800, 1000)).single.width,
      lessThan(300),
    );
    ink.dispose();
  });
  test(
    'existing installations start new boxes at 12; later custom sizes persist',
    () async {
      final temp = await Directory.systemTemp.createTemp('fastink-text137-');
      try {
        final file = File('${temp.path}/settings.json');
        await file.writeAsString(jsonEncode({'defaultTextSize': 28}));
        final repo = SettingsRepository(configRoot: temp.path);
        final migrated = await repo.load();
        expect(migrated.defaultTextSize, 12);
        await repo.save(migrated.copyWith(defaultTextSize: 17.5));
        expect((await repo.load()).defaultTextSize, 17.5);
      } finally {
        await temp.delete(recursive: true);
      }
    },
  );
}
