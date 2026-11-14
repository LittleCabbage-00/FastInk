part of '../../app/fastink_app.dart';

/// 把设置页的选项同时应用到当前会话和持久配置。
///
/// 每个方法先更新运行时对象，让界面和手势立即生效；随后通过
/// SettingsRepository 的串行队列写盘，快速连续调整也不会丢值。
extension _FastInkSettings on _FastInkHomeState {
  /// pressureEnabled：是否将触笔压力用于笔宽；鼠标输入不能污染该开关。
  Future<void> _setPressureEnabled(bool value) async {
    _updateState(() => _settings.pressureEnabled = value);
    await _settings.saveBool('pressureEnabled', value);
  }

  /// pressureSensitivity：输入时的压感响应倍率；形成有效压力点，修改偏好不追溯改写旧笔迹。
  Future<void> _setPressureSensitivity(double value) async {
    final double next = value.clamp(0.5, 2.0);
    _updateState(() => _settings.pressureSensitivity = next);
    await _settings.saveNum('pressureSensitivity', next);
  }

  /// stylusOnly：是否只接受触笔书写；鼠标选择等非书写操作仍按输入规则处理。
  Future<void> _setStylusOnly(bool value) async {
    _updateState(() => _settings.stylusOnly = value);
    await _settings.saveBool('stylusOnly', value);
  }

  /// showPerformance：是否显示诊断性能信息，不改变实际渲染精度。
  Future<void> _setShowPerformance(bool value) async {
    _updateState(() => _settings.showPerformance = value);
    await _settings.saveBool('showPerformance', value);
  }

  /// doubleTapZoomEnabled：是否启用纸面双击缩放手势，浮层按钮会排除在识别范围外。
  Future<void> _setDoubleTapZoomEnabled(bool value) async {
    _updateState(() => _settings.doubleTapZoomEnabled = value);
    await _settings.saveBool('doubleTapZoomEnabled', value);
  }

  /// keepZoomOnPageChange：切页时是否保留缩放比例。
  Future<void> _setKeepZoomOnPageChange(bool value) async {
    _updateState(() => _settings.keepZoomOnPageChange = value);
    await _settings.saveBool('keepZoomOnPageChange', value);
  }

  /// touchInertiaStrength：触摸平移惯性的强度参数，不降低笔采样频率。
  Future<void> _setTouchInertiaStrength(double value) async {
    final double next = value.clamp(0, 2);
    _updateState(() => _settings.touchInertiaStrength = next);
    await _settings.saveNum('touchInertiaStrength', next);
  }

  /// 恢复导航/显示相关默认配置并同步运行时预算，不修改文稿内容或清空笔迹。
  Future<void> _restoreNavigationPerformanceDefaults() async {
    _updateState(() {
      _settings.doubleTapZoomEnabled = true;
      _settings.edgeBounceEnabled = true;
      _settings.keepZoomOnPageChange = true;
      _settings.maximumZoom = 5;
      _settings.wheelZoomSensitivity = 1;
      _settings.pageAnimationsEnabled = true;
      _settings.touchInertiaStrength = 1;
      final DocumentViewportLayout? layout = _viewport.documentViewportLayout;
      _viewport.zoomController.value = layout == null
          ? _viewport.constrainZoom(
              _viewport.zoomController.value,
              _settings.maximumZoom,
            )
          : layout.constrainCamera(
              _viewport.zoomController.value,
              maximumScale: _settings.maximumZoom,
            );
    });
    await _settings.saveAll({
      'doubleTapZoomEnabled': true,
      'edgeBounceEnabled': true,
      'keepZoomOnPageChange': true,
      'maximumZoom': 5,
      'wheelZoomSensitivity': 1,
      'pageAnimationsEnabled': true,
      'touchInertiaStrength': 1,
    });
  }

  /// penStyle：钢笔、圆珠笔、画笔等笔型名称，决定宽度响应与绘制方式。
  Future<void> _setDefaultPenStyle(PenStyle value) async {
    _updateState(() => _settings.penStyle = value.name);
    await _settings.saveString('penStyle', value.name);
  }

  /// penColor：普通笔颜色，使用 32 位 ARGB 保存。
  Future<void> _setDefaultPenColor(Color value) async {
    _updateState(() {
      _settings.penColor = value.toARGB32();
      // 当前正使用钢笔时同步工具栏颜色；其他工具保留各自的颜色。
      if (_toolState.tool == InkTool.pen) _toolState.color = value;
    });
    await _settings.saveNum('penColor', value.toARGB32());
  }

  /// 将当前快速颜色槽保存到配置，和临时工具颜色分开处理。
  Future<void> _persistPenColorPresets() async {
    await _settingsRepository.update(
      (current) => current.copyWith(penColorPresets: _settings.penColorPresets),
    );
  }

  /// autoSaveEnabled：手写笔迹自动保存开关；关闭不取消切页/退出刷盘。
  Future<void> _setAutoSaveEnabled(bool value) async {
    _updateState(() => _settings.autoSaveEnabled = value);
    _doc.saveTimer?.cancel();
    if (value && _doc.dirty) {
      _doc.saveTimer = Timer(
        Duration(milliseconds: _settings.autoSaveDelayMs),
        _saveWhenIdle,
      );
    }
    await _settings.saveBool('autoSaveEnabled', value);
  }

  /// selectionPriority：命中已有选区时是否优先移动，避免直接开始新选区。
  Future<void> _setSelectionPriority(bool value) async {
    _updateState(() => _settings.selectionPriority = value);
    await _settings.saveBool('selectionPriority', value);
  }

  /// selectionHitRadius：选择命中的容差，使用方按屏幕比例换算。
  Future<void> _setSelectionHitRadius(double value) async {
    final double next = value.clamp(32, 96);
    _updateState(() => _settings.selectionHitRadius = next);
    await _settings.saveNum('selectionHitRadius', next);
  }

  /// 更新显式传入的橡皮模式/范围并持久化，未传参数保持原配置。
  Future<void> _setEraserDefaults({EraserMode? mode, double? size}) async {
    if (mode != null) {
      _updateState(() {
        _settings.eraserMode = mode.name;
        _toolState.partialEraserFromButton = false;
      });
    }
    if (size != null) _updateState(() => _settings.eraserSize = size);
    await _settings.saveAll({
      'eraserMode': (mode != null) ? mode.name : _settings.eraserMode,
      'eraserSize': size ?? _settings.eraserSize,
    });
  }

  /// defaultTextSize：新文本的字号，单位页面布局逻辑像素，默认 12。
  Future<void> _setDefaultTextSize(double value) async {
    final double next = value.clamp(1, 72);
    _updateState(() => _settings.defaultTextSize = next);
    await _settings.saveNum('defaultTextSize', next);
  }

  /// showPageNumber：是否绘制页面角标，不控制顶部页码输入框。
  Future<void> _setShowPageNumber(bool value) async {
    _updateState(() => _settings.showPageNumber = value);
    await _settings.saveBool('showPageNumber', value);
  }

  /// 更新指定逻辑侧键动作，物理键交换与瞬时工具覆盖仍由输入层处理。
  Future<void> _setPenButtonAction(
    int logicalButton,
    PenButtonAction action,
  ) async {
    _updateState(() {
      // 改映射时先解除旧的临时工具，防止按键已松开但界面仍停在橡皮。
      _toolState.heldPenButton = 0;
      if (logicalButton == 1) {
        _settings.penButtonOneAction = action.name;
      } else {
        _settings.penButtonTwoAction = action.name;
      }
      final PenButtonAction btn1 = _decodePenButtonAction(
        _settings.penButtonOneAction,
        PenButtonAction.eraser,
      );
      final PenButtonAction btn2 = _decodePenButtonAction(
        _settings.penButtonTwoAction,
        PenButtonAction.lasso,
      );
      _lastPenEvent = tr(
        '一键：${btn1.label} · 二键：${btn2.label}',
        'Button 1: ${btn1.label} · Button 2: ${btn2.label}',
      );
    });
    await _settings.saveAll({
      'penButtonOneAction': _settings.penButtonOneAction,
      'penButtonTwoAction': _settings.penButtonTwoAction,
    });
  }

  /// penButtonMomentary：侧键是否只在按住期间临时切换工具。
  Future<void> _setPenButtonMomentary(bool value) async {
    _updateState(() {
      _toolState.heldPenButton = 0;
      _settings.penButtonMomentary = value;
    });
    await _settings.saveBool('penButtonMomentary', value);
  }

  /// swapPenButtons：是否交换两个物理侧键对应的逻辑动作。
  Future<void> _setSwapPenButtons(bool value) async {
    _updateState(() {
      _toolState.heldPenButton = 0;
      _settings.swapPenButtons = value;
      _lastPenEvent = value
          ? tr('已交换一键/二键识别，立即生效', 'Button 1 and 2 are swapped; change applied')
          : tr('一键/二键按默认顺序识别', 'Button 1 and 2 use their default order');
    });
    await _settings.saveBool('swapPenButtons', value);
  }
}
