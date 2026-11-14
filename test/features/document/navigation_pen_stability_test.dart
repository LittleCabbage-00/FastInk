import 'dart:io';
import 'dart:ui' as ui;
import 'package:fastink_flutter/main.dart';
import 'package:fastink_flutter/src/core/app_settings.dart';
import 'package:fastink_flutter/src/engine/ink_canvas.dart';
import 'package:fastink_flutter/src/models/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as raster;

void main() {
  setUpAll(() async {
    // Ahem has artificial font metrics and previously hid Windows' misalignment.
    final font = File(r'C:\Windows\Fonts\segoeui.ttf');
    if (await font.exists()) {
      final bytes = ByteData.sublistView(await font.readAsBytes());
      for (final family in ['Segoe UI Variable', 'Segoe UI', 'Roboto']) {
        await (FontLoader(family)..addFont(Future.value(bytes))).load();
      }
    }
  });
  testWidgets(
    'page number baseline aligns and pen button pixels remain stable through writing and saving',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      final temp = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('fastink_toolbar_'),
      ))!;
      final file = File('${temp.path}/page.png');
      await tester.runAsync(
        () => file.writeAsBytes(
          raster.encodePng(raster.Image(width: 200, height: 280)),
        ),
      );
      await tester.runAsync(
        () => tester.pumpWidget(
          FastInkApp(
            settings: AppSettings(
              dataRoot: '${temp.path}/data',
              language: 'en',
              autoSaveDelayMs: 100,
              openSidebarByDefault: false,
            ),
            initialPath: file.path,
          ),
        ),
      );
      for (var i = 0; i < 100; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 40)),
        );
        await tester.pump(const Duration(milliseconds: 40));
        if (find.byType(InkLayer).evaluate().isNotEmpty) break;
      }
      await tester.pump(const Duration(seconds: 1));
      final field = find.byKey(const ValueKey('page-number-input'));
      for (final (width, textScale, number) in [
        (1280.0, 1.0, '1'),
        (1280.0, 1.0, '26'),
        (800.0, 1.0, '3022'),
        (1280.0, 1.3, '26'),
        (800.0, 1.3, '3022'),
      ]) {
        tester.view.physicalSize = Size(width, 800);
        tester.platformDispatcher.textScaleFactorTestValue = textScale;
        await tester.pump(const Duration(milliseconds: 500));
        tester.widget<TextField>(field).controller!.text = number;
        await tester.pump();
        final editFinder = find.descendant(
          of: field,
          matching: find.byType(EditableText),
        );
        final edit = tester.state<EditableTextState>(editFinder).renderEditable;
        final total = tester.renderObject<RenderParagraph>(
          find.byKey(const ValueKey('page-number-total')),
        );
        const selection = TextSelection(baseOffset: 0, extentOffset: 1);
        final a = edit
            .localToGlobal(
              edit.getBoxesForSelection(selection).first.toRect().center,
            )
            .dy;
        final b = total
            .localToGlobal(
              total
                  .getBoxesForSelection(
                    selection,
                    boxHeightStyle: edit.selectionHeightStyle,
                  )
                  .first
                  .toRect()
                  .center,
            )
            .dy;
        expect(
          (a - b).abs(),
          lessThanOrEqualTo(1),
          reason:
              'Number baselines at width $width: a=$a b=$b editable=${edit.size} origin=${edit.localToGlobal(Offset.zero)} box=${edit.getBoxesForSelection(selection).first} caret=${edit.getLocalRectForCaret(const TextPosition(offset: 0))}',
        );
        expect(tester.takeException(), isNull);
      }
      tester.view.physicalSize = const Size(1280, 800);
      tester.platformDispatcher.textScaleFactorTestValue = 1;
      await tester.pump(const Duration(milliseconds: 500));
      for (final brightness in [Brightness.dark, Brightness.light]) {
        tester.platformDispatcher.platformBrightnessTestValue = brightness;
        await tester.pumpAndSettle();
        final preview = find.byKey(const ValueKey('width-preview-0'));
        final toolbar = find.ancestor(
          of: preview,
          matching: find.byType(SingleChildScrollView),
        );
        await tester.drag(toolbar, const Offset(-800, 0));
        await tester.pumpAndSettle();
        for (var i = 0; i < 3; i++) {
          final chip = tester.widget<ChoiceChip>(
            find.byKey(ValueKey('width-preset-$i')),
          );
          expect(
            chip.showCheckmark,
            isFalse,
            reason: 'Selection must not replace the thickness preview',
          );
          final dot = tester.widget<Container>(
            find.byKey(ValueKey('width-preview-$i')),
          );
          final foreground = (dot.decoration! as BoxDecoration).color!;
          final colors = Theme.of(tester.element(preview)).colorScheme;
          final background = chip.selected
              ? chip.selectedColor!
              : colors.surface;
          final light = foreground.computeLuminance();
          final dark = background.computeLuminance();
          final contrast = light > dark
              ? (light + .05) / (dark + .05)
              : (dark + .05) / (light + .05);
          expect(
            contrast,
            greaterThan(4.5),
            reason: '$brightness width slot $i',
          );
          expect(
            tester
                .getSize(find.byKey(ValueKey('width-preview-$i')))
                .shortestSide,
            greaterThanOrEqualTo(3),
          );
        }
        if (!tester
            .widget<ChoiceChip>(find.byKey(const ValueKey('width-preset-0')))
            .selected) {
          await tester.tap(find.byKey(const ValueKey('width-preset-0')));
          await tester.pumpAndSettle();
        }
        expect(
          tester
              .widget<ChoiceChip>(find.byKey(const ValueKey('width-preset-0')))
              .selected,
          isTrue,
        );
        await tester.tap(find.byKey(const ValueKey('width-preset-0')));
        await tester.pumpAndSettle();
        expect(find.byType(Slider), findsOneWidget);
        await tester.tapAt(const Offset(1100, 750));
        await tester.pumpAndSettle();
        await tester.drag(toolbar, const Offset(800, 0));
        await tester.pumpAndSettle();
      }
      final pen = find.byKey(const ValueKey('pen-type-button'));
      final bounds = tester.getRect(pen);
      Future<List<int>> pixels() async {
        final image = await tester.runAsync(
          () => tester.renderObject<RenderRepaintBoundary>(pen).toImage(),
        );
        final data = await tester.runAsync(
          () => image!.toByteData(format: ui.ImageByteFormat.rawRgba),
        );
        image!.dispose();
        return data!.buffer.asUint8List().toList();
      }

      final before = await pixels();
      final ink = tester
          .widget<InkLayer>(find.byType(InkLayer).first)
          .controller;
      for (var i = 0; i < 3; i++) {
        ink.pasteStrokes([
          InkStroke(
            color: 0xff123456,
            width: .002,
            points: [
              InkPoint(.2, .3 + i * .1, .5),
              InkPoint(.4, .4 + i * .1, .5),
            ],
          ),
        ]);
        for (var frame = 0; frame < 4; frame++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 60)),
          );
          await tester.pump(const Duration(milliseconds: 60));
          expect(tester.getRect(pen), bounds);
          expect(
            await pixels(),
            orderedEquals(before),
            reason: 'Pen button changed during write/save frame $frame',
          );
        }
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 300));
      imageCache.clear();
      imageCache.clearLiveImages();
      await tester.runAsync(() async {
        for (var i = 0; i < 10; i++) {
          try {
            await temp.delete(recursive: true);
            return;
          } on FileSystemException {
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
        }
      });
    },
  );
}
