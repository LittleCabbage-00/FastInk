part of '../../app/fastink_app.dart';

/// 汇总工具选择、笔侧键、触摸缩放和平移输入。
/// 原生 Windows 事件与 Flutter 指针事件都进入这里，最终共享同一套工具状态。
extension _FastInkDocumentInput on _FastInkHomeState {
  /// 切换当前工具并保留普通笔、荧光笔与文字各自样式；侧键临时橡皮来源不应覆盖持久默认值。
  void _selectTool(
    InkTool tool, {
    Color? color,
    double? width,
    bool partialEraserFromButton = false,
  }) {
    _updateState(() {
      _toolState.partialEraserFromButton = partialEraserFromButton;
      // 离开钢笔或荧光笔前先保存各自参数，来回切换不会互相覆盖颜色和粗细。
      if (_toolState.tool == InkTool.pen) {
        _settings.penColor = _toolState.color.toARGB32();
        _settings.penWidth = _toolState.width;
      } else if (_toolState.tool == InkTool.highlighter) {
        _toolState.highlighterColor = _toolState.color;
        _settings.highlighterWidth = _toolState.width;
      }
      _toolState.tool = tool;
      if (tool == InkTool.pen) {
        _toolState.lastInkTool = tool;
        _toolState.color = color ?? Color(_settings.penColor);
        _toolState.width = width ?? _settings.penWidth;
        _settings.penColor = _toolState.color.toARGB32();
        _settings.penWidth = _toolState.width;
      } else if (tool == InkTool.highlighter) {
        _toolState.lastInkTool = tool;
        _toolState.color = color ?? _toolState.highlighterColor;
        _toolState.width = width ?? _settings.highlighterWidth;
        _toolState.highlighterColor = _toolState.color;
        _settings.highlighterWidth = _toolState.width;
      } else if (tool == InkTool.text) {
        _toolState.color = color ?? _toolState.textColor;
      }
    });
  }

  /// 接收 Windows 通道压力或侧键消息，兼容旧启动器；未知方法忽略，具体工具切换走统一侧键入口。
  Future<Object?> _handleNativePenMethod(MethodCall call) async {
    if (call.method == 'pressure') {
      // 兼容旧启动器。Windows pointer 不是 Flutter 每次落笔的 pointer 编号。
      final Map<Object?, Object?> event =
          call.arguments! as Map<Object?, Object?>;
      _nativePressure.update((event['pressure']! as num).toDouble());
      return null;
    }
    if (call.method != 'button') return null;
    final Map<Object?, Object?> event =
        call.arguments! as Map<Object?, Object?>;
    final int button = (event['button']! as num).toInt();
    final bool pressed = event['pressed'] as bool? ?? true;
    final String source = event['source'] as String? ?? 'Windows';
    _handlePenButton(button, pressed, source);
    return null;
  }

  /// 处理物理侧键按下/松开，结合交换和瞬时模式选择临时工具；截图独占输入时不改底层文稿工具。
  void _handlePenButton(int button, bool pressed, String source) {
    if (button == 1 || button == 2) {
      final mask = button == 1 ? kPrimaryStylusButton : kSecondaryStylusButton;
      _capturePenButtons.value = pressed
          ? _capturePenButtons.value | mask
          : _capturePenButtons.value & ~mask;
    }
    // 截图界面打开时独占笔侧键，不切换底层文稿工具，
    // 也不修改文稿橡皮擦设置。
    if (_captureBusy) return;
    final bool firstButton = (button == 2) != _settings.swapPenButtons;
    final PenButtonAction action = _actionForPhysicalButton(button);
    final String name = firstButton
        ? tr('一键/${action.label}', 'Button 1/${action.label}')
        : tr('二键/${action.label}', 'Button 2/${action.label}');
    _updateState(() {
      // 瞬时模式只在按住期间覆盖当前工具；切换模式则在按下时永久选中。
      if (_settings.penButtonMomentary && pressed) {
        _toolState.heldPenButton = button;
      } else if (_toolState.heldPenButton == button) {
        _toolState.heldPenButton = 0;
      }
      _lastPenEvent = tr(
        '$name${pressed ? '按下' : '松开'} · $source',
        '$name ${pressed ? 'pressed' : 'released'} · $source',
      );
    });
    if (!_settings.penButtonMomentary && pressed && action.tool != null) {
      _selectTool(
        action.tool!,
        partialEraserFromButton: action == PenButtonAction.eraser,
      );
    }
  }

  /// 把物理键编号映射到逻辑动作，应用交换配置并对未知名称回退。
  PenButtonAction _actionForPhysicalButton(int button) {
    final bool firstButton = (button == 2) != _settings.swapPenButtons;
    return _decodePenButtonAction(
      firstButton ? _settings.penButtonOneAction : _settings.penButtonTwoAction,
      firstButton ? PenButtonAction.eraser : PenButtonAction.lasso,
    );
  }

  /// 读取持久配置中的橡皮模式，未知值回退整笔擦除。
  EraserMode get _configuredEraserMode => EraserMode.values.firstWhere(
    (mode) => mode.name == _settings.eraserMode,
    orElse: () => EraserMode.stroke,
  );

  /// 返回指定侧键临时覆盖的橡皮模式；该动作不是橡皮时返回 null。
  EraserMode? _eraserModeForButton(int button) {
    final action = _actionForPhysicalButton(button);
    if (action.tool != InkTool.eraser) return null;
    return action == PenButtonAction.eraser
        ? EraserMode.point
        : _configuredEraserMode;
  }

  /// 组合当前侧键覆盖与持久设置，得到实际擦除模式；临时覆盖不会写回默认值。
  EraserMode get _activeEraserMode {
    if (_toolState.heldPenButton != 0) {
      final mode = _eraserModeForButton(_toolState.heldPenButton);
      if (mode != null) return mode;
    }
    return _toolState.tool == InkTool.eraser &&
            _toolState.partialEraserFromButton
        ? EraserMode.point
        : _configuredEraserMode;
  }

  /// 停止现有导航动画并恢复相机基准；notify 控制是否立即刷新宿主界面，换文稿时还需取消旧可见页任务。
  void _resetZoom({bool notify = true}) {
    _ink.finishTextRelocation();
    _touchPoints.clear();
    _viewport.zoomReturnController.stop();
    _viewport.zoomController.value = Matrix4.identity();
    if (notify && mounted) _updateState(() {});
  }

  /// 按 delta 调整相机比例并限制在允许范围，围绕可见区域中心缩放。
  void _stepZoom(double delta) {
    final double current = _viewport.zoomController.value.getMaxScaleOnAxis();
    final double next = (current + delta).clamp(1.0, _settings.maximumZoom);
    if ((next - current).abs() < 0.001) return;
    final Offset focal = _canvasViewport.isEmpty
        ? Offset.zero
        : _canvasViewport.center(Offset.zero);
    _zoomAt(next, focal);
  }

  /// 只有页面导航尚未开始时，已选图片才能独占这根手指。
  bool _claimImageTouch(int pointer) {
    if (_touchPoints.isNotEmpty || _overlayPointers.isNotEmpty) return false;
    _viewport.zoomReturnController.stop();
    _overlayPointers.add(pointer);
    return true;
  }

  /// 记录参与导航的手指，排除正在拖动选区或操作浮层的指针。
  void _touchDown(PointerDownEvent event) {
    if (event.kind != PointerDeviceKind.touch || _overlayPointers.isNotEmpty) {
      return;
    }
    _viewport.cameraNavigationTarget = null;
    _viewport.cameraNavigationTimer?.cancel();
    _viewport.zoomReturnController.stop();
    if (_touchPoints.isEmpty) {
      _touchPanVelocity = Offset.zero;
      _touchPanLastMove = null;
    }
    _touchPoints[event.pointer] = event.localPosition;
    if (_touchPoints.length == 2) {
      // 第二根手指落下后记录缩放手势的场景焦点。
      // 后续缩放围绕该点计算，内容不会从指缝下滑走。
      _touchPanVelocity = Offset.zero;
      _touchPanLastMove = null;
      final List<Offset> points = _touchPoints.values.toList(growable: false);
      _pinchStartDistance = (points[0] - points[1]).distance;
      _pinchStartScale = _viewport.zoomController.value.getMaxScaleOnAxis();
      final Offset focal = (points[0] + points[1]) / 2;
      _pinchSceneFocal = _viewport.zoomController.toScene(focal);
      _updateState(() {});
    }
  }

  /// 按手指数执行单指平移或双指缩放，始终围绕起始焦点与累计比例计算，不生成持久笔迹。
  void _touchMove(PointerMoveEvent event) {
    if (event.kind != PointerDeviceKind.touch ||
        !_touchPoints.containsKey(event.pointer)) {
      return;
    }
    final Offset previous = _touchPoints[event.pointer]!;
    _viewport.zoomReturnController.stop();
    _touchPoints[event.pointer] = event.localPosition;
    if (_touchPoints.length >= 2) {
      final List<Offset> points = _touchPoints.values.toList(growable: false);
      final double distance = (points[0] - points[1]).distance;
      final Offset focal = (points[0] + points[1]) / 2;
      final double scale =
          (_pinchStartScale * distance / math.max(1, _pinchStartDistance))
              .clamp(1.0, _settings.maximumZoom);
      final Matrix4 matrix = Matrix4.identity();
      matrix[0] = scale;
      matrix[5] = scale;
      matrix[12] = focal.dx - _pinchSceneFocal.dx * scale;
      matrix[13] = focal.dy - _pinchSceneFocal.dy * scale;
      _viewport.zoomController.value = _elasticConstrainZoom(matrix);
    } else {
      final Offset delta = event.localPosition - previous;
      _recordTouchPanVelocity(delta, event.timeStamp);
      final Matrix4 matrix = Matrix4.copy(_viewport.zoomController.value);
      matrix[12] += delta.dx;
      matrix[13] += delta.dy;
      // 整个文稿共用一个相机：纵向位移自然跨页，横向在内容未超出
      // 视口时会被硬约束；只有真正的首末边缘保留弹性阻尼。
      _viewport.zoomController.value = _elasticConstrainZoom(matrix);
    }
  }

  /// 移除结束指针并根据剩余手指数更新手势状态；最后抬手时可启动受约束惯性。
  void _touchEnd(PointerEvent event) {
    _overlayPointers.remove(event.pointer);
    if (event.kind != PointerDeviceKind.touch ||
        !_touchPoints.containsKey(event.pointer)) {
      return;
    }
    _touchPoints.remove(event.pointer);
    if (_touchPoints.isEmpty) {
      final Matrix4 current = _viewport.zoomController.value;
      final DocumentViewportLayout? layout = _viewport.documentViewportLayout;
      final Matrix4 legal = layout == null
          ? _viewport.constrainZoom(current, _settings.maximumZoom)
          : layout.constrainCamera(
              current,
              maximumScale: _settings.maximumZoom,
            );
      final bool atElasticEdge = (current[13] - legal[13]).abs() > 0.5;
      // 首末页已经被拉出边界时不启动普通惯性。回弹会接管松手速度，
      // 先顺着快速外甩方向移动少量距离，再连续地收回合法位置。
      if (atElasticEdge) {
        _springZoomToBounds(releaseVelocity: _touchPanVelocity);
      } else if (!_coastTouchPan(event.timeStamp)) {
        _springZoomToBounds();
      }
    }
    _updateState(() {});
  }
}
