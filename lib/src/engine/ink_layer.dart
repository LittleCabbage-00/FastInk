part of 'ink_canvas.dart';

/// 对屏幕笔迹层应用纸面主题，复用原笔迹绘制与缓存。
Widget _displayInk(Widget child, ColorFilter? filter) =>
    filter == null ? child : ColorFiltered(colorFilter: filter, child: child);

/// 只读的笔迹预览层：在 [child]（页面图像）之上叠加某一页的笔迹和图片。
///
/// 笔迹点和粗细都按页面归一化（见 [InkStroke.width]），整层先在
/// [sourceSize] 的尺度下绘制、再由画布矩阵缩到缩略图，所以任何缩略图尺寸
/// 下粗细都自动正确。[sourceSize] 只需要和页面同比例——它同时决定页面在
/// 预览框里的摆放矩形。为 null 表示布局尚未建立，此时原样返回 [child]。
///
/// [strokes] 的来源按页而定：当前页直接用 [InkController.strokes] 并传
/// [repaint] 实时刷新；其他页传侧栏缓存里的快照，那时不需要 repaint。
/// 正在书写的那一笔只有当前页有，通过 [live] 传入。
///
/// 已提交笔迹和活动笔迹分成两层绘制，且各自套 RepaintBoundary：否则每来
/// 一个采样点都要把整张缩略图和全部已提交笔迹重新光栅化一遍。主画布
/// [InkLayer] 同样是每层一个边界。
///
/// 用 [StackFit.passthrough] 而不是 expand，是让 Stack 跟着 [child] 的
/// 尺寸走。缩略图的外框要贴着页面图像，如果反过来让 Stack 撑满可用宽度，
/// 图像会被 letterbox，外框两侧多出一条空白。
class InkPreview extends StatelessWidget {
  /// 创建按原页面尺寸解释笔迹的只读缩略层，可复用渲染缓存和实时提交信号，不接收页面编辑输入。
  const InkPreview({
    super.key,
    required this.child,
    required this.sourceSize,
    required this.strokes,
    this.repaint,
    this.live,
    this.imagesBuilder,
    this.displayFilter,
    this.paperDark,
  });

  /// child：由当前组件包裹的子组件，布局、绘制或交互能力在外层补充。
  final Widget child;

  /// 预览笔迹的显示滤镜，底图和嵌入图片由调用方独立处理。
  final ColorFilter? displayFilter;

  /// 模板纸色明暗，为空时使用原墨色。
  final bool? paperDark;

  /// 笔迹绘制所参照的页面尺寸：决定页面在预览框里的摆放矩形，
  /// 必须和页面同比例（主画布用的那份布局尺寸即可）。
  final Size? sourceSize;

  /// 这一页已提交的笔迹。
  final List<InkStroke> strokes;

  /// 笔迹变化时通知重绘；静态快照传 null。
  final Listenable? repaint;

  /// 仅当前页：正在书写的那一笔从这里实时取。
  final InkController? live;

  /// 嵌入图片的图层构造器。
  ///
  /// 交给调用方是因为渲染图片要访问文件系统（dart:io），引擎层不该依赖它。
  /// 回调拿到的是页面在缩略图里的实际摆放矩形，按这个尺寸布局就能和笔迹对齐。
  final Widget Function(Rect pageRect)? imagesBuilder;

  /// 将静态笔迹、当前活动笔迹与图片对齐到同一预览矩形，避免底图等比缩放后笔迹仍按整个卡片拉伸。
  @override
  Widget build(BuildContext context) {
    final Size? source = sourceSize;
    if (source == null) return child;
    final InkController? liveController = live;
    final Widget Function(Rect)? images = imagesBuilder;
    return Stack(
      fit: StackFit.passthrough,
      children: <Widget>[
        child,
        if (images != null)
          Positioned.fill(child: IgnorePointer(child: _images(source, images))),
        // 覆盖层只负责显示，不参与命中测试，避免挡住缩略图的点击翻页。
        if (liveController != null)
          Positioned.fill(
            child: IgnorePointer(
              child: _displayInk(
                _images(
                  source,
                  (rect) => FittedBox(
                    fit: BoxFit.fill,
                    child: SizedBox(
                      width: source.width,
                      height: source.height,
                      child: _CommittedInkLayers(
                        controller: liveController,
                        strokes: strokes,
                        previewScale: rect.width / source.width,
                        paperDark: paperDark,
                      ),
                    ),
                  ),
                ),
                displayFilter,
              ),
            ),
          )
        else
          Positioned.fill(
            child: IgnorePointer(
              child: _displayInk(
                RepaintBoundary(
                  child: CustomPaint(
                    painter: _InkPreviewStrokesPainter(
                      strokes,
                      source,
                      repaint,
                      cache: liveController?._committedRenderCache,
                      paperDark: paperDark,
                    ),
                    isComplex: true,
                  ),
                ),
                displayFilter,
              ),
            ),
          ),
        if (liveController != null)
          Positioned.fill(
            child: IgnorePointer(
              child: _displayInk(
                RepaintBoundary(
                  child: CustomPaint(
                    painter: _InkPreviewActivePainter(
                      liveController,
                      source,
                      paperDark,
                    ),
                  ),
                ),
                displayFilter,
              ),
            ),
          ),
      ],
    );
  }

  /// 按原页面尺寸布局预览图片，再由显示矩形统一缩放，避免嵌入图片与笔迹错位。
  Widget _images(Size source, Widget Function(Rect) builder) => LayoutBuilder(
    builder: (BuildContext context, BoxConstraints constraints) {
      final Rect rect = _previewPageRect(constraints.biggest, source);
      if (rect.isEmpty) return const SizedBox.shrink();
      return Stack(
        children: <Widget>[
          Positioned(
            left: rect.left,
            top: rect.top,
            width: rect.width,
            height: rect.height,
            child: builder(rect),
          ),
        ],
      );
    },
  );
}

/// 页面在预览框里的实际摆放矩形，与 [BoxFit.contain] 一致。
///
/// 缩略图外框的比例和页面比例可能有细微出入，直接按宽度缩放会让笔迹相对
/// 纸面偏移，所以等比缩放后居中，和底层 [Image] 的摆放对齐。笔迹层和图片
/// 层都走这一个函数，保证两者不会错位。
Rect _previewPageRect(Size box, Size sourceSize) {
  if (box.isEmpty || sourceSize.isEmpty) return Rect.zero;
  final double scale = math.min(
    box.width / sourceSize.width,
    box.height / sourceSize.height,
  );
  if (!scale.isFinite || scale <= 0) return Rect.zero;
  final double width = sourceSize.width * scale;
  final double height = sourceSize.height * scale;
  return Rect.fromLTWH(
    (box.width - width) / 2,
    (box.height - height) / 2,
    width,
    height,
  );
}

/// 把画布变换到页面坐标系。返回 false 表示尺寸无效，调用方应跳过绘制。
bool _beginPreviewTransform(Canvas canvas, Size size, Size sourceSize) {
  final Rect rect = _previewPageRect(size, sourceSize);
  if (rect.isEmpty) return false;
  canvas
    ..save()
    ..translate(rect.left, rect.top)
    ..scale(rect.width / sourceSize.width);
  return true;
}

class _InkPreviewStrokesPainter extends CustomPainter {
  /// 建立静态缩略笔迹绘制代理，保存原页面尺寸与可选 Picture 缓存。
  _InkPreviewStrokesPainter(
    this.strokes,
    this.sourceSize,
    Listenable? repaint, {
    this.cache,
    this.paperDark,
  }) : super(repaint: repaint);

  /// strokes：当前对象持有的笔画集合，元素坐标和宽度遵循 InkStroke 数据约定。
  final List<InkStroke> strokes;

  /// sourceSize：原页面的逻辑尺寸，缩略图绘制需先按此尺寸解释坐标。
  final Size sourceSize;

  /// cache：可选的笔画渲染缓存，用于复用静态图形而非重复排版。
  final _InkStrokeRenderCache? cache;

  /// 静态缩略图使用的模板纸色明暗。
  final bool? paperDark;

  /// 按原页面尺寸解释归一化笔画，再映射到预览区域；静态与活动层使用各自更新信号。
  @override
  void paint(Canvas canvas, Size size) {
    if (!_beginPreviewTransform(canvas, size, sourceSize)) return;
    for (final InkStroke stroke in strokes) {
      final cached = cache;
      if (cached == null) {
        _paintBatchedInkStroke(
          canvas,
          sourceSize,
          stroke,
          color: _displayStrokeColor(stroke, paperDark),
        );
      } else {
        cached.paint(canvas, sourceSize, stroke, paperDark: paperDark);
      }
    }
    canvas.restore();
  }

  /// 笔迹快照、页面尺寸或纸色变化时重绘静态缩略图。
  @override
  bool shouldRepaint(covariant _InkPreviewStrokesPainter oldDelegate) =>
      !identical(oldDelegate.strokes, strokes) ||
      oldDelegate.sourceSize != sourceSize ||
      oldDelegate.paperDark != paperDark;
}

class _InkPreviewActivePainter extends CustomPainter {
  /// 订阅活动笔迹重绘，只预览未提交的当前笔画，不重建静态缩略内容。
  _InkPreviewActivePainter(this.controller, this.sourceSize, this.paperDark)
    : super(repaint: controller.activeRepaint);

  /// controller：该组件或绘制层使用的控制器，由构造方传入，具体内容遵循声明类型。
  final InkController controller;

  /// sourceSize：原页面的逻辑尺寸，缩略图绘制需先按此尺寸解释坐标。
  final Size sourceSize;

  /// 当前页活动笔迹的模板纸色明暗。
  final bool? paperDark;

  /// 按原页面尺寸解释归一化笔画，再映射到预览区域；静态与活动层使用各自更新信号。
  @override
  void paint(Canvas canvas, Size size) {
    final InkStroke? active = controller.activeStroke;
    if (active == null && !controller.isTextRelocating) return;
    if (!_beginPreviewTransform(canvas, size, sourceSize)) return;
    _paintTextRelocation(canvas, sourceSize, controller, paperDark);
    if (active != null && controller._activePathSize == sourceSize) {
      _paintActiveInkStroke(canvas, sourceSize, controller, active, paperDark);
    } else if (active != null) {
      _paintInkStroke(
        canvas,
        sourceSize,
        active,
        color: _displayStrokeColor(active, paperDark),
      );
    }
    canvas.restore();
  }

  /// 活动笔迹由监听信号刷新。切换控制器、尺寸或纸色时重新绘制。
  @override
  bool shouldRepaint(covariant _InkPreviewActivePainter oldDelegate) =>
      !identical(oldDelegate.controller, controller) ||
      oldDelegate.sourceSize != sourceSize ||
      oldDelegate.paperDark != paperDark;
}

class InkLayer extends StatefulWidget {
  /// 接收本页工具、输入策略和控制器，实例本身不持久保存文稿；采样与手势由对应 State 负责。
  const InkLayer({
    super.key,
    required this.controller,
    required this.tool,
    this.lassoShape = LassoShape.freehand,
    required this.color,
    required this.width,
    this.penStyle = PenStyle.fountain,
    this.shapeType = ShapeType.line,
    required this.eraserMode,
    required this.eraserSize,
    required this.momentaryTool,
    required this.enabled,
    required this.onDrawingChanged,
    required this.onPenButtonChanged,
    required this.onTextRequested,
    this.pressureEnabled = true,
    this.pressureSensitivity = 1.0,
    this.pressureCurve = PressureCurve.linear,
    this.stylusOnly = false,
    this.pressureForEvent,
    this.selectionHitRadius = 64,
    this.selectionPriority = true,
    this.retainCommittedLayers = true,
    this.primaryButtonTool = InkTool.lasso,
    this.secondaryButtonTool = InkTool.eraser,
    this.primaryButtonEraserMode,
    this.secondaryButtonEraserMode,
    this.laserMode = LaserMode.trail,
    this.laserColor = const Color(0xffff3b30),
    this.laserWidth = 7,
    this.laserFadeMs = 800,
    this.displayFilter,
    this.claimImageTouch,
    this.paperDark,
  });

  /// controller：该组件或绘制层使用的控制器，由构造方传入，具体内容遵循声明类型。
  final InkController controller;

  /// 纸面主题用于已提交和活动笔迹，选择控制柄仍使用自己的配色。
  final ColorFilter? displayFilter;

  /// 模板纸色明暗，决定已有中性笔迹的显示对比。
  final bool? paperDark;

  /// 请求宿主把已选图片上的手指交给对象变换，返回 false 时继续页面导航。
  final bool Function(int pointer)? claimImageTouch;

  /// tool：当前画布输入工具；与临时侧键工具共同决定本次手势的行为。
  final InkTool tool;

  /// lassoShape：自由套索或矩形套索的名称。
  final LassoShape lassoShape;

  /// 绘制颜色。
  final Color color;

  /// width：当前书写工具基准宽度，输入时与页面尺寸统一转换。
  final double width;

  /// penStyle：当前笔型枚举，决定有效压力对应的笔宽变化，不再次应用用户输入曲线。
  final PenStyle penStyle;

  /// shapeType：形状工具当前几何类型，影响拖动时生成的点列。
  final ShapeType shapeType;

  /// eraserMode：整笔擦除或局部擦除的名称。
  final EraserMode eraserMode;

  /// eraserSize：橡皮范围的逻辑像素半径，显示与命中使用同一参数。
  final double eraserSize;

  /// momentaryTool：按住侧键期间覆盖的临时工具，松开后不改动用户默认工具。
  final InkTool? momentaryTool;

  /// enabled：是否允许该组件接受当前操作；禁用不等于删除其显示内容。
  final bool enabled;

  /// onDrawingChanged：书写开始/结束状态变化通知，用于宿主协调交互。
  final ValueChanged<bool> onDrawingChanged;

  /// onPenButtonChanged：侧键状态回调，参数分别表示物理键编号与是否按下。
  final void Function(int button, bool pressed) onPenButtonChanged;

  /// onTextRequested：请求在页面归一化点位创建/编辑文字，并携带当前页面逻辑尺寸。
  final void Function(InkPoint point, Size size) onTextRequested;

  /// pressureEnabled：是否将触笔压力用于笔宽；鼠标输入不能污染该开关。
  final bool pressureEnabled;

  /// pressureSensitivity：输入时的压感响应倍率；形成有效压力点，修改偏好不追溯改写旧笔迹。
  final double pressureSensitivity;

  /// pressureCurve：压力映射曲线名称，用于笔迹宽度计算。
  final PressureCurve pressureCurve;

  /// stylusOnly：是否只接受触笔书写；鼠标选择等非书写操作仍按输入规则处理。
  final bool stylusOnly;

  /// 为旧版 Windows 启动器提供可选的原生笔压采样。
  final double? Function(PointerEvent event)? pressureForEvent;

  /// 旋转与缩放控制点的命中半径，单位为屏幕像素。
  final double selectionHitRadius;

  /// 选区控制柄是否优先于画笔接收指针事件。
  final bool selectionPriority;

  /// retainCommittedLayers：是否保留分块静态显示层，避免当前落笔迫使整页反复绘制。
  final bool retainCommittedLayers;

  /// 两个侧键位掩码对应的工具；由父组件传入，用于首个指针事件。
  final InkTool? primaryButtonTool;

  /// secondaryButtonTool：物理二键映射的临时工具，为空时不覆盖当前工具。
  final InkTool? secondaryButtonTool;

  /// primaryButtonEraserMode：物理一键临时橡皮模式；为空时沿用当前橡皮设置。
  final EraserMode? primaryButtonEraserMode;

  /// secondaryButtonEraserMode：物理二键临时橡皮模式；为空时沿用当前橡皮设置。
  final EraserMode? secondaryButtonEraserMode;

  /// laserMode：激光点或尾迹模式名称，激光不写入持久笔迹。
  final LaserMode laserMode;

  /// laserColor：激光显示颜色，使用 32 位 ARGB 保存。
  final Color laserColor;

  /// laserWidth：激光显示宽度，单位逻辑像素。
  final double laserWidth;

  /// laserFadeMs：激光尾迹保留时长，单位毫秒。
  final int laserFadeMs;

  /// 跟踪触笔采样、选择手势及激光尾迹。
  @override
  State<InkLayer> createState() => _InkLayerState();
}
