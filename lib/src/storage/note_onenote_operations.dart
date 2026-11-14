part of 'note_repository.dart';

class OneNoteImportedDocument {
  /// 配对一份已转换文稿及其 OneNote 分组、章节标题映射。
  OneNoteImportedDocument(this.document, this.groups, this.pageTitles);

  /// document：当前文稿元数据对象，页面和笔迹分别按需装载。
  final NoteDocument document;

  /// groups：OneNote 分区组层级名称列表，导入时映射到对应资料库结构。
  final List<String> groups;

  /// pageTitles：零基页面索引到手工章节标题的映射，独立于 PDF 原生目录。
  final Map<int, String> pageTitles;
}

class OneNoteImportBatch {
  /// 返回整批导入文稿、转换警告与源文件保留副本位置，供宿主登记资料库。
  OneNoteImportBatch(this.documents, this.warnings, this.backupPath);

  /// documents：资料库或导入结果中的文稿记录集合，不直接包含全部解码图像。
  final List<OneNoteImportedDocument> documents;

  /// warnings：转换中不能完整处理的内容提示，不能静默冒充完全无损导入。
  final List<String> warnings;

  /// backupPath：OneNote 导入保留副本或恢复备份的路径，原始来源不在此直接改写。
  final String backupPath;
}

extension NoteOneNoteOperations on NoteRepository {
  /// 选择本地 .one、.onex 或 .onepkg 文件，取消返回空列表。
  Future<List<File>> pickOneNoteFiles() async {
    final picker = OpenFilePicker()
      ..title = tr('导入可编辑 OneNote 笔记', 'Import editable OneNote notes')
      ..filterSpecification = {
        'OneNote (*.one; *.onex; *.onepkg)': '*.one;*.onex;*.onepkg',
      };
    return picker.getFiles();
  }

  /// 保留源文件副本，调用 Windows 导入桥并将可提取对象转换为 FastInk 页面/笔画/图片，报告警告而不声称所有对象无损兼容。
  Future<OneNoteImportBatch> importOneNote(
    File source, {
    required void Function(String) onProgress,
  }) async {
    final work = await Directory.systemTemp.createTemp('fastink-onenote-');
    final backup = await _newImportDirectory(
      '${_withoutExtension(_fileName(source.path))}-OneNote-source',
    );
    final warnings = <String>[];
    final documents = <OneNoteImportedDocument>[];
    try {
      // 每次导入归档一份未修改的原文件，确保复杂格式、嵌入文件
      // 及未来对象类型仍可从原文件恢复。
      final archivedSource = await source.copy(
        '${backup.path}/${_fileName(source.path)}',
      );
      final read = await OneNoteReader().read(
        archivedSource,
        work,
        onProgress: onProgress,
      );
      warnings.addAll(read.warnings);
      final sections = <String, List<OneNoteSourcePage>>{};
      for (final page in read.pages) {
        (sections[jsonEncode([...page.groups, page.section])] ??= []).add(page);
      }
      var completed = 0;
      for (final pages in sections.values) {
        final title = source.path.toLowerCase().endsWith('.onepkg')
            ? pages.first.section
            : _withoutExtension(_fileName(source.path));
        final directory = await _newImportDirectory(title);
        final notePages = <NotePage>[];
        final document = NoteDocument(
          id: _stableId(directory.path),
          title: title,
          directory: directory.path,
          pages: notePages,
          initialIndex: 0,
        );
        final titles = <int, String>{};
        for (final page in pages) {
          onProgress(
            tr(
              '正在转换可编辑页面 ${completed + 1} / ${read.pages.length}',
              'Converting editable page ${completed + 1} / ${read.pages.length}',
            ),
          );
          final xml = await page.xml.readAsString();
          final decoded =
              jsonDecode(await page.ink.readAsString()) as List<dynamic>;
          final parsed = parseOneNotePage(xml, decoded);
          warnings.addAll(parsed.warnings.map((w) => '${page.title}: $w'));
          final original = notePages.length + 1;
          final background = File(
            '${directory.path}/${_safeName(title)} #$original.png',
          );
          // 背景仅是一张尺寸受限的空白位图；所有导入内容对象
          // 都保存在可编辑的 PageInk 中，不合并进背景图。
          final factor = math.min(
            1.0,
            math.sqrt(2000000 / (parsed.size.width * parsed.size.height)),
          );
          final width = math.max(1, (parsed.size.width * factor).round());
          final height = math.max(1, (parsed.size.height * factor).round());
          if (width > 32768 || height > 32768) {
            throw const FormatException('OneNote page is too large to import.');
          }
          final recorder = ui.PictureRecorder();
          final canvas = ui.Canvas(recorder);
          canvas.drawColor(const ui.Color(0xffffffff), ui.BlendMode.src);
          final picture = recorder.endRecording();
          final image = await picture.toImage(width, height);
          picture.dispose();
          try {
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await background.writeAsBytes(
              bytes!.buffer.asUint8List(),
              flush: true,
            );
          } finally {
            image.dispose();
          }
          final notePage = NotePage(
            index: notePages.length,
            originalPage: original,
            path: background.path,
            name: page.title,
          );
          notePages.add(notePage);
          titles[notePage.index] = page.title;
          final assets = <String, String>{};
          for (final entry in parsed.images.entries) {
            var bytes = entry.value;
            var extension =
                bytes.length >= 8 && bytes[0] == 137 && bytes[1] == 80
                ? '.png'
                : bytes.length >= 3 && bytes[0] == 255 && bytes[1] == 216
                ? '.jpg'
                : '';
            if (extension.isEmpty) {
              final codec = await ui.instantiateImageCodec(bytes);
              try {
                final frame = await codec.getNextFrame();
                try {
                  bytes = (await frame.image.toByteData(
                    format: ui.ImageByteFormat.png,
                  ))!.buffer.asUint8List();
                } finally {
                  frame.image.dispose();
                }
              } finally {
                codec.dispose();
              }
              extension = '.png';
            }
            final temporary = File('${work.path}/${entry.key}$extension');
            await temporary.writeAsBytes(bytes);
            assets[entry.key] = await importEmbeddedImage(document, temporary);
          }
          await savePageInk(
            document,
            notePage,
            PageInk(
              strokes: [
                for (final stroke in parsed.strokes)
                  stroke.imageAsset == null
                      ? stroke
                      : stroke.copy(imageAsset: assets[stroke.imageAsset]),
              ],
            ),
          );
          await File(
            '${directory.path}/onenote-page-$original.xml',
          ).writeAsString(xml, flush: true);
          completed++;
        }
        await File('${directory.path}/.fastink-notebook.json').writeAsString(
          jsonEncode({'version': 1, 'title': title, 'importedFrom': 'OneNote'}),
          flush: true,
        );
        await saveDocumentManifest(document);
        documents.add(
          OneNoteImportedDocument(document, pages.first.groups, titles),
        );
      }
      await File('${backup.path}/import-report.json').writeAsString(
        jsonEncode({
          'source': _fileName(source.path),
          'documents': documents.map((d) => d.document.id).toList(),
          'warnings': warnings.toSet().toList(),
        }),
        flush: true,
      );
      return OneNoteImportBatch(
        documents,
        warnings.toSet().toList(),
        backup.path,
      );
    } finally {
      // OneNote 关闭后可能需要短暂时间才能释放私有文件。
      // 不能删除链接，也不能删除本次新建工作区以外的路径。
      final tempRoot =
          '${(await Directory.systemTemp.resolveSymbolicLinks()).replaceAll('/', '\\').toLowerCase()}\\';
      final resolved = (await work.resolveSymbolicLinks())
          .replaceAll('/', '\\')
          .toLowerCase();
      var canClean =
          resolved.startsWith(tempRoot) &&
          _fileName(work.path).startsWith('fastink-onenote-');
      await for (final entry in work.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entry is Link) canClean = false;
      }
      for (var attempt = 0; canClean && attempt < 5; attempt++) {
        try {
          await work.delete(recursive: true);
          break;
        } on FileSystemException {
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
      }
    }
  }
}
