part of '../../app/fastink_app.dart';

extension _FastInkInputTools on _FastInkHomeState {
  /// 按当前文稿记录与零基页索引判断该页是否有书签。
  bool get _currentPageBookmarked =>
      _currentLibraryDocument?.bookmarkedPages.contains(_doc.pageIndex) ??
      false;

  /// 切换当前页书签并持久化资料库记录，页面笔迹不变。
  Future<void> _toggleCurrentPageBookmark() async {
    final NoteDocument? document = _doc.document;
    if (document == null) return;
    final List<LibraryDocument> documents = _library.documents.map((item) {
      if (item.id != document.id) return item;
      final List<int> bookmarks = List<int>.of(item.bookmarkedPages);
      if (!bookmarks.remove(_doc.pageIndex)) bookmarks.add(_doc.pageIndex);
      bookmarks.sort();
      return item.copyWith(bookmarkedPages: bookmarks);
    }).toList();
    _updateState(() {
      _library = LibraryState(documents: documents, folders: _library.folders);
    });
    await _saveLibrary();
  }

  /// 把工具栏上的滚轮输入用于横向访问隐藏工具，不让事件继续滚动画布。
  void _handleToolbarScroll(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !_toolbarScroll.hasClients) return;
    final double delta = event.scrollDelta.dx.abs() > 0
        ? event.scrollDelta.dx
        : event.scrollDelta.dy;
    final double destination = (_toolbarScroll.offset + delta).clamp(
      0.0,
      _toolbarScroll.position.maxScrollExtent,
    );
    _toolbarScroll.jumpTo(destination);
  }

  /// 把画布滚轮事件交给指针信号解析器，避免嵌套滚动同时处理同一事件。
  void _panZoomedPage(PointerSignalEvent event) {
    _ink.finishTextRelocation();
    if (event is! PointerScrollEvent) return;
    // 文档画布没有内部 Scrollable，收到滚轮后直接移动相机。交给全局
    // PointerSignalResolver 仲裁会让侧栏或其他组件先注册后吞掉事件。
    _handleDocumentWheel(event);
  }

  /// 区分 Ctrl+滚轮缩放与普通页面平移，保留鼠标滚轮约定，不套用触摸方向修正。
  void _handleDocumentWheel(PointerSignalEvent resolvedEvent) {
    if (resolvedEvent is! PointerScrollEvent) return;
    // 修饰键以当前硬件状态为准。缓存 KeyDown/KeyUp 会在窗口切换或系统
    // 手势打断时漏掉 KeyUp，随后普通滚轮会一直被误判为 Shift+滚轮。
    final DocumentWheelIntent intent = documentWheelIntent(
      controlPressed: HardwareKeyboard.instance.isControlPressed,
      shiftPressed: HardwareKeyboard.instance.isShiftPressed,
    );
    final PointerScrollEvent scroll = resolvedEvent;
    // 触控板发送连续高密度事件（Surface 触控板 dy 约 30–50 px/帧），
    // 鼠标滚轮是离散步进（~120 px/tick）。前者需要衰减才不会飞快。
    final bool isTrackpad = scroll.kind == PointerDeviceKind.trackpad;
    final Offset rawWheel = scroll.scrollDelta;
    final Offset wheel = isTrackpad ? rawWheel * 0.28 : rawWheel;
    final double primaryDelta = wheel.dy.abs() >= wheel.dx.abs()
        ? wheel.dy
        : wheel.dx;
    if (intent == DocumentWheelIntent.zoom) {
      final double current = _viewport.zoomController.value.getMaxScaleOnAxis();
      final double factor = math
          .pow(1.0018, -primaryDelta * _settings.wheelZoomSensitivity)
          .toDouble();
      _zoomAt(
        (current * factor).clamp(1.0, _settings.maximumZoom),
        scroll.localPosition,
      );
    } else if (intent == DocumentWheelIntent.horizontalPan) {
      final double horizontalDelta = wheel.dx.abs() > 0.01
          ? wheel.dx
          : wheel.dy;
      // 页面宽度没有超出视口时约束器会保持居中；Shift 不会抢走
      // 普通滚轮的纵向语义，也不会制造横向橡皮筋。
      _panDocumentCamera(horizontalDelta, horizontal: true);
    } else {
      _panDocumentCamera(primaryDelta, horizontal: false);
    }
  }

  /// 沿指定轴移动相机并应用文稿边界，delta 为逻辑像素增量。
  void _panDocumentCamera(double delta, {required bool horizontal}) {
    if (delta.abs() < 0.1 || _viewport.documentViewportLayout == null) return;
    _viewport.cameraNavigationTarget = null;
    _viewport.cameraNavigationTimer?.cancel();
    _viewport.zoomReturnController.stop();
    final Matrix4 requested = Matrix4.copy(_viewport.zoomController.value);
    requested[horizontal ? 12 : 13] -= delta;
    // 滚轮是确定性输入，不施加橡皮筋。硬约束缩放和位置，防止文档滚出屏幕。
    final DocumentViewportLayout? layout = _viewport.documentViewportLayout;
    _viewport.zoomController.value = layout == null
        ? _viewport.constrainZoom(requested, _settings.maximumZoom)
        : layout.constrainCamera(
            requested,
            maximumScale: _settings.maximumZoom,
          );
  }

  /// 围绕屏幕 focal 对应的文稿点建立新比例相机，并对超出文稿边界的平移进行约束。
  void _zoomAt(double scale, Offset focal) {
    _ink.finishTextRelocation();
    _viewport.cameraNavigationTarget = null;
    _viewport.cameraNavigationTimer?.cancel();
    // 缩放锚点取鼠标或手指下的页面坐标。
    final Offset scene = _viewport.zoomController.toScene(focal);
    final Matrix4 matrix = Matrix4.identity();
    matrix[0] = scale;
    matrix[5] = scale;
    matrix[12] = focal.dx - scene.dx * scale;
    matrix[13] = focal.dy - scene.dy * scale;
    // 锚点缩放只保证 focal 下的页面坐标不动，落点可能越出文档边界——
    // 缩小时尤其明显，页面会偏到一侧并露出空白。和其他相机操作一样
    // 交给布局做硬约束，位置和缩放一起收紧。
    final DocumentViewportLayout? layout = _viewport.documentViewportLayout;
    _viewport.zoomController.value = layout == null
        ? _viewport.constrainZoom(matrix, _settings.maximumZoom)
        : layout.constrainCamera(matrix, maximumScale: _settings.maximumZoom);
  }

  // ── 触控板手势 ──────────────────────────────────────────────────
  // Windows Precision Touchpad 发送 PointerPanZoom* 事件处理双指操作。
  // pan 是平移量，scale 是缩放因子，rotation 在 Windows 上一般为 0。

  /// 记录触控板累计缩放基准和初始相机，取消尚未完成的自动导航。
  void _trackpadGestureStart(PointerPanZoomStartEvent event) {
    _ink.finishTextRelocation();
    _viewport.cameraNavigationTarget = null;
    _viewport.cameraNavigationTimer?.cancel();
    _viewport.zoomReturnController.stop();
    _viewport.trackpadScaleOrigin = 1;
    _viewport.trackpadStartMatrix = Matrix4.copy(
      _viewport.zoomController.value,
    );
  }

  /// 应用触控板平移增量与累计比例，保持手势焦点稳定，不能把累计 scale 逐次相乘。
  void _trackpadGestureUpdate(PointerPanZoomUpdateEvent event) {
    final Matrix4? start = _viewport.trackpadStartMatrix;
    if (start == null) return;
    // panDelta 是本帧的平移增量（屏幕像素），scale 是累积缩放因子。
    final Offset panDelta = event.localPanDelta;
    final double scaleDelta = event.scale / _viewport.trackpadScaleOrigin;
    _viewport.trackpadScaleOrigin = event.scale;
    final double startScale = start.getMaxScaleOnAxis();
    final double newScale = (startScale * scaleDelta).clamp(
      1.0,
      _settings.maximumZoom,
    );
    // 缩放锚点取触控板双指中心（position 字段继承自 PointerEvent）。
    final Offset focal = event.localPosition;
    final Offset scene = _viewport.zoomController.toScene(focal);
    final Matrix4 next = Matrix4.identity();
    next[0] = newScale;
    next[5] = newScale;
    // PanZoom 的 panDelta 与手指位移同向；滚轮的 scrollDelta 才需要取反。
    // 两个轴都在屏幕坐标中叠加，缩放后不会再把手势位移乘一次比例。
    next[12] = focal.dx - scene.dx * newScale + panDelta.dx;
    next[13] = focal.dy - scene.dy * newScale + panDelta.dy;
    // 边缘弹性约束：触控板手势不使用硬约束，拖到边界有橡皮筋手感。
    _viewport.zoomController.value = _elasticConstrainZoom(next);
    _viewport.trackpadStartMatrix = Matrix4.copy(
      _viewport.zoomController.value,
    );
  }

  /// 清理触控板手势基准并将相机回收到合法边界。
  void _trackpadGestureEnd(PointerPanZoomEndEvent event) {
    _viewport.trackpadStartMatrix = null;
    // 松手后弹回边界（如果有越界）
    _springZoomToBounds();
  }

  /// 以纸面双击位置为焦点在默认适配与放大比例之间切换，浮层指针已由识别器排除。
  void _doubleTapZoom(TapDownDetails details) {
    if (details.kind != PointerDeviceKind.touch) return;
    final double current = _viewport.zoomController.value.getMaxScaleOnAxis();
    _zoomAt(current < 1.5 ? 2 : 1, details.localPosition);
  }

  /// 按设置的适配方式计算比例并定位当前页，不改变纸张实际大小。
  void _applyDefaultPageFit() {
    final DocumentViewportLayout? layout = _viewport.documentViewportLayout;
    if (layout == null || layout.pages.isEmpty) return;
    if (_settings.defaultPageFit == 'page') {
      _resetZoom();
      _moveViewportToPage(_doc.pageIndex, animate: false);
      return;
    }
    // 默认比例按侧栏右侧的可用宽度计算。
    final double scale = _defaultPageFitScale();
    // 从单位矩阵重新计算，避免“恢复默认比例”时保留此前的平移偏移。
    _resetZoom(notify: false);
    _zoomAt(scale, _canvasViewport.center(Offset.zero));
    _moveViewportToPage(_doc.pageIndex, animate: false);
  }

  /// 对越界相机施加弹性约束，为回正动画保留有限超出，不修改持久页面几何。
  Matrix4 _elasticConstrainZoom(Matrix4 value) {
    final DocumentViewportLayout? layout = _viewport.documentViewportLayout;
    return layout == null
        ? value
        : _settings.edgeBounceEnabled
        ? layout.elasticCamera(value, maximumScale: _settings.maximumZoom)
        : layout.constrainCamera(value, maximumScale: _settings.maximumZoom);
  }

  /// 根据释放速度和合法边界安排相机回正/惯性，新的用户手势可停止该动画。
  void _springZoomToBounds({Offset releaseVelocity = Offset.zero}) {
    final Matrix4 begin = Matrix4.copy(_viewport.zoomController.value);
    final DocumentViewportLayout? layout = _viewport.documentViewportLayout;
    final Matrix4 end = layout == null
        ? _viewport.constrainZoom(begin, _settings.maximumZoom)
        : layout.constrainCamera(begin, maximumScale: _settings.maximumZoom);
    bool changed = false;
    for (int index = 0; index < 16; index++) {
      if ((begin[index] - end[index]).abs() > 0.01) {
        changed = true;
        break;
      }
    }
    if (!changed) return;
    final double overflow = begin[13] - end[13];
    final bool movingOutward =
        overflow.abs() > 0.5 &&
        releaseVelocity.dy.abs() > 80 &&
        releaseVelocity.dy.sign == overflow.sign;
    if (movingOutward) {
      final Matrix4 peak = Matrix4.copy(begin);
      // 延续位移严格限制在 10px 内，只消除松手瞬间的速度折角，
      // 不会造成一次新的明显弹跳。
      peak[13] +=
          overflow.sign * (releaseVelocity.dy.abs() * 0.01).clamp(2.0, 10.0);
      _viewport.zoomReturnController.duration = const Duration(
        milliseconds: 225,
      );
      _viewport.zoomReturnAnimation =
          TweenSequence<Matrix4>(<TweenSequenceItem<Matrix4>>[
            TweenSequenceItem<Matrix4>(
              tween: Matrix4Tween(
                begin: begin,
                end: peak,
              ).chain(CurveTween(curve: Curves.easeOutSine)),
              weight: 14,
            ),
            TweenSequenceItem<Matrix4>(
              tween: Matrix4Tween(
                begin: peak,
                end: end,
              ).chain(CurveTween(curve: Curves.easeOutCubic)),
              weight: 86,
            ),
          ]).animate(_viewport.zoomReturnController);
    } else {
      final int milliseconds = (155 + overflow.abs() * 0.7).round().clamp(
        155,
        225,
      );
      _viewport.zoomReturnController.duration = Duration(
        milliseconds: milliseconds,
      );
      _viewport.zoomReturnAnimation = Matrix4Tween(begin: begin, end: end)
          .animate(
            CurvedAnimation(
              parent: _viewport.zoomReturnController,
              curve: Curves.easeOutCubic,
            ),
          );
    }
    _viewport.zoomReturnController.forward(from: 0);
  }
}
