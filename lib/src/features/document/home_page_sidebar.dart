part of '../../app/fastink_app.dart';

/// _thumbPadH：侧栏缩略图布局累计的水平留白，单位逻辑像素，用于计算实际预览宽度。
const double _thumbPadH = 12 + 14;

/// _thumbPadBottom：侧栏缩略图槽位底部间距，单位逻辑像素。
const double _thumbPadBottom = 12;

/// _thumbInfoRow：侧栏页码/菜单信息行高度，单位逻辑像素。
const double _thumbInfoRow = 24;

/// _thumbInfoGap：缩略图与信息行之间的间距，单位逻辑像素。
const double _thumbInfoGap = 5;

/// _thumbDefaultRatio：未知页面的稳定默认宽高比，真实文件头读取后再统一更新布局。
const double _thumbDefaultRatio = 0.707;

/// 依据页面真实比例和侧栏宽度计算缩略图槽位总高度，包含编号与外边距，供滚动定位一致使用。
double _thumbExtent(
  NoteDocument doc,
  int index,
  double sidebarWidth,
  Map<String, double> aspectRatioCache,
) {
  final double ratio =
      aspectRatioCache[doc.pages[index].path] ?? _thumbDefaultRatio;
  final double imageWidth = sidebarWidth - _thumbPadH;
  return imageWidth / ratio + _thumbInfoGap + _thumbInfoRow + _thumbPadBottom;
}

extension _FastInkPageSidebar on _FastInkHomeState {
  /// 构建页面、目录和书签页签，仅为可见附近页安排笔迹/图像加载；当前页使用实时笔迹。
  Widget _pageSidebar(NoteDocument document, double sidebarWidth) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final Map<int, String> pageTitles =
        _currentLibraryDocument?.pageTitles ?? const <int, String>{};
    final List<int>? bookmarkedIndexes = _sidebarTab == 2
        ? (_currentLibraryDocument?.bookmarkedPages ?? const <int>[])
              .where((int index) => index >= 0 && index < document.pages.length)
              .toList()
        : null;
    final int visiblePageCount =
        bookmarkedIndexes?.length ?? document.pages.length;
    final int cacheWidth = math.max(160, (sidebarWidth - _thumbPadH).round());
    // 首次显示时触发侧栏内可见页面的加载（页面页签和书签页签都算——
    // 书签列表同样要笔迹预览；目录页签没有缩略图列表）。
    //
    // 笔迹和缩略图分开判断：缩略图只有懒渲染的 PDF 才需要按需生成，而
    // 笔迹对任何文档都要读（笔记本的页面图本来就在磁盘上，但笔迹不在）。
    if (_sidebarTab != 1) {
      final List<int>? mapForLoad = bookmarkedIndexes;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_showPageSidebar || !_thumbnailScroll.hasClients) {
          return;
        }
        final ScrollMetrics metrics = _thumbnailScroll.position;
        _loadVisibleSidebarInk(document, metrics, _doc.pageIndex, mapForLoad);
        if (_repository.isLazyPdf(document)) {
          _loadVisibleSidebarThumbnails(
            document,
            metrics,
            _doc.pageIndex,
            mapForLoad,
          );
        }
      });
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 14, 10, 10),
          child: SegmentedButton<int>(
            showSelectedIcon: false,
            segments: <ButtonSegment<int>>[
              ButtonSegment<int>(value: 0, label: Text(tr('页面'))),
              ButtonSegment<int>(value: 1, label: Text(tr('目录'))),
              ButtonSegment<int>(value: 2, label: Text(tr('书签'))),
            ],
            selected: <int>{_sidebarTab},
            onSelectionChanged: (Set<int> values) => _updateState(() {
              _sidebarTab = values.first;
            }),
          ),
        ),
        if (_sidebarTab == 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: _doc.busy
                        ? null
                        : () => _addPage(afterIndex: _doc.pageIndex),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: Text(tr('添加页面', 'Add page')),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton.filledTonal(
                  key: const ValueKey('manage-pages'),
                  tooltip: tr('批量管理页面', 'Manage pages'),
                  onPressed: _doc.anyBusy || _doc.readOnly
                      ? null
                      : _managePages,
                  icon: const Icon(Icons.checklist_rounded, size: 20),
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
          child: Text(
            _sidebarTab == 1
                ? tr(
                    '${pageTitles.length + (_currentLibraryDocument?.pdfOutline.fold<int>(0, (sum, entry) => sum + entry.count) ?? 0)} 个目录项',
                    '${pageTitles.length + (_currentLibraryDocument?.pdfOutline.fold<int>(0, (sum, entry) => sum + entry.count) ?? 0)} outline entries',
                  )
                : tr(
                    '$visiblePageCount / ${document.pages.length} 页',
                    '$visiblePageCount / ${document.pages.length} pages',
                  ),
            style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12),
          ),
        ),
        if (_sidebarTab == 1 && _repository.isLazyPdf(document))
          TextButton.icon(
            key: const ValueKey('reload-pdf-outline'),
            onPressed: _pdfOutlineReading.contains(document.id)
                ? null
                : () => _ensurePdfOutline(document, force: true),
            icon: const Icon(Icons.refresh, size: 18),
            label: Text(tr('重新读取 PDF 目录', 'Reload PDF outline')),
          ),
        Expanded(
          child: _sidebarTab == 1
              ? _outlineList(document, pageTitles, colors)
              : visiblePageCount == 0
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      tr(
                        '还没有书签\n点击顶部书签按钮收藏当前页',
                        'No bookmarks yet\nUse the bookmark button above to save the current page',
                      ),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: colors.onSurfaceVariant),
                    ),
                  ),
                )
              : Scrollbar(
                  controller: _thumbnailScroll,
                  thumbVisibility: true,
                  child: NotificationListener<ScrollNotification>(
                    onNotification: (ScrollNotification notification) {
                      if (notification is ScrollUpdateNotification ||
                          notification is ScrollEndNotification) {
                        _scheduleSidebarThumbnailLoad(
                          document,
                          notification.metrics,
                          _doc.pageIndex,
                          bookmarkedIndexes,
                        );
                      }
                      return false;
                    },
                    child: ReorderableListView.builder(
                      scrollController: _thumbnailScroll,
                      padding: const EdgeInsets.fromLTRB(12, 0, 14, 20),
                      itemCount: visiblePageCount,
                      buildDefaultDragHandles: _sidebarTab == 0,
                      onReorderItem: (int oldIndex, int newIndex) {
                        if (_sidebarTab == 0) {
                          unawaited(_reorderPages(oldIndex, newIndex));
                        }
                      },
                      itemBuilder: (BuildContext context, int itemIndex) {
                        final int pageIndex =
                            bookmarkedIndexes?[itemIndex] ?? itemIndex;
                        final NotePage page = document.pages[pageIndex];
                        final ColorFilter? paperFilter = _paperDisplayFilter(
                          page,
                          colors.brightness,
                        );
                        final bool active = pageIndex == _doc.pageIndex;
                        // 笔迹不在页面位图里，要单独叠一层预览。
                        //
                        // 实时笔迹按"归属"判断，不看 pageIndex/loading：哪页
                        // 的字在内存里由 _doc.inkPage 标记，翻页的异步窗口里
                        // pageIndex 已经翻新但 _ink.strokes 还是上一页的——
                        // 此刻上一页的缩略图照旧实时跟手（它就是内存里那份），
                        // 新页用缓存快照顶着，replace() 一到再交给实时笔迹。
                        //
                        // take 而不是 peek：正在显示的页就是"最近使用"，不推进
                        // LRU 的话它会先被淘汰，滚回来就闪一下空白再重读。
                        final bool liveNow = identical(_doc.inkPage, page);
                        final List<InkStroke>? previewStrokes = liveNow
                            ? _ink.strokes
                            : _pageInkCache.take(page.path)?.strokes;
                        final Size? previewSize = previewStrokes == null
                            ? null
                            : _previewSourceSize(pageIndex);
                        final bool bookmarked =
                            _currentLibraryDocument?.bookmarkedPages.contains(
                              pageIndex,
                            ) ??
                            false;
                        final double extent = _thumbExtent(
                          document,
                          pageIndex,
                          sidebarWidth,
                          _pageAspectRatioCache,
                        );
                        return Padding(
                          key: ValueKey<String>('page-${page.originalPage}'),
                          padding: const EdgeInsets.only(bottom: 12),
                          child: SizedBox(
                            height: extent - 12,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: () => _goToPage(pageIndex),
                              child: Column(
                                children: <Widget>[
                                  Expanded(
                                    child: Container(
                                      clipBehavior: Clip.antiAlias,
                                      decoration: BoxDecoration(
                                        color:
                                            paperFilter != null ||
                                                _paperAppearanceCache[page.path]
                                                        ?.dark ==
                                                    true
                                            ? const Color(0xff202226)
                                            : Colors.white,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: active
                                              ? colors.primary
                                              : colors.outlineVariant,
                                          width: active ? 3 : 1,
                                        ),
                                      ),
                                      child: InkPreview(
                                        displayFilter: paperFilter,
                                        paperDark: _templateInkTone(page),
                                        sourceSize: previewSize,
                                        strokes:
                                            previewStrokes ??
                                            const <InkStroke>[],
                                        repaint: liveNow
                                            ? _ink.committedRepaint
                                            : null,
                                        live: liveNow ? _ink : null,
                                        // 嵌入图片要访问文件系统，引擎层不依赖
                                        // dart:io，所以由这里构造图层；回调给的
                                        // 矩形就是页面在缩略图里的摆放区域。
                                        imagesBuilder: previewStrokes == null
                                            ? null
                                            : (
                                                Rect pageRect,
                                              ) => EmbeddedImageLayer(
                                                strokes: previewStrokes,
                                                // 和主画布一样订阅提交通知，
                                                // 拖动图片选区时缩略图跟手。
                                                repaint: liveNow
                                                    ? _ink.committedRepaint
                                                    : null,
                                                // 按缩略图实际宽度解码，否则
                                                // 每张嵌入图都按原图分辨率
                                                // 解码，十几个可见缩略图
                                                // 就能吃掉几十 MB。
                                                cacheWidth: pageRect.width
                                                    .round()
                                                    .clamp(64, cacheWidth),
                                                resolvePath: (String asset) =>
                                                    _repository
                                                        .resolveEmbeddedImagePath(
                                                          document,
                                                          asset,
                                                        ),
                                              ),
                                        child: _displayPaper(
                                          Image(
                                            image: ResizeImage(
                                              _paperFileImage(page),
                                              width: cacheWidth,
                                            ),
                                            fit: BoxFit.contain,
                                            gaplessPlayback: true,
                                            filterQuality: FilterQuality.low,
                                            errorBuilder: (_, _, _) => Center(
                                              child: Icon(
                                                Icons.picture_as_pdf_outlined,
                                                color: colors.onSurfaceVariant,
                                              ),
                                            ),
                                          ),
                                          paperFilter,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: <Widget>[
                                      Text(
                                        '${pageIndex + 1}',
                                        style: TextStyle(
                                          color: active
                                              ? colors.primary
                                              : colors.onSurfaceVariant,
                                          fontWeight: active
                                              ? FontWeight.w700
                                              : FontWeight.w400,
                                        ),
                                      ),
                                      if (bookmarked) ...<Widget>[
                                        const SizedBox(width: 4),
                                        Icon(
                                          Icons.bookmark_rounded,
                                          size: 15,
                                          color: colors.primary,
                                        ),
                                      ],
                                      const Spacer(),
                                      PopupMenuButton<String>(
                                        popUpAnimationStyle: appMotionStyle(
                                          context,
                                        ),
                                        tooltip: tr('页面操作'),
                                        padding: EdgeInsets.zero,
                                        iconSize: 18,
                                        onSelected: (String value) {
                                          if (value == 'outline') {
                                            unawaited(_setPageTitle(pageIndex));
                                          } else if (value == 'cover') {
                                            unawaited(
                                              _setPageAsCover(pageIndex),
                                            );
                                          } else if (value == 'rotate-left') {
                                            unawaited(
                                              _rotatePage(
                                                pageIndex,
                                                clockwise: false,
                                              ),
                                            );
                                          } else if (value == 'rotate-right') {
                                            unawaited(_rotatePage(pageIndex));
                                          } else if (value == 'duplicate') {
                                            unawaited(
                                              _duplicatePage(pageIndex),
                                            );
                                          } else if (value == 'delete') {
                                            unawaited(_deletePage(pageIndex));
                                          }
                                        },
                                        itemBuilder: (_) => <PopupMenuEntry<String>>[
                                          PopupMenuItem<String>(
                                            value: 'outline',
                                            child: ListTile(
                                              contentPadding: EdgeInsets.zero,
                                              leading: const Icon(
                                                Icons
                                                    .format_list_bulleted_rounded,
                                              ),
                                              title: Text(tr('设置目录标题')),
                                            ),
                                          ),
                                          PopupMenuItem<String>(
                                            value: 'cover',
                                            enabled: !_doc.busy,
                                            child: ListTile(
                                              contentPadding: EdgeInsets.zero,
                                              leading: const Icon(
                                                Icons
                                                    .collections_bookmark_outlined,
                                              ),
                                              title: Text(tr('设为文稿封面')),
                                            ),
                                          ),
                                          PopupMenuItem<String>(
                                            value: 'rotate-left',
                                            enabled: !_doc.busy,
                                            child: ListTile(
                                              contentPadding: EdgeInsets.zero,
                                              leading: const Icon(
                                                Icons.rotate_left,
                                              ),
                                              title: Text(tr('页面向左旋转')),
                                            ),
                                          ),
                                          PopupMenuItem<String>(
                                            value: 'rotate-right',
                                            enabled: !_doc.busy,
                                            child: ListTile(
                                              contentPadding: EdgeInsets.zero,
                                              leading: const Icon(
                                                Icons.rotate_right,
                                              ),
                                              title: Text(tr('页面向右旋转')),
                                            ),
                                          ),
                                          PopupMenuItem<String>(
                                            value: 'duplicate',
                                            enabled: !_doc.busy,
                                            child: ListTile(
                                              contentPadding: EdgeInsets.zero,
                                              leading: const Icon(
                                                Icons.copy_rounded,
                                              ),
                                              title: Text(tr('复制页面')),
                                            ),
                                          ),
                                          PopupMenuItem<String>(
                                            value: 'delete',
                                            enabled: !_doc.busy,
                                            child: ListTile(
                                              contentPadding: EdgeInsets.zero,
                                              leading: const Icon(
                                                Icons.delete_outline,
                                              ),
                                              title: Text(tr('删除页面')),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  /// 取页面在主画布布局里的尺寸，交给 [InkPreview] 作为绘制参照。
  ///
  /// 笔迹粗细已按页面归一化，缩略图在什么尺度下画都自动正确，这里只要
  /// 比例与页面一致（用来算页面在预览框里的摆放矩形）。布局尚未建立时
  /// 返回 null，此时不画笔迹预览。
  Size? _previewSourceSize(int pageIndex) {
    final DocumentViewportLayout? layout = _viewport.documentViewportLayout;
    if (layout == null || pageIndex < 0 || pageIndex >= layout.pages.length) {
      return null;
    }
    return layout.pages[pageIndex].size;
  }

  /// 经济模式等待书写、手势和滚动空隙；每次等待复查文稿、页签和任务代次，过期返回 false。
  Future<bool> _waitForSidebarPreview(NoteDocument document, int generation) =>
      waitForPreviewTurn(
        active: () =>
            mounted &&
            _showPageSidebar &&
            _sidebarTab != 1 &&
            identical(_doc.document, document) &&
            generation == _sidebarThumbnailGeneration,
        busy: () =>
            _ink.isInteracting ||
            _touchPoints.isNotEmpty ||
            _viewport.trackpadStartMatrix != null ||
            _viewport.zoomReturnController.isAnimating ||
            (_thumbnailScroll.hasClients &&
                _thumbnailScroll.position.isScrollingNotifier.value) ||
            (_previewViewActivity.isRunning &&
                _previewViewActivity.elapsedMilliseconds < 180) ||
            WidgetsBinding.instance.lifecycleState ==
                AppLifecycleState.paused ||
            WidgetsBinding.instance.lifecycleState == AppLifecycleState.hidden,
      );

  /// 滚动变化时递增代次并重置 150 毫秒防抖，旧范围任务在提交前必须作废。
  void _scheduleSidebarThumbnailLoad(
    NoteDocument document,
    ScrollMetrics metrics,
    int currentPage,
    List<int>? indexMap,
  ) {
    _sidebarThumbnailTimer?.cancel();
    _sidebarThumbnailGeneration++;
    _sidebarThumbnailTimer = Timer(const Duration(milliseconds: 150), () {
      if (!mounted) return;
      _loadVisibleSidebarInk(document, metrics, currentPage, indexMap);
      // 只有懒渲染的 PDF 才需要按需生成缩略图；其他文档的页面图本来
      // 就在磁盘上，侧栏直接 Image.file 读得到。
      if (_repository.isLazyPdf(document)) {
        _loadVisibleSidebarThumbnails(document, metrics, currentPage, indexMap);
      }
    });
  }

  /// 加载侧栏可见范围内各页的笔迹，填进 [_pageInkCache] 供缩略图预览。
  ///
  /// [indexMap] 把列表槽位映射到文档页码（书签页签只有书签页；null 表示
  /// 页面页签，槽位就是页码）。可见范围必须先按槽位算再映射——拿槽位直接
  /// 索引 document.pages 在书签页签里会加载错误的页甚至越界。
  ///
  /// 每次滚动停止后最多处理 [MemoryPolicy.sidebarThumbnailBudget] 页，且
  /// 全部挂在 [_sidebarInkChain] 上串行执行，所以最多只有一次读盘在飞。
  /// 它和 pdftoppm 渲染队列是分开的两条，互不阻塞；两者同时进行时总并发
  /// 也就是"一次读取 + 一次渲染"。
  ///
  /// 当前页跳过：它的笔迹就在 [InkController] 里，缩略图直接读实时的，
  /// 而且此刻可能还没落盘。
  Future<void> _loadVisibleSidebarInk(
    NoteDocument document,
    ScrollMetrics metrics,
    int currentPage,
    List<int>? indexMap,
  ) async {
    // 内存档位可以随时改，每次装载都按当前档位刷新容量。
    _pageInkCache.capacity = _memoryPolicy.sidebarInkCachePages;
    final int pageCount = document.pages.length;
    final int itemCount = indexMap?.length ?? pageCount;
    if (itemCount == 0) return;
    final double top = metrics.pixels;
    final double bottom = top + metrics.viewportDimension;
    // 与缩略图同样的近似：可见范围用固定 200 估算，多算几项不影响正确性。
    final int first = (top / 200).floor().clamp(0, itemCount - 1);
    final int last = (bottom / 200).ceil().clamp(0, itemCount - 1);
    final int generation = _sidebarThumbnailGeneration;

    // 已经在缓存里的页不用再读盘；顺手按"离当前页由近到远"排好，
    // 跳转后最先想看的是目标页周围的笔迹。peek 不推进 LRU——这里只是
    // 判断要不要读盘，淘汰顺序由真正显示它的那一侧（take）决定。
    final List<(int, NotePage)> pending = <(int, NotePage)>[];
    for (int slot = first; slot <= last; slot++) {
      final int i = indexMap?[slot] ?? slot;
      if (i == currentPage || i < 0 || i >= pageCount) continue;
      final NotePage page = document.pages[i];
      if (_pageInkCache.peek(page.path) != null &&
          _paperAppearanceCache.containsKey(page.path)) {
        continue;
      }
      pending.add((i, page));
    }
    if (pending.isEmpty) return;
    if (!_sidebarInkQueued.add(generation)) return;
    pending.sort(
      ((int, NotePage) a, (int, NotePage) b) =>
          (a.$1 - currentPage).abs().compareTo((b.$1 - currentPage).abs()),
    );

    await (_sidebarInkChain = _sidebarInkChain
        .catchError((Object _) {})
        .then((_) async {
          bool anyLoaded = false;
          int budget = _memoryPolicy.sidebarThumbnailBudget;
          for (final (int, NotePage) entry in pending) {
            if (budget <= 0) break;
            if (!mounted || generation != _sidebarThumbnailGeneration) return;
            // 入队到执行之间这页可能已经被别的路径填好（翻页离开时的
            // put-on-leave 就会），再查一次：命中就直接用，省一次 IO，
            // 也免得用旧读数覆盖更新的快照。
            final path = entry.$2.path;
            final needsAppearance = !_paperAppearanceCache.containsKey(path);
            final needsInk = _pageInkCache.take(path) == null;
            if (!needsAppearance && !needsInk) continue;
            if (!await _waitForSidebarPreview(document, generation)) return;
            budget--;
            try {
              if (needsAppearance) {
                await _warmPageAppearances(document, [entry.$1], notify: false);
                // PDF 尚未生成底图时不会得到外观结果，等待生成任务通知刷新。
                anyLoaded |= _paperAppearanceCache.containsKey(path);
              }
              if (!mounted || generation != _sidebarThumbnailGeneration) return;
              if (needsInk && _pageInkCache.peek(path) == null) {
                final PageInk ink = await _repository.loadPageInk(
                  document,
                  entry.$2,
                  // 走到这里 generation 已经校验过，布局就是本文稿的。
                  legacyWidthReference: _legacyInkWidthReference(entry.$1),
                  background: true,
                );
                if (!mounted || generation != _sidebarThumbnailGeneration) {
                  return;
                }
                // 翻页期间可能已填入更新的笔迹快照。
                if (_pageInkCache.peek(path) == null) {
                  _pageInkCache.put(path, ink);
                  anyLoaded = true;
                }
              }
            } catch (_) {
              // 单页读失败不影响其他页，下次滚动会重试。
            }
          }
          if (anyLoaded &&
              mounted &&
              generation == _sidebarThumbnailGeneration) {
            _sidebarThumbnailUpdateTimer?.cancel();
            _sidebarThumbnailUpdateTimer = Timer(
              const Duration(milliseconds: 200),
              () {
                if (mounted) _updateState(() {});
              },
            );
          }
        })
        .whenComplete(() => _sidebarInkQueued.remove(generation)));
  }

  /// 只为懒渲染 PDF 的侧栏可见页串行生成图像，同一代次合并排队；经济策略下逐项等待操作空隙。
  Future<void> _loadVisibleSidebarThumbnails(
    NoteDocument document,
    ScrollMetrics metrics,
    int currentPage,
    List<int>? indexMap,
  ) async {
    if (!_repository.isLazyPdf(document)) return;
    final int pageCount = document.pages.length;
    final int itemCount = indexMap?.length ?? pageCount;
    if (itemCount == 0) return;
    final double top = metrics.pixels;
    final double bottom = top + metrics.viewportDimension;
    // 可见范围用固定200近似，保守多算几项不影响正确性。
    final int first = (top / 200).floor().clamp(0, itemCount - 1);
    final int last = (bottom / 200).ceil().clamp(0, itemCount - 1);
    // 串行渲染，与主视口预取共享同一 pdftoppm 队列，避免低压 CPU
    // 同时启动多个进程导致卡顿和发热。
    final int generation = _sidebarThumbnailGeneration;
    if (!_sidebarImagesQueued.add(generation)) return;
    _sidebarThumbnailChain = _sidebarThumbnailChain
        .catchError((Object _) {})
        .then((_) async {
          bool anyLoaded = false;
          int budget = _memoryPolicy.sidebarThumbnailBudget;
          // 当前页优先：跳转到远端页面时，目标页立即渲染，不用等前面的页排完。
          // 书签页签里要按映射后的槽位判断在不在可见范围内。
          final int currentSlot = indexMap == null
              ? currentPage
              : indexMap.indexOf(currentPage);
          if (currentSlot >= first &&
              currentSlot <= last &&
              !File(document.pages[currentPage].path).existsSync()) {
            if (!mounted || generation != _sidebarThumbnailGeneration) return;
            if (!await _waitForSidebarPreview(document, generation)) return;
            try {
              await _repository.ensurePageImage(
                document,
                document.pages[currentPage],
              );
              anyLoaded = true;
              budget--;
            } catch (_) {}
          }
          // 当前页渲染完后再处理可见范围内的其余页面。
          for (int slot = first; slot <= last && budget > 0; slot++) {
            final int i = indexMap?[slot] ?? slot;
            if (i == currentPage || i < 0 || i >= pageCount) continue;
            if (!mounted || generation != _sidebarThumbnailGeneration) return;
            final NotePage page = document.pages[i];
            if (File(page.path).existsSync()) continue;
            if (!await _waitForSidebarPreview(document, generation)) return;
            try {
              await _repository.ensurePageImage(document, page);
              anyLoaded = true;
              budget--;
            } catch (_) {}
          }
          if (anyLoaded &&
              mounted &&
              generation == _sidebarThumbnailGeneration) {
            _sidebarThumbnailUpdateTimer?.cancel();
            _sidebarThumbnailUpdateTimer = Timer(
              const Duration(milliseconds: 200),
              () {
                if (mounted) _updateState(() {});
              },
            );
          }
        })
        .whenComplete(() => _sidebarImagesQueued.remove(generation));
  }

  /// 按逐页实际槽位高度累计偏移，使侧栏当前页进入可见范围，不按固定页高猜测滚动位置。
  void _animateSidebarToPage(
    NoteDocument document,
    int index,
    double sidebarWidth,
  ) {
    if (!_thumbnailScroll.hasClients) return;
    double offset = 0;
    for (int i = 0; i < index; i++) {
      offset += _thumbExtent(document, i, sidebarWidth, _pageAspectRatioCache);
    }
    final double itemH = _thumbExtent(
      document,
      index,
      sidebarWidth,
      _pageAspectRatioCache,
    );
    final double viewport = _thumbnailScroll.position.viewportDimension;
    final double target = offset + itemH / 2 - viewport / 2;
    _thumbnailScroll.animateTo(
      target.clamp(0.0, _thumbnailScroll.position.maxScrollExtent),
      duration: appMotionDuration(context, 160),
      curve: Curves.easeOutCubic,
    );
  }
}
