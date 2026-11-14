part of '../../app/fastink_app.dart';

/// 把浅色纸面映射为深色。用亮度调整各颜色分量，保留颜色方向与透明度。
const _darkPaperFilter = ColorFilter.matrix(<double>[
  0.621572,
  -1.273056,
  -0.128516,
  0,
  232,
  -0.378428,
  -0.273056,
  -0.128516,
  0,
  232,
  -0.378428,
  -1.273056,
  0.871484,
  0,
  232,
  0,
  0,
  0,
  1,
  0,
]);

/// 只在需要时安装显示滤镜，直接复用已有解码位图与笔迹缓存。
Widget _displayPaper(Widget child, ColorFilter? filter) =>
    filter == null ? child : ColorFiltered(colorFilter: filter, child: child);

/// 文件路径不变时，纸张代次也必须进入 FileImage 和 ResizeImage 的缓存键。
class _PaperFileImage extends FileImage {
  const _PaperFileImage(super.file, this.revision);

  /// 该文件在本次运行中的底图版本。
  final int revision;

  @override
  bool operator ==(Object other) =>
      other is _PaperFileImage &&
      other.file.path == file.path &&
      other.revision == revision;

  @override
  int get hashCode => Object.hash(file.path, revision);
}

/// 构造连续画布中的单页内容。
///
/// 外层视口只创建可见页附近的组件；高清位图和可编辑笔迹仍只属于当前页。
extension _FastInkDocumentPage on _FastInkHomeState {
  /// 选定的纸张模板始终显示本色，深色阅读滤镜用于普通浅色导入页。
  ColorFilter? _paperDisplayFilter(NotePage page, Brightness brightness) {
    final appearance = _paperAppearanceCache[page.path];
    return brightness == Brightness.dark &&
            appearance?.hasTemplate != true &&
            appearance?.dark != true
        ? _darkPaperFilter
        : null;
  }

  /// 为底图和侧栏预览提供同一版本的文件图像。
  FileImage _paperFileImage(NotePage page) =>
      _PaperFileImage(File(page.path), _paperImageRevisions[page.path] ?? 0);

  /// 只有模板页调整已有中性墨色，导入底图上的原注释保留配色。
  bool? _templateInkTone(NotePage page) {
    final appearance = _paperAppearanceCache[page.path];
    return appearance?.hasTemplate == true ? appearance!.dark : null;
  }

  /// 组装单页底图、嵌入图、笔迹与浮层；高清与可编辑内容只属于当前已装载页，邻页保留低分辨率预览。
  /// pageSize 为文稿逻辑尺寸，viewScale 为相机倍率；供电策略只调整显示预算，不改原始内容。
  Widget _documentPageWidget(
    NoteDocument document,
    int index,
    Size pageSize,
    double viewScale,
  ) {
    final NotePage page = document.pages[index];
    final bool current = index == _doc.pageIndex;
    final ui.Image? image = current ? _doc.pageImage : null;
    final ColorScheme colors = Theme.of(context).colorScheme;
    final ColorFilter? paperFilter = _paperDisplayFilter(
      page,
      colors.brightness,
    );
    final bool pageDark = _paperAppearanceCache[page.path]?.dark ?? false;
    final Color pageBackground = pageDark || paperFilter != null
        ? const Color(0xff202226)
        : Colors.white;
    final int previewWidth = math
        .max(
          _settings.pagePreviewWidth,
          pageSize.width * viewScale * MediaQuery.devicePixelRatioOf(context),
        )
        .round()
        .clamp(
          480,
          math.min(_memoryPolicy.previewPageWidth, _renderPolicy.previewWidth),
        );

    return RepaintBoundary(
      key: ValueKey<String>('page-${page.path}'),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: pageBackground,
          boxShadow: _renderPolicy.economical
              ? null
              : <BoxShadow>[
                  BoxShadow(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.black45
                        : Colors.black26,
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
        ),
        child: ClipRect(
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              // 预览始终保留在底层。当前页高清图卸载或切页时先露出已经
              // 解码的预览，不会在 RawImage 与 Image.file 之间出现空帧。
              _displayPaper(
                Image(
                  image: ResizeImage(
                    _paperFileImage(page),
                    width: current
                        ? math.min(previewWidth, _settings.pagePreviewWidth)
                        : previewWidth,
                    height: _renderPolicy.economical ? 1200 : null,
                    policy: ResizeImagePolicy.fit,
                  ),
                  key: ValueKey<String>('preview-${page.path}'),
                  fit: BoxFit.fill,
                  gaplessPlayback: true,
                  filterQuality: _renderPolicy.economical
                      ? FilterQuality.low
                      : FilterQuality.medium,
                  errorBuilder: (_, _, _) => Center(
                    child: Icon(
                      Icons.broken_image_outlined,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
                paperFilter,
              ),
              // 只在换页窗口里藏高清位图：那时 pageIndex 已经翻新，位图还是
              // 上一页的。导出、换纸这类后台任务（_doc.busy）不该动画面。
              if (image != null && !_doc.pageLoading)
                _displayPaper(
                  RawImage(
                    image: image,
                    fit: BoxFit.fill,
                    filterQuality: _renderPolicy.economical
                        ? FilterQuality.low
                        : FilterQuality.medium,
                  ),
                  paperFilter,
                ),
              if (current && image != null && !_doc.pageLoading)
                EmbeddedImageLayer(
                  cacheWidth: _renderPolicy.economical
                      ? _renderPolicy.pageWidth
                      : null,
                  cacheHeight: _renderPolicy.pageHeight,
                  filterQuality: _renderPolicy.economical
                      ? FilterQuality.low
                      : FilterQuality.high,
                  strokes: _ink.strokes,
                  repaint: _ink.committedRepaint,
                  resolvePath: (String asset) =>
                      _repository.resolveEmbeddedImagePath(document, asset),
                ),
              if (current && image != null && !_doc.pageLoading)
                InkLayer(
                  controller: _ink,
                  displayFilter: paperFilter,
                  paperDark: _templateInkTone(page),
                  claimImageTouch: _claimImageTouch,
                  tool: _toolState.tool,
                  lassoShape: LassoShape.values.firstWhere(
                    (v) => v.name == _settings.lassoShape,
                    orElse: () => LassoShape.freehand,
                  ),
                  color: _toolState.color,
                  width: _toolState.width,
                  penStyle: PenStyle.values.firstWhere(
                    (v) => v.name == _settings.penStyle,
                    orElse: () => PenStyle.fountain,
                  ),
                  shapeType: _toolState.shapeType,
                  eraserMode: _activeEraserMode,
                  eraserSize: _settings.eraserSize,
                  pressureEnabled: _settings.pressureEnabled,
                  pressureSensitivity: _settings.pressureSensitivity,
                  pressureCurve: PressureCurve.values.firstWhere(
                    (v) => v.name == _settings.pressureCurve,
                    orElse: () => PressureCurve.linear,
                  ),
                  stylusOnly: _settings.stylusOnly,
                  pressureForEvent: _nativePressure.forEvent,
                  selectionHitRadius: _settings.selectionHitRadius,
                  selectionPriority: _settings.selectionPriority,
                  primaryButtonTool: _actionForPhysicalButton(1).tool,
                  secondaryButtonTool: _actionForPhysicalButton(2).tool,
                  primaryButtonEraserMode: _eraserModeForButton(1),
                  secondaryButtonEraserMode: _eraserModeForButton(2),
                  laserMode: LaserMode.values.firstWhere(
                    (v) => v.name == _settings.laserMode,
                    orElse: () => LaserMode.trail,
                  ),
                  laserColor: Color(_settings.laserColor),
                  laserWidth: _settings.laserWidth,
                  laserFadeMs: _settings.laserFadeMs,
                  momentaryTool: _toolState.heldPenButton == 0
                      ? null
                      : _actionForPhysicalButton(_toolState.heldPenButton).tool,
                  enabled: !_doc.readOnly && !_doc.inkInputBlocked,
                  onDrawingChanged: (_) {},
                  onPenButtonChanged: (int button, bool pressed) =>
                      _handlePenButton(button, pressed, 'Flutter pointer'),
                  onTextRequested: _handleTextRequested,
                ),
              // 换页和后台任务都转圈，但只有换页会卸载位图和笔迹层。
              if (current && (_doc.pageLoading || _doc.busy))
                const Center(child: CircularProgressIndicator()),
              if (current && _inlineTextPoint != null)
                _inlineTextEditor(pageSize),
              if (current &&
                  _ink.hasSelection &&
                  !_ink.isTextRelocating &&
                  _inlineTextPoint == null)
                AnimatedBuilder(
                  animation: _viewport.zoomController,
                  builder: (BuildContext context, Widget? child) =>
                      _selectionActionsMenu(pageSize),
                ),
              if (_settings.showPageNumber)
                Positioned(
                  right: 10,
                  bottom: 8,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 3,
                      ),
                      child: Text(
                        '${index + 1}',
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                ),
              if (current &&
                  _settings.showPerformance &&
                  _doc.performance.isNotEmpty)
                Positioned(
                  top: 9,
                  right: 9,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.66),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        child: Text(
                          _doc.performance,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontFeatures: <FontFeature>[
                              FontFeature.tabularFigures(),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
