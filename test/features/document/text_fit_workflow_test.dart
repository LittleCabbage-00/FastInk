import 'dart:convert';
import 'dart:io';
import 'package:fastink_flutter/main.dart';
import 'package:fastink_flutter/src/core/app_localizations.dart';
import 'package:fastink_flutter/src/core/app_settings.dart';
import 'package:fastink_flutter/src/engine/ink_canvas.dart';
import 'package:fastink_flutter/src/models/models.dart';
import 'package:fastink_flutter/src/platform/render_power_policy.dart';
import 'package:fastink_flutter/src/storage/library_repository.dart';
import 'package:fastink_flutter/src/storage/note_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as raster;
import 'window_usability_test.dart' show drainIO, waitForInk, key, preview;

Future<void> fitAndWait(WidgetTester tester) async {
  await tester.tap(key('text-properties-fit'));
  await tester.pump();
  for (var i = 0; i < 40; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
    if (tester.widget<OutlinedButton>(key('text-properties-fit')).onPressed !=
        null) {
      return;
    }
  }
  fail('Fit calculation did not complete');
}

void main() {
  setUpAll(() async {
    final font = File(r'C:\Windows\Fonts\segoeui.ttf');
    if (await font.exists()) {
      final bytes = ByteData.sublistView(await font.readAsBytes());
      for (final family in [
        'Segoe UI Variable',
        'Segoe UI',
        'Microsoft YaHei UI',
        'Roboto',
      ]) {
        await (FontLoader(family)..addFont(Future.value(bytes))).load();
      }
    }
    final icons = File(
      'D:/ComputerProgram/path/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
    if (await icons.exists()) {
      await (FontLoader('MaterialIcons')..addFont(
            Future.value(ByteData.sublistView(await icons.readAsBytes())),
          ))
          .load();
    }
  });
  testWidgets(
    'fit avoids handwriting, warns only for tiny text, and leaves a full page untouched',
    (tester) async {
      tester.view.physicalSize = const Size(960, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final temp = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('fastink-text-fit-'),
      ))!;
      final notes = NoteRepository(dataRoot: '${temp.path}/data');
      late NoteDocument document;
      late String imageAsset;
      final content = List.filled(
        18,
        'Stream filters and maps each item. Keep all of this editable text.',
      ).join('\n');
      final original = InkController(onCommitted: () {});
      for (var line = 0; line < 6; line++) {
        original.begin(
          InkPoint(.06, .08 + line * .06, .4),
          Colors.black,
          .003,
          StrokeKind.pen,
        );
        for (var x = 1; x <= 35; x++) {
          original.append(
            InkPoint(.06 + x * .025, .08 + line * .06 + (x % 2) * .018, .7),
          );
        }
        original.finish();
      }
      original.addText(
        const InkPoint(.04, .04, .5),
        const Size(800, 1000),
        content,
        Colors.black,
        48,
        boxWidth: 736,
      );
      await tester.runAsync(() async {
        final image = File('${temp.path}/page.png');
        await image.writeAsBytes(
          raster.encodePng(
            raster.fill(
              raster.Image(width: 600, height: 800),
              color: raster.ColorRgb8(255, 255, 255),
            ),
          ),
        );
        document = await notes.importImages([image], onProgress: (_) {});
        imageAsset = await notes.importEmbeddedImage(document, image);
        await notes.savePageInk(
          document,
          document.pages.first,
          PageInk(strokes: original.snapshot()),
        );
        final now = DateTime.utc(2026);
        await LibraryRepository(root: notes.dataRoot).save(
          LibraryState(
            documents: [
              LibraryDocument(
                id: document.id,
                title: document.title,
                sourcePath: document.pages.first.path,
                coverPath: document.pages.first.path,
                pageCount: 1,
                importedAt: now,
                lastOpenedAt: now,
              ),
            ],
          ),
        );
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('usability-preview'),
            child: FastInkApp(
              settings: AppSettings(
                dataRoot: notes.dataRoot,
                language: 'en',
                autoSaveEnabled: false,
                openSidebarByDefault: false,
              ),
            ),
          ),
        );
      });
      original.dispose();
      await drainIO(tester);
      await tester.tap(key('document-${document.id}'));
      await waitForInk(tester);
      final layer = tester.widget<InkLayer>(find.byType(InkLayer).first);
      final ink = layer.controller;
      final page = tester.getSize(find.byType(InkLayer).first);
      final oldText = ink.strokes.last;
      final oldJson = jsonEncode(oldText.toJson());
      final handwriting = jsonEncode(
        ink.strokes.take(6).map((s) => s.toJson()).toList(),
      );
      ink.selectOnly(oldText);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(AppText.get('编辑文字')));
      await tester.pumpAndSettle();
      await fitAndWait(tester);
      expect(key('text-properties-fit-status'), findsOneWidget);
      expect(key('text-properties-fit-warning'), findsNothing);
      await tester.tap(key('text-properties-apply'));
      await tester.pump();
      expect(ink.isTextRelocating, isTrue);
      final savedDuringMotion = jsonEncode(
        ink.snapshot().map((s) => s.toJson()).toList(),
      );
      await tester.pump(const Duration(milliseconds: 70));
      expect(ink.textRelocationProgress, inExclusiveRange(0, 1));
      expect(
        jsonEncode(ink.snapshot().map((s) => s.toJson()).toList()),
        savedDuringMotion,
      );
      await tester.pumpAndSettle();
      expect(ink.isTextRelocating, isFalse);
      final fitted = ink.selectedTextStroke!;
      final bounds = Rect.fromLTRB(
        fitted.points.first.x * page.width,
        fitted.points.first.y * page.height,
        fitted.points[2].x * page.width,
        fitted.points[2].y * page.height,
      );
      expect(
        ink.contentBounds(page, excluding: fitted).any(bounds.overlaps),
        isFalse,
      );
      expect(fitted.text, content);
      expect(
        jsonEncode(ink.strokes.take(6).map((s) => s.toJson()).toList()),
        handwriting,
      );
      await preview(tester, 'text-fit1312-after');
      ink.undo();
      expect(jsonEncode(ink.strokes.last.toJson()), oldJson);
      ink.redo();
      ink.selectOnly(ink.strokes.last);
      await tester.pumpAndSettle();

      // 很长的文字允许继续缩小，只在低于可读阈值时提示，应用按钮仍可用。
      RenderPowerMonitor.instance.value = const RenderPowerPolicy(
        onBattery: true,
      );
      await tester.tap(find.byTooltip(AppText.get('编辑文字')));
      await tester.pumpAndSettle();
      final long = List.filled(
        200,
        'All 200 lines must remain editable.',
      ).join('\n');
      await tester.enterText(key('text-properties-content'), long);
      await tester.enterText(key('text-properties-size'), '12');
      await fitAndWait(tester);
      expect(key('text-properties-fit-warning'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(key('text-properties-apply')).onPressed,
        isNotNull,
      );
      await preview(tester, 'text-fit1312-small-warning');
      await tester.tap(key('text-properties-apply'));
      await tester.pump();
      expect(ink.isTextRelocating, isTrue);
      await tester.pump(const Duration(milliseconds: 50));
      expect(ink.textRelocationProgress, inExclusiveRange(0, 1));
      await tester.pump(const Duration(milliseconds: 100));
      expect(ink.isTextRelocating, isFalse);
      await tester.pumpAndSettle();
      expect(ink.selectedTextStroke!.text, long);
      expect(ink.selectedTextStroke!.textSize * page.height, lessThan(8));

      // 全页被图片占用时没有空白；失败不能改写原文本或静默盖到图片上。
      final textBeforeFailure = ink.selectedTextStroke!;
      final beforeFailure = jsonEncode(textBeforeFailure.toJson());
      ink.pasteStrokes([
        InkStroke(
          color: 0,
          width: 1,
          kind: StrokeKind.image,
          imageAsset: imageAsset,
          points: const [
            InkPoint(0, 0, 1),
            InkPoint(1, 0, 1),
            InkPoint(1, 1, 1),
            InkPoint(0, 1, 1),
          ],
        ),
      ]);
      ink.selectOnly(textBeforeFailure);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(AppText.get('编辑文字')));
      await tester.pumpAndSettle();
      await fitAndWait(tester);
      expect(
        tester.widget<FilledButton>(key('text-properties-apply')).onPressed,
        isNull,
      );
      expect(ink.strokes.contains(textBeforeFailure), isTrue);
      expect(jsonEncode(textBeforeFailure.toJson()), beforeFailure);
      expect(key('text-properties-fit-warning'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text(AppText.get('取消')));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      RenderPowerMonitor.instance.value = const RenderPowerPolicy();
      await drainIO(tester);
      imageCache.clear();
      imageCache.clearLiveImages();
      await tester.runAsync(() => temp.delete(recursive: true));
    },
  );
}
