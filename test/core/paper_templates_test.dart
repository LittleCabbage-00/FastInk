import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:fastink_flutter/src/storage/note_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('paper presets retain shape and sanitize invalid spacing', () {
    for (final size in PaperSizePreset.values) {
      final PaperTemplate paper = PaperTemplate(
        size: size,
        pattern: PaperPattern.weekly,
        color: const ui.Color(0xff202226),
        spacing: 1.3,
      );
      final PaperTemplate loaded = PaperTemplate.fromJson(
        jsonDecode(jsonEncode(paper.toJson())) as Map<String, Object?>,
      );
      expect(loaded.toJson(), paper.toJson());
      expect(
        paper.copyWith(landscape: true).aspectRatio,
        closeTo(1 / paper.aspectRatio, .00001),
      );
    }
    expect(
      PaperTemplate.fromJson(<String, Object?>{
        'spacing': double.infinity,
      }).spacing,
      1,
    );
    expect(
      PaperTemplate.fromJson(<String, Object?>{'pattern': 'unknown'}).pattern,
      PaperPattern.blank,
    );
  });

  test(
    'template identity survives reopen duplicate rotate and change',
    () async {
      final Directory root = await Directory.systemTemp.createTemp(
        'fastink_paper_',
      );
      addTearDown(() => root.delete(recursive: true));
      final NoteRepository repo = NoteRepository(dataRoot: root.path);
      const PaperTemplate paper = PaperTemplate(
        pattern: PaperPattern.cornell,
        size: PaperSizePreset.b5,
        spacing: 1.25,
        color: ui.Color(0xfffffbed),
      );
      final original = await repo.createBlankNote('Templates', template: paper);
      final recorder = ui.PictureRecorder();
      paintPaperTemplate(ui.Canvas(recorder), paper.pixelSize, paper);
      final picture = recorder.endRecording();
      final preview = await picture.toImage(
        paper.pixelSize.width.toInt(),
        paper.pixelSize.height.toInt(),
      );
      final previewBytes = await preview.toByteData(
        format: ui.ImageByteFormat.png,
      );
      expect(
        await File(original.pages.first.path).readAsBytes(),
        previewBytes!.buffer.asUint8List(),
      );
      preview.dispose();
      picture.dispose();
      final copy = await repo.duplicatePage(original, 0);
      expect(
        (await repo.loadPaperTemplate(copy.pages[1]))!.toJson(),
        paper.toJson(),
      );
      final rotated = await repo.rotatePage(copy, 1);
      expect(
        (await repo.loadPaperTemplate(rotated.pages[1]))!.landscape,
        isTrue,
      );
      expect(
        (await repo.loadPaperTemplate(rotated.pages[0]))!.landscape,
        isFalse,
      );
      await repo.applyPaperTemplate(rotated, <int>[
        1,
      ], paper.copyWith(pattern: PaperPattern.monthly));
      final NoteRepository reopened = NoteRepository(dataRoot: root.path);
      expect(
        (await reopened.loadPaperTemplate(rotated.pages[1]))!.pattern,
        PaperPattern.monthly,
      );
      expect(
        (await reopened.loadPaperTemplate(rotated.pages[0]))!.pattern,
        PaperPattern.cornell,
      );
    },
  );

  test(
    'all templates render in both orientations and preview matches saved background',
    () async {
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      const double cellW = 220, cellH = 300;
      for (int i = 0; i < PaperPattern.values.length; i++) {
        for (final bool landscape in <bool>[false, true]) {
          final paper = PaperTemplate(
            pattern: PaperPattern.values[i],
            landscape: landscape,
          );
          final rec = ui.PictureRecorder();
          final target = ui.Canvas(rec);
          paintPaperTemplate(
            target,
            ui.Size(180, 180 / paper.aspectRatio),
            paper,
          );
          final picture = rec.endRecording();
          final image = await picture.toImage(
            180,
            (180 / paper.aspectRatio).ceil(),
          );
          expect(await image.toByteData(), isNotNull);
          picture.dispose();
          image.dispose();
        }
        canvas.save();
        canvas.translate((i % 5) * cellW + 15, (i ~/ 5) * cellH + 15);
        paintPaperTemplate(
          canvas,
          const ui.Size(190, 269),
          PaperTemplate(pattern: PaperPattern.values[i]),
        );
        canvas.restore();
      }
      final picture = recorder.endRecording();
      final image = await picture.toImage(1100, 900);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('build/diagnostics/template-gallery.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
      picture.dispose();
    },
  );
  test(
    'paper replacement protects imports while allowing added blank pages',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'fastink_import_paper_',
      );
      addTearDown(() => root.delete(recursive: true));
      final repo = NoteRepository(dataRoot: root.path);
      final notebook = await repo.createBlankNote('Source');
      final folder = await Directory('${root.path}/external').create();
      final file = await File(
        notebook.pages.first.path,
      ).copy('${folder.path}/original.png');
      final originalBytes = await file.readAsBytes();
      final imported = await repo.indexFromDirectory(folder.path);
      final added = await repo.addBlankPage(
        imported,
        insertIndex: 1,
        template: const PaperTemplate(pattern: PaperPattern.weekly),
      );
      expect(repo.canChangePaperTemplate(added, 0), isFalse);
      expect(repo.canChangePaperTemplate(added, 1), isTrue);
      await expectLater(
        repo.applyPaperTemplate(added, <int>[
          0,
          1,
        ], const PaperTemplate(pattern: PaperPattern.monthly)),
        throwsStateError,
      );
      expect(await file.readAsBytes(), originalBytes);
      expect(
        (await repo.loadPaperTemplate(added.pages[1]))!.pattern,
        PaperPattern.weekly,
      );
      await repo.applyPaperTemplate(added, <int>[
        1,
      ], const PaperTemplate(pattern: PaperPattern.monthly));
      expect(
        (await repo.loadPaperTemplate(added.pages[1]))!.pattern,
        PaperPattern.monthly,
      );
    },
  );
}
