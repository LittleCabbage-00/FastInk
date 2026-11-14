part of 'ink_canvas.dart';

class _LaserSample {
  /// 记录激光位置和时间戳，用于尾迹衰减。
  /// position：激光样本在当前画布中的逻辑像素坐标。
  /// createdAtMs：采样点创建的 Unix 毫秒时间，用于计算激光尾迹淡出。
  /// startsStroke：该激光样本是否开启一段新尾迹，防止跨手势误连线。
  const _LaserSample(
    this.position,
    this.createdAtMs, {
    this.startsStroke = false,
  });

  /// position：激光样本在当前画布中的逻辑像素坐标。
  final Offset position;

  /// createdAtMs：采样点创建的 Unix 毫秒时间，用于计算激光尾迹淡出。
  final int createdAtMs;

  /// startsStroke：该激光样本是否开启一段新尾迹，防止跨手势误连线。
  final bool startsStroke;
}

class _LaserPainter extends CustomPainter {
  /// 接收激光采样及衰减参数，用于当前帧绘制。
  /// samples：仍需显示的激光样本，不写入文稿笔迹文件。
  /// mode：激光点或多段尾迹显示模式。
  /// 绘制颜色。
  /// width：激光显示线宽，单位画布逻辑像素。
  /// nowMs：本次绘制的 Unix 毫秒时间，整帧统一用于尾迹透明度计算。
  /// fadeMs：样本从出现到消失的时长，单位毫秒。
  const _LaserPainter({
    required this.samples,
    required this.mode,
    required this.color,
    required this.width,
    required this.nowMs,
    required this.fadeMs,
  });

  /// samples：仍需显示的激光样本，不写入文稿笔迹文件。
  final List<_LaserSample> samples;

  /// mode：激光点或多段尾迹显示模式。
  final LaserMode mode;

  /// 绘制颜色。
  final Color color;

  /// width：激光显示线宽，单位画布逻辑像素。
  final double width;

  /// nowMs：本次绘制的 Unix 毫秒时间，整帧统一用于尾迹透明度计算。
  final int nowMs;

  /// fadeMs：样本从出现到消失的时长，单位毫秒。
  final int fadeMs;

  /// 根据当前时间与样本创建时刻计算透明度，超过 fadeMs 的样本不再可见。
  double _opacity(_LaserSample sample) =>
      (1 - (nowMs - sample.createdAtMs) / fadeMs).clamp(0.0, 1.0);

  /// 按当前时间绘制尚未过期的点或多段尾迹，跨笔画样本不连线，透明度仅影响临时显示。
  @override
  void paint(Canvas canvas, Size size) {
    if (samples.isEmpty) return;
    if (mode == LaserMode.dot) {
      final Offset point = samples.last.position;
      canvas.drawCircle(
        point,
        width * 1.55,
        Paint()
          ..color = color.withValues(alpha: 0.22)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      );
      canvas.drawCircle(point, width, Paint()..color = color);
      canvas.drawCircle(
        point - Offset(width * 0.22, width * 0.22),
        math.max(1.2, width * 0.24),
        Paint()..color = Colors.white.withValues(alpha: 0.82),
      );
      return;
    }

    final Paint glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = width * 2.1
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    final Paint core = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = width;
    if (samples.length == 1) {
      final double opacity = _opacity(samples.first);
      canvas.drawCircle(
        samples.first.position,
        width / 2,
        Paint()..color = color.withValues(alpha: opacity),
      );
      return;
    }
    // 各线段按生成时间淡出，形成移动尾迹。
    for (int index = 1; index < samples.length; index++) {
      final _LaserSample from = samples[index - 1];
      final _LaserSample to = samples[index];
      if (to.startsStroke) continue;
      final double opacity = (_opacity(from) + _opacity(to)) / 2;
      if (opacity <= 0) continue;
      glow.color = color.withValues(alpha: opacity * 0.20);
      core.color = color.withValues(alpha: opacity);
      canvas.drawLine(from.position, to.position, glow);
      canvas.drawLine(from.position, to.position, core);
    }
  }

  /// 激光位置、样式和当前时间变化时重新计算尾迹。
  @override
  bool shouldRepaint(covariant _LaserPainter oldDelegate) =>
      oldDelegate.nowMs != nowMs ||
      oldDelegate.samples != samples ||
      oldDelegate.mode != mode ||
      oldDelegate.color != color ||
      oldDelegate.width != width ||
      oldDelegate.fadeMs != fadeMs;
}
