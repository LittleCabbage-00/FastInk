import 'package:flutter/material.dart';
import '../platform/render_power_policy.dart';

/// 资料库与编辑器之间的轻量导航过渡。
///
/// 始终只挂载当前界面，避免退场画布继续使用已释放的位图或共用控制器。
/// 动画帧只平移重绘边界，不截取整屏图片、不做整屏透明混合或重复布局。
class AppScreenTransition extends StatefulWidget {
  /// 创建不可变的 AppScreenTransition 参数对象；各参数保存在对应字段中，不在构造时执行外部读写。
  /// destination：当前顶层页面身份，变化时触发一次进入/返回过渡。
  /// returning：是否返回资料库，用于选择过渡平移方向，不决定数据保存。
  /// child：由当前组件包裹的子组件，布局、绘制或交互能力在外层补充。
  const AppScreenTransition({
    super.key,
    required this.destination,
    required this.returning,
    required this.child,
  });

  /// destination：当前顶层页面身份，变化时触发一次进入/返回过渡。
  final String destination;

  /// returning：是否返回资料库，用于选择过渡平移方向，不决定数据保存。
  final bool returning;

  /// child：由当前组件包裹的子组件，布局、绘制或交互能力在外层补充。
  final Widget child;

  @override
  State<AppScreenTransition> createState() => _AppScreenTransitionState();
}

class _AppScreenTransitionState extends State<AppScreenTransition>
    with SingleTickerProviderStateMixin {
  /// _controller：顶层导航动画控制器，只驱动变换层，不保留旧画布。
  late final _controller = AnimationController(vsync: this, value: 1);

  /// _distance：导航过渡的初始平移距离，单位屏幕逻辑像素，电池模式缩短。
  double _distance = 20;

  /// 根据系统减少动画与供电策略设置导航时长/位移，电池保留短方向反馈，禁用动画时立即结束。
  void _configureMotion() {
    final battery = RenderPowerMonitor.instance.value.economical;
    _distance = battery ? 12 : 20;
    // 导航需要保留方向反馈；电池模式缩短时长，系统减少动画时立即完成。
    _controller.duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : Duration(milliseconds: battery ? 120 : 180);
    if (_controller.duration == Duration.zero) _controller.value = 1;
  }

  /// 主题/MediaQuery 等环境变化后重新读取减少动画策略，不沿用旧窗口设置。
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _configureMotion();
  }

  /// 目标界面身份变化才重播过渡，同一编辑器状态更新只替换子内容，不生成重复导航动画。
  @override
  void didUpdateWidget(covariant AppScreenTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    _configureMotion();
    if (oldWidget.destination != widget.destination &&
        _controller.duration != Duration.zero) {
      _controller.forward(from: 0);
    }
  }

  /// 释放界面过渡动画的控制器，停止逐帧回调。
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 只挂载当前界面的子树并平移其重绘边界，不保留旧画布或创建全屏透明混合。
  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Theme.of(context).scaffoldBackgroundColor,
    child: ClipRect(
      child: AnimatedBuilder(
        animation: _controller,
        child: RepaintBoundary(child: widget.child),
        builder: (context, child) => Transform.translate(
          key: const ValueKey('screen-transition-offset'),
          offset: Offset(
            (widget.returning ? -1 : 1) *
                _distance *
                (1 - Curves.easeOutCubic.transform(_controller.value)),
            0,
          ),
          child: child,
        ),
      ),
    ),
  );
}
