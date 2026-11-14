part of '../../app/fastink_app.dart';

/// 维护连续文稿布局与相机之间的关系。
extension _FastInkDocumentViewport on _FastInkHomeState {
  /// 按当前文稿、视口、几何修订和已知宽高比复用或创建连续布局；未知页面使用稳定参考比例。
  DocumentViewportLayout _layoutForDocument(
    NoteDocument document,
    Size viewport,
    double referenceRatio,
  ) {
    final DocumentViewportLayout? cached = _viewport.documentViewportLayout;
    final bool reusable =
        cached != null &&
        _viewport.documentLayoutId == document.id &&
        cached.viewport == viewport &&
        _viewport.documentLayoutRevision == _viewport.pageGeometryRevision &&
        (_viewport.documentLayoutReferenceRatio - referenceRatio).abs() <
            0.0001;
    if (reusable) return cached;

    // 只有页数、纸张比例或视口真正变化时才扫描页面。工具切换、落笔、
    // 保存状态等普通 setState 不再重复遍历数千页。
    final List<double> ratios = List<double>.generate(
      document.pages.length,
      (int index) =>
          _pageAspectRatioCache[document.pages[index].path] ?? referenceRatio,
      growable: false,
    );
    final DocumentViewportLayout next = DocumentViewportLayout.build(
      viewport: viewport,
      aspectRatios: ratios,
      referenceAspectRatio: referenceRatio,
    );
    _viewport.documentLayoutId = document.id;
    _viewport.documentLayoutRevision = _viewport.pageGeometryRevision;
    _viewport.documentLayoutReferenceRatio = referenceRatio;
    return next;
  }

  /// 缓存页面真实比例，比例变化时使文稿几何版本失效，后续布局再统一计算。
  void _rememberPageAspectRatio(String path, double ratio) {
    if (!ratio.isFinite || ratio <= 0) return;
    final double? previous = _pageAspectRatioCache[path];
    if (previous != null && (previous - ratio).abs() < 0.0001) return;
    _pageAspectRatioCache[path] = ratio;
    _viewport.pageGeometryRevision++;
  }

  /// 接纳新布局并处理待定位页/默认适配，更新相机边界，防止旧布局回调接管新文稿。
  void _adoptDocumentViewportLayout(DocumentViewportLayout next) {
    final DocumentViewportLayout? previous = _viewport.documentViewportLayout;
    _canvasViewport = next.viewport;
    _pageViewportRect = next.pages.isEmpty
        ? Rect.zero
        : next.pages[_doc.pageIndex.clamp(0, next.pages.length - 1)];
    if (previous?.signature == next.signature) return;

    final Matrix4 before = Matrix4.copy(_viewport.zoomController.value);
    final double? anchorTop = previous == null || previous.pages.isEmpty
        ? null
        : previous
              .screenPageRect(
                _doc.pageIndex.clamp(0, previous.pages.length - 1),
                before,
              )
              .top;
    _viewport.documentViewportLayout = next;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !identical(_viewport.documentViewportLayout, next)) {
        return;
      }
      final int? targetPage = _viewport.pendingViewportPage;
      if (targetPage != null && next.pages.isNotEmpty) {
        _viewport.pendingViewportPage = null;
        _moveViewportToPage(targetPage, animate: false);
        if (_applyDefaultFitOnNextLayout) {
          _applyDefaultFitOnNextLayout = false;
          _applyDefaultPageFit();
        }
        return;
      }

      final Matrix4 adjusted = Matrix4.copy(before);
      if (anchorTop != null && next.pages.isNotEmpty) {
        final int index = _doc.pageIndex.clamp(0, next.pages.length - 1);
        final double newTop = next.screenPageRect(index, adjusted).top;
        adjusted[13] += anchorTop - newTop;
      }
      _viewport.zoomController.value = next.constrainCamera(
        adjusted,
        maximumScale: _settings.maximumZoom,
      );
    });
  }

  /// 相机中心变化后防抖确认活动页，连续滚动只为最终附近页装载高清和笔迹。
  void _scheduleVisiblePage(int index) {
    // 布局还没建立时收到回调，说明它来自上一份文稿那些仍在树上的旧组件
    // （切文稿时 documentViewportLayout 会先置空）。这时算出来的"中心页"
    // 属于旧布局，采纳它会跳回错误的页。
    if (_viewport.documentViewportLayout == null) return;
    if (_viewport.cameraNavigationTarget != null) return;
    if (index == _doc.pageIndex) {
      // 适应页面或重置时，可能在一帧内经过第 0 页再返回目标页；
      // 取消中间回调，避免错误地跳回第一页。
      _viewport.visiblePageTimer?.cancel();
      _viewport.pendingVisiblePage = null;
      return;
    }
    if (index == _viewport.pendingVisiblePage) {
      return;
    }
    _viewport.pendingVisiblePage = index;
    _viewport.visiblePageTimer?.cancel();
    // 连续滚动中只加载用户真正停留的页面，避免快速扫过数十页时
    // 反复解码高清图和读写笔迹。
    _viewport.visiblePageTimer = Timer(const Duration(milliseconds: 72), () {
      final int? target = _viewport.pendingVisiblePage;
      _viewport.pendingVisiblePage = null;
      if (!mounted || target == null || target == _doc.pageIndex) return;
      unawaited(_loadPage(target));
    });
  }

  /// 把目标零基页约束到现有范围并计算目标相机，animate 控制平滑导航，手势接管时需取消待执行目标。
  void _moveViewportToPage(int requestedIndex, {required bool animate}) {
    final DocumentViewportLayout? layout = _viewport.documentViewportLayout;
    final NoteDocument? document = _doc.document;
    if (layout == null || document == null || layout.pages.isEmpty) {
      _viewport.pendingViewportPage = requestedIndex;
      return;
    }
    final int index = requestedIndex.clamp(0, document.pages.length - 1);
    final Matrix4 target = layout.cameraForPage(
      _viewport.zoomController.value,
      index,
      maximumScale: _settings.maximumZoom,
    );
    if (!animate ||
        !_settings.pageAnimationsEnabled ||
        _renderPolicy.economical) {
      _viewport.cameraNavigationTarget = null;
      _viewport.cameraNavigationTimer?.cancel();
      _viewport.zoomController.value = target;
      return;
    }
    _viewport.cameraNavigationTarget = index;
    _viewport.cameraNavigationTimer?.cancel();
    _viewport.zoomReturnAnimation =
        Matrix4Tween(
          begin: Matrix4.copy(_viewport.zoomController.value),
          end: target,
        ).animate(
          CurvedAnimation(
            parent: _viewport.zoomReturnController,
            curve: Curves.easeOutCubic,
          ),
        );
    _viewport.zoomReturnController.forward(from: 0);
    _viewport.cameraNavigationTimer = Timer(
      const Duration(milliseconds: 300),
      () {
        if (!mounted || _viewport.cameraNavigationTarget != index) return;
        _viewport.cameraNavigationTarget = null;
      },
    );
  }
}
