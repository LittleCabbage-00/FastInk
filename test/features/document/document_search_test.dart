import 'dart:convert';
import 'dart:io';

import 'package:fastink_flutter/src/models/models.dart';
import 'package:fastink_flutter/src/storage/note_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;

void main() {
  test(
    'PDF search extracts text per source page without rasterizing pages',
    () async {
      final Directory temp = await Directory.systemTemp.createTemp(
        'fastink_search_',
      );
      addTearDown(() => temp.delete(recursive: true));
      final pw.Document pdf = pw.Document();
      pdf.addPage(pw.Page(build: (_) => pw.Text('First searchable page')));
      pdf.addPage(pw.Page(build: (_) => pw.Text('Second searchable page')));
      final File source = File('${temp.path}/source.pdf');
      await source.writeAsBytes(await pdf.save());
      await File('${temp.path}/.fastink-pdf.json').writeAsString(
        jsonEncode(<String, Object?>{'source': source.path, 'dpi': 132}),
      );
      final NoteDocument document = NoteDocument(
        id: 'test',
        title: 'PDF',
        directory: temp.path,
        pages: const <NotePage>[],
        initialIndex: 0,
      );
      final Map<int, String> text = await NoteRepository(
        dataRoot: temp.path,
      ).extractPdfSearchText(document);
      expect(text[1], contains('First searchable page'));
      expect(text[2], contains('Second searchable page'));
      expect(
        temp.listSync().whereType<File>().any((f) => f.path.endsWith('.jpg')),
        isFalse,
      );
    },
    skip: !Platform.isWindows,
  );

  test(
    'cross document image copy is independent of source asset',
    () async {
      final Directory temp = await Directory.systemTemp.createTemp(
        'fastink_clipboard_',
      );
      addTearDown(() => temp.delete(recursive: true));
      final NoteRepository repository = NoteRepository(dataRoot: temp.path);
      final NoteDocument source = NoteDocument(
        id: 'source',
        title: 'Source',
        directory: temp.path,
        pages: const <NotePage>[],
        initialIndex: 0,
      );
      final NoteDocument target = NoteDocument(
        id: 'target',
        title: 'Target',
        directory: temp.path,
        pages: const <NotePage>[],
        initialIndex: 0,
      );
      final File file = File('${temp.path}/original.png');
      final List<int> bytes = <int>[137, 80, 78, 71, 13, 10, 26, 10];
      await file.writeAsBytes(bytes);
      final String original = await repository.importEmbeddedImage(
        source,
        file,
      );
      final File sourceAsset = File(
        repository.resolveEmbeddedImagePath(source, original),
      );
      final String copied = await repository.importEmbeddedImage(
        target,
        sourceAsset,
      );
      await sourceAsset.delete();
      expect(
        await File(
          repository.resolveEmbeddedImagePath(target, copied),
        ).readAsBytes(),
        bytes,
      );
    },
    skip: !Platform.isWindows,
  );
}
