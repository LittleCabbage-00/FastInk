part of 'export_repository.dart';

extension ExportPdfFast on ExportRepository {
  /// 优先复用原 PDF 页面并为有内容页准备叠加层；仅当所有安全条件满足时返回成功，其他情况回退逐页导出。
  Future<bool> _exportOriginalPages(
    NoteDocument document,
    File destination,
    List<int> indexes,
    void Function(String, double?) report,
  ) async {
    // 阶段耗时只用于诊断瓶颈，不把一次样本耗时作为所有文稿保证。
    final phaseWatch = Stopwatch()..start();
    // 记录快速导出当前阶段与耗时，供进度和瓶颈诊断。
    void mark(String phase) {
      onTiming?.call(phase, phaseWatch.elapsed);
      phaseWatch.reset();
    }

    // 原始 PDF 是快速导出的复用来源，不能用屏幕低分辨率位图替代。
    final original = await notes.originalPdfSource(document);
    if (original == null) return false;
    final originals = notes.originalPdfPageIndexes(document).values.toSet();
    // 先读有笔迹文件的页身份，避免为数千空批注页逐页解析空 JSON。
    final ids = await notes.savedInkPageIds(document);
    // 预检只保留非空页标记和首个分块，避免整本密集笔迹同时驻留内存。
    // 仅缓存本次需要叠加的页笔迹，按稳定原页身份关联。
    final inkById = <int, PageInk>{};
    // 记录真正非空笔迹页，决定哪些原 PDF 页需要叠加。
    final nonEmptyInk = <int>{};
    // 避免同一原页身份在页映射中重复检查，显示页序仍单独保留。
    final inspected = <int>{};
    final feedback = Stopwatch()..start();
    for (var position = 0; position < indexes.length; position++) {
      final page = document.pages[indexes[position]];
      if (ids.contains(page.originalPage) && inspected.add(page.originalPage)) {
        final ink = await notes.loadPageInk(
          document,
          page,
          legacyWidthReference: _inkWidthReference,
          background: true,
        );
        if (ink.strokes.isNotEmpty) {
          nonEmptyInk.add(page.originalPage);
          if (inkById.length < _pdfPagesPerPart) {
            inkById[page.originalPage] = ink;
          }
        }
      }
      if (feedback.elapsedMilliseconds >= 40 ||
          position == indexes.length - 1) {
        report(
          tr(
            '正在检查笔迹：${position + 1} / ${indexes.length} 页',
            'Checking ink: ${position + 1} / ${indexes.length} pages',
          ),
          .03 * (position + 1) / indexes.length,
        );
        feedback.reset();
      }
    }
    // 原页尺寸与叠加安全性来自 PDF 几何，旋转/裁切不安全时需回退。
    final geometries = nonEmptyInk.isNotEmpty
        ? await notes.pdfExportGeometry(document)
        : <int, ({ui.Size size, bool overlaySafe})>{};
    for (final index in indexes) {
      final page = document.pages[index];
      if (nonEmptyInk.contains(page.originalPage) &&
          geometries[page.originalPage]?.overlaySafe != true) {
        originals.remove(index);
      }
    }
    // 这是最终输出页序，不允许因批次分组或去重改变用户页序。
    final originalOrder =
        originals.length == document.pages.length &&
        indexes.length == document.pages.length &&
        await notes.canExportOriginalPdf(document) &&
        List.generate(indexes.length, (i) => i).every((i) => indexes[i] == i);
    // 自建插入页必须单独构建，不能冒充原 PDF 中存在的页面。
    final custom = <int>[
      for (final index in indexes)
        if (!originals.contains(index)) index,
    ];
    // 仅有批注的页进入叠加准备，未改原页继续复用原数据。
    final annotated = <int>[
      for (var out = 0; out < indexes.length; out++)
        if (originals.contains(indexes[out]) &&
            nonEmptyInk.contains(document.pages[indexes[out]].originalPage))
          out,
    ];
    await destination.parent.create(recursive: true);
    final sameSource =
        original.absolute.path.replaceAll('\\', '/').toLowerCase() ==
        destination.absolute.path.replaceAll('\\', '/').toLowerCase();
    if (sameSource) {
      if (originalOrder && annotated.isEmpty) {
        report(tr('导出完成', 'Export complete'), 1);
        return true;
      }
      throw StateError(
        tr(
          '请选择原始 PDF 以外的导出位置',
          'Choose a destination other than the original PDF',
        ),
      );
    }
    mark('preflight');
    // 所有临时段写入本次独立目录，结束后只清理本任务拥有的文件。
    final working = await Directory(
      '${destination.parent.path}/.fastink-export-${DateTime.now().microsecondsSinceEpoch}',
    ).create();
    final output = File('${working.path}/result.pdf');
    try {
      if (originalOrder && annotated.isEmpty) {
        final length = await original.length();
        final sink = output.openWrite();
        var copied = 0;
        try {
          await sink.addStream(
            original.openRead().map((bytes) {
              copied += bytes.length;
              report(
                tr('正在无损复制原 PDF…', 'Copying original PDF losslessly…'),
                length == 0 ? .95 : math.min(.99, copied / length),
              );
              return bytes;
            }),
          );
          await sink.flush();
        } finally {
          await sink.close();
        }
      } else {
        final qpdf = _qpdfExecutable();
        report(
          tr(
            '复用原 PDF 页面，准备新增页和批注…',
            'Reusing original PDF pages; preparing additions and annotations…',
          ),
          .04,
        );
        // 这里不渲染原始 PDF，只为独立背景生成图像。
        // 相同的无批注纸张只生成一个 PDF 页面，输出顺序通过引用映射保留。
        // 无批注的相同底图可复用代表页，哈希用于验证一致，不改变多次出现的页序。
        final representatives = await _plainPageRepresentatives(
          document,
          custom,
          nonEmptyInk,
          onProgress: (done) => report(
            tr('正在准备新增页面…', 'Preparing added pages…'),
            .04 + .04 * done / math.max(1, custom.length),
          ),
        );
        final uniqueCustom = custom
            .where((i) => representatives[i] == i)
            .toList();
        // 记录自建代表页在临时 PDF 段中的位置，最终合并按这个映射取页。
        final customLocation = <int, ({String file, int page})>{};
        for (
          var offset = 0;
          offset < uniqueCustom.length;
          offset += _pdfPagesPerPart
        ) {
          final batch = uniqueCustom
              .skip(offset)
              .take(_pdfPagesPerPart)
              .toList();
          final part = File('${working.path}/custom-$offset.pdf');
          await _writePdfPart(
            document,
            batch,
            part,
            totalPages: uniqueCustom.length,
            completedBeforePart: offset,
            nonEmptyInkIds: nonEmptyInk,
            onProgress: (_) => report(
              tr('正在生成新增页面…', 'Building added pages…'),
              .08 +
                  .26 *
                      (offset + batch.length) /
                      math.max(1, uniqueCustom.length),
            ),
          );
          for (var i = 0; i < batch.length; i++) {
            customLocation[batch[i]] = (file: part.path, page: i + 1);
          }
        }
        for (final index in custom) {
          customLocation[index] = customLocation[representatives[index]]!;
        }
        mark('custom-pages');
        // 叠加临时段按受限页数构建，防止大量图片/文字同时占满内存。
        final overlayParts = <File>[];
        if (annotated.isNotEmpty) {
          for (
            var offset = 0;
            offset < annotated.length;
            offset += _pdfPagesPerPart
          ) {
            final prepared = <_PreparedPdfInkPage>[];
            final batch = annotated
                .skip(offset)
                .take(_pdfPagesPerPart)
                .toList();
            for (var i = 0; i < batch.length; i++) {
              final page = document.pages[indexes[batch[i]]];
              final size = geometries[page.originalPage]?.size;
              if (size == null || size.isEmpty) {
                throw StateError(
                  'Missing PDF geometry for page ${page.originalPage}',
                );
              }
              prepared.add(
                await _prepareInkOverlayPage(
                  document,
                  size,
                  inkById.remove(page.originalPage) ??
                      await notes.loadPageInk(
                        document,
                        page,
                        legacyWidthReference: _inkWidthReference,
                        background: true,
                      ),
                ),
              );
              report(
                tr(
                  '正在处理批注：${offset + i + 1} / ${annotated.length} 页',
                  'Preparing annotations: ${offset + i + 1} / ${annotated.length} pages',
                ),
                .34 + .30 * (offset + (i + 1) * .15) / annotated.length,
              );
              // 长时间矢量导出期间让出执行权，以处理画面、进度和输入事件。
              if (i % 4 == 0) await Future<void>.delayed(Duration.zero);
            }
            final part = File('${working.path}/ink-${overlayParts.length}.pdf');
            await _writePreparedPdfInk(
              prepared,
              part.path,
              onProgress: (value) => report(
                tr(
                  '正在生成批注图层：${offset + 1}–${offset + batch.length} / ${annotated.length} 页',
                  'Writing annotation layers: ${offset + 1}–${offset + batch.length} / ${annotated.length} pages',
                ),
                .34 +
                    .30 *
                        (offset + batch.length * (.15 + .85 * value)) /
                        annotated.length,
              ),
            );
            overlayParts.add(part);
          }
        }
        File? overlay;
        if (overlayParts.length == 1) {
          overlay = overlayParts.single;
        } else if (overlayParts.isNotEmpty) {
          overlay = File('${working.path}/ink.pdf');
          await _runQpdf(
            qpdf,
            [
              '--empty',
              '--stream-data=preserve',
              '--pages',
              for (final part in overlayParts) ...[
                '--file=${part.path}',
                '--range=1-z',
              ],
              '--',
              overlay.path,
            ],
            working,
            (value) => report(
              tr('正在合并批注图层…', 'Joining annotation layers…'),
              .64 + value * .08,
            ),
          );
        }
        mark('annotations');
        final args = <String>[
          original.path, '--stream-data=preserve',
          // qpdf 新建的批注 Form 流原本未压缩；仅无损压缩这些新流，
          // 保留原 PDF 已压缩的图像与文字流，不解码、不重采样。
          if (annotated.isNotEmpty) ...[
            '--compress-streams=y',
            '--compression-level=1',
          ],
        ];
        if (!originalOrder) {
          args.add('--pages');
          // 同一文件的连续页面合并处理，避免 Windows 命令行长度限制。
          String? file;
          final pages = <int>[];
          // 把当前连续页范围写入合并计划，避免为每一页重复启动工具。
          void flush() {
            if (file == null) return;
            args.addAll(['--file=$file', '--range=${_pageRanges(pages)}']);
            pages.clear();
          }

          for (final index in indexes) {
            final source =
                customLocation[index] ??
                (file: original.path, page: document.pages[index].originalPage);
            if (file != source.file) {
              flush();
              file = source.file;
            }
            pages.add(source.page);
          }
          flush();
          args.add('--');
        }
        if (overlay != null) {
          args.addAll([
            '--overlay',
            overlay.path,
            '--to=${_pageRanges(annotated.map((i) => i + 1).toList())}',
            '--from=1-z',
            '--',
          ]);
        }
        args.add(output.path);
        report(
          tr(
            '正在写入 PDF：${indexes.length} 页…',
            'Writing PDF: ${indexes.length} pages…',
          ),
          .72,
        );
        await _runQpdf(
          qpdf,
          args,
          working,
          (value) => report(
            tr(
              '正在写入 PDF：${indexes.length} 页…',
              'Writing PDF: ${indexes.length} pages…',
            ),
            .72 + value * .27,
          ),
        );
      }
      mark('merge-or-copy');
      if (!await output.exists() || await output.length() == 0) {
        throw StateError('Empty PDF export');
      }
      report(tr('正在保存导出文件…', 'Saving exported file…'), .99);
      // Windows 重命名可直接替换目标文件，无需先删除旧文件。
      await output.rename(destination.path);
      mark('publish');
      report(
        tr(
          '导出完成：${indexes.length} 页',
          'Export complete: ${indexes.length} pages',
        ),
        1,
      );
      return true;
    } finally {
      if (await working.exists()) await working.delete(recursive: true);
    }
  }

  /// 相同路径直接复用；不同路径只有字节指纹相同才合并，不能只凭名称或大小。
  /// 大文件跳过内容去重，避免给不同扫描页额外增加一次大文件读取。
  Future<Map<int, int>> _plainPageRepresentatives(
    NoteDocument document,
    List<int> indexes,
    Set<int> nonEmptyInk, {
    void Function(int)? onProgress,
  }) async {
    final result = <int, int>{};
    final byPath = <String, int>{};
    final byLength = <int, List<int>>{};
    final feedback = Stopwatch()..start();
    for (var position = 0; position < indexes.length; position++) {
      final index = indexes[position];
      final page = document.pages[index];
      result[index] = index;
      if (!nonEmptyInk.contains(page.originalPage)) {
        final path = File(
          page.path,
        ).absolute.path.replaceAll('\\', '/').toLowerCase();
        final previous = byPath[path];
        if (previous != null) {
          result[index] = previous;
        } else {
          byPath[path] = index;
          final stat = await File(page.path).stat();
          if (stat.type == FileSystemEntityType.file &&
              stat.size > 0 &&
              stat.size <= 2 * 1024 * 1024) {
            (byLength[stat.size] ??= []).add(index);
          }
        }
      }
      if (feedback.elapsedMilliseconds >= 40 ||
          position == indexes.length - 1) {
        onProgress?.call(position + 1);
        feedback.reset();
      }
    }
    for (final candidates in byLength.values) {
      if (candidates.length < 2) continue;
      final byContent = <String, int>{};
      for (final index in candidates) {
        final digest =
            (await crypto.sha256
                    .bind(File(document.pages[index].path).openRead())
                    .first)
                .toString();
        result[index] = byContent.putIfAbsent(digest, () => index);
      }
    }
    for (final index in indexes) {
      var representative = result[index]!;
      while (result[representative] != representative) {
        representative = result[representative]!;
      }
      result[index] = representative;
    }
    return result;
  }

  /// 定位随包 qpdf 可执行文件，缺失时不假装快速路径已可用。
  String _qpdfExecutable() {
    for (final base in [
      File(Platform.resolvedExecutable).parent.path,
      '${Directory.current.path}/windows',
    ]) {
      final path = '$base/tools/qpdf/qpdf.exe';
      if (File(path).existsSync()) return path;
    }
    throw StateError(
      tr(
        '缺少快速 PDF 导出组件，请使用完整的 FastInk 安装包',
        'Fast PDF export component missing. Use the complete FastInk package.',
      ),
    );
  }

  /// 执行 qpdf 合并/叠加命令并检查退出码、错误输出和最终文件，不能只凭进程启动成功判断完成。
  Future<void> _runQpdf(
    String executable,
    List<String> args,
    Directory working,
    void Function(double) onWrite,
  ) async {
    final arguments = File('${working.path}/qpdf-args.txt');
    await arguments.writeAsString(
      ['--progress', ...args].join('\n'),
      encoding: utf8,
    );
    final process = await Process.start(executable, ['@${arguments.path}']);
    final error = StringBuffer();
    final out = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .forEach((line) {
          final match = RegExp(r'write progress: (\d+)%').firstMatch(line);
          if (match != null) onWrite(int.parse(match[1]!) / 100);
        });
    final err = process.stderr.transform(utf8.decoder).forEach(error.write);
    final code = await process.exitCode;
    await out;
    await err;
    if (code != 0 && code != 3) throw StateError('PDF export: $error');
  }

  /// 把页面编号列表压缩成 qpdf 可用的连续范围表达，保持指定顺序。
  String _pageRanges(List<int> pages) {
    final ranges = <String>[];
    for (var i = 0; i < pages.length; i++) {
      final first = pages[i];
      var last = first;
      while (i + 1 < pages.length && pages[i + 1] == last + 1) {
        last = pages[++i];
      }
      ranges.add(first == last ? '$first' : '$first-$last');
    }
    return ranges.join(',');
  }
}
