part of 'ink_canvas.dart';

// ---------------------------------------------------------------------------
// 墨迹层的指针输入状态机。
//
// ## 为什么需要状态机？
//
// 一次完整的绘图手势涉及多个阶段：落笔(down) → 移动(move) → 抬笔(up)。
// 每个阶段的行为取决于当前激活的工具（钢笔/橡皮/套索/激光/形状）。
// 如果用简单的 if/else 处理，分支会爆炸式增长且难以维护。
// 状态机将"当前处于哪个分支"编码为一组布尔标志（_erasing, _lassoing 等），
// _down 进入分支，_move 按分支路由，_up 结束分支并清理状态。
//
// ## 单指针模型
//
// _activePointer 锁定第一个落下的指针，忽略后续多点触控。
// 这简化了状态管理（不需要处理双指缩放与绘画的竞争），也避免了
// 手掌误触问题——只有笔/鼠标能触发绘画。
//
// ## 侧键中途切换
//
// Windows 原生手写笔的侧键信号（kPrimaryStylusButton / kSecondaryStylusButton）
// 有时会晚于落笔事件到达。例如：用户按下侧键的同时笔尖碰屏幕，
// 但系统先报笔尖 down 事件，侧键状态在后续 move 事件中才体现。
//
// 处理方式：didUpdateWidget 检测到 momentaryTool 变化时，调用
// _adoptMomentaryTool——先安全结束当前分支（finishLasso / finishEraseGesture 等），
// 再从最近采样点（_lastInkPoint）启动新工具。这样不会丢失采样点，
// 也不会产生悬挂的未完成笔画。
// ---------------------------------------------------------------------------

/// 工具条上的笔宽是"屏幕上的像素"，落笔时按当前页面尺寸换算成归一化粗细。
///
/// [size] 是页面布局尺寸（相机缩放作用在页面外层，不影响这里），所以
/// 同一支笔在任何缩放下存进笔迹的都是同一个相对纸面的粗细，导出也一致。
double _normalizedInkWidth(double pixels, Size size) {
  final double reference = math.sqrt(size.width * size.height);
  if (!reference.isFinite || reference <= 0) return pixels;
  return pixels / reference;
}

/// 把一段指针手势路由给唯一的绘图工具。
///
/// Windows 原生侧键信号有时晚于落笔事件，因此本状态机会在手势中途
/// 安全结束原分支，再从最近采样点切换到橡皮或套索。
class _InkLayerState extends State<InkLayer> {
  /// _straightenDelay：长按拉直的等待时间，700 毫秒内抖动不应直接认作停笔。
  static const Duration _straightenDelay = Duration(milliseconds: 700);

  /// _straightenJitterRadius：长按拉直允许的屏幕逻辑像素抖动范围。
  static const double _straightenJitterRadius = 4;

  // ---- 状态机核心变量 ----
  // _activePointer：锁定当前手势的指针 ID，忽略其他指针。
  // 以下布尔标志互斥地表示当前手势处于哪个分支。
  // 切换工具时先结束当前分支再进入新分支（见 _adoptMomentaryTool）。
  /// _activePointer：当前笔迹手势拥有的指针编号，拒绝其他指针接管该笔画。
  int? _activePointer;

  /// _erasing：本次活动手势是否在擦除，用于合并一次手势的历史记录。
  bool _erasing = false;

  /// _lassoing：本次活动手势是否正在采集套索。
  bool _lassoing = false;

  /// _lassoStart：矩形套索的起始归一化点位。
  InkPoint? _lassoStart;

  /// _shaping：本次活动手势是否正在构造几何形状。
  bool _shaping = false;

  /// _lasering：当前是否仍在输入激光样本，决定尾迹计时器何时停止。
  bool _lasering = false;

  /// _laserSamples：当前激光尾迹点列，按淡出时限清理，不属于持久笔迹。
  final List<_LaserSample> _laserSamples = <_LaserSample>[];

  /// _laserTicker：激光尾迹的周期刷新任务，没有尾迹且已停笔时主动取消。
  Timer? _laserTicker;

  /// _laserNowMs：最近一次激光刷新时刻，单位 Unix 毫秒。
  int _laserNowMs = 0;

  /// _selectionTransform：当前拖动是平移、缩放还是旋转；没有变换时为 null。
  SelectionTransform? _selectionTransform;

  /// _lastButtons：最近观察到的原始按钮位掩码，用于识别按下/松开边沿。
  int _lastButtons = 0;

  /// _gestureTool：手势开始时确定的工具，避免按键状态在半笔中改变语义。
  InkTool? _gestureTool;

  /// _lastInkPoint：当前手势最近采样的页面点，用于结束或刷新未提交输入。
  InkPoint? _lastInkPoint;

  /// _lastCanvasSize：最近输入事件对应的页面逻辑尺寸。
  Size? _lastCanvasSize;

  /// _cursorPosition：橡皮悬停位置通知器，仅重绘光标而不重建整页。
  final ValueNotifier<Offset?> _cursorPosition = ValueNotifier(null);

  /// _transformFrame：尚未执行的帧回调编号，合并高频对象拖动事件。
  int? _transformFrame;

  /// _pendingTransform：等待下一显示帧应用的最新变换点和页面尺寸。
  (InkPoint, Size)? _pendingTransform;

  /// 在下一显示帧应用已合并的最新选区变换，避免一个屏幕帧处理多次昂贵几何修改。
  void _flushTransform() {
    if (_transformFrame != null) {
      WidgetsBinding.instance.cancelFrameCallbackWithId(_transformFrame!);
      _transformFrame = null;
    }
    final pending = _pendingTransform;
    _pendingTransform = null;
    if (pending != null) {
      widget.controller.updateSelectionTransform(pending.$1, pending.$2);
    }
  }

  /// 记录最新变换点并安排至多一个帧回调；输入点采样不因此降频。
  void _queueTransform(InkPoint point, Size size) {
    _pendingTransform = (point, size);
    _transformFrame ??= WidgetsBinding.instance.scheduleFrameCallback((_) {
      _transformFrame = null;
      _flushTransform();
    });
  }

  /// _straightenTimer：停笔拉直的延迟任务，移动、抬笔或换工具时取消。
  Timer? _straightenTimer;

  /// _straightenAnchor：拉直等待开始时的点位，用于检测是否超出抖动范围。
  InkPoint? _straightenAnchor;

  /// _straightened：当前笔画是否已完成长按拉直，防止同一笔重复触发。
  bool _straightened = false;

  /// _activePointerKind：当前手势的输入设备种类，鼠标与触笔压力状态不能混用。
  PointerDeviceKind? _activePointerKind;

  /// 取消停笔拉直等待并清理锚点标志，抬笔或工具变化后不能处理旧笔画。
  void _cancelStraighten() {
    _straightenTimer?.cancel();
    _straightenTimer = null;
    _straightenAnchor = null;
    _straightened = false;
  }

  /// 仅在普通笔停留在抖动范围内时启动延迟拉直，移动超范围会重置计时。
  void _trackStraightenHold(InkPoint point, Size size) {
    if (_activePointerKind != PointerDeviceKind.stylus ||
        _gestureTool != InkTool.pen ||
        _straightened) {
      return;
    }
    final InkPoint? anchor = _straightenAnchor;
    final double distance = anchor == null
        ? double.infinity
        : math.sqrt(
            math.pow((point.x - anchor.x) * size.width, 2) +
                math.pow((point.y - anchor.y) * size.height, 2),
          );
    // 手仍在移动时不断更新停留点；4px 内的笔尖抖动不重置计时。
    if (distance <= _straightenJitterRadius &&
        _straightenTimer?.isActive == true) {
      return;
    }
    _straightenAnchor = point;
    _straightenTimer?.cancel();
    _straightenTimer = Timer(_straightenDelay, () {
      if (!mounted || _activePointer == null || _gestureTool != InkTool.pen) {
        return;
      }
      if (widget.controller.straightenActiveStroke(size)) {
        _straightened = true;
      }
    });
  }

  /// 有激光内容时启动约 30 Hz 淡出刷新，无尾迹且停笔后取消，避免空转计时器。
  void _ensureLaserTicker() {
    if (_laserTicker?.isActive == true) return;
    // 指针移动即时更新，激光尾迹淡出按 30 Hz 刷新。
    _laserTicker = Timer.periodic(const Duration(milliseconds: 33), (_) {
      if (!mounted) return;
      final int now = DateTime.now().millisecondsSinceEpoch;
      final int oldest = now - widget.laserFadeMs;
      _laserSamples.removeWhere(
        (_LaserSample sample) => sample.createdAtMs < oldest,
      );
      if (_laserSamples.isEmpty && !_lasering) {
        _laserTicker?.cancel();
      }
      setState(() => _laserNowMs = now);
    });
  }

  /// 追加激光显示样本，点模式替换当前位置，尾迹模式按最小距离采样且分开多段手势。
  void _appendLaser(InkPoint point, Size size, {bool start = false}) {
    final Offset position = Offset(point.x * size.width, point.y * size.height);
    final int now = DateTime.now().millisecondsSinceEpoch;
    if (widget.laserMode == LaserMode.dot) {
      _laserSamples
        ..clear()
        ..add(_LaserSample(position, now));
    } else {
      if (start) {
        // 新笔画只标记边界，旧尾迹留待淡出，避免两段误连。
        _laserSamples.add(_LaserSample(position, now, startsStroke: true));
      } else if (_laserSamples.isEmpty ||
          (_laserSamples.last.position - position).distance >= 1.25) {
        _laserSamples.add(_LaserSample(position, now));
      }
      if (_laserSamples.length > 600) {
        _laserSamples.removeRange(0, _laserSamples.length - 600);
      }
    }
    _laserNowMs = now;
    _ensureLaserTicker();
    if (mounted) setState(() {});
  }

  /// 结束激光输入，已出现的尾迹仍可按时限淡出，不提交为持久笔画。
  void _endLaser() {
    _lasering = false;
    if (widget.laserMode == LaserMode.dot) {
      _laserSamples.clear();
      _laserTicker?.cancel();
      if (mounted) setState(() {});
    } else {
      _ensureLaserTicker();
    }
  }

  /// 工具、输入模式或控制器变化时结束不兼容的活动手势并重新关联通知，旧指针不能继续编辑新页。
  @override
  void didUpdateWidget(covariant InkLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateCursor(_cursorPosition.value);
    final InkTool target = widget.momentaryTool ?? widget.tool;
    if (_activePointer != null &&
        _activePointerKind != PointerDeviceKind.touch &&
        widget.momentaryTool != oldWidget.momentaryTool &&
        target != _gestureTool) {
      _adoptMomentaryTool(target);
    }
  }

  /// 按输入设备与仅笔模式判断该指针能否参与书写，手指导航不冒充触笔。
  bool _isInkPointer(PointerEvent event) =>
      event.kind == PointerDeviceKind.mouse ||
      event.kind == PointerDeviceKind.stylus ||
      event.kind == PointerDeviceKind.invertedStylus;

  /// 根据当前侧键覆盖和工具设置解析本次事件实际使用的橡皮模式。
  EraserMode _eraserMode(PointerEvent event) {
    if (event.buttons & kSecondaryStylusButton != 0 &&
        widget.secondaryButtonTool == InkTool.eraser) {
      return widget.secondaryButtonEraserMode ?? widget.eraserMode;
    }
    if (event.buttons & kPrimaryStylusButton != 0 &&
        widget.primaryButtonTool == InkTool.eraser) {
      return widget.primaryButtonEraserMode ?? widget.eraserMode;
    }
    return widget.eraserMode;
  }

  /// 把输入事件的局部逻辑像素坐标换成页面归一化点，并读取适合该设备的压力。
  InkPoint _point(PointerEvent event, Size size) {
    final normalizedPressure = effectivePenPressure(
      event,
      enabled: widget.pressureEnabled,
      curve: widget.pressureCurve,
      sensitivity: widget.pressureSensitivity,
      fallback: widget.pressureForEvent,
    );
    return InkPoint(
      (event.localPosition.dx / size.width).clamp(0.0, 1.0),
      (event.localPosition.dy / size.height).clamp(0.0, 1.0),
      normalizedPressure,
    );
  }

  /// 追踪侧键状态变化并向上传递事件。
  ///
  /// 每个 PointerEvent 都携带一个 buttons 位掩码，表示事件瞬间哪些按钮被按下。
  /// 通过与上一次的 _lastButtons 对比，可以检测到按下/释放的边沿变化。
  ///
  /// 关键细节：侧键状态嵌入在 move 事件中，不一定有独立的 down/up 事件。
  /// 所以 _handleButtons 必须在每次 move 中调用，而不是只在 down/up 中调用。
  void _handleButtons(PointerEvent event) {
    final bool primary = event.buttons & kPrimaryStylusButton != 0;
    final bool secondary = event.buttons & kSecondaryStylusButton != 0;
    final bool previousPrimary = _lastButtons & kPrimaryStylusButton != 0;
    final bool previousSecondary = _lastButtons & kSecondaryStylusButton != 0;
    if (primary != previousPrimary) widget.onPenButtonChanged(1, primary);
    if (secondary != previousSecondary) widget.onPenButtonChanged(2, secondary);
    _lastButtons = event.buttons;
  }

  /// 确定当前事件的有效工具——三级优先级。
  ///
  /// 1. momentaryTool：外部强制指定的临时工具（如软件切换），最高优先。
  /// 2. 侧键工具：如果侧键被按下，使用该侧键绑定的工具。
  ///    二级键优先于一级键（二级通常是橡皮擦，用户期望它更"强"）。
  /// 3. 工具栏工具：没有侧键时的默认工具。
  InkTool _effectiveTool(PointerEvent event) =>
      widget.momentaryTool ??
      (event.buttons & kSecondaryStylusButton != 0
          ? (widget.secondaryButtonTool ?? widget.tool)
          : event.buttons & kPrimaryStylusButton != 0
          ? (widget.primaryButtonTool ?? widget.tool)
          : widget.tool);

  /// 中途切换到新工具——安全结束当前分支，再从最近采样点启动新分支。
  ///
  /// 典型场景：
  /// 1. 用户按住侧键（橡皮）落笔，但系统先报了笔尖 down（钢笔），
  ///    然后在后续 move 中才体现侧键状态 → didUpdateWidget 触发此方法。
  /// 2. 用户在绘画过程中通过软件切换工具（如点击橡皮按钮）。
  ///
  /// 处理步骤：
  /// - 结束当前分支（finishLasso / finishEraseGesture / cancel 等）
  /// - 清除所有布尔标志
  /// - 从 _lastInkPoint（最后一个采样点）启动新工具
  /// - 如果侧键晚到时已经产生了钢笔点，cancel() 会撤销它们，
  ///   避免用户意图是橡皮却留下了钢笔痕迹。
  void _adoptMomentaryTool(InkTool tool) {
    final InkPoint? point = _lastInkPoint;
    final Size? size = _lastCanvasSize;
    if (point == null || size == null) return;

    // 侧键信号可能晚于落笔；结束原分支后，从最近落点启动目标工具。
    if (_lasering) {
      _endLaser();
    } else if (_lassoing) {
      widget.controller.finishLasso();
    } else if (_selectionTransform != null) {
      _flushTransform();
      widget.controller.finishSelectionTransform();
    } else if (_erasing) {
      widget.controller.finishEraseGesture();
    } else if (!_erasing) {
      // 侧键晚到时撤销已生成的钢笔点，再切换手势。
      widget.controller.cancel();
    }
    _erasing = false;
    _lassoing = false;
    _updateCursor(_cursorPosition.value);
    _lassoStart = null;
    _shaping = false;
    _lasering = false;
    _selectionTransform = null;
    _cancelStraighten();
    _gestureTool = tool;

    if (tool == InkTool.eraser) {
      _erasing = true;
      widget.controller.beginHistoryTransaction(deferSnapshot: true);
      widget.controller.eraseAt(
        point,
        size,
        widget.eraserSize,
        widget.eraserMode,
      );
    } else if (tool == InkTool.lasso) {
      _selectionTransform = widget.controller.beginSelectionTransform(
        point,
        size,
        hitRadius: widget.selectionHitRadius,
      );
      if (_selectionTransform == null) {
        _lassoing = true;
        _lassoStart = point;
        widget.controller.beginLasso(point);
      }
    } else if (tool == InkTool.laser) {
      _lasering = true;
      _appendLaser(point, size, start: true);
    } else if (tool == InkTool.shape) {
      _shaping = true;
      widget.controller.beginShape(
        point,
        widget.color,
        _normalizedInkWidth(widget.width, size),
        widget.shapeType,
        canvasSize: size,
      );
    } else if (tool != InkTool.text) {
      widget.controller.begin(
        point,
        widget.color,
        _normalizedInkWidth(widget.width, size),
        tool == InkTool.highlighter ? StrokeKind.highlighter : StrokeKind.pen,
        widget.penStyle,
      );
    }
  }

  /// 仅更新悬停位置通知器，避免橡皮光标移动时重建整页界面。
  void _updateCursor(Offset? position) {
    // 悬停只更新橡皮范围圈；钢笔使用系统光标。
    final bool showEraserCursor =
        _erasing ||
        widget.tool == InkTool.eraser ||
        widget.momentaryTool == InkTool.eraser;
    final Offset? next = showEraserCursor ? position : null;
    if (_cursorPosition.value == next || !mounted) return;
    _cursorPosition.value = next;
  }

  /// 开始并归属一个画布指针手势，按有效工具分派书写、擦除、套索、形状、激光或文字。
  void _down(PointerDownEvent event, Size size) {
    if (event.kind == PointerDeviceKind.touch) {
      _startImageTouch(event, size);
      return;
    }
    if (!widget.enabled || !_isInkPointer(event)) {
      return;
    }
    widget.controller.finishTextRelocation();
    // 先处理按键再决定工具，确保按住侧键落笔时首个点就进入正确分支。
    _handleButtons(event);
    if (_activePointer != null) return;
    _activePointer = event.pointer;
    _activePointerKind = event.kind;
    _cancelStraighten();
    widget.onDrawingChanged(true);
    final InkPoint point = _point(event, size);
    _lastInkPoint = point;
    _lastCanvasSize = size;
    _updateCursor(event.localPosition);
    final InkTool effectiveTool = _effectiveTool(event);
    _gestureTool = effectiveTool;

    // 选区控制柄优先于画笔命中，防止拖动选区时误落笔。
    // selectionPriority 为 true 时，只要存在选区，落笔先尝试"抓住"选区。
    // 只有当手指不在控制柄/选区内部时，才继续往下走到画笔逻辑。
    if (widget.selectionPriority &&
        effectiveTool != InkTool.lasso &&
        effectiveTool != InkTool.text &&
        widget.controller.hasSelection) {
      _selectionTransform = widget.controller.beginSelectionTransform(
        point,
        size,
        hitRadius: widget.selectionHitRadius,
        includeInterior: true,
      );
      if (_selectionTransform != null) return;
    }
    if (widget.stylusOnly &&
        event.kind == PointerDeviceKind.mouse &&
        effectiveTool != InkTool.lasso &&
        effectiveTool != InkTool.text) {
      _activePointer = null;
      widget.onDrawingChanged(false);
      return;
    }
    if (effectiveTool == InkTool.lasso) {
      _selectionTransform = widget.controller.beginSelectionTransform(
        point,
        size,
        hitRadius: widget.selectionHitRadius,
      );
      if (_selectionTransform == null) {
        final InkStroke? object = widget.controller.objectStrokeAt(point);
        if (object != null) {
          widget.controller.selectOnly(object);
          if (object.kind == StrokeKind.image) {
            _selectionTransform = widget.controller.beginSelectionTransform(
              point,
              size,
              hitRadius: 0,
            );
          }
          return;
        }
      }
      if (_selectionTransform == null) {
        _lassoing = true;
        _lassoStart = point;
        widget.controller.beginLasso(point);
      }
      return;
    }
    if (effectiveTool == InkTool.laser) {
      _lasering = true;
      _appendLaser(point, size, start: true);
      return;
    }
    if (effectiveTool == InkTool.text) {
      widget.onTextRequested(point, size);
      return;
    }
    // Wacom 等手写笔翻转笔身时，系统上报 invertedStylus 设备类型，
    // 这等同于物理橡皮擦，不需要用户手动切换工具。
    _erasing =
        effectiveTool == InkTool.eraser ||
        event.kind == PointerDeviceKind.invertedStylus;
    if (_erasing) {
      // 延迟历史快照，只有实际擦到内容时才复制；空擦不会制造撤销记录。
      // deferSnapshot: true 让控制器记住事务起点，如果最终没有擦到任何笔画，
      // 就不会产生撤销记录，避免空操作污染撤销栈。
      widget.controller.beginHistoryTransaction(deferSnapshot: true);
      widget.controller.eraseAt(
        point,
        size,
        widget.eraserSize,
        _eraserMode(event),
      );
    } else if (effectiveTool == InkTool.shape) {
      _shaping = true;
      widget.controller.beginShape(
        point,
        widget.color,
        _normalizedInkWidth(widget.width, size),
        widget.shapeType,
        canvasSize: size,
      );
    } else {
      widget.controller.begin(
        point,
        widget.color,
        _normalizedInkWidth(widget.width, size),
        effectiveTool == InkTool.highlighter
            ? StrokeKind.highlighter
            : StrokeKind.pen,
        widget.penStyle,
      );
      if (effectiveTool == InkTool.pen) _trackStraightenHold(point, size);
    }
  }

  /// 已选图片可用单指抓住；空白处或宿主已在导航时，仍交给页面相机。
  void _startImageTouch(PointerDownEvent event, Size size) {
    final claim = widget.claimImageTouch;
    final controller = widget.controller;
    if (!widget.enabled ||
        widget.tool != InkTool.lasso ||
        _activePointer != null ||
        claim == null ||
        controller.selectedStrokes.length != 1 ||
        controller.selectedStrokes.single.kind != StrokeKind.image) {
      return;
    }
    final point = _point(event, size);
    final transform = controller.beginSelectionTransform(
      point,
      size,
      hitRadius: widget.selectionHitRadius,
    );
    if (transform == null) return;
    if (!claim(event.pointer)) {
      controller.finishSelectionTransform();
      return;
    }
    _selectionTransform = transform;
    _activePointer = event.pointer;
    _activePointerKind = event.kind;
    _gestureTool = InkTool.lasso;
    widget.onDrawingChanged(true);
  }

  /// 只处理当前手势拥有的指针，更新活动采样或合并对象变换，不接管其他输入设备的手势。
  void _move(PointerMoveEvent event, Size size) {
    _handleButtons(event);
    if (event.pointer != _activePointer) return;
    final InkPoint point = _point(event, size);
    _lastInkPoint = point;
    _lastCanvasSize = size;
    _updateCursor(event.localPosition);
    if (_lassoing) {
      if (widget.lassoShape == LassoShape.rectangle && _lassoStart != null) {
        widget.controller.setRectangleLasso(_lassoStart!, point);
      } else {
        widget.controller.appendLasso(point);
      }
    } else if (_selectionTransform != null) {
      _queueTransform(point, size);
    } else if (_erasing) {
      widget.controller.eraseAt(
        point,
        size,
        widget.eraserSize,
        _eraserMode(event),
      );
    } else if (_shaping) {
      widget.controller.updateShape(point, widget.shapeType);
    } else if (_lasering) {
      _appendLaser(point, size);
    } else {
      if (_straightened) {
        widget.controller.updateStraightenedStroke(point);
      } else {
        widget.controller.append(point);
        _trackStraightenHold(point, size);
      }
    }
  }

  /// 结束当前指针手势，提交或取消对应内容事务并清理临时工具、计时和输入归属。
  void _up(PointerEvent event) {
    _handleButtons(event);
    if (event.pointer != _activePointer) return;
    _straightenTimer?.cancel();
    if (_lassoing) {
      widget.controller.finishLasso();
    } else if (_selectionTransform != null) {
      _flushTransform();
      widget.controller.finishSelectionTransform();
    } else if (_shaping) {
      widget.controller.finish();
    } else if (_lasering) {
      _endLaser();
    } else if (!_erasing) {
      widget.controller.finish();
    }
    // 结束手势后统一提交历史、保存通知和工具栏刷新。
    if (_erasing) widget.controller.finishEraseGesture();
    _activePointer = null;
    _activePointerKind = null;
    _lastInkPoint = null;
    _lastCanvasSize = null;
    _erasing = false;
    _lassoing = false;
    _updateCursor(_cursorPosition.value);
    _lassoStart = null;
    _shaping = false;
    _lasering = false;
    _selectionTransform = null;
    _gestureTool = null;
    _cancelStraighten();
    widget.onDrawingChanged(false);
  }

  /// 将指针监听与已提交、活动、选区、激光、橡皮光标分层组装；各高频显示信号使用独立重绘边界。
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final Size size = constraints.biggest;
        return MouseRegion(
          onHover: (PointerHoverEvent event) {
            _handleButtons(event);
            _updateCursor(event.localPosition);
          },
          onExit: (_) {
            _lastButtons = 0;
            _updateCursor(null);
          },
          cursor: (widget.momentaryTool ?? widget.tool) == InkTool.eraser
              ? SystemMouseCursors.cell
              : (widget.momentaryTool ?? widget.tool) == InkTool.lasso
              ? SystemMouseCursors.click
              : SystemMouseCursors.precise,
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (PointerDownEvent event) => _down(event, size),
            onPointerMove: (PointerMoveEvent event) => _move(event, size),
            onPointerUp: _up,
            onPointerCancel: (PointerCancelEvent event) {
              if (event.pointer == _activePointer) {
                widget.controller.cancel();
                if (_erasing) {
                  widget.controller.finishEraseGesture();
                } else {
                  widget.controller.finishHistoryTransaction(commit: false);
                }
              }
              _up(event);
            },
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                // 已提交笔迹、活动笔迹和选区分层重绘。落笔移动时不必重画
                // 整页旧笔迹，选区菜单变化也不会污染页面位图缓存。
                _displayInk(
                  widget.retainCommittedLayers
                      ? _CommittedInkLayers(
                          controller: widget.controller,
                          strokes: widget.controller.strokes,
                          paperDark: widget.paperDark,
                        )
                      : RepaintBoundary(
                          child: CustomPaint(
                            painter: _CommittedInkPainter(
                              widget.controller,
                              widget.paperDark,
                            ),
                            isComplex: true,
                          ),
                        ),
                  widget.displayFilter,
                ),
                _displayInk(
                  RepaintBoundary(
                    child: CustomPaint(
                      painter: _ActiveInkPainter(
                        widget.controller,
                        widget.paperDark,
                      ),
                      willChange: true,
                    ),
                  ),
                  widget.displayFilter,
                ),
                RepaintBoundary(
                  child: CustomPaint(
                    painter: _SelectionPainter(widget.controller),
                  ),
                ),
                if (_laserSamples.isNotEmpty)
                  IgnorePointer(
                    child: CustomPaint(
                      painter: _LaserPainter(
                        samples: List<_LaserSample>.unmodifiable(_laserSamples),
                        mode: widget.laserMode,
                        color: widget.laserColor,
                        width: widget.laserWidth,
                        nowMs: _laserNowMs,
                        fadeMs: widget.laserFadeMs,
                      ),
                    ),
                  ),
                IgnorePointer(
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: _EraserCursorPainter(
                        position: _cursorPosition,
                        radius: widget.eraserSize,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 取消选区变换、自动拉直和激光尾迹回调，释放橡皮光标状态。
  @override
  void dispose() {
    if (_transformFrame != null) {
      WidgetsBinding.instance.cancelFrameCallbackWithId(_transformFrame!);
    }
    _cursorPosition.dispose();
    _straightenTimer?.cancel();
    _laserTicker?.cancel();
    super.dispose();
  }
}
