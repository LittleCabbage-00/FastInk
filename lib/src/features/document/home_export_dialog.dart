part of '../../app/fastink_app.dart';

extension _FastInkExportDialog on _FastInkHomeState {
  /// 将独立导出进度叠加在当前界面上，进度通知不要求每次重建文档画布。
  Widget _withExportProgress(Widget child) => Stack(
    fit: StackFit.expand,
    children: [
      child,
      Positioned(
        right: 16,
        bottom: 16,
        child: ValueListenableBuilder<ExportProgress?>(
          valueListenable: _exportProgress,
          builder: (context, progress, _) => progress == null
              ? const SizedBox.shrink()
              : SizedBox(
                  width: math.min(380, MediaQuery.sizeOf(context).width - 32),
                  child: ExportProgressPanel(
                    key: const ValueKey('export-progress-panel'),
                    title: _exportTitle,
                    progress: progress,
                  ),
                ),
        ),
      ),
    ],
  );

  /// 更新导出进度通知与兼容状态文本，避免计时更新触发整页 setState。
  void _setExportProgress(ExportProgress progress) {
    if (!mounted) return;
    _exportProgress.value = progress;
    // 保留旧状态文本接口，但不因每次计时刷新而重建整个编辑器。
    _doc.status = progress.message;
  }

  /// 按导出格式与页数生成范围摘要，供确认窗口说明本次输出内容。
  Widget _exportPageSummary(int pageCount, NoteExportFormat format) => Text(
    format == NoteExportFormat.pdf
        ? tr('$pageCount 页，合并为一个 PDF', '$pageCount pages merged into one PDF')
        : tr(
            '$pageCount 页，按编号保存到文件夹',
            '$pageCount numbered images saved to a folder',
          ),
  );

  /// 从资料库索引装载导出目标并以整本为范围启动导出，不使用编辑器当前页概念。
  Future<void> _exportLibraryDocument(LibraryDocument item) async {
    if (_rejectConcurrentHeavyJob()) return;
    // 等菜单退场后打开导出选项，保持资料库和当前正在编辑的文稿不变。
    await Future<void>.delayed(const Duration(milliseconds: 180));
    if (!mounted) return;
    try {
      final indexed = _doc.document?.id == item.id
          ? _doc.document!
          : await _repository.indexFromSelectedPath(
              item.sourcePath,
              documentId: item.id,
            );
      if (!mounted) return;
      await _exportDocument(
        targetDocument: NoteDocument(
          id: indexed.id,
          title: item.title,
          directory: indexed.directory,
          pages: indexed.pages,
          initialIndex: indexed.initialIndex,
        ),
        allowCurrentPage: false,
        targetPageIndex: _doc.document?.id == item.id
            ? _doc.pageIndex
            : item.lastPageIndex,
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr('导出失败：$error', 'Export failed: $error'))),
        );
      }
    }
  }

  /// 收集输出格式和范围，等待保存并持有目标文稿任务/笔迹锁，更新进度后调用导出服务，最后释放锁与临时资源。
  Future<void> _exportDocument({
    NoteDocument? targetDocument,
    int? targetPageIndex,
    bool allowCurrentPage = true,
  }) async {
    final NoteDocument? document = targetDocument ?? _doc.document;
    if (document == null || document.pages.isEmpty) return;
    final selectedPageIndex = (targetPageIndex ?? _doc.pageIndex).clamp(
      0,
      document.pages.length - 1,
    );
    final NotePage page = document.pages[selectedPageIndex];
    final widthReference = document.id == _doc.document?.id
        ? _legacyInkWidthReference(selectedPageIndex)
        : legacyInkWidthFallbackReference;
    // 导出、换纸同一时刻只跑一个：两边同时读盘写盘，进度还会互相覆盖。
    if (_rejectConcurrentHeavyJob()) return;
    NoteExportFormat format = NoteExportFormat.pdf;
    bool allPages = true;
    final _ExportDialogResult? choice = await showDialog<_ExportDialogResult>(
      context: context,
      animationStyle: appMotionStyle(context),
      builder: (BuildContext dialogContext) => StatefulBuilder(
        builder:
            (
              BuildContext context,
              void Function(void Function()) setDialog,
            ) => AlertDialog(
              scrollable: true,
              title: Text(tr('导出文稿')),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 430),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Text(
                      document.title,
                      key: const ValueKey('export-document-title'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 14),
                    SegmentedButton<NoteExportFormat>(
                      segments: const <ButtonSegment<NoteExportFormat>>[
                        ButtonSegment<NoteExportFormat>(
                          value: NoteExportFormat.pdf,
                          icon: Icon(Icons.picture_as_pdf_outlined),
                          label: Text('PDF'),
                        ),
                        ButtonSegment<NoteExportFormat>(
                          value: NoteExportFormat.png,
                          icon: Icon(Icons.image_outlined),
                          label: Text('PNG'),
                        ),
                        ButtonSegment<NoteExportFormat>(
                          value: NoteExportFormat.jpg,
                          icon: Icon(Icons.photo_outlined),
                          label: Text('JPG'),
                        ),
                      ],
                      selected: <NoteExportFormat>{format},
                      onSelectionChanged: (Set<NoteExportFormat> values) {
                        setDialog(() => format = values.first);
                      },
                    ),
                    const SizedBox(height: 18),
                    if (allowCurrentPage)
                      RadioGroup<bool>(
                        groupValue: allPages,
                        onChanged: (bool? value) {
                          if (value != null) setDialog(() => allPages = value);
                        },
                        child: Column(
                          children: <Widget>[
                            RadioListTile<bool>(
                              key: const ValueKey('export-current-page'),
                              value: false,
                              title: Text(tr('只导出当前页')),
                              subtitle: Text(
                                tr(
                                  '第 ${selectedPageIndex + 1} 页',
                                  'Page ${selectedPageIndex + 1}',
                                ),
                              ),
                            ),
                            RadioListTile<bool>(
                              value: true,
                              title: Text(tr('导出整本文稿')),
                              subtitle: _exportPageSummary(
                                document.pages.length,
                                format,
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      ListTile(
                        key: const ValueKey('export-library-scope'),
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.description_outlined),
                        title: Text(tr('导出整本文稿')),
                        subtitle: _exportPageSummary(
                          document.pages.length,
                          format,
                        ),
                      ),
                    const SizedBox(height: 6),
                    Text(tr('背景、原页面、手写笔迹和荧光笔会合并到导出结果中。')),
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(tr('取消')),
                ),
                FilledButton.icon(
                  onPressed: () => Navigator.pop(
                    dialogContext,
                    _ExportDialogResult(format, !allowCurrentPage || allPages),
                  ),
                  icon: const Icon(Icons.save_alt_rounded),
                  label: Text(tr('选择保存位置')),
                ),
              ],
            ),
      ),
    );
    if (choice == null || !mounted) return;
    final String suffix = choice.allPages
        ? ''
        : tr('-第${selectedPageIndex + 1}页', '-page-${selectedPageIndex + 1}');
    File? destination;
    Directory? imageDirectory;
    if (choice.allPages && choice.format != NoteExportFormat.pdf) {
      imageDirectory = await _exportRepository.pickImageDirectory();
      if (imageDirectory == null) return;
    } else {
      destination = await _exportRepository.pickDestination(
        '${document.title}$suffix',
        choice.format,
      );
      if (destination == null) return;
    }
    // 先把任务挂到这份文稿上，再刷盘——刷盘是导出的一部分，标记提前置位
    // 才能堵住"两次点击都在 await 里"的重入窗口。两者按文稿记账：导出
    // 期间切到别的文稿，那边照常能写能改页。
    if (!mounted || _rejectConcurrentHeavyJob()) return;
    final String documentId = document.id;
    _doc.busyDocumentId = documentId;
    _doc.lockInk(documentId);
    _exportTitle = document.title;
    _setExportProgress(
      ExportProgress(tr('准备导出…', 'Preparing export…'), value: 0),
    );
    _updateState(() => _doc.status = tr('准备导出…', 'Preparing export…'));
    try {
      // 导出读的是刷过盘的磁盘内容，所以先刷盘再逐页读。
      if (!await _saveNow() || !mounted) return;
      // 基准取当前页：几何平均对 90° 旋转不变，同一份文稿横竖页共用一个值。
      _exportRepository.inkWidthReference = widthReference;
      if (choice.format == NoteExportFormat.pdf) {
        await _exportRepository.exportPdf(
          document,
          destination!,
          pageIndexes: choice.allPages ? null : <int>[selectedPageIndex],
          onUpdate: _setExportProgress,
        );
      } else if (choice.allPages) {
        await _exportRepository.exportImages(
          document,
          imageDirectory!,
          choice.format,
          onUpdate: _setExportProgress,
        );
      } else {
        await _exportRepository.exportImage(
          document,
          page,
          destination!,
          choice.format,
          onUpdate: _setExportProgress,
        );
      }

      final String exportedPath = destination?.path ?? imageDirectory!.path;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              tr('导出完成：$exportedPath', 'Export complete: $exportedPath'),
            ),
          ),
        );
        _updateState(
          () => _doc.status = tr(
            '已导出到 $exportedPath',
            'Exported to $exportedPath',
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr('导出失败：$error', 'Export failed: $error'))),
        );
        _updateState(
          () => _doc.status = tr('导出失败：$error', 'Export failed: $error'),
        );
      }
    } finally {
      // 先复位标志再重建：即使组件已被卸载也要把锁放掉。都按 id 释放——
      // 期间可能已经切到别的文稿，不能顺手清掉别人的状态。
      _doc.unlockInk(documentId);
      if (_doc.busyDocumentId == documentId) _doc.busyDocumentId = null;
      if (mounted) _exportProgress.value = null;
      if (mounted) _updateState(() {});
    }
  }
}
