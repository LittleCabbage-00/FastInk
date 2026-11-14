import 'dart:io';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:fastink_flutter/src/capture/screenshot_document.dart';
import 'package:fastink_flutter/src/capture/screenshot_editor.dart';
import 'package:fastink_flutter/src/core/app_localizations.dart';
import 'package:fastink_flutter/src/platform/windows_capture.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as raster;

Future<ui.Image> sourceImage({int width = 160, int height = 100}) async {
  final image = raster.Image(width: width, height: height);
  for (final p in image) {
    p.setRgb((p.x * 17) % 256, (p.y * 23) % 256, (p.x + p.y) % 256);
  }
  final codec = await ui.instantiateImageCodec(raster.encodePng(image));
  try {
    return (await codec.getNextFrame()).image;
  } finally {
    codec.dispose();
  }
}

Future<ui.Image> worksheetImage() async {
  final recorder = ui.PictureRecorder();
  final paper = Canvas(recorder);
  paper.drawRect(
    const Rect.fromLTWH(0, 0, 800, 500),
    Paint()..color = const Color(0xfffafbfd),
  );
  for (var y = 34.0; y < 500; y += 28) {
    paper.drawLine(
      Offset(40, y),
      Offset(760, y),
      Paint()..color = const Color(0xffe7ebf1),
    );
  }
  void text(String value, Offset position, double size, Color color) {
    final painter = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(
          fontFamily: 'Microsoft YaHei UI',
          fontSize: size,
          color: color,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(paper, position);
    painter.dispose();
  }

  text('线性代数 · 课堂摘录', const Offset(60, 36), 28, const Color(0xff243653));
  text('03   矩阵与线性变换', const Offset(60, 91), 19, const Color(0xff5e708c));
  text('A x = b', const Offset(160, 152), 38, const Color(0xff26354b));
  text(
    '理解矩阵的列空间与方程解之间的关系。',
    const Offset(160, 216),
    20,
    const Color(0xff4c5c71),
  );
  text(
    '课堂记录 / 2026.10.23',
    const Offset(160, 300),
    16,
    const Color(0xff738197),
  );
  text(
    '姓名：张同学   学号：20261023',
    const Offset(160, 365),
    18,
    const Color(0xff4c5c71),
  );
  final picture = recorder.endRecording();
  final result = await picture.toImage(800, 500);
  picture.dispose();
  return result;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => AppText.locale = const Locale('en'));
  test(
    'clipboard PNG/DIB round trip preserves dimensions, colors and orientation',
    () {
      final source = raster.Image(width: 31, height: 17)
        ..setPixelRgba(0, 0, 12, 34, 56, 255)
        ..setPixelRgba(30, 16, 98, 76, 54, 255);
      final png = raster.encodePng(source);
      final decoded = raster.decodePng(dibToPng(pngToDib(png)))!;
      expect(decoded.width, 31);
      expect(decoded.height, 17);
      expect(decoded.getPixel(0, 0).r, 12);
      expect(decoded.getPixel(0, 0).b, 56);
      expect(decoded.getPixel(30, 16).r, 98);
      expect(() => dibToPng(Uint8List(8)), throwsFormatException);
      final invalid = pngToDib(png);
      ByteData.sublistView(invalid).setInt32(4, 2147483647, Endian.little);
      expect(() => dibToPng(invalid), throwsFormatException);
    },
  );
  test(
    '24-bit bottom-up DIB supports row padding and real clipboard orientation',
    () {
      final source = raster.Image(width: 3, height: 2)
        ..setPixelRgb(0, 0, 255, 0, 0)
        ..setPixelRgb(2, 1, 0, 255, 0);
      final bmp = raster.encodeBmp(source);
      final decoded = raster.decodePng(
        dibToPng(Uint8List.sublistView(bmp, 14)),
      )!;
      expect(decoded.getPixel(0, 0).r, 255);
      expect(decoded.getPixel(2, 1).g, 255);
    },
  );
  test(
    'crop and all four rotations export exactly the intended source pixels',
    () async {
      final doc = await ScreenshotDocument.create(await sourceImage());
      addTearDown(doc.dispose);
      doc.crop = const Rect.fromLTRB(20, 10, 90, 60);
      for (var turn = 0; turn < 4; turn++) {
        final png = raster.decodePng(await doc.exportPng())!;
        expect(png.width, turn.isEven ? 70 : 50);
        expect(png.height, turn.isEven ? 50 : 70);
        final positions = [
          const (0, 0),
          const (49, 0),
          const (69, 49),
          const (0, 69),
        ];
        final (x, y) = positions[turn];
        final pixel = png.getPixel(x, y);
        expect(pixel.r, (20 * 17) % 256);
        expect(pixel.g, (10 * 23) % 256);
        final original = const Offset(42, 33);
        expect(
          (doc.fromDisplay(doc.toDisplay(original)) - original).distance,
          lessThan(.0001),
        );
        doc.rotateImage();
      }
      doc.undo();
      expect(doc.turns, 3);
      doc.redo();
      expect(doc.turns, 0);
    },
  );
  test(
    'mosaic is flattened in exported crop and undo restores original pixels',
    () async {
      final doc = await ScreenshotDocument.create(await sourceImage());
      addTearDown(doc.dispose);
      doc.crop = const Rect.fromLTRB(10, 10, 110, 80);
      final originalBytes = await doc.exportPng();
      final original = raster.decodePng(originalBytes)!;
      doc.add(
        const CaptureMark(
          tool: CaptureTool.mosaic,
          points: [Offset(20, 20), Offset(80, 60)],
        ),
      );
      final redacted = raster.decodePng(await doc.exportPng())!;
      expect(redacted.getPixel(20, 20).r, redacted.getPixel(21, 20).r);
      expect(redacted.getPixel(20, 20).g, redacted.getPixel(21, 20).g);
      expect(redacted.getPixel(20, 20).r, isNot(original.getPixel(20, 20).r));
      expect(redacted.getPixel(1, 1).r, original.getPixel(1, 1).r);
      expect(redacted.textData?.isEmpty ?? true, isTrue);
      doc.undo();
      expect(await doc.exportPng(), originalBytes);
      doc.redo();
      expect(
        raster.decodePng(await doc.exportPng())!.getPixel(20, 20).r,
        redacted.getPixel(20, 20).r,
      );
      doc.undo();
      final restored = raster.decodePng(await doc.exportPng())!;
      expect(restored.getPixel(20, 20).r, original.getPixel(20, 20).r);
    },
  );
  test(
    'annotations export, move, rotate, delete and restore independently',
    () async {
      final doc = await ScreenshotDocument.create(
        await sourceImage(width: 400, height: 260),
        selectAll: true,
      );
      addTearDown(doc.dispose);
      for (final tool in [
        CaptureTool.pen,
        CaptureTool.arrow,
        CaptureTool.rectangle,
        CaptureTool.ellipse,
        CaptureTool.text,
      ]) {
        doc.add(
          CaptureMark(
            tool: tool,
            points: const [Offset(30, 30), Offset(160, 120)],
            color: Colors.red,
            width: 4,
            text: 'PDF 摘录',
          ),
        );
      }
      doc.rotateSelected(math.pi / 4);
      expect(doc.marks.last.angle, math.pi / 4);
      final moved = doc.marks.last.move(const Offset(40, 20));
      expect(moved.points.first, const Offset(70, 50));
      expect(moved.hit(moved.bounds.center, 2), isTrue);
      doc.deleteSelected();
      expect(doc.marks.length, 4);
      doc.undo();
      expect(doc.marks.length, 5);
      expect(raster.decodePng(await doc.exportPng())!.width, 400);
    },
  );
  testWidgets(
    'pen region drag, resize, move, shapes, text, rotation, undo, clipboard and output',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(() async {
        final systemFont = File('C:/Windows/Fonts/msyh.ttc');
        if (await systemFont.exists()) {
          await (FontLoader('Microsoft YaHei UI')
                ..addFont(systemFont.readAsBytes().then(ByteData.sublistView)))
              .load();
        }
        final configFile = File('.dart_tool/package_config.json').absolute;
        if (await configFile.exists()) {
          final config =
              jsonDecode(await configFile.readAsString())
                  as Map<String, dynamic>;
          final flutterPackage = (config['packages'] as List)
              .cast<Map<String, dynamic>>()
              .firstWhere((p) => p['name'] == 'flutter');
          final root = Directory.fromUri(
            configFile.uri.resolve(flutterPackage['rootUri'] as String),
          ).parent.parent;
          final icons = File(
            '${root.path}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
          );
          if (await icons.exists()) {
            await (FontLoader(
              'MaterialIcons',
            )..addFont(icons.readAsBytes().then(ByteData.sublistView))).load();
          }
        }
      });
      final doc = (await tester.runAsync(
        () async => ScreenshotDocument.create(await worksheetImage()),
      ))!;
      Uint8List? copied, saved;
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(fontFamily: 'Microsoft YaHei UI'),
          home: RepaintBoundary(
            key: key,
            child: ScreenshotEditor(
              document: doc,
              onCopy: (png) async => copied = png,
              onSave: (png) async {
                saved = png;
                return true;
              },
            ),
          ),
        ),
      );
      await tester.pump();
      final canvas = find.byKey(const ValueKey('capture-canvas'));
      Offset position(Offset p) {
        final rect = tester.getRect(canvas), size = doc.displaySize;
        final scale = math
            .min(
              (rect.width - 32) / size.width,
              (rect.height - 32) / size.height,
            )
            .clamp(.001, 4.0);
        final origin =
            rect.center - Offset(size.width, size.height) * scale / 2;
        return origin + doc.toDisplay(p) * scale;
      }

      Future<void> drag(Offset from, Offset to) async {
        final gesture = await tester.startGesture(
          position(from),
          kind: ui.PointerDeviceKind.stylus,
          buttons: kPrimaryButton,
        );
        await gesture.moveTo(position(to));
        await gesture.up();
        await tester.pump();
      }

      await drag(const Offset(80, 60), const Offset(600, 380));
      expect(doc.crop!.left, closeTo(80, .01));
      await drag(const Offset(300, 180), const Offset(340, 200));
      expect(doc.crop!.left, closeTo(120, .01));
      await drag(doc.crop!.bottomRight, const Offset(700, 440));
      expect(doc.crop!.right, closeTo(700, .01));
      for (final tool in [
        CaptureTool.rectangle,
        CaptureTool.ellipse,
        CaptureTool.pen,
        CaptureTool.arrow,
        CaptureTool.mosaic,
      ]) {
        await tester.tap(
          find.byKey(ValueKey('capture-${tool.name}')),
          kind: ui.PointerDeviceKind.mouse,
        );
        await tester.pump();
        await drag(const Offset(170, 140), const Offset(320, 260));
      }
      expect(doc.marks.length, 5);
      await tester.tap(
        find.byKey(const ValueKey('capture-select')),
        kind: ui.PointerDeviceKind.mouse,
      );
      await tester.pump();
      await drag(const Offset(240, 200), const Offset(280, 220));
      expect(doc.marks.last.points.first.dx, closeTo(210, .01));
      await tester.ensureVisible(
        find.byKey(const ValueKey('capture-rotate-mark')),
      );
      await tester.pump();
      expect(
        tester.getRect(find.byKey(const ValueKey('capture-crop'))).left,
        inInclusiveRange(0, 24),
      );
      await tester.tap(
        find.byKey(const ValueKey('capture-rotate-mark')),
        kind: ui.PointerDeviceKind.mouse,
      );
      await tester.pump();
      expect(doc.marks.last.angle, closeTo(math.pi / 12, .0001));
      await tester.tap(
        find.byKey(const ValueKey('capture-undo')),
        kind: ui.PointerDeviceKind.mouse,
      );
      await tester.pump();
      expect(doc.marks.last.angle, 0);
      await tester.tap(
        find.byKey(const ValueKey('capture-text')),
        kind: ui.PointerDeviceKind.mouse,
      );
      await tester.pump();
      await tester.tapAt(
        position(const Offset(380, 160)),
        kind: ui.PointerDeviceKind.stylus,
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('capture-text-input')),
        '重点公式',
      );
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      expect(doc.marks.last.text, '重点公式');
      // Save an implementation-generated preview for visual inspection.
      await tester.runAsync(() async {
        final image =
            await (key.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage();
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        await Directory('build/diagnostics').create(recursive: true);
        await File(
          'build/diagnostics/screenshot-editor-preview.png',
        ).writeAsBytes(data!.buffer.asUint8List());
      });
      await tester.runAsync(
        () => tester.tap(
          find.byKey(const ValueKey('capture-copy')),
          kind: ui.PointerDeviceKind.mouse,
        ),
      );
      for (var i = 0; i < 30 && copied == null; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        await tester.pump();
      }
      expect(copied, isNotNull);
      await tester.runAsync(
        () => tester.tap(
          find.byKey(const ValueKey('capture-save')),
          kind: ui.PointerDeviceKind.mouse,
        ),
      );
      for (var i = 0; i < 30 && saved == null; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        await tester.pump();
      }
      expect(saved, isNotNull);
      await tester.ensureVisible(find.byKey(const ValueKey('capture-rotate')));
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('capture-rotate')),
        kind: ui.PointerDeviceKind.mouse,
      );
      await tester.pump();
      expect(doc.turns, 1);
      tester.view.physicalSize = const Size(640, 700);
      await tester.pump();
      expect(tester.takeException(), isNull);
      // Keyboard undo/redo stays inside the editor.
      await tester.ensureVisible(find.byKey(const ValueKey('capture-select')));
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('capture-select')),
        kind: ui.PointerDeviceKind.mouse,
      );
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(doc.turns, 0);
      // 选中的标注可复制、粘贴、剪切，再用与文稿相同的快捷键撤销。
      doc.selected = doc.marks.length - 1;
      doc.changed();
      await tester.pump();
      final originalCount = doc.marks.length;
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
      expect(doc.marks, hasLength(originalCount + 1));
      await tester.sendKeyEvent(LogicalKeyboardKey.keyX);
      expect(doc.marks, hasLength(originalCount));
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      expect(doc.marks, hasLength(originalCount + 1));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      expect(doc.marks, hasLength(originalCount));
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      doc.dispose();
    },
  );
}
