part of '../../app/fastink_app.dart';

/// 处理连续画布的单指速度估算和松手惯性。
extension _FastInkTouchPageFlow on _FastInkHomeState {
  /// 根据实际事件时间间隔估算并平滑手指平移速度，用于松手惯性而不是影响采样点。
  void _recordTouchPanVelocity(Offset delta, Duration timeStamp) {
    final Duration? previous = _touchPanLastMove;
    if (previous != null) {
      final int elapsedMs = (timeStamp - previous).inMilliseconds.clamp(1, 100);
      final Offset instant = delta * (1000 / elapsedMs);
      // 指数平滑过滤触摸采样抖动，同时保留松手前的真实方向。
      _touchPanVelocity = instant * 0.8 + _touchPanVelocity * 0.2;
    }
    _touchPanLastMove = timeStamp;
  }

  /// 判断释放速度与时间是否足以启动惯性，安排受文稿边界约束的相机运动，返回是否已接管。
  bool _coastTouchPan(Duration releaseTime) {
    final Duration? lastMove = _touchPanLastMove;
    if (!hasFreshTouchVelocity(lastMove: lastMove, releaseTime: releaseTime)) {
      return false;
    }
    if (_settings.touchInertiaStrength <= 0 ||
        _touchPanVelocity.distance < 40) {
      return false;
    }
    final Matrix4 begin = Matrix4.copy(_viewport.zoomController.value);
    final Matrix4 requested = Matrix4.copy(begin);
    requested[12] += touchPanCoastDistance(
      _touchPanVelocity.dx,
      _settings.touchInertiaStrength,
    );
    requested[13] += touchPanCoastDistance(
      _touchPanVelocity.dy,
      _settings.touchInertiaStrength,
    );
    final DocumentViewportLayout? layout = _viewport.documentViewportLayout;
    final Matrix4 end = layout == null
        ? _viewport.constrainZoom(requested, _settings.maximumZoom)
        : layout.constrainCamera(
            requested,
            maximumScale: _settings.maximumZoom,
          );
    if ((end[12] - begin[12]).abs() < 1 && (end[13] - begin[13]).abs() < 1) {
      return false;
    }
    // 回弹会修改同一个动画控制器的时长，普通惯性必须在每次启动前
    // 显式设置自己的时长，不能沿用上一次 155ms 的短回弹参数。
    _viewport.zoomReturnController.duration = touchPanCoastDuration(
      _touchPanVelocity.distance,
      _settings.touchInertiaStrength,
    );
    _viewport.zoomReturnAnimation = Matrix4Tween(begin: begin, end: end)
        .animate(
          CurvedAnimation(
            parent: _viewport.zoomReturnController,
            curve: Curves.easeOutSine,
          ),
        );
    _viewport.zoomReturnController.forward(from: 0);
    return true;
  }
}
