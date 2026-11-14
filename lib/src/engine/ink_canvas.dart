import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../models/models.dart';

part 'ink_controller_drawing.dart';
part 'ink_controller_editing.dart';
part 'ink_controller_selection.dart';
part 'ink_controller_transform.dart';
part 'ink_spatial_bounds.dart';
part 'ink_pressure_curve.dart';
part 'ink_layer.dart';
part 'ink_layer_state.dart';
part 'ink_laser.dart';
part 'ink_painters.dart';
part 'ink_stroke_render_cache.dart';
part 'ink_committed_layers.dart';
part 'ink_tile_cache.dart';
part 'ink_eraser_geometry.dart';
part 'ink_text_relocation.dart';

enum InkTool { pen, highlighter, eraser, lasso, shape, laser, text }

enum LassoShape { freehand, rectangle }

enum ShapeType { line, rectangle, ellipse, arrow, triangle, diamond }

enum EraserMode { stroke, point }

enum LaserMode { dot, trail }

enum PressureCurve { linear, gentle, firm }

enum SelectionTransform { move, scale, rotate }

/// 在指定缩略图尺寸内绘制静态笔迹；调用方负责背景、图片和画布裁切。
/// 缩略图生成后应缓存为位图，不能在资料库滚动时反复排版整页文字。
void paintInkThumbnail(Canvas canvas, Size size, List<InkStroke> strokes) {
  for (final stroke in strokes) {
    if (stroke.kind != StrokeKind.image) {
      _paintBatchedInkStroke(canvas, size, stroke);
    }
  }
}

/// _selectionPaddingScreen：选区边框额外留白，单位屏幕逻辑像素。
const double _selectionPaddingScreen = 4;

/// _selectionHandleRadiusScreen：选区把手半径，单位屏幕逻辑像素。
const double _selectionHandleRadiusScreen = 5;

/// _selectionRotateGapScreen：旋转柄与选区的间隔，单位屏幕逻辑像素。
const double _selectionRotateGapScreen = 22;

class InkController extends ChangeNotifier {
  /// 建立当前页笔迹、选区和历史控制器，onCommitted 只在完整内容变更提交后通知宿主保存。
  InkController({required this.onCommitted});

  /// onCommitted：完整笔迹或编辑事务提交后通知宿主的回调，用于标记脏页与安排保存。
  final VoidCallback onCommitted;

  /// strokes：当前对象持有的笔画集合，元素坐标和宽度遵循 InkStroke 数据约定。
  final List<InkStroke> strokes = <InkStroke>[];

  /// _undoHistory：可撤销的前后状态条目；新提交后清空重做分支。
  final List<_InkHistoryEntry> _undoHistory = <_InkHistoryEntry>[];

  /// _redoHistory：已撤销、尚可恢复的历史条目，执行新编辑后失效。
  final List<_InkHistoryEntry> _redoHistory = <_InkHistoryEntry>[];

  /// _historyTransactionStart：当前合并历史事务的起点快照，未开始时为 null。
  _InkHistorySnapshot? _historyTransactionStart;

  /// _historyTransactionPending：是否已准备一次事务但尚未产生有效改动。
  bool _historyTransactionPending = false;

  /// _historyPointTargets：事务中需要保存点列的目标笔画；只复制受影响对象，避免整页点列深拷贝。
  Set<InkStroke> _historyPointTargets = <InkStroke>{};

  /// _historyTransactionChanged：本次事务是否实际改变内容，空手势不生成历史条目。
  bool _historyTransactionChanged = false;

  /// _eraserBounds：橡皮命中用的笔画边界缓存，结构修改后需要作废。
  final _InkStrokeBoundsCache _eraserBounds = _InkStrokeBoundsCache();
  // 落笔只重绘活动笔迹层；工具栏和已保存笔迹不随采样点重绘。
  /// _committedRevision：已提交笔迹的版本通知，驱动静态显示层更新。
  final ValueNotifier<int> _committedRevision = ValueNotifier<int>(0);

  /// _activeRevision：活动笔迹增量版本，仅重绘当前落笔层。
  final ValueNotifier<int> _activeRevision = ValueNotifier<int>(0);

  /// _selectionRevision：选区和变换版本，驱动选框及选择相关显示。
  final ValueNotifier<int> _selectionRevision = ValueNotifier<int>(0);

  /// selectedStrokes：当前选中的笔画对象集合，以对象身份关联历史和显示缓存。
  final Set<InkStroke> selectedStrokes = <InkStroke>{};

  /// lassoPoints：正在采集的套索点列，结束或取消选择时清空。
  final List<InkPoint> lassoPoints = <InkPoint>[];

  /// _rectangularLasso：本次选区是否按矩形解释，而不是按自由闭合点列解释。
  bool _rectangularLasso = false;

  /// eraseHighlighterOnly：是否只让橡皮命中荧光笔，其他笔画保持不变。
  bool eraseHighlighterOnly = false;

  /// selectHandwriting：套索是否纳入普通手写笔画。
  bool selectHandwriting = true;

  /// selectHighlighter：套索是否纳入荧光笔画。
  bool selectHighlighter = true;

  /// selectText：套索是否纳入文字对象。
  bool selectText = true;

  /// selectImages：套索是否纳入嵌入图片。
  bool selectImages = true;

  /// 根据笔画类型应用手写、荧光笔、文字和图片的选择过滤开关。
  bool canSelectStroke(InkStroke stroke) => stroke.text != null
      ? selectText
      : stroke.kind == StrokeKind.image
      ? selectImages
      : stroke.kind == StrokeKind.highlighter
      ? selectHighlighter
      : selectHandwriting;

  /// _transformOrigin：选区变换前各笔画的点列，手势全过程以该原点计算，避免累计误差。
  final Map<InkStroke, List<InkPoint>> _transformOrigin =
      <InkStroke, List<InkPoint>>{};

  /// _transformStart：选区变换的起始归一化页面坐标。
  InkPoint? _transformStart;

  /// _transformBounds：变换开始时的选区边界，用于固定旋转中心与缩放基准。
  Rect? _transformBounds;

  /// _selectionTransform：当前拖动是平移、缩放还是旋转；没有变换时为 null。
  SelectionTransform? _selectionTransform;

  /// _selectionChangedDuringDrag：拖动过程中是否有有效几何变化，结束时决定是否提交历史。
  bool _selectionChangedDuringDrag = false;

  /// _transformStartAngle：旋转手势起始角度，单位弧度。
  double _transformStartAngle = 0;

  /// activeStroke：尚未提交的当前笔画；结束后移入已提交集合并清空。
  InkStroke? activeStroke;

  /// _relocatingText：只在屏幕上执行定位动画的文本对象，持久数据已处于最终位置。
  InkStroke? _relocatingText;

  /// _relocationFrom：文本定位动画的起始四角点列，不作为最终保存坐标。
  List<InkPoint> _relocationFrom = const [];

  /// _relocationBackground：定位动画期间的静态背景笔画快照，排除正在运动的文本避免双重显示。
  List<InkStroke>? _relocationBackground;

  /// _relocationProgress：文本定位动画进度，范围 0–1，只影响屏幕插值。
  double _relocationProgress = 0;

  /// 判断文本是否正在执行仅影响屏幕的定位动画。
  bool get isTextRelocating => _relocatingText != null;

  /// 返回文本定位动画进度 0–1，供测试验证中间帧。
  @visibleForTesting
  double get textRelocationProgress => _relocationProgress;

  /// 定位动画时返回排除移动文本的静态背景，否则返回当前持久笔画集合。
  List<InkStroke> get _displayStrokes => _relocationBackground ?? strokes;
  // 当前笔迹按压感宽度归入少量 Path。新采样只追加一条线段，避免一条
  // 长笔迹在第 n 个点到来时再次遍历前 n-1 个点而形成 O(n²) 开销。
  /// _activePaths：当前长笔画按宽度分桶的增量 Path，避免每个采样点重算整条路径。
  final Map<int, Path> _activePaths = <int, Path>{};

  /// _committedRenderCache：静态笔画的 Picture 与边界缓存，编辑后按对象失效。
  final _InkStrokeRenderCache _committedRenderCache = _InkStrokeRenderCache();

  /// _tileCache：按空间分块保存的显示缓存；清理时需要释放持有的 GPU 图像。
  final _InkTileCache _tileCache = _InkTileCache();

  /// _viewRevision：相机可见区域或栅格密度变化的版本，只通知依赖视口的显示层。
  final ValueNotifier<int> _viewRevision = ValueNotifier<int>(0);

  /// _visiblePageRect：当前可见页面区域，使用页面逻辑坐标并按瓦片边界取整。
  Rect? _visiblePageRect;

  /// _rasterViewScale：当前屏幕瓦片的栅格密度，综合视图比例、设备像素比与预算。
  double _rasterViewScale = 1;

  /// _economicalRendering：是否启用经济显示策略，不改变采样和持久笔迹。
  bool _economicalRendering = false;

  /// _viewActivity：记录最近相机活动的计时器，后台缓存等待导航空隙后再生成。
  final Stopwatch _viewActivity = Stopwatch();

  /// 按当前栅格密度与经济策略计算空间瓦片逻辑边长。
  double get _tileExtent =>
      _inkTileExtent(_rasterViewScale, economical: _economicalRendering);

  /// 电池模式逐块生成缓存，并让连续拖动、缩放和落笔优先使用渲染线程。
  /// 等待时保留已有位图或矢量显示，既不冻结输入，也不改写原始点列。
  Future<bool> _waitForRasterTurn(bool Function() isCurrent) async {
    if (!_economicalRendering) return isCurrent();
    do {
      await Future<void>.delayed(const Duration(milliseconds: 16));
      if (!isCurrent()) return false;
    } while (_economicalRendering &&
        (isInteracting ||
            (_viewActivity.isRunning &&
                _viewActivity.elapsedMilliseconds < 100)));
    return true;
  }

  /// 接收页面可见矩形、缩放与设备像素比；按瓦片边界合并视口变化，只在区域或密度改变时通知缓存层。
  /// maxRasterDensity 限制显示密度，economical 只改变显示预算；原始采样点与导出精度不受影响。
  void updateView({
    required Rect? visibleRect,
    required double scale,
    double pixelRatio = 1,
    double maxRasterDensity = double.infinity,
    bool economical = false,
  }) {
    _viewActivity
      ..reset()
      ..start();
    final policyChanged = _economicalRendering != economical;
    _economicalRendering = economical;
    final density = _inkRasterDensity(
      math.min(scale * pixelRatio, maxRasterDensity),
    );
    final cell = _inkTileExtent(density, economical: economical);
    final region = visibleRect == null
        ? null
        : Rect.fromLTRB(
            (visibleRect.left / cell).floor() * cell,
            (visibleRect.top / cell).floor() * cell,
            (visibleRect.right / cell).ceil() * cell,
            (visibleRect.bottom / cell).ceil() * cell,
          );
    if (!policyChanged &&
        _visiblePageRect == region &&
        _rasterViewScale == density) {
      return;
    }
    _visiblePageRect = region;
    _rasterViewScale = density;
    _viewRevision.value++;
  }

  /// 判断是否正在落笔、套索、变换、历史事务或文本定位，用于让后台栅格任务避开交互。
  bool get isInteracting =>
      isTextRelocating ||
      activeStroke != null ||
      _historyTransactionPending ||
      _historyTransactionStart != null ||
      _selectionTransform != null ||
      lassoPoints.isNotEmpty;

  /// 返回当前已持有的栅格瓦片数量，供内存与合成开销测试。
  @visibleForTesting
  int get debugRasterTileCount => _tileCache._images.length;

  /// 返回栅格缓存估算占用字节数，不包含全部应用内存。
  @visibleForTesting
  int get debugRasterBytes => _tileCache._bytes;

  /// 返回已完成的瓦片光栅准备次数，供测试验证重复工作是否减少。
  @visibleForTesting
  int get debugRasterPrepareCount => _tileCache.preparedCount;

  /// 读取或设置笔迹屏幕瓦片缓存预算，单位 MB；调整预算不会删除持久笔迹。
  int get rasterCacheMegabytes => _tileCache.limitBytes ~/ (1024 * 1024);

  /// 读取或设置笔迹屏幕瓦片缓存预算，单位 MB；调整预算不会删除持久笔迹。
  set rasterCacheMegabytes(int value) => _tileCache.setBudget(value);

  /// _debugCommittedPaintCount：测试统计的静态绘制次数，不用于业务状态判断。
  int _debugCommittedPaintCount = 0;

  /// 返回静态绘制累计次数，供基准测试比较不同显示策略。
  @visibleForTesting
  int get debugCommittedPaintCount => _debugCommittedPaintCount;

  /// _activePathSize：活动 Path 建立时使用的页面尺寸，尺寸变化时路径需要重建。
  Size _activePathSize = Size.zero;

  /// _activePathStroke：活动 Path 当前关联的笔画对象。
  InkStroke? _activePathStroke;

  /// _activePathPointCount：已纳入增量 Path 的采样点数量，下一次只追加新增线段。
  int _activePathPointCount = 0;

  /// _activePathLastPoint：增量路径最后已绘制的采样点，用于连接新段。
  InkPoint? _activePathLastPoint;

  /// _shapeStart：形状手势起始点，后续几何始终相对它计算。
  InkPoint? _shapeStart;

  /// _shapeCanvasSize：形状生成的页面逻辑尺寸，用于换算归一化坐标和角度。
  Size _shapeCanvasSize = const Size(1, 1);

  /// _selectionViewScale：选区控件使用的当前视图倍数，保证把手和操作条维持屏幕尺寸。
  double _selectionViewScale = 1;

  /// 判断当前页是否有可撤销的完整编辑条目。
  bool get canUndo => _undoHistory.isNotEmpty;

  /// 判断撤销分支是否还存在可恢复条目。
  bool get canRedo => _redoHistory.isNotEmpty;

  /// 判断是否存在选中笔画，不以选框的屏幕可见性代替选择状态。
  bool get hasSelection => selectedStrokes.isNotEmpty;

  /// 读取或更新选择控件使用的视图倍率，使边框留白和把手保持固定屏幕尺寸。
  double get selectionViewScale => _selectionViewScale;

  /// 返回菜单需避开的上侧旋转把手空间，单位屏幕逻辑像素。
  double get selectionMenuTopClearanceScreen =>
      _selectionPaddingScreen +
      _selectionRotateGapScreen +
      _selectionHandleRadiusScreen;

  /// 返回菜单需避开的下侧选择把手空间，单位屏幕逻辑像素。
  double get selectionMenuBottomClearanceScreen =>
      _selectionPaddingScreen + _selectionHandleRadiusScreen;

  /// 读取或更新选择控件使用的视图倍率，使边框留白和把手保持固定屏幕尺寸。
  set selectionViewScale(double value) {
    final double next = value.clamp(1.0, 8.0);
    if ((next - _selectionViewScale).abs() < 0.001) return;
    _selectionViewScale = next;
    if (hasSelection) _selectionChanged(notifyToolbar: false);
  }

  /// 仅当选中对象恰好可作为单个文本编辑时返回该文本笔画，否则返回 null。
  InkStroke? get selectedTextStroke {
    if (selectedStrokes.length != 1) return null;
    final InkStroke stroke = selectedStrokes.first;
    return stroke.text == null ? null : stroke;
  }

  /// 提供已提交笔迹的局部重绘信号，避免活动点刷新重绘整页。
  Listenable get committedRepaint => _committedRevision;

  /// 提供当前未提交笔画的增量重绘信号。
  Listenable get activeRepaint => _activeRevision;

  /// 提供选择边框、套索和变换的局部重绘信号。
  Listenable get selectionRepaint => _selectionRevision;

  /// 计算选中笔画的归一化联合边界；未选中时返回 null。
  Rect? get selectionBounds {
    if (selectedStrokes.isEmpty) return null;
    double left = 1;
    double top = 1;
    double right = 0;
    double bottom = 0;
    for (final InkStroke stroke in selectedStrokes) {
      if (stroke.points.isEmpty) continue;
      final box = _eraserBounds.bounds(stroke);
      left = math.min(left, box.left);
      top = math.min(top, box.top);
      right = math.max(right, box.right);
      bottom = math.max(bottom, box.bottom);
    }
    return Rect.fromLTRB(left, top, right, bottom);
  }

  /// 按给定页面尺寸获取占用矩形，支持排除正在编辑的文字，供文本避让使用。
  List<Rect> contentBounds(Size size, {InkStroke? excluding}) => [
    for (final stroke in strokes)
      if (stroke != excluding && stroke.points.isNotEmpty)
        Rect.fromLTRB(
          _eraserBounds.bounds(stroke).left * size.width,
          _eraserBounds.bounds(stroke).top * size.height,
          _eraserBounds.bounds(stroke).right * size.width,
          _eraserBounds.bounds(stroke).bottom * size.height,
        ).inflate(
          stroke.text != null || stroke.kind == StrokeKind.image
              ? 4
              : math.max(4, inkPixelWidth(stroke.width, size) / 2 + 2),
        ),
  ];

  /// 作废受影响的静态显示缓存并递增提交版本；非追加编辑需清理空间索引，最后通知工具栏与宿主。
  void _committedChanged({bool appendOnly = false}) {
    // 后续编辑、撤销、翻页接管控制；定位动画不阻塞实际操作。
    finishTextRelocation();
    if (!appendOnly) {
      _committedRenderCache.clear();
      _tileCache.clear();
      _eraserBounds.clear();
    }
    _committedRevision.value++;
    notifyListeners();
  }

  /// 只递增活动笔迹版本，让新增采样点局部重绘，不广播整页状态。
  void _activeChanged() => _activeRevision.value++;

  /// 清空当前笔画的增量路径、尺寸与点数计数，下一笔从头建立。
  void _clearActivePathCache() {
    _activePaths.clear();
    _activePathSize = Size.zero;
    _activePathStroke = null;
    _activePathPointCount = 0;
    _activePathLastPoint = null;
  }

  /// 递增选区版本；notifyToolbar 为 false 时只更新显示，不重建宿主工具栏。
  void _selectionChanged({bool notifyToolbar = true}) {
    _selectionRevision.value++;
    if (notifyToolbar) notifyListeners();
  }

  /// 建立历史快照；只深存需要变换的点列，其他笔画按结构列表复用，降低密集文稿的复制开销。
  _InkHistorySnapshot _captureHistory([
    Iterable<InkStroke> pointTargets = const <InkStroke>[],
  ]) => _InkHistorySnapshot(
    // 结构编辑保存笔画列表；变换只保存选中点列，拖动时无需逐帧复制整页。
    strokes: List<InkStroke>.of(strokes),
    points: <InkStroke, List<InkPoint>>{
      for (final InkStroke stroke in pointTargets)
        stroke: List<InkPoint>.of(stroke.points),
    },
  );

  /// 将修改前后快照压入撤销栈并清空旧重做分支。
  void _pushHistory(_InkHistorySnapshot before, _InkHistorySnapshot after) {
    _undoHistory.add(_InkHistoryEntry(before: before, after: after));
    if (_undoHistory.length > 80) _undoHistory.removeAt(0);
    _redoHistory.clear();
  }

  /// 比较事务前后状态，确有变动才生成一个历史条目并触发提交。
  void _commitHistoryChange(_InkHistorySnapshot before) {
    if (_historyTransactionPending) {
      _historyTransactionStart = before;
      _historyTransactionPending = false;
      _historyTransactionChanged = true;
      return;
    }
    if (_historyTransactionStart != null) {
      _historyTransactionChanged = true;
      return;
    }
    _pushHistory(before, _captureHistory(before.points.keys));
  }

  /// 合并一整次连续手势的历史，按需记录会被原位修改的点列，避免每个输入事件复制整页。
  void beginHistoryTransaction({
    bool captureSelectedPoints = false,
    bool deferSnapshot = false,
  }) {
    if (_historyTransactionStart != null || _historyTransactionPending) return;
    _historyPointTargets = captureSelectedPoints
        ? Set<InkStroke>.of(selectedStrokes)
        : <InkStroke>{};
    _historyTransactionPending = deferSnapshot;
    _historyTransactionStart = deferSnapshot
        ? null
        : _captureHistory(_historyPointTargets);
    _historyTransactionChanged = false;
  }

  /// 结束事务；commit 决定保存或还原，返回是否产生有效内容变化。
  bool finishHistoryTransaction({bool commit = true}) {
    // 一次落笔对应一条撤销记录，移动和擦除采样不单独入栈。
    final _InkHistorySnapshot? before = _historyTransactionStart;
    final bool changed = before != null && commit && _historyTransactionChanged;
    if (changed) {
      _pushHistory(before, _captureHistory(_historyPointTargets));
    }
    _historyTransactionStart = null;
    _historyTransactionPending = false;
    _historyPointTargets = <InkStroke>{};
    _historyTransactionChanged = false;
    if (changed) notifyListeners();
    return changed;
  }

  /// 结束一整次擦除手势并统一提交/取消历史，避免一个采样点形成一条撤销记录。
  void finishEraseGesture({bool commit = true}) {
    if (finishHistoryTransaction(commit: commit)) onCommitted();
  }

  /// 恢复快照的笔画结构与点列并清理旧选区/缓存，历史恢复也必须触发显示更新。
  void _restoreHistory(_InkHistorySnapshot snapshot) {
    strokes
      ..clear()
      ..addAll(snapshot.strokes);
    for (final MapEntry<InkStroke, List<InkPoint>> entry
        in snapshot.points.entries) {
      entry.key.points
        ..clear()
        ..addAll(entry.value);
    }
    activeStroke = null;
    selectedStrokes.clear();
    lassoPoints.clear();
    _committedRenderCache.invalidate(snapshot.points.keys);
    for (final stroke in snapshot.points.keys) {
      _eraserBounds.remove(stroke);
    }
    _committedChanged(appendOnly: true);
    _activeChanged();
    _selectionChanged();
    onCommitted();
  }

  /// 用另一页的笔画替换当前内容并清理本页历史及显示缓存，不能把跨页载入当成可撤销编辑。
  void replace(List<InkStroke> value) {
    strokes
      ..clear()
      ..addAll(value);
    _undoHistory.clear();
    _redoHistory.clear();
    finishHistoryTransaction(commit: false);
    activeStroke = null;
    _clearActivePathCache();
    selectedStrokes.clear();
    lassoPoints.clear();
    _committedChanged();
    _activeChanged();
    _selectionChanged();
  }

  /// 释放活动笔迹路径、已提交笔迹的绘制缓存和各图层重绘信号。
  @override
  void dispose() {
    _clearActivePathCache();
    _committedRenderCache.clear();
    _tileCache.dispose();
    _viewRevision.dispose();
    _committedRevision.dispose();
    _activeRevision.dispose();
    _selectionRevision.dispose();
    super.dispose();
  }
}

class _InkHistorySnapshot {
  /// 保存某时刻的笔画结构与必要点列；供事务撤销使用，不包含 UI 控制器。
  const _InkHistorySnapshot({required this.strokes, required this.points});

  /// strokes：当前对象持有的笔画集合，元素坐标和宽度遵循 InkStroke 数据约定。
  final List<InkStroke> strokes;

  /// points：历史快照按笔画对象保存的原点列，恢复时不依赖被变换后的点。
  final Map<InkStroke, List<InkPoint>> points;
}

class _InkHistoryEntry {
  /// 将操作前后快照配成一个完整历史条目。
  const _InkHistoryEntry({required this.before, required this.after});

  /// before：本条历史操作的修改前快照。
  final _InkHistorySnapshot before;

  /// after：本条历史操作的修改后快照。
  final _InkHistorySnapshot after;
}
