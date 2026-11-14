part of '../../app/fastink_app.dart';

/// 组装连续文稿视口和页面侧栏。
///
/// 页面不再装进 PageView 的独立槽位。所有页面先排进同一个文稿坐标系，
/// 相机矩阵统一负责缩放和平移，因此跨页时不会重置比例或发生页面重叠。
extension _FastInkDocumentView on _FastInkHomeState {
  /// 组装连续画布与页面侧栏；主相机与高频输入分离，侧栏只在显示时挂载，窄窗口使用覆盖布局。
  Widget _documentView(NoteDocument document) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final Widget pageFlow = Focus(
      focusNode: _canvasFocus,
      onKeyEvent: _handleCanvasKey,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerSignal: _panZoomedPage,
        onPointerPanZoomStart: _trackpadGestureStart,
        onPointerPanZoomUpdate: _trackpadGestureUpdate,
        onPointerPanZoomEnd: _trackpadGestureEnd,
        onPointerDown: (PointerDownEvent event) {
          _ink.finishTextRelocation();
          _canvasFocus.requestFocus();
          _touchDown(event);
        },
        onPointerMove: _touchMove,
        onPointerUp: _touchEnd,
        onPointerCancel: _touchEnd,
        child: RawGestureDetector(
          behavior: HitTestBehavior.translucent,
          gestures: {
            if (_settings.doubleTapZoomEnabled)
              _CanvasDoubleTapRecognizer:
                  GestureRecognizerFactoryWithHandlers<
                    _CanvasDoubleTapRecognizer
                  >(
                    _CanvasDoubleTapRecognizer.new,
                    (recognizer) => recognizer
                      ..ignoredPointers = _overlayPointers
                      ..onDoubleTapDown = _doubleTapZoom,
                  ),
          },
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final Size viewport = constraints.biggest;
              final DocumentViewportLayout layout = _layoutForDocument(
                document,
                viewport,
                // 文稿坐标系的基准不能随当前页横竖方向变化。每一页仍使用
                // 自己缓存的真实比例，尚未知晓的页面稳定按 A4 竖版占位。
                0.707,
              );
              _adoptDocumentViewportLayout(layout);
              return _VirtualDocumentViewport(
                layout: layout,
                camera: _viewport.zoomController,
                onCenteredPageChanged: (index) {
                  if (identical(_doc.document, document)) {
                    _scheduleVisiblePage(index);
                  }
                },
                pageBuilder:
                    (BuildContext context, int index, double viewScale) {
                      final Size pageSize = layout.pages[index].size;
                      return _documentPageWidget(
                        document,
                        index,
                        pageSize,
                        viewScale,
                      );
                    },
              );
            },
          ),
        ),
      ),
    );
    if (_immersiveMode) {
      return ColoredBox(color: colors.surfaceContainerHighest, child: pageFlow);
    }
    return ColoredBox(
      color: colors.surfaceContainerHighest,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final bool compact = constraints.maxWidth < 1000;
          final double sidebarWidth = compact
              ? math.min(_settings.sidebarWidth, constraints.maxWidth * 0.82)
              : _settings.sidebarWidth;
          // 宽度动画会逐帧改变画布约束，触发整本文稿重新布局和瓦片重建。
          // 一次切换到最终尺寸，保证长 PDF 的侧栏操作及时响应。
          final Widget sidebar = Container(
            width: _showPageSidebar ? sidebarWidth : 0,
            clipBehavior: Clip.hardEdge,
            decoration: BoxDecoration(
              color: colors.surfaceContainerLow,
              border: Border(
                right: BorderSide(
                  color: _showPageSidebar
                      ? colors.outlineVariant
                      : Colors.transparent,
                ),
              ),
              boxShadow: compact && _showPageSidebar
                  ? const <BoxShadow>[
                      BoxShadow(color: Colors.black38, blurRadius: 24),
                    ]
                  : null,
            ),
            child: _showPageSidebar
                ? _pageSidebar(document, sidebarWidth)
                : const SizedBox.shrink(),
          );
          return Stack(
            children: <Widget>[
              Positioned.fill(
                child: compact
                    ? pageFlow
                    : Row(
                        children: [
                          sidebar,
                          Expanded(child: pageFlow),
                        ],
                      ),
              ),
              if (compact && _showPageSidebar)
                Positioned.fill(
                  left: sidebarWidth,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _updateState(() => _showPageSidebar = false),
                    child: ColoredBox(
                      color: Colors.black.withValues(alpha: 0.18),
                    ),
                  ),
                ),
              if (compact)
                Positioned(left: 0, top: 0, bottom: 0, child: sidebar),
            ],
          );
        },
      ),
    );
  }
}

/// 工具浮层的点击无需等待画布双击超时，仍保留纸面上的手指双击缩放。
/// 子层 Listener 先标记指针，识别器在加入手势竞争前排除这些事件。
class _CanvasDoubleTapRecognizer extends DoubleTapGestureRecognizer {
  /// 只识别手指双击；鼠标与触笔不参与纸面双击缩放竞争。
  _CanvasDoubleTapRecognizer()
    : super(supportedDevices: const {PointerDeviceKind.touch});

  /// ignoredPointers：由页面浮层占用的指针编号集合，双击缩放识别器必须拒绝它们。
  Set<int> ignoredPointers = const {};

  /// 拒绝已被浮层登记的指针，再按默认双击识别条件判断，避免工具按钮等待纸面手势超时。
  @override
  bool isPointerAllowed(PointerDownEvent event) =>
      !ignoredPointers.contains(event.pointer) && super.isPointerAllowed(event);
}
