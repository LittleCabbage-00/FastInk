part of 'note_repository.dart';

/// 修改文稿页序、页面背景和对应笔迹。
///
/// 页面索引只是当前顺序，originalPage 是持久标识；重排页面时不能拿
/// index 当文件名或笔迹键，否则移动页面后批注会串页。
extension NotePageOperations on NoteRepository {
  /// 追加独立页面；全部背景与笔迹就绪后才发布清单。
  Future<NoteDocument> copyPagesToDocument(
    NoteDocument source,
    NoteDocument target,
    Iterable<int> indexes, {
    double legacyWidthReference = legacyInkWidthFallbackReference,
  }) async {
    final selected = indexes.toSet();
    if (source.id == target.id ||
        selected.isEmpty ||
        selected.any((i) => i < 0 || i >= source.pages.length)) {
      throw ArgumentError(
        tr('请选择其他文稿和有效页面。', 'Choose another document and valid pages.'),
      );
    }
    final pages = List<NotePage>.of(target.pages);
    final created = <File>[];
    final assets = <String, String>{};
    // 同时计入已删除页面保留的笔迹文件，避免旧页码虽已移出
    // 清单，其笔迹却被同号新页面覆盖。
    int next =
        target.pages.map((p) => p.originalPage).fold<int>(0, math.max) + 1;
    try {
      for (int index = 0; index < source.pages.length; index++) {
        if (!selected.contains(index)) continue;
        final page = source.pages[index];
        while (await File(
              '$dataRoot/documents/${target.id}/pages/${next.toString().padLeft(6, '0')}.json',
            ).exists() ||
            await File(
              '$dataRoot/documents/${target.id}/pages/${next.toString().padLeft(6, '0')}.json.previous',
            ).exists()) {
          next++;
        }
        final image = await ensurePageImage(source, page);
        final output = File(
          '$dataRoot/documents/${target.id}/backgrounds/copied-$next-${DateTime.now().microsecondsSinceEpoch}${_extension(page.path)}',
        );
        await output.parent.create(recursive: true);
        created.add(output);
        await image.copy(output.path);
        final paper = await loadPaperTemplate(page);
        if (paper != null) {
          final metadata = File('${output.path}.paper.json');
          created.add(metadata);
          // 导入的纸张背景也必须脱离源资料库依赖。
          final independentPaper = paper.backgroundAsset == null
              ? paper
              : paper.copyWith(backgroundAsset: output.path);
          await metadata.writeAsString(
            jsonEncode(independentPaper.toJson()),
            flush: true,
          );
        }
        final copy = NotePage(
          index: pages.length,
          originalPage: next++,
          path: output.path,
          name: page.name,
        );
        final ink = await loadPageInk(
          source,
          page,
          legacyWidthReference: legacyWidthReference,
        );
        final strokes = <InkStroke>[];
        for (final stroke in ink.strokes) {
          final asset = stroke.imageAsset;
          if (asset == null) {
            strokes.add(stroke.copy());
          } else {
            if (!assets.containsKey(asset)) {
              final imported = await importEmbeddedImage(
                target,
                File(resolveEmbeddedImagePath(source, asset)),
              );
              assets[asset] = imported;
              created.add(File(resolveEmbeddedImagePath(target, imported)));
            }
            strokes.add(stroke.copy(imageAsset: assets[asset]));
          }
        }
        final inkFile = File(_inkPath(target, copy));
        created.addAll([inkFile, File('${inkFile.path}.previous')]);
        await savePageInk(target, copy, PageInk(strokes: strokes));
        pages.add(copy);
      }
      final updated = _withPages(target, pages);
      await saveDocumentManifest(updated);
      return updated;
    } catch (_) {
      for (final file in created.reversed) {
        try {
          if (await file.exists()) await file.delete();
        } catch (_) {}
      }
      rethrow;
    }
  }

  /// 批量操作仅发布一次新清单；移除页面时保留既有页面文件，
  /// 确保清理失败也不会丢失原始内容。
  Future<NoteDocument> batchPages(
    NoteDocument document,
    Iterable<int> indexes, {
    required bool duplicate,
    double legacyWidthReference = legacyInkWidthFallbackReference,
  }) async {
    final selected = indexes.toSet();
    if (selected.isEmpty ||
        selected.any((i) => i < 0 || i >= document.pages.length)) {
      throw ArgumentError('请选择有效页面。');
    }
    if (!duplicate && selected.length == document.pages.length) {
      throw StateError('文稿至少需要保留一页。');
    }
    final pages = <NotePage>[];
    final created = <File>[];
    int next =
        document.pages.map((p) => p.originalPage).fold<int>(0, math.max) + 1;
    try {
      for (final source in document.pages) {
        if (duplicate || !selected.contains(source.index)) pages.add(source);
        if (!duplicate || !selected.contains(source.index)) continue;
        final image = await ensurePageImage(document, source);
        final output = File(
          '$dataRoot/documents/${document.id}/backgrounds/batch-$next-${DateTime.now().microsecondsSinceEpoch}${_extension(source.path)}',
        );
        await output.parent.create(recursive: true);
        created.add(output);
        await image.copy(output.path);
        final paper = await loadPaperTemplate(source);
        if (paper != null) {
          final metadata = File('${output.path}.paper.json');
          created.add(metadata);
          await metadata.writeAsString(jsonEncode(paper.toJson()));
        }
        final copy = NotePage(
          index: pages.length,
          originalPage: next++,
          path: output.path,
          name: '${source.name} ${tr('副本', 'copy')}',
        );
        final ink = await loadPageInk(
          document,
          source,
          legacyWidthReference: legacyWidthReference,
        );
        created.add(File(_inkPath(document, copy)));
        await savePageInk(document, copy, ink);
        pages.add(copy);
      }
      final updated = _withPages(document, pages);
      await saveDocumentManifest(updated);
      return updated;
    } catch (_) {
      for (final file in created) {
        try {
          if (await file.exists()) await file.delete();
        } catch (_) {}
      }
      rethrow;
    }
  }

  /// 保存当前文稿页面清单，页序和稳定原始编号必须同时保留。
  Future<void> saveDocumentManifest(NoteDocument document) async {
    final File manifest = File(_manifestPath(document.id));
    await manifest.parent.create(recursive: true);
    final File temporary = File('${manifest.path}.tmp');
    // 清单先写临时文件再替换，进程中断时不会留下半截 JSON。
    await temporary.writeAsString(
      jsonEncode(<String, Object?>{
        'version': 1,
        'title': document.title,
        'directory': document.directory,
        'pages': document.pages
            .map(
              (page) => <String, Object?>{
                'path': page.path,
                'name': page.name,
                'originalPage': page.originalPage,
              },
            )
            .toList(),
      }),
      flush: true,
    );
    if (await manifest.exists()) await manifest.delete();
    await temporary.rename(manifest.path);
  }

  /// 在指定位置创建新模板页并更新清单，新页面身份不复用被删除页的笔迹位置。
  Future<NoteDocument> addBlankPage(
    NoteDocument document, {
    required int insertIndex,
    PaperTemplate template = const PaperTemplate(),
  }) async {
    final int originalPage =
        document.pages.map((page) => page.originalPage).fold<int>(0, math.max) +
        1;
    final Directory backgrounds = Directory(
      '$dataRoot/documents/${document.id}/backgrounds',
    );
    final File destination = File(
      '${backgrounds.path}/page-$originalPage-${DateTime.now().microsecondsSinceEpoch}.png',
    );
    await _writePaperPage(destination, template);
    final List<NotePage> pages = List<NotePage>.of(document.pages)
      ..insert(
        insertIndex.clamp(0, document.pages.length),
        NotePage(
          index: insertIndex,
          originalPage: originalPage,
          path: destination.path,
          name: tr('页面 $originalPage', 'Page $originalPage'),
        ),
      );
    final NoteDocument updated = _withPages(document, pages);
    await savePageInk(
      updated,
      updated.pages[insertIndex.clamp(0, updated.pages.length - 1)],
      const PageInk(strokes: []),
    );
    await saveDocumentManifest(updated);
    return updated;
  }

  /// 把选中图像收集为独立页面并按目标位置插入，返回更新后的文稿对象。
  Future<NoteDocument> insertImagePages(
    NoteDocument document,
    int insertIndex,
    List<File> images,
  ) async {
    if (images.isEmpty) return document;
    final Directory backgrounds = Directory(
      '$dataRoot/documents/${document.id}/backgrounds',
    );
    await backgrounds.create(recursive: true);
    int nextOriginal =
        document.pages.map((page) => page.originalPage).fold<int>(0, math.max) +
        1;
    final List<NotePage> additions = <NotePage>[];
    for (final File source in images) {
      // 先把图片复制进文稿私有目录，全部准备好后才提交新清单。
      final String extension = _extension(source.path);
      final File destination = File(
        '${backgrounds.path}/image-${DateTime.now().microsecondsSinceEpoch}-${additions.length}$extension',
      );
      await source.copy(destination.path);
      additions.add(
        NotePage(
          index: insertIndex + additions.length,
          originalPage: nextOriginal++,
          path: destination.path,
          name: _fileName(source.path),
        ),
      );
    }
    final List<NotePage> pages = List<NotePage>.of(document.pages)
      ..insertAll(insertIndex.clamp(0, document.pages.length), additions);
    final NoteDocument updated = _withPages(document, pages);
    await saveDocumentManifest(updated);
    return updated;
  }

  /// 复制底图、笔迹和模板配置到新页面身份，原页仍保留。
  Future<NoteDocument> duplicatePage(
    NoteDocument document,
    int pageIndex, {
    // 源页可能是 v2 旧笔迹，读出来必须换算成归一化粗细再写进副本，
    // 否则副本会以"像素"当"归一化"存进 v3 文件，粗上一个页面尺度。
    double legacyWidthReference = legacyInkWidthFallbackReference,
  }) async {
    final NotePage source = document.pages[pageIndex];
    final int originalPage =
        document.pages.map((page) => page.originalPage).fold<int>(0, math.max) +
        1;
    final Directory backgrounds = Directory(
      '$dataRoot/documents/${document.id}/backgrounds',
    );
    await backgrounds.create(recursive: true);
    final File destination = File(
      '${backgrounds.path}/page-$originalPage-${DateTime.now().microsecondsSinceEpoch}${_extension(source.path)}',
    );
    await File(source.path).copy(destination.path);
    final PaperTemplate? paper = await loadPaperTemplate(source);
    if (paper != null) {
      await File(
        '${destination.path}.paper.json',
      ).writeAsString(jsonEncode(paper.toJson()), flush: true);
    }
    final List<NotePage> pages = List<NotePage>.of(document.pages)
      ..insert(
        pageIndex + 1,
        NotePage(
          index: pageIndex + 1,
          originalPage: originalPage,
          path: destination.path,
          name: tr('${source.name} 副本', '${source.name} copy'),
        ),
      );
    final NoteDocument updated = _withPages(document, pages);
    // 页面背景和笔迹分别存储，复制页面时二者必须一起复制。
    final PageInk sourceInk = await loadPageInk(
      document,
      source,
      legacyWidthReference: legacyWidthReference,
    );
    await savePageInk(updated, updated.pages[pageIndex + 1], sourceInk);
    await saveDocumentManifest(updated);
    return updated;
  }

  /// 从清单移除指定页并返回更新文稿，至少保留一页；不把移除等同于立即清理所有磁盘文件。
  Future<NoteDocument> deletePage(NoteDocument document, int pageIndex) async {
    if (document.pages.length <= 1) {
      throw StateError(
        tr('文稿至少需要保留一页。', 'A document must keep at least one page.'),
      );
    }
    final NotePage removed = document.pages[pageIndex];
    final List<NotePage> pages = List<NotePage>.of(document.pages)
      ..removeAt(pageIndex);
    final NoteDocument updated = _withPages(document, pages);
    final File ink = File(_inkPath(document, removed));
    if (await ink.exists()) await ink.delete();
    // 只有应用私有 backgrounds 目录中的文件可删除；外部源图只移出清单。
    final String backgroundsRoot = _normalizedAbsolute(
      '$dataRoot/documents/${document.id}/backgrounds',
    );
    if (_isStrictChild(removed.path, backgroundsRoot) &&
        await File(removed.path).exists()) {
      await File(removed.path).delete();
    }
    await saveDocumentManifest(updated);
    return updated;
  }

  /// 按拖动索引重排页面列表并重建连续序号，稳定原始编号不随显示页序改变。
  Future<NoteDocument> reorderPages(
    NoteDocument document,
    int oldIndex,
    int newIndex,
  ) async {
    final List<NotePage> pages = List<NotePage>.of(document.pages);
    final NotePage moved = pages.removeAt(oldIndex);
    pages.insert(newIndex.clamp(0, pages.length), moved);
    final NoteDocument updated = _withPages(document, pages);
    await saveDocumentManifest(updated);
    return updated;
  }

  /// 生成旋转后的页面及同步变换的文字/图片/笔迹，保存后返回更新清单，失败应保留有效旧内容。
  Future<NoteDocument> rotatePage(
    NoteDocument document,
    int pageIndex, {
    bool clockwise = true,
    double legacyWidthReference = legacyInkWidthFallbackReference,
  }) async {
    final NotePage page = document.pages[pageIndex];
    final PageInk existingInk = await loadPageInk(
      document,
      page,
      legacyWidthReference: legacyWidthReference,
    );
    final raster.Image? decoded = raster.decodeImage(
      await File(page.path).readAsBytes(),
    );
    if (decoded == null) {
      throw StateError(tr('无法读取页面图像。', 'Could not read the page image.'));
    }
    final raster.Image rotated = raster.copyRotate(
      decoded,
      angle: clockwise ? 90 : -90,
    );
    final Directory backgrounds = Directory(
      '$dataRoot/documents/${document.id}/backgrounds',
    );
    await backgrounds.create(recursive: true);
    final File destination = File(
      '${backgrounds.path}/page-${page.originalPage}-rotated-${DateTime.now().microsecondsSinceEpoch}.png',
    );
    final File temporary = File('${destination.path}.tmp');
    await temporary.writeAsBytes(raster.encodePng(rotated), flush: true);
    await temporary.rename(destination.path);
    final PaperTemplate? paper = await loadPaperTemplate(page);
    if (paper != null) {
      await File('${destination.path}.paper.json').writeAsString(
        jsonEncode(
          paper
              .copyWith(
                landscape: !paper.landscape,
                backgroundAsset: paper.backgroundAsset == null
                    ? null
                    : destination.path,
                customWidth: paper.backgroundAsset == null
                    ? null
                    : rotated.width,
                customHeight: paper.backgroundAsset == null
                    ? null
                    : rotated.height,
              )
              .toJson(),
        ),
        flush: true,
      );
    }

    final List<NotePage> pages = List<NotePage>.of(document.pages);
    pages[pageIndex] = NotePage(
      index: pageIndex,
      originalPage: page.originalPage,
      path: destination.path,
      name: page.name,
    );
    final NoteDocument updated = _withPages(document, pages);
    // 背景旋转后，笔迹的归一化坐标也按同一方向旋转，二者才能继续重合。
    // 使用归一化坐标可直接处理横竖页切换，不依赖原图像素尺寸。
    // 换点列走 stroke.copy()：手工重列字段会漏掉 imageAsset 这类后加的
    // 字段（见 ARCHITECTURE.md「修改功能时」第 3 条），图片会当场丢失。
    final List<InkStroke> rotatedStrokes = existingInk.strokes
        .map(
          (stroke) => stroke.copy(
            points: stroke.points
                .map(
                  (point) => clockwise
                      ? InkPoint(1 - point.y, point.x, point.pressure)
                      : InkPoint(point.y, 1 - point.x, point.pressure),
                )
                .toList(),
          ),
        )
        .toList();
    await savePageInk(
      updated,
      updated.pages[pageIndex],
      PageInk(strokes: rotatedStrokes, updatedAt: DateTime.now()),
    );
    await saveDocumentManifest(updated);

    final String backgroundsRoot = _normalizedAbsolute(backgrounds.path);
    if (_isStrictChild(page.path, backgroundsRoot) &&
        !_samePath(page.path, destination.path) &&
        await File(page.path).exists()) {
      await File(page.path).delete();
    }
    return updated;
  }

  /// 由新页列表生成文稿快照，重建显示索引并保持文稿身份与来源目录。
  NoteDocument _withPages(NoteDocument document, List<NotePage> source) =>
      NoteDocument(
        id: document.id,
        title: document.title,
        directory: document.directory,
        // 每次结构变更后重新生成连续 index；originalPage 保持不变。
        pages: <NotePage>[
          for (int i = 0; i < source.length; i++)
            NotePage(
              index: i,
              originalPage: source[i].originalPage,
              path: source[i].path,
              name: source[i].name,
            ),
        ],
        initialIndex: document.initialIndex.clamp(0, source.length - 1),
      );
}
