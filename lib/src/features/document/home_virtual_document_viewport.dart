part of '../../app/fastink_app.dart';

// ---------------------------------------------------------------------------
// 虚拟文档视口：将页面组件树与高频相机变换解耦。
//
// 核心思路：
// 1. 页面组件被收拢在一个"窗口容器"（SizedBox + Stack）内，只有窗口范围
//    内的页面才会被创建。窗口范围比屏幕大一屏（缓冲窗口），防止滚动到边界
//    时出现白闪或组件抖动。
// 2. 相机变换（缩放 + 平移）由 AnimatedBuilder 驱动一个 Transform 小组件，
//    每帧只更新矩阵的 4 个浮点数，不触发页面重建。
// 3. 只有当真正可见的页面范围（0.05 屏精度）越出当前缓冲窗口时，
//    才会重新计算窗口并 setState——这避免了在页边界附近来回滚动时的"抖动"：
//    小幅来回移动不会反复跨越窗口边界，所以组件树保持稳定。
// ---------------------------------------------------------------------------

typedef _DocumentPageBuilder =
    Widget Function(BuildContext context, int index, double viewScale);

/// 将页面树与高频相机变换分开。
///
/// 拖动和缩放时，AnimatedBuilder 只更新一个 Transform；页面组件仅在
/// 可见窗口跨过页面边界时重建。这样图片、笔迹层和浮层不会按帧 build。
class _VirtualDocumentViewport extends StatefulWidget {
  /// 接收虚拟视口的页面范围、相机及页面构建回调。
  /// layout：当前连续文稿的布局对象，包含同一坐标系的页面矩形与整体边界。
  /// camera：将文稿坐标映射到屏幕的相机矩阵通知器，高频平移只更新变换层。
  /// pageBuilder：按页索引和当前显示比例生成单页组件的回调，由宿主提供内容层。
  /// onCenteredPageChanged：视口中心跨入另一页时的回调，宿主据此防抖装载高清与笔迹。
  const _VirtualDocumentViewport({
    required this.layout,
    required this.camera,
    required this.pageBuilder,
    required this.onCenteredPageChanged,
  });

  /// layout：当前连续文稿的布局对象，包含同一坐标系的页面矩形与整体边界。
  final DocumentViewportLayout layout;

  /// camera：将文稿坐标映射到屏幕的相机矩阵通知器，高频平移只更新变换层。
  final TransformationController camera;

  /// pageBuilder：按页索引和当前显示比例生成单页组件的回调，由宿主提供内容层。
  final _DocumentPageBuilder pageBuilder;

  /// onCenteredPageChanged：视口中心跨入另一页时的回调，宿主据此防抖装载高清与笔迹。
  final ValueChanged<int> onCenteredPageChanged;

  /// 根据相机位置维护需要挂载的页面窗口。
  @override
  State<_VirtualDocumentViewport> createState() =>
      _VirtualDocumentViewportState();
}

class _VirtualDocumentViewportState extends State<_VirtualDocumentViewport> {
  /// _first：当前虚拟窗口包含的首个页面零基索引，不等同于视口中心页。
  int _first = 0;

  /// _last：当前虚拟窗口包含的最后页面零基索引，初始负值表示窗口未建立。
  int _last = -1;

  /// _centered：最近一次读相机时的中心页索引，用于仅在真正跨页后通知宿主。
  int _centered = -1;

  /// 读取初始相机建立缓冲窗口并订阅后续矩阵变化，避免首次创建整本文稿页面树。
  @override
  void initState() {
    super.initState();
    _readCamera(notify: false);
    widget.camera.addListener(_cameraChanged);
  }

  /// 相机或布局签名变化时重新计算窗口，替换相机前解除旧监听。
  @override
  void didUpdateWidget(covariant _VirtualDocumentViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.camera, widget.camera)) {
      oldWidget.camera.removeListener(_cameraChanged);
      widget.camera.addListener(_cameraChanged);
    }
    if (oldWidget.layout.signature != widget.layout.signature ||
        !identical(oldWidget.camera, widget.camera)) {
      _readCamera(notify: false);
    }
  }

  /// 相机通知入口，重新计算可见页和缓冲窗口；只在跨出缓冲范围时重建页面树。
  void _cameraChanged() => _readCamera(notify: true);

  /// 用小可见范围判断是否越出缓存窗口，必要时补一屏页面；仅页中心变化时通知装载目标，降低滚动重建频率。
  void _readCamera({required bool notify}) {
    // 相机把文稿坐标映射到屏幕；这里只读取，不改写页面点列。
    final Matrix4 matrix = widget.camera.value;

    // ---- 真正可见范围（0.05 屏精度）----
    // 用很小的 cacheScreens 来判断"屏幕上真的有哪些页面"。
    // 这个范围比缓冲窗口小得多，用来检测是否需要扩大窗口。
    final (int visibleFirst, int visibleLast) = widget.layout.visibleRange(
      matrix,
      cacheScreens: 0.05,
    );

    // ---- 缓冲窗口更新策略 ----
    // 当前真实可见页仍在缓冲窗口内时，只移动相机，不改页面树。跨出窗口
    // 后一次性在前后各补一屏，避免在页边界附近来回滚动造成组件抖动。
    //
    // 为什么这样防抖动？假设用户在第 5 页底部来回小幅滑动：
    // - 如果每次都按精确可见范围重建组件树，就会不停地 build/dispose 页面 6。
    // - 使用 1 屏缓冲后，页面 6 早就在树里了，来回滑动只移动 Transform。
    // - 只有当用户真正滑到页面 7 的位置时，才扩展窗口。
    // 只有真实可见页越出缓冲窗口才重建页面树，小幅滚动只更新 Transform。
    final bool needsWindow =
        !notify ||
        _last < _first ||
        visibleFirst < _first ||
        visibleLast > _last;
    // needsWindow 为 true 时用 1 屏缓冲重新计算窗口；否则保持现有窗口。
    final (int first, int last) = needsWindow
        ? widget.layout.visibleRange(matrix, cacheScreens: 1)
        : (_first, _last);
    final int centered = widget.layout.pageAtViewportCenter(matrix);
    // 范围变化与中心页变化分开，不能每次跨半页就重建整个窗口。
    final bool rangeChanged = first != _first || last != _last;
    // 只有中心页变更才通知宿主安排高清/笔迹装载。
    final bool centerChanged = centered != _centered;
    _first = first;
    _last = last;
    _centered = centered;
    if (notify && centerChanged) widget.onCenteredPageChanged(centered);
    if (notify && rangeChanged && mounted) setState(() {});
  }

  /// 解除当前相机监听后执行基类清理；相机由宿主持有，这里不能 dispose 共享控制器。
  @override
  void dispose() {
    widget.camera.removeListener(_cameraChanged);
    super.dispose();
  }

  /// 只为当前缓冲窗口创建页面子树，高频相机变化只改变外层 Transform，窗口跨界时才补建页面。
  @override
  Widget build(BuildContext context) {
    final double viewScale = widget.camera.value.getMaxScaleOnAxis();
    // 窗口高度 = 从第一个可见页顶部到最后一个可见页底部的距离。
    // 页面组件使用"窗口局部坐标"（相对于 windowTop），这样 Stack 可以
    // 只分配窗口高度而不是整个文档高度，大幅减少布局开销。
    // 缓冲窗口的文稿原点，页面改用相对它的局部坐标以避免巨高组件。
    final double windowTop = _last < _first
        ? 0
        : widget.layout.pages[_first].top;
    final double windowBottom = _last < _first
        ? widget.layout.viewport.height
        : widget.layout.pages[_last].bottom;
    // 实际组件只分配缓冲窗口高度，不分配整本数千页的总高度。
    final double windowHeight = math.max(1, windowBottom - windowTop);
    // pageWindow 作为 AnimatedBuilder.child 复用，相机逐帧变化不重复构建这些页面。
    final Widget pageWindow = SizedBox(
      width: widget.layout.viewport.width,
      height: windowHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          for (int index = _first; index <= _last; index++)
            Positioned.fromRect(
              rect: widget.layout.pages[index].translate(0, -windowTop),
              child: widget.pageBuilder(context, index, viewScale),
            ),
        ],
      ),
    );
    return ClipRect(
      child: OverflowBox(
        alignment: Alignment.topLeft,
        minWidth: widget.layout.viewport.width,
        maxWidth: widget.layout.viewport.width,
        minHeight: windowHeight,
        maxHeight: windowHeight,
        child: AnimatedBuilder(
          animation: widget.camera,
          child: pageWindow,
          builder: (BuildContext context, Widget? child) {
            // 窗口使用局部坐标，附加世界坐标原点后仍与全局相机完全一致。
            //
            // 变换推导：
            // 全局相机将"世界坐标"映射到"屏幕坐标"：screen = world * scale + camera[13]
            // 页面组件使用"窗口坐标"：windowY = worldY - windowTop
            // 要让"窗口坐标"正确映射到屏幕，需要：
            //   屏幕坐标换算：screen = (windowY + windowTop) * scale + camera[13]
            //         = windowY * scale + (windowTop * scale + camera[13])
            // 所以只需在 camera[13] 上加 windowTop * scale。
            // 复制相机再加窗口原点修正，不能原位改动共享矩阵导致下一帧累计平移。
            final Matrix4 transform = Matrix4.copy(widget.camera.value);
            transform[13] += windowTop * transform.getMaxScaleOnAxis();
            return Transform(
              transform: transform,
              alignment: Alignment.topLeft,
              transformHitTests: true,
              child: child,
            );
          },
        ),
      ),
    );
  }
}
