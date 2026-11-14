part of '../../app/fastink_app.dart';

/// 页面的实际纸色，以及是否应优先显示选定的纸张模板。
typedef _PaperAppearance = ({bool dark, bool hasTemplate});

// ---------------------------------------------------------------------------
// 文档页面加载与预热流程。
//
// 本扩展负责将 PDF 页面从磁盘解码到屏幕的完整流程，包含三个核心机制：
//
// ## 1. 代次令牌（Page Token）
//
// 页面加载是异步的，用户可能在第一页还在加载时就跳到第五页。
// 如果不做处理，第一页的加载结果会覆盖第五页的数据——画面闪回到旧页面。
//
// 解决方案：每次调用 _loadPage 时递增 _doc.pageToken。异步操作返回后先比较
// token == _doc.pageToken，不匹配则丢弃结果（释放位图内存）。
// 这保证了"只有最新一次请求的结果会被应用"。
//
// ## 2. 并行等待（Dart Records + .wait）
//
// 当前页的数据源互不依赖：
//   - 位图（_decodePage）：需要完整解码 PNG。
//   - 笔迹（loadPageInk）：需要读取 JSON 文件。
//   - 纸张外观（_samplePaperAppearance）：模板取纸色，普通底图按 16x16 采样。
//   - 原图比例（_samplePageAspectRatio）：读取文件头，避免屏幕缓存取整误差。
//
// 使用 Dart 3 的 Record 解构 + .wait 并行等待，已有深浅和比例则直接复用。
//
// ## 3. 纸张深浅检测
//
// 某些 PDF 的纸张是深色/黑色的，如果墨迹颜色也是深色就会看不见。
// _detectPageDark 将页面缩小到 16x16，计算平均亮度（ITU-R BT.709 公式），
// 如果低于 0.48 则判定为"深色纸张"，自动将笔迹颜色切换为白色。
//
// 为什么用 16x16？极小的尺寸足以判断整体明暗趋势，解码速度极快（<5ms），
// 且只读取一次原始像素数据，对内存几乎无影响。
// ---------------------------------------------------------------------------

extension _FastInkDocumentLoad on _FastInkHomeState {
  /// 按物理视口与内存/供电预算解码当前页底图；返回的 ui.Image 由接收方负责释放，原图片不变。
  Future<ui.Image> _decodePage(String path) {
    // 当前页按物理视口解码，插电时最高 2600 px，电池模式最高 1600 px。
    // 此限制只影响屏幕底图；笔迹采样及原始 PDF、导出精度不变。
    final double physicalViewportWidth =
        _canvasViewport.width * MediaQuery.devicePixelRatioOf(context);
    final int targetWidth = math
        .max(1800, physicalViewportWidth * 1.5)
        .round()
        .clamp(
          1000,
          math.min(_memoryPolicy.currentPageWidth, _renderPolicy.pageWidth),
        );
    return decodeImageFile(
      path,
      targetWidth: targetWidth,
      maximumHeight: _renderPolicy.pageHeight,
    );
  }

  /// 刷新纸张或供电策略使用的底图，保留当前页的笔迹、选区与撤销历史。
  Future<void> _refreshPageDisplayResolution({
    bool paperChanged = false,
  }) async {
    final page = _doc.inkPage;
    if (page == null || _doc.pageLoading || _doc.pageImage == null) return;
    final token = ++_displayDecodeToken;
    final pageToken = _doc.pageToken;
    final paperRevision = _paperImageRevisions[page.path] ?? 0;
    final economical = _renderPolicy.economical;
    try {
      final image = await _decodePage(page.path);
      if (!mounted ||
          token != _displayDecodeToken ||
          pageToken != _doc.pageToken ||
          !identical(page, _doc.inkPage) ||
          paperRevision != (_paperImageRevisions[page.path] ?? 0) ||
          economical != _renderPolicy.economical) {
        image.dispose();
        return;
      }
      final previous = _doc.pageImage;
      _updateState(() => _doc.pageImage = image);
      final dark = _paperAppearanceCache[page.path]?.dark ?? false;
      if (paperChanged || _toolState.paperDark != dark) {
        _applyPaperContrast(dark);
      }
      if (previous != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => previous.dispose());
      }
    } catch (_) {
      if (paperChanged && mounted && pageToken == _doc.pageToken) rethrow;
      // 屏幕缓存刷新失败时继续显示现有底图，避免打断当前编辑。
    }
  }

  /// 按路径合并宽高比读取任务，读取文件头后缓存结果，避免先显示错误比例再跳变。
  Future<double> _samplePageAspectRatio(String path) =>
      _pageAspectRatioFlights.putIfAbsent(path, () async {
        try {
          final ({int width, int height}) dimensions =
              await readImageFileDimensions(path);
          return dimensions.width / dimensions.height;
        } finally {
          _pageAspectRatioFlights.remove(path);
        }
      });

  /// 内置模板直接取纸色。导入底图和自定义图案用低分辨率像素采样。
  Future<_PaperAppearance> _samplePaperAppearance(NotePage page) {
    final key = (page.path, _paperImageRevisions[page.path] ?? 0);
    return _paperAppearanceFlights.putIfAbsent(key, () async {
      try {
        final template = await _repository.loadPaperTemplate(page);
        return (
          dark: template != null && template.backgroundAsset == null
              ? _paperColorIsDark(template.color)
              : await _detectPageDark(page.path),
          hasTemplate: template != null,
        );
      } finally {
        _paperAppearanceFlights.remove(key);
      }
    });
  }

  /// 以与像素采样相同的 sRGB 权重判定模板纸色。
  bool _paperColorIsDark(Color color) =>
      0.2126 * color.r + 0.7152 * color.g + 0.0722 * color.b < 0.48;

  /// 旧笔迹（v2 及以前）换算成归一化粗细用的页面基准：该页布局尺寸的
  /// 几何平均边长（见 [PageInk.withNormalizedWidths]）。
  ///
  /// 旧 `width` 存的是绘制当时的布局像素，而那个尺寸没被记下来。用户通常
  /// 在同一台设备的同一个窗口里画和看，所以拿当前布局当基准，换算后屏幕
  /// 上粗细不变；文件下次保存就固化下来，此后各设备一致。布局还没建立时
  /// 退回设计基准——只影响打开文稿第一帧的极小竞态窗口。
  double _legacyInkWidthReference(int index) {
    final NoteDocument? document = _doc.document;
    final DocumentViewportLayout? layout = _viewport.documentViewportLayout;
    if (document == null ||
        layout == null ||
        index < 0 ||
        index >= layout.pages.length) {
      return legacyInkWidthFallbackReference;
    }
    final Size size = layout.pages[index].size;
    if (size.isEmpty) return legacyInkWidthFallbackReference;
    return math.sqrt(size.width * size.height);
  }

  /// 加载指定页面并更新 UI。
  ///
  /// 完整流程：保存当前状态 → 请求解码 → 并行等待(位图+笔迹+深浅) → 更新 UI → 预取邻页。
  /// 每一步都会检查 token 是否过期，过期则提前退出。
  Future<void> _loadPage(int requestedIndex) async {
    final NoteDocument? document = _doc.document;
    if (document == null) return;
    _commitInlineText();
    final int index = requestedIndex.clamp(0, document.pages.length - 1);
    final int direction = index < _doc.pageIndex ? -1 : 1;

    // ---- 代次令牌 ----
    // 每次页面切换递增 token。异步操作返回后比较 token：
    // 如果不匹配说明用户已经翻到另一页，当前结果作废。
    final int token = ++_doc.pageToken;
    final NotePage page = document.pages[index];
    final Stopwatch stopwatch = Stopwatch()..start();

    // 先掐断笔迹输入，再做任何磁盘等待。pageLoading 置位后 InkLayer 直接
    // 卸载，加载窗口里落笔/撤销都进不来——否则它们会把 dirty 重新点亮，
    // 而提交块结尾的 dirty=false 会把这次修改无声吞掉。
    _updateState(() {
      _doc.pageLoading = true;
      _doc.pageIndex = index;
      _pageInput.text = '${index + 1}';
      _doc.status = tr(
        '只加载第 ${index + 1} 页…',
        'Loading page ${index + 1} only…',
      );
    });
    // 离开页（inkPage 指向的那页）刷盘。上面已经掐了输入，这就是最终内容。
    final saved = await _saveNow();
    if (!mounted ||
        token != _doc.pageToken ||
        !identical(_doc.document, document)) {
      return;
    }
    if (!saved) {
      // 返回笔迹实际所属页，保留原控制器和撤销记录，修好存储后可以重试。
      final original = _doc.inkPage?.originalPage;
      final restore = document.pages.indexWhere(
        (page) => page.originalPage == original,
      );
      _updateState(() {
        _doc.pageLoading = false;
        if (restore >= 0) {
          _doc.pageIndex = restore;
          _pageInput.text = '${restore + 1}';
        }
      });
      _viewport.zoomReturnController.stop();
      _viewport.visiblePageTimer?.cancel();
      _viewport.pendingVisiblePage = null;
      if (restore >= 0) _moveViewportToPage(restore, animate: false);
      return;
    }
    // 把离开页的实时笔迹存进侧栏缓存：比读盘新，也免得翻走再回来看到
    // 编辑前的旧快照。进入页不必作废缓存——缓存内容与磁盘一致，加载窗口
    // 里正好拿它顶着显示，作废反而闪一下空白。
    final NotePage? leaving = _doc.inkPage;
    if (leaving != null &&
        leaving.path != page.path &&
        _doc.inkDocument?.id == document.id) {
      _pageInkCache.put(leaving.path, PageInk(strokes: _ink.snapshot()));
    }

    if (_showPageSidebar && _sidebarTab == 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _animateSidebarToPage(document, index, _settings.sidebarWidth);
        }
      });
    }
    try {
      _repository.prioritizePdfPage(document, page);
      // 预取页数按翻页间隔的指数移动平均调整。
      final List<int> prefetchIndexes = _prefetchPlanner.plan(
        index: index,
        pageCount: document.pages.length,
        direction: direction,
        maximumAhead: math.min(
          _settings.pdfPrefetchPages,
          _renderPolicy.economical ? 0 : _memoryPolicy.maximumPrefetchPages,
        ),
        now: DateTime.now(),
      );
      unawaited(_warmPageAppearances(document, prefetchIndexes));
      _repository.updatePdfCacheWindow(document, <int>[
        index,
        ...prefetchIndexes,
      ]);
      if (!await File(page.path).exists() &&
          mounted &&
          token == _doc.pageToken) {
        _updateState(
          () => _doc.status = tr(
            '正在按需转换第 ${index + 1} 页…',
            'Rendering page ${index + 1} on demand…',
          ),
        );
      }
      await _repository.ensurePageImage(document, page);
      final paperRevision = _paperImageRevisions[page.path] ?? 0;
      final cachedPaper = _paperAppearanceCache[page.path];

      // ---- 并行等待独立数据源 ----
      // 原图尺寸也从文件头读取，不能拿降采样后的整数像素推算纸张比例；
      // 超长页面被限高后宽度取整的误差会被放大，导致笔迹与底图错位。
      // 如果深浅已有缓存则直接返回缓存值，不再采样。
      final (
        ui.Image image,
        PageInk ink,
        _PaperAppearance paper,
        double aspect,
      ) = await (
        _decodePage(page.path),
        _repository.loadPageInk(
          document,
          page,
          legacyWidthReference: _legacyInkWidthReference(index),
          // 密集笔迹的 JSON 解析不占用界面线程，翻页期间仍能响应输入。
          background: true,
        ),
        cachedPaper == null
            ? _samplePaperAppearance(page)
            : Future.value(cachedPaper),
        _pageAspectRatioCache.containsKey(page.path)
            ? Future<double>.value(_pageAspectRatioCache[page.path]!)
            : _samplePageAspectRatio(page.path),
      ).wait;

      // ---- 代次校验 ----
      // 等待期间用户可能已经翻到其他页面，token 会不匹配。
      // 此时必须释放刚解码的位图，否则会造成内存泄漏。
      if (!mounted || token != _doc.pageToken) {
        image.dispose();
        return;
      }
      if (paperRevision != (_paperImageRevisions[page.path] ?? 0)) {
        image.dispose();
        await _loadPage(index);
        return;
      }
      // 保存旧位图引用，稍后在帧回调中释放——避免在当前帧内释放 GPU 纹理
      // 导致闪烁（新位图还未上屏时旧位图就消失了）。
      final ui.Image? previous = _doc.pageImage;
      _paperAppearanceCache[page.path] = paper;
      // 页面几何始终遵循原图比例，屏幕缓存的清晰度不影响笔迹坐标。
      _rememberPageAspectRatio(page.path, aspect);
      _doc.pageImage = image;
      _ink.replace(ink.strokes);
      // 归属与 replace 同一段同步代码里翻页：从此 _ink.strokes 装的是这一页。
      _doc.inkDocument = document;
      _doc.inkPage = page;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && identical(_doc.inkPage, page)) {
          _syncSelectionViewScale();
        }
      });
      _applyPaperContrast(paper.dark);
      stopwatch.stop();
      _updateState(() {
        _doc.pageLoading = false;
        _doc.dirty = false;
        _doc.performance =
            '${stopwatch.elapsedMilliseconds} ms · '
            '${tr('${image.width}×${image.height} · ${document.pages.length} 页', '${image.width}×${image.height} · ${document.pages.length} pages')}';
        _doc.status = tr(
          '已加载 · 手指上下翻页，笔尖书写',
          'Loaded · swipe vertically to turn pages, write with the pen',
        );
      });
      if (previous != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => previous.dispose());
      }
      _checkWorkingSet();
      await _persistLastPage(index);
      unawaited(
        _repository
            .prefetchPdfPages(document, prefetchIndexes)
            .then((_) => _warmPageAppearances(document, prefetchIndexes)),
      );
    } catch (error) {
      if (mounted && token == _doc.pageToken) {
        // 失败也不能把界面留在"半新半旧"状态：pageIndex 在异步等待之前就
        // 翻到新页了（页号框、侧栏高亮都跟了过去），而位图和 _ink.strokes
        // 仍是上一页的。把页码回滚到内存笔迹真正属于的那一页，两边才一致。
        // 内存笔迹不属于本文稿（换文稿途中）时不回滚，保持原页码最安全。
        final NotePage? inkPage = _doc.inkPage;
        final int restoreIndex =
            inkPage == null || _doc.inkDocument?.id != document.id
            ? _doc.pageIndex
            : document.pages.indexWhere(
                (NotePage candidate) =>
                    candidate.originalPage == inkPage.originalPage,
              );
        _updateState(() {
          _doc.pageLoading = false;
          if (restoreIndex >= 0 && restoreIndex < document.pages.length) {
            _doc.pageIndex = restoreIndex;
            _pageInput.text = '${restoreIndex + 1}';
          }
          _doc.status = tr('页面加载失败：$error', 'Page failed to load: $error');
        });
      }
    }
  }

  /// 预热邻页的外观数据（深浅 + 宽高比），但不完整解码。
  ///
  /// 为什么预热？
  /// - 宽高比：布局引擎需要所有可见页的宽高比来计算页面位置。如果不预热，
  ///   邻页进入视口时才读宽高比，会导致布局突然跳动。
  /// - 深浅：进入视口时需要知道纸张颜色以选择笔迹颜色。预热后直接从缓存读取。
  ///
  /// 为什么只读文件头？
  /// 宽高比只需图像尺寸（存在文件头中），深浅只需 16x16 缩略图。
  /// 完整解码一张 2000x3000 的页面可能需要 100ms+，而预热只需 ~5ms。
  Future<void> _warmPageAppearances(
    NoteDocument document,
    Iterable<int> indexes, {
    bool notify = true,
  }) async {
    bool changed = false;
    for (final int index in indexes.toSet()) {
      if (index < 0 || index >= document.pages.length) continue;
      final NotePage page = document.pages[index];
      final String path = page.path;
      final revision = _paperImageRevisions[path] ?? 0;
      final bool needsAppearance = !_paperAppearanceCache.containsKey(path);
      final bool needsAspectRatio = !_pageAspectRatioCache.containsKey(path);
      if (!needsAppearance && !needsAspectRatio) continue;
      final File file = File(path);
      if (!await file.exists()) continue;
      try {
        // 记录文件修改时间，预热完成后再次检查——如果期间文件被写入（如后台渲染），
        // 结果可能已过期，跳过缓存以避免使用旧数据。
        final DateTime before = await file.lastModified();
        final (_PaperAppearance? appearance, double? aspectRatio) = await (
          needsAppearance
              ? _samplePaperAppearance(page)
              : Future<_PaperAppearance?>.value(null),
          needsAspectRatio
              ? _samplePageAspectRatio(
                  path,
                ).then<double?>((double value) => value)
              : Future<double?>.value(null),
        ).wait;
        if (!await file.exists() ||
            await file.lastModified() != before ||
            revision != (_paperImageRevisions[path] ?? 0)) {
          continue;
        }
        if (appearance != null) _paperAppearanceCache[path] = appearance;
        if (aspectRatio != null && aspectRatio.isFinite && aspectRatio > 0) {
          _rememberPageAspectRatio(path, aspectRatio);
        }
        changed = true;
      } catch (_) {
        // 预热失败不写入缓存，页面进入视口后由完整解码结果补齐。
      }
    }
    if (notify && changed && mounted && _doc.document?.id == document.id) {
      _updateState(() {});
    }
  }

  /// 检测页面纸张是否为深色。
  ///
  /// 算法：
  /// 1. 将页面缩小到 16x16（极快，只读文件头元数据级别）。
  /// 2. 读取原始 RGBA 像素数据。
  /// 3. 每隔 4 个像素采样一次（offset += 16，因为 RGBA = 4 字节/像素），
  ///    减少计算量，16x16 图只需处理约 64 个采样点。
  /// 4. 使用 ITU-R BT.709 亮度公式：Y = 0.2126R + 0.7152G + 0.0722B
  ///    这是人眼感知亮度的标准权重（绿色最敏感，蓝色最不敏感）。
  /// 5. 平均亮度 < 0.48 判定为深色纸张。
  ///
  /// 为什么是 0.48 而不是 0.5？
  /// 纯白 = 1.0，纯黑 = 0.0，但实际纸张很少是纯白（约 0.9）。
  /// 0.48 足以覆盖大多数深色/灰色纸张，同时不会误判偏黄的浅色纸。
  Future<bool> _detectPageDark(String path) async {
    try {
      final ui.Image sample = await decodeImageFile(
        path,
        targetWidth: 16,
        targetHeight: 16,
      );
      try {
        final ByteData? data = await sample.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        if (data == null) return false;
        double total = 0;
        int count = 0;
        // 每隔 16 字节（4 像素）采样，覆盖约 25% 的像素。
        for (int offset = 0; offset + 3 < data.lengthInBytes; offset += 16) {
          final int r = data.getUint8(offset);
          final int g = data.getUint8(offset + 1);
          final int b = data.getUint8(offset + 2);
          // ITU-R BT.709 亮度系数，归一化到 [0, 1]。
          total += (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255;
          count++;
        }
        return count > 0 && total / count < 0.48;
      } finally {
        sample.dispose();
      }
    } catch (_) {
      return false;
    }
  }

  /// 判断墨迹颜色是否为"中性色"（极黑或极白）。
  ///
  /// 中性色会根据纸张深浅自动反转（黑纸用白笔，白纸用黑笔），
  /// 而非中性色（如红色、蓝色）保持不变——用户特意选的颜色不应被覆盖。
  bool _isNeutralInkColor(Color color) => isNeutralPaperInk(color);

  /// 根据纸张深浅调整笔迹颜色，确保对比度。
  ///
  /// 深色纸 → 笔迹改为白色；浅色纸 → 笔迹改为深灰色（#202124）。
  /// 只替换"中性色"笔迹（极黑/极白），用户手动选择的彩色笔迹不受影响。
  void _applyPaperContrast(bool dark) {
    final Color next = dark ? Colors.white : const Color(0xff202124);
    final bool replacePen = _isNeutralInkColor(Color(_settings.penColor));
    final bool replaceText = _isNeutralInkColor(_toolState.textColor);
    if (!mounted) return;
    _updateState(() {
      _toolState.paperDark = dark;
      if (replacePen) {
        _settings.penColor = next.toARGB32();
        if (_toolState.tool == InkTool.pen) _toolState.color = next;
      }
      if (replaceText) {
        _toolState.textColor = next;
        if (_toolState.tool == InkTool.text) _toolState.color = next;
      }
    });
  }

  /// 将指定零基页索引写入资料库的最后阅读位置，更新记录但不改变页面笔迹。
  Future<void> _persistLastPage(int index) async {
    final String? documentId = _doc.document?.id;
    if (documentId == null) return;
    bool changed = false;
    final List<LibraryDocument> documents = _library.documents.map((item) {
      if (item.id != documentId || item.lastPageIndex == index) return item;
      changed = true;
      return item.copyWith(lastPageIndex: index);
    }).toList();
    if (!changed) return;
    _library = LibraryState(documents: documents, folders: _library.folders);
    await _saveLibrary();
  }

  /// 将请求索引约束到现有页范围，移动相机并在目标变化时装载页面；大跨度跳转和经济策略避免昂贵翻页动画。
  void _goToPage(int requestedIndex) {
    final NoteDocument? document = _doc.document;
    if (document == null) return;
    final int index = requestedIndex.clamp(0, document.pages.length - 1);
    _viewport.visiblePageTimer?.cancel();
    _viewport.pendingVisiblePage = null;
    if (index != _doc.pageIndex && !_settings.keepZoomOnPageChange) {
      _resetZoom(notify: false);
    }
    _moveViewportToPage(
      index,
      animate:
          _settings.pageAnimationsEnabled &&
          !_renderPolicy.economical &&
          (index - _doc.pageIndex).abs() <= 1,
    );
    if (index != _doc.pageIndex) unawaited(_loadPage(index));
  }

  /// 处理用户从 1 开始的页码输入；空值恢复当前页，越界规范到首末页，确认后回到画布焦点。
  void _goToSubmitted(String value) {
    final document = _doc.document;
    if (document == null) return;
    final int? page = int.tryParse(value.trim());
    final index = page == null
        ? _doc.pageIndex
        : (page - 1).clamp(0, document.pages.length - 1);
    _pageInput.text = '${index + 1}';
    if (page != null) _goToPage(index);
    _canvasFocus.requestFocus();
  }
}
