import '../platform/render_power_policy.dart';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/app_localizations.dart';
import '../core/canvas_edit_shortcut.dart';
import '../engine/ink_canvas.dart';
import '../models/models.dart' show PenStyle;
import 'screenshot_document.dart';

/// 文稿解析后的物理侧键动作和该键使用的橡皮模式。
typedef ScreenshotPenBinding = ({InkTool? tool, EraserMode? eraser});

class ScreenshotEditor extends StatefulWidget {
  /// 接收待标注的截图、笔工具配置和输出回调。
  /// document：当前文稿元数据对象，页面和笔迹分别按需装载。
  /// onCopy：将截图 PNG 字节交给系统剪贴板的异步回调。
  /// onSave：将截图 PNG 字节保存到用户目标的异步回调，返回是否保存成功。
  /// canInsert：当前截图是否允许作为图片插入活动文稿，外部使用场景可禁用。
  /// 原生侧键通知与已解析的文稿配置共同驱动截图标注。
  const ScreenshotEditor({
    super.key,
    required this.document,
    required this.onCopy,
    required this.onSave,
    this.canInsert = true,
    this.nativePenButtons,
    this.penButtons = const {},
    this.penButtonMomentary = true,
    this.stylusOnly = false,
    this.penStyle = PenStyle.ball,
    this.penPressure,
    this.penColor = const Color(0xffed4245),
    this.penWidth = 4,
    this.highlighterColor = const Color(0xffffc107),
    this.highlighterWidth = 12,
    this.eraserMode = EraserMode.stroke,
    this.eraserSize = 24,
    this.shape = ShapeType.line,
    this.laserColor = const Color(0xffff3b30),
    this.laserWidth = 7,
    this.laserMode = LaserMode.trail,
  });

  /// document：当前文稿元数据对象，页面和笔迹分别按需装载。
  final ScreenshotDocument document;

  /// onCopy：将截图 PNG 字节交给系统剪贴板的异步回调。
  final Future<void> Function(Uint8List) onCopy;

  /// onSave：将截图 PNG 字节保存到用户目标的异步回调，返回是否保存成功。
  final Future<bool> Function(Uint8List) onSave;

  /// canInsert：当前截图是否允许作为图片插入活动文稿，外部使用场景可禁用。
  final bool canInsert;

  /// Flutter 未提供侧键位时使用的原生后备状态。
  final ValueListenable<int>? nativePenButtons;

  /// Flutter 物理侧键位掩码对应的文稿绑定，已经处理侧键交换。
  final Map<int, ScreenshotPenBinding> penButtons;

  /// 按住临时切换或按一下切换，和文稿设置相同。
  final bool penButtonMomentary;

  /// 鼠标仍可裁切和选中对象，书写限制沿用文稿配置。
  final bool stylusOnly;

  /// 文稿笔型和有效压力采样。
  final PenStyle penStyle;
  final double Function(PointerEvent)? penPressure;

  /// 文稿默认笔色、荧光笔色与逻辑像素宽度。
  final Color penColor, highlighterColor;
  final double penWidth, highlighterWidth;

  /// 文稿配置的默认橡皮模式和屏幕逻辑像素半径。
  final EraserMode eraserMode;
  final double eraserSize;

  /// 侧键进入形状工具时使用的文稿形状。
  final ShapeType shape;

  /// 激光标记仅供截图预览，抬笔消失。
  final Color laserColor;
  final double laserWidth;
  final LaserMode laserMode;

  /// 维护当前标注工具、选择内容和笔侧键状态。
  @override
  State<ScreenshotEditor> createState() => _ScreenshotEditorState();
}

class _ScreenshotEditorState extends State<ScreenshotEditor> {
  /// doc：当前截图编辑模型，持有裁切、标注与历史，不等同于手写 NoteDocument。
  ScreenshotDocument get doc => widget.document;

  /// tool：当前画布输入工具；与临时侧键工具共同决定本次手势的行为。
  CaptureTool tool = CaptureTool.crop;

  /// 绘制颜色。
  late Color color = widget.penColor;

  /// 荧光笔独立配色，切回钢笔时恢复原设置。
  late Color highlighterColor = widget.highlighterColor;

  /// width：当前截图标注线宽，缩放显示时按视图换算。
  late double width = widget.penWidth.clamp(.5, 24);

  /// 荧光笔线宽与橡皮半径，均以屏幕逻辑像素计。
  late double highlighterWidth = widget.highlighterWidth.clamp(2, 64);
  late double eraserSize = widget.eraserSize.clamp(12, 120);

  /// 截图手动橡皮模式及切换式侧键覆盖。
  late EraserMode eraserMode = widget.eraserMode;
  EraserMode? latchedEraser;

  /// 本次擦除前的标注列表。移动期间只更新预览，结束时一次入历史。
  List<CaptureMark>? eraseStart;
  EraserMode? gestureEraser;

  /// mosaicStrength：截图马赛克块大小倍率，不修改原图文件。
  double mosaicStrength = 1;

  /// scale：截图图像到编辑窗口的显示倍率，命中坐标需逆变换。
  double scale = 1;

  /// origin：截图图像在编辑窗口中的逻辑坐标原点。
  Offset origin = Offset.zero;

  /// start：当前截图手势的起点，未开始手势时为空。
  Offset? start;

  /// startCrop：本次拖动前的裁切矩形快照，避免累计偏移导致尺寸漂移。
  Rect? startCrop;

  /// startMark：本次对象变换开始时的标注快照，结束前以此计算最终几何；draft：尚未确认的截图标注草稿，预览时显示，取消不写入标注列表。
  CaptureMark? startMark, draft;

  /// Ctrl+C / Ctrl+X 保存的可编辑标注，只在这次截图窗口中使用。
  CaptureMark? copiedMark;

  /// pointer：当前截图手势拥有的指针编号，其他指针不能中途接管。
  int? pointer;

  /// gestureTool：截图手势起点确定的工具，中途按钮改变不重新解释旧点列。
  CaptureTool? gestureTool;

  /// rawButtonSources：报告侧键按下的设备/来源组合，合并原生与 Flutter 事件避免重复边沿。
  final Set<(int, int)> rawButtonSources = {};

  /// 最近一次触笔事件的原始位掩码和设备，以及合并后按住的侧键。
  int rawButtons = 0;
  int? penDevice;
  int heldButtons = 0;

  /// handle：命中的裁切/标注调整把手索引，负值表示没有把手命中。
  int handle = -1; // -1 new crop, 0..7 resize, 8 move crop, 9 move mark
  /// busy：截图窗口是否在执行复制、保存或生成输出，避免重复提交。
  bool busy = false;

  /// status：当前操作的可读状态文案，不能单独替代加载/锁等业务标志。
  String status = '';

  /// focus：该编辑区域的键盘焦点依赖，快捷键只在适当输入上下文处理。
  final focus = FocusNode();

  /// 绑定截图模型和原生侧键通知，卸载时配对解除。
  @override
  void initState() {
    super.initState();
    doc.addListener(_changed);
    widget.nativePenButtons?.addListener(_nativeButtonsChanged);
    _syncPenButtons(notify: false);
  }

  /// 宿主替换原生侧键通知器时重新绑定，旧通知不能继续驱动当前截图手势。
  @override
  void didUpdateWidget(covariant ScreenshotEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.nativePenButtons != widget.nativePenButtons) {
      oldWidget.nativePenButtons?.removeListener(_nativeButtonsChanged);
      widget.nativePenButtons?.addListener(_nativeButtonsChanged);
    }
  }

  /// 合并触笔事件和原生后备。已报告过原始位的设备优先用事件状态。
  void _syncPenButtons({PointerEvent? event, bool notify = true}) {
    if (event != null) {
      if (event.kind != PointerDeviceKind.stylus) return;
      rawButtons = event.buttons;
      penDevice = event.device;
    }
    var next = 0;
    for (final mask in [kPrimaryStylusButton, kSecondaryStylusButton]) {
      if (penDevice != null && rawButtons & mask != 0) {
        rawButtonSources.add((penDevice!, mask));
      }
      final buttons =
          penDevice != null && rawButtonSources.contains((penDevice!, mask))
          ? rawButtons
          : widget.nativePenButtons?.value ?? 0;
      next |= buttons & mask;
    }
    if (next == heldButtons) return;
    final pressed = next & ~heldButtons;
    heldButtons = next;
    if (!widget.penButtonMomentary) {
      final binding = _binding(pressed);
      final target = _mapTool(binding?.tool);
      if (target != null) {
        tool = target;
        latchedEraser = binding?.eraser;
      }
    }
    if (notify && mounted) setState(() {});
  }

  /// 原生侧键边沿更新工具提示，活动笔画在下个指针采样点衔接。
  void _nativeButtonsChanged() => _syncPenButtons();

  /// 取按下的文稿侧键绑定，同时按下时优先副键。
  ScreenshotPenBinding? _binding(int buttons) =>
      widget.penButtons[buttons & kSecondaryStylusButton != 0
          ? kSecondaryStylusButton
          : buttons & kPrimaryStylusButton != 0
          ? kPrimaryStylusButton
          : 0];

  /// 将文稿工具映射到截图中的同类编辑工具，裁切没有侧键映射。
  CaptureTool? _mapTool(InkTool? value) => switch (value) {
    InkTool.pen => CaptureTool.pen,
    InkTool.highlighter => CaptureTool.highlighter,
    InkTool.eraser => CaptureTool.eraser,
    InkTool.lasso => CaptureTool.select,
    InkTool.text => CaptureTool.text,
    InkTool.laser => CaptureTool.laser,
    InkTool.shape => switch (widget.shape) {
      ShapeType.line => CaptureTool.line,
      ShapeType.arrow => CaptureTool.arrow,
      ShapeType.rectangle => CaptureTool.rectangle,
      ShapeType.ellipse => CaptureTool.ellipse,
      ShapeType.triangle => CaptureTool.triangle,
      ShapeType.diamond => CaptureTool.diamond,
    },
    null => null,
  };

  /// 瞬时侧键只在按住时覆盖当前工具。
  CaptureTool get shownTool =>
      (widget.penButtonMomentary
          ? _mapTool(_binding(heldButtons)?.tool)
          : null) ??
      tool;

  /// 翻转触笔使用橡皮，鼠标使用工具栏选中的工具。
  CaptureTool _toolFor(PointerEvent event) => switch (event.kind) {
    PointerDeviceKind.invertedStylus => CaptureTool.eraser,
    PointerDeviceKind.stylus => shownTool,
    _ => tool,
  };

  /// 计算这次擦除沿用的默认或侧键模式。
  EraserMode _eraserFor(PointerEvent event) =>
      (widget.penButtonMomentary && event.kind == PointerDeviceKind.stylus
          ? _binding(heldButtons)?.eraser
          : null) ??
      latchedEraser ??
      eraserMode;

  /// 笔和荧光笔采集连续点，激光只做临时预览。
  bool _isFreehand(CaptureTool value) =>
      value == CaptureTool.pen ||
      value == CaptureTool.highlighter ||
      value == CaptureTool.laser;

  /// 把截图模型通知转为当前窗口显示更新，已卸载时不刷新。
  void _changed() {
    if (mounted) setState(() {});
  }

  /// 退出标注时解除截图和触笔侧键监听，释放快捷键焦点。
  @override
  void dispose() {
    doc.removeListener(_changed);
    widget.nativePenButtons?.removeListener(_nativeButtonsChanged);
    focus.dispose();
    super.dispose();
  }

  /// 将屏幕点减去 origin、除以 scale，再逆转整图方向，得到原图坐标。
  Offset _point(Offset p) => doc.fromDisplay((p - origin) / scale);

  /// 将一个点约束到给定图像矩形内，避免框选或调整超出有效像素范围。
  Offset _clamp(Offset p, Rect r) =>
      Offset(p.dx.clamp(r.left, r.right), p.dy.clamp(r.top, r.bottom));

  /// 计算矩形角点与边中点等调整把手位置，命中和绘制共用。
  List<Offset> _handles(Rect r) => [
    r.topLeft,
    r.topCenter,
    r.topRight,
    r.centerRight,
    r.bottomRight,
    r.bottomCenter,
    r.bottomLeft,
    r.centerLeft,
  ];

  /// 建立裁切、变换、擦除或书写手势。选择截图区域后，触笔与鼠标都可直接拖动。
  void _down(PointerEvent e) {
    if (busy || pointer != null) return;
    // 手掌触摸不能创建截图选区、批注或历史记录。
    if (e.kind != PointerDeviceKind.stylus &&
        e.kind != PointerDeviceKind.mouse &&
        e.kind != PointerDeviceKind.invertedStylus) {
      return;
    }
    final mouse = e.kind == PointerDeviceKind.mouse;
    if (mouse && e.buttons & kPrimaryMouseButton == 0) return;
    _syncPenButtons(event: e);
    final activeTool = _toolFor(e);
    if (mouse &&
        widget.stylusOnly &&
        activeTool != CaptureTool.crop &&
        activeTool != CaptureTool.select &&
        activeTool != CaptureTool.text) {
      return;
    }
    focus.requestFocus();
    final p = _point(e.localPosition);
    if (!doc.imageRect.contains(p)) return;
    if (activeTool != CaptureTool.crop && !(doc.crop?.contains(p) ?? false)) {
      return;
    }
    if (activeTool == CaptureTool.text) {
      _text(p);
      return;
    }
    pointer = e.pointer;
    gestureTool = activeTool;
    start = p;
    startCrop = doc.crop;
    startMark = null;
    handle = -1;
    if (activeTool == CaptureTool.crop) {
      final crop = doc.crop;
      if (crop != null) {
        handle = _handles(
          crop,
        ).indexWhere((h) => (h - p).distance < 15 / scale);
        if (handle == -1 && crop.contains(p)) handle = 8;
      }
      if (handle == -1) doc.crop = Rect.fromPoints(p, p);
    } else if (activeTool == CaptureTool.select) {
      doc.selected = null;
      for (var i = doc.marks.length - 1; i >= 0; i--) {
        if (doc.marks[i].hit(p, 8 / scale)) {
          doc.selected = i;
          startMark = doc.marks[i];
          handle = 9;
          break;
        }
      }
    } else if (activeTool == CaptureTool.eraser) {
      eraseStart = doc.marks;
      gestureEraser = _eraserFor(e);
      doc.eraseAt(p, eraserSize / scale, gestureEraser!);
    } else {
      doc.selected = null;
      final pressure = activeTool == CaptureTool.pen
          ? widget.penPressure?.call(e)
          : null;
      draft = CaptureMark(
        tool: activeTool,
        points: _isFreehand(activeTool) ? [p] : [p, p],
        color: switch (activeTool) {
          CaptureTool.highlighter => highlighterColor,
          CaptureTool.laser => widget.laserColor,
          _ => color,
        },
        width: switch (activeTool) {
          CaptureTool.mosaic => [8.0, 18.0, 36.0][mosaicStrength.round()],
          CaptureTool.highlighter => highlighterWidth / scale,
          CaptureTool.laser => widget.laserWidth / scale,
          _ => width / scale,
        },
        penStyle: widget.penStyle,
        pressures: pressure == null ? null : [pressure],
      );
    }
    setState(() {});
  }

  /// 已按住的笔尖收到侧键边沿时结束前一个动作，从当前位置进入新工具。
  void _move(PointerMoveEvent e) {
    if (e.pointer != pointer || start == null || busy) return;
    _syncPenButtons(event: e);
    final target = _toolFor(e);
    if (target != gestureTool ||
        (target == CaptureTool.eraser && _eraserFor(e) != gestureEraser)) {
      _endGesture();
      _down(e);
      return;
    }
    final p = _clamp(_point(e.localPosition), doc.imageRect);
    if (gestureTool == CaptureTool.crop) {
      final old = startCrop;
      if (handle == 8 && old != null) {
        final delta = p - start!;
        doc.crop = old.shift(
          Offset(
            delta.dx.clamp(-old.left, doc.imageRect.right - old.right),
            delta.dy.clamp(-old.top, doc.imageRect.bottom - old.bottom),
          ),
        );
      } else if (handle >= 0 && old != null) {
        double l = old.left, r = old.right, t = old.top, b = old.bottom;
        if ([0, 6, 7].contains(handle)) l = math.min(p.dx, r - 2);
        if ([2, 3, 4].contains(handle)) r = math.max(p.dx, l + 2);
        if ([0, 1, 2].contains(handle)) t = math.min(p.dy, b - 2);
        if ([4, 5, 6].contains(handle)) b = math.max(p.dy, t + 2);
        doc.crop = Rect.fromLTRB(l, t, r, b).intersect(doc.imageRect);
      } else {
        doc.crop = Rect.fromPoints(start!, p);
      }
    } else if (handle == 9 && startMark != null && doc.selected != null) {
      doc.marks[doc.selected!] = startMark!.move(p - start!);
    } else if (gestureTool == CaptureTool.eraser) {
      if (doc.crop!.contains(p)) {
        doc.eraseAt(p, eraserSize / scale, gestureEraser!);
      }
    } else if (draft != null) {
      final point = _clamp(p, doc.crop!);
      if (_isFreehand(gestureTool!)) {
        // 手写只追加尾点，避免每次指针采样都复制整条草稿。
        if (gestureTool == CaptureTool.laser &&
            widget.laserMode == LaserMode.dot) {
          draft!.points.clear();
        }
        draft!.points.add(point);
        draft!.pressures?.add(widget.penPressure!.call(e));
      } else {
        draft!.points[1] = point;
      }
    }
    setState(() {});
  }

  /// 结束或取消当前指针操作，提交必要的标注草稿，清理设备与侧键手势状态。
  void _up(PointerEvent e, {bool cancelled = false}) {
    if (e.kind == PointerDeviceKind.touch || e.pointer != pointer) return;
    _endGesture(cancelled: cancelled);
    _syncPenButtons(event: e);
  }

  /// 统一结束活动手势；cancelled 决定丢弃草稿/恢复起点，普通结束生成完整历史。
  void _endGesture({bool cancelled = false}) {
    if (gestureTool == CaptureTool.crop) {
      final result = doc.crop;
      doc.crop = startCrop;
      if (!cancelled &&
          result != null &&
          result.shortestSide >= 2 &&
          result != startCrop) {
        doc.checkpoint();
        doc.crop = result;
      }
    } else if (handle == 9 && startMark != null && doc.selected != null) {
      final index = doc.selected!;
      final result = doc.marks[index];
      doc.marks[index] = startMark!;
      if (!cancelled && result.points.first != startMark!.points.first) {
        doc.checkpoint();
        doc.marks[index] = result;
      }
    } else if (eraseStart != null) {
      final result = doc.marks;
      doc.marks = eraseStart!;
      if (!cancelled && !identical(result, eraseStart)) {
        doc.checkpoint();
        doc.marks = result;
      }
    } else if (!cancelled &&
        draft != null &&
        gestureTool != CaptureTool.laser) {
      if (_isFreehand(gestureTool!) ||
          (draft!.points.last - draft!.points.first).distance > 2 / scale) {
        doc.add(draft!);
      }
    }
    pointer = null;
    gestureTool = null;
    start = null;
    draft = null;
    startMark = null;
    eraseStart = null;
    gestureEraser = null;
    setState(() {});
  }

  /// 在指定原图点位请求文字输入，确认后建立文字标注，取消保持图像与其他标注不变。
  Future<void> _text(Offset point) async {
    final input = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      animationStyle: appMotionStyle(context),
      builder: (ctx) => AlertDialog(
        title: Text(tr('文字标注', 'Text annotation')),
        content: SizedBox(
          width: 400,
          child: TextField(
            key: const ValueKey('capture-text-input'),
            controller: input,
            autofocus: true,
            minLines: 1,
            maxLines: 5,
            decoration: InputDecoration(
              hintText: tr('输入标注内容', 'Enter annotation text'),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr('取消', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, input.text),
            child: Text(tr('添加', 'Add')),
          ),
        ],
      ),
    );
    // 等对话框关闭动画释放输入框，再释放其控制器。
    Future<void>.delayed(const Duration(milliseconds: 300), input.dispose);
    if (!mounted) return;
    if (text != null && text.trim().isNotEmpty) {
      doc.add(
        CaptureMark(
          tool: CaptureTool.text,
          points: [point],
          color: color,
          width: width / scale,
          text: text.trim(),
        ),
      );
    }
    focus.requestFocus();
  }

  /// 切换截图工具并结束不兼容的未完成手势，避免草稿以新工具语义提交。
  void _choose(CaptureTool value) {
    if (pointer != null || busy) return;
    setState(() {
      tool = value;
      latchedEraser = null;
      status = '';
    });
    focus.requestFocus();
  }

  /// 按复制、保存或插入动作生成当前 PNG，再调用宿主异步入口，维护 busy 并反馈失败。
  Future<void> _finish(String action) async {
    if (busy ||
        pointer != null ||
        doc.crop == null ||
        doc.crop!.shortestSide < 2) {
      return;
    }
    setState(() => busy = true);
    try {
      final png = await doc.exportPng();
      if (!mounted) return;
      if (action == 'insert') {
        Navigator.pop(context, png);
        return;
      }
      if (action == 'copy') {
        await widget.onCopy(png);
        status = tr('已复制图片', 'Image copied');
      } else {
        status = await widget.onSave(png)
            ? tr('截图已保存', 'Screenshot saved')
            : '';
      }
    } catch (error) {
      status = tr('操作失败：$error', 'Operation failed: $error');
    } finally {
      if (mounted) {
        setState(() => busy = false);
        focus.requestFocus();
      }
    }
  }

  /// 返回当前可见选区中的标注。框选模式下 Ctrl+C 复制合成图片。
  CaptureMark? get selectedMark {
    final index = doc.selected;
    return tool == CaptureTool.crop || index == null ? null : doc.marks[index];
  }

  /// 将标注副本稍微错开，贴边时收回到裁切区域，方便立即拖动。
  void _pasteMark(CaptureMark mark) {
    final crop = doc.crop;
    if (crop == null) return;
    final bounds = mark.bounds;
    final offset = 12 / scale;
    final left = math.min(crop.left, crop.right - bounds.width);
    final top = math.min(crop.top, crop.bottom - bounds.height);
    final target = Offset(
      (bounds.left + offset).clamp(left, crop.right - bounds.width),
      (bounds.top + offset).clamp(top, crop.bottom - bounds.height),
    );
    doc.add(mark.move(target - bounds.topLeft));
    _choose(CaptureTool.select);
  }

  /// 使用文稿的编辑键位，PNG 输出和插入由截图窗口单独处理。
  KeyEventResult _key(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent ||
        busy ||
        pointer != null ||
        ModalRoute.of(context)?.isCurrent == false) {
      return KeyEventResult.ignored;
    }
    if (e.logicalKey == LogicalKeyboardKey.enter && widget.canInsert) {
      _finish('insert');
      return KeyEventResult.handled;
    }
    final mark = selectedMark;
    switch (canvasEditShortcut(e)) {
      case CanvasEditShortcut.escape:
        if (mark == null) {
          Navigator.pop(context);
        } else {
          doc.selected = null;
          doc.changed();
        }
      case CanvasEditShortcut.undo:
        doc.undo();
      case CanvasEditShortcut.redo:
        doc.redo();
      case CanvasEditShortcut.copy:
        if (HardwareKeyboard.instance.isShiftPressed) {
          _finish('copy');
        } else if (mark != null) {
          copiedMark = mark;
          setState(() => status = tr('已复制标注', 'Annotation copied'));
        } else {
          return KeyEventResult.ignored;
        }
      case CanvasEditShortcut.cut when mark != null:
        copiedMark = mark;
        doc.deleteSelected();
      case CanvasEditShortcut.paste when copiedMark != null:
        _pasteMark(copiedMark!);
      case CanvasEditShortcut.duplicate when mark != null:
        _pasteMark(mark);
      case CanvasEditShortcut.delete when mark != null:
        doc.deleteSelected();
      case CanvasEditShortcut.save:
        _finish('save');
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  /// 创建反映当前截图工具/动作状态的按钮，显示明确提示并绑定稳定动作。
  Widget _button(
    String id,
    IconData icon,
    String label,
    VoidCallback? action, {
    bool selected = false,
  }) => IconButton(
    key: ValueKey('capture-$id'),
    tooltip: label,
    isSelected: selected,
    style: IconButton.styleFrom(
      backgroundColor: selected ? const Color(0xffdbe7ff) : null,
      foregroundColor: selected ? const Color(0xff284e91) : null,
    ),
    onPressed: busy || pointer != null ? null : action,
    icon: Icon(icon, size: 22),
  );

  /// 裁切和常用编辑工具用与文稿相同的有文字工具按钮。
  Widget _toolButton(CaptureTool value, IconData icon, String label) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: TextButton.icon(
        key: ValueKey('capture-${value.name}'),
        style: TextButton.styleFrom(
          backgroundColor: shownTool == value
              ? colors.secondaryContainer
              : null,
          foregroundColor: shownTool == value
              ? colors.onSecondaryContainer
              : colors.onSurface,
        ),
        onPressed: busy || pointer != null ? null : () => _choose(value),
        icon: Icon(icon, size: 18),
        label: Text(label),
      ),
    );
  }

  /// 只显示当前编辑工具的参数，截图侧键直接读取文稿设置。
  Widget _toolOptions() {
    final current = shownTool;
    final active = !busy && pointer == null;
    final isMosaic = current == CaptureTool.mosaic;
    final isEraser = current == CaptureTool.eraser;
    final isHighlighter = current == CaptureTool.highlighter;
    final hasColor =
        !isMosaic &&
        !isEraser &&
        current != CaptureTool.crop &&
        current != CaptureTool.select &&
        current != CaptureTool.laser;
    final palette = isHighlighter
        ? const [Color(0xffffc107), Color(0xff8bc34a), Color(0xffff6fae)]
        : const [
            Color(0xff202124),
            Color(0xff3387fa),
            Color(0xffed4245),
            Color(0xffffb020),
            Color(0xff32bd76),
            Color(0xffa865ed),
            Colors.white,
          ];
    final selectedColor = isHighlighter ? highlighterColor : color;
    final colors = Theme.of(context).colorScheme;
    final value = isMosaic
        ? mosaicStrength
        : isEraser
        ? eraserSize
        : isHighlighter
        ? highlighterWidth
        : width;
    return SizedBox(
      height: 40,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            if (current == CaptureTool.crop)
              Text(
                tr('用笔或鼠标拖动调整截取范围', 'Drag with pen or mouse to set the region'),
              ),
            if (current == CaptureTool.select)
              Text(
                tr('点选标注后可拖动或复制', 'Select an annotation to move or copy it'),
              ),
            if (hasColor)
              for (final c in palette)
                Padding(
                  padding: const EdgeInsets.only(right: 7),
                  child: InkWell(
                    key: ValueKey('capture-color-${c.toARGB32()}'),
                    onTap: !active
                        ? null
                        : () => setState(() {
                            if (isHighlighter) {
                              highlighterColor = c;
                            } else {
                              color = c;
                            }
                          }),
                    customBorder: const CircleBorder(),
                    child: Container(
                      width: 25,
                      height: 25,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: c,
                        border: Border.all(
                          color: selectedColor == c
                              ? colors.primary
                              : colors.outline,
                          width: selectedColor == c ? 3 : 1,
                        ),
                      ),
                    ),
                  ),
                ),
            if (isEraser)
              DropdownButton<EraserMode>(
                value: latchedEraser ?? eraserMode,
                onChanged: !active
                    ? null
                    : (next) {
                        if (next != null) {
                          setState(() {
                            latchedEraser = null;
                            eraserMode = next;
                          });
                        }
                      },
                items: [
                  DropdownMenuItem(
                    value: EraserMode.stroke,
                    child: Text(tr('整笔擦除', 'Stroke eraser')),
                  ),
                  DropdownMenuItem(
                    value: EraserMode.point,
                    child: Text(tr('局部擦除', 'Partial eraser')),
                  ),
                ],
              ),
            if (hasColor || isEraser || isMosaic) ...[
              const SizedBox(width: 12),
              Text(
                isMosaic
                    ? tr('马赛克强度', 'Mosaic strength')
                    : isEraser
                    ? tr('擦除半径', 'Eraser radius')
                    : tr('粗细', 'Width'),
              ),
              SizedBox(
                width: 150,
                child: Slider(
                  value: value,
                  min: isMosaic
                      ? 0
                      : isEraser
                      ? 12
                      : isHighlighter
                      ? 2
                      : .5,
                  max: isMosaic
                      ? 2
                      : isEraser
                      ? 120
                      : isHighlighter
                      ? 64
                      : 24,
                  divisions: isMosaic ? 2 : null,
                  label: value.toStringAsFixed(1),
                  onChanged: !active
                      ? null
                      : (next) => setState(() {
                          if (isMosaic) {
                            mosaicStrength = next;
                          } else if (isEraser) {
                            eraserSize = next;
                          } else if (isHighlighter) {
                            highlighterWidth = next;
                          } else {
                            width = next;
                          }
                        }),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 组装截图画布、裁切遮罩、标注工具和输出操作，按可用窗口计算图像 origin 与 scale。
  @override
  Widget build(BuildContext context) {
    final ready = doc.crop != null && doc.crop!.shortestSide >= 2 && !busy;
    // 先接管触摸手势，防止按钮或滑块把手掌误判为点击。
    return RawGestureDetector(
      behavior: HitTestBehavior.translucent,
      gestures: {
        EagerGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<EagerGestureRecognizer>(
              () => EagerGestureRecognizer(
                supportedDevices: {PointerDeviceKind.touch},
              ),
              (_) {},
            ),
      },
      child: Focus(
        autofocus: true,
        focusNode: focus,
        onKeyEvent: _key,
        child: Scaffold(
          backgroundColor: const Color(0xff151923),
          appBar: AppBar(
            automaticallyImplyLeading: false,
            titleSpacing: 12,
            toolbarHeight: 58,
            title: Row(
              children: [
                _button(
                  'cancel',
                  Icons.close,
                  tr('取消截图 · Esc', 'Cancel · Esc'),
                  () => Navigator.pop(context),
                ),
                const SizedBox(width: 8),
                Text(
                  tr('截图编辑', 'Screenshot editor'),
                  style: const TextStyle(fontSize: 18),
                ),
                const Spacer(),
                _button(
                  'copy',
                  Icons.copy,
                  tr('复制图片 · Ctrl+Shift+C', 'Copy image · Ctrl+Shift+C'),
                  ready ? () => _finish('copy') : null,
                ),
                _button(
                  'save',
                  Icons.save_alt,
                  tr('保存图片 · Ctrl+S', 'Save image · Ctrl+S'),
                  ready ? () => _finish('save') : null,
                ),
                if (widget.canInsert)
                  FilledButton.icon(
                    key: const ValueKey('capture-insert'),
                    onPressed: ready ? () => _finish('insert') : null,
                    icon: const Icon(
                      Icons.add_photo_alternate_outlined,
                      size: 19,
                    ),
                    label: Text(tr('插入笔记', 'Insert')),
                  ),
              ],
            ),
          ),
          body: Column(
            children: [
              Material(
                color: Theme.of(context).colorScheme.surface,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      child: Row(
                        children: [
                          // 截取范围是独立操作，标注栏横向滚动时仍要能随时切回。
                          _toolButton(
                            CaptureTool.crop,
                            Icons.crop,
                            tr('选择截图区域', 'Select screenshot region'),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  _toolButton(
                                    CaptureTool.pen,
                                    Icons.edit_outlined,
                                    tr('笔', 'Pen'),
                                  ),
                                  _toolButton(
                                    CaptureTool.highlighter,
                                    Icons.border_color_outlined,
                                    tr('荧光笔', 'Highlighter'),
                                  ),
                                  _toolButton(
                                    CaptureTool.eraser,
                                    Icons.auto_fix_normal_outlined,
                                    tr('橡皮擦', 'Eraser'),
                                  ),
                                  _toolButton(
                                    CaptureTool.select,
                                    Icons.gesture_rounded,
                                    tr('选区', 'Select'),
                                  ),
                                  const SizedBox(width: 8),
                                  for (final (value, icon, zh, en)
                                      in <
                                        (CaptureTool, IconData, String, String)
                                      >[
                                        (
                                          CaptureTool.arrow,
                                          Icons.north_east,
                                          '箭头',
                                          'Arrow',
                                        ),
                                        (
                                          CaptureTool.rectangle,
                                          Icons.crop_square,
                                          '方框',
                                          'Rectangle',
                                        ),
                                        (
                                          CaptureTool.ellipse,
                                          Icons.circle_outlined,
                                          '圆圈',
                                          'Ellipse',
                                        ),
                                        (
                                          CaptureTool.text,
                                          Icons.text_fields,
                                          '文字',
                                          'Text',
                                        ),
                                        (
                                          CaptureTool.mosaic,
                                          Icons.grid_on,
                                          '马赛克',
                                          'Mosaic',
                                        ),
                                      ])
                                    _button(
                                      value.name,
                                      icon,
                                      tr(zh, en),
                                      () => _choose(value),
                                      selected: shownTool == value,
                                    ),
                                  const SizedBox(width: 12),
                                  _button(
                                    'rotate',
                                    Icons.rotate_right,
                                    tr(
                                      '整张截图顺时针旋转 90°',
                                      'Rotate screenshot 90°',
                                    ),
                                    doc.rotateImage,
                                  ),
                                  _button(
                                    'rotate-mark',
                                    Icons.rotate_90_degrees_ccw,
                                    tr('所选标注旋转 15°', 'Rotate annotation 15°'),
                                    doc.selected == null
                                        ? null
                                        : () =>
                                              doc.rotateSelected(math.pi / 12),
                                  ),
                                  _button(
                                    'duplicate',
                                    Icons.control_point_duplicate_rounded,
                                    tr(
                                      '复制标注副本 · Ctrl+D',
                                      'Duplicate annotation · Ctrl+D',
                                    ),
                                    selectedMark == null
                                        ? null
                                        : () => _pasteMark(selectedMark!),
                                  ),
                                  _button(
                                    'delete',
                                    Icons.delete_outline,
                                    tr(
                                      '删除标注 · Delete',
                                      'Delete annotation · Delete',
                                    ),
                                    doc.selected == null
                                        ? null
                                        : doc.deleteSelected,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          _button(
                            'undo',
                            Icons.undo,
                            tr('撤销 · Ctrl+Z', 'Undo · Ctrl+Z'),
                            doc.canUndo ? doc.undo : null,
                          ),
                          _button(
                            'redo',
                            Icons.redo,
                            tr(
                              '重做 · Ctrl+Y / Ctrl+Shift+Z',
                              'Redo · Ctrl+Y / Ctrl+Shift+Z',
                            ),
                            doc.canRedo ? doc.redo : null,
                          ),
                        ],
                      ),
                    ),
                    _toolOptions(),
                  ],
                ),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (_, constraints) {
                    final size = doc.displaySize;
                    scale = math
                        .min(
                          (constraints.maxWidth - 32) / size.width,
                          (constraints.maxHeight - 32) / size.height,
                        )
                        .clamp(.001, 4);
                    origin = Offset(
                      (constraints.maxWidth - size.width * scale) / 2,
                      (constraints.maxHeight - size.height * scale) / 2,
                    );
                    return Listener(
                      key: const ValueKey('capture-canvas'),
                      behavior: HitTestBehavior.opaque,
                      onPointerDown: _down,
                      onPointerHover: (e) => _syncPenButtons(event: e),
                      onPointerMove: _move,
                      onPointerUp: _up,
                      onPointerCancel: (e) => _up(e, cancelled: true),
                      child: CustomPaint(
                        size: constraints.biggest,
                        painter: _CapturePainter(
                          doc,
                          origin,
                          scale,
                          draft,
                          gestureTool ?? shownTool,
                        ),
                      ),
                    );
                  },
                ),
              ),
              SafeArea(
                top: false,
                child: Container(
                  height: 34,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  alignment: Alignment.centerLeft,
                  child: Text(
                    status.isNotEmpty
                        ? status
                        : doc.crop == null
                        ? tr(
                            '点击「选择截图区域」，用笔或鼠标拖动',
                            'Choose Select screenshot region, then drag with pen or mouse',
                          )
                        : '${doc.crop!.width.round()} × ${doc.crop!.height.round()} px  ·  ${tr('笔侧键沿用文稿编辑动作', 'Pen buttons use the same editing actions as the note')}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xffd6dcea),
                      fontSize: 12,
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

class _CapturePainter extends CustomPainter {
  /// 绑定截图模型、显示原点/比例和草稿，订阅模型变化只重绘截图区域。
  _CapturePainter(this.doc, this.origin, this.scale, this.draft, this.tool);

  /// doc：当前截图编辑模型，持有裁切、标注与历史，不等同于手写 NoteDocument。
  final ScreenshotDocument doc;

  /// origin：截图图像在编辑窗口中的逻辑坐标原点。
  final Offset origin;

  /// scale：截图图像到编辑窗口的显示倍率，命中坐标需逆变换。
  final double scale;

  /// draft：尚未确认的截图标注草稿，预览时显示，取消不写入标注列表。
  final CaptureMark? draft;

  /// tool：当前画布输入工具；与临时侧键工具共同决定本次手势的行为。
  final CaptureTool tool;

  /// 按图像与显示坐标转换绘制截图、裁切遮罩和选择把手，保持工具命中与显示一致。
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(origin.dx, origin.dy);
    canvas.scale(scale);
    doc.transform(
      canvas,
      doc.image.width.toDouble(),
      doc.image.height.toDouble(),
    );
    doc.paintContent(canvas, draft: draft);
    final crop = doc.crop;
    if (crop == null) {
      canvas.drawRect(doc.imageRect, Paint()..color = const Color(0x55000000));
    } else {
      canvas.drawPath(
        Path.combine(
          PathOperation.difference,
          Path()..addRect(doc.imageRect),
          Path()..addRect(crop),
        ),
        Paint()..color = const Color(0x99000000),
      );
      canvas.drawRect(
        crop,
        Paint()
          ..color = const Color(0xff71a5ff)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5 / scale,
      );
      if (tool == CaptureTool.crop) {
        for (final p in [
          crop.topLeft,
          crop.topCenter,
          crop.topRight,
          crop.centerRight,
          crop.bottomRight,
          crop.bottomCenter,
          crop.bottomLeft,
          crop.centerLeft,
        ]) {
          canvas.drawCircle(p, 5 / scale, Paint()..color = Colors.white);
          canvas.drawCircle(
            p,
            5 / scale,
            Paint()
              ..color = const Color(0xff477ad3)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1 / scale,
          );
        }
      }
    }
    final i = doc.selected;
    if (i != null && tool == CaptureTool.select && i < doc.marks.length) {
      final mark = doc.marks[i], center = doc.marks[i].bounds.center;
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(mark.angle);
      canvas.translate(-center.dx, -center.dy);
      canvas.drawRect(
        mark.bounds.inflate(5 / scale),
        Paint()
          ..color = const Color(0xff71a5ff)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1 / scale,
      );
      canvas.restore();
    }
    canvas.restore();
  }

  /// 标注可原地更新，每次更换绘制代理都重新绘制。
  @override
  bool shouldRepaint(covariant _CapturePainter oldDelegate) => true;
}
