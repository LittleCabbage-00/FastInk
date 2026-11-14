part of 'ink_canvas.dart';

/// 统一文稿与截图的压力采样，当前事件优先，原生样本仅用于旧驱动回退。
double effectivePenPressure(
  PointerEvent event, {
  required bool enabled,
  required PressureCurve curve,
  required double sensitivity,
  double? Function(PointerEvent)? fallback,
}) {
  final native = fallback?.call(event);
  if (!enabled ||
      (event.kind != PointerDeviceKind.stylus &&
          event.kind != PointerDeviceKind.invertedStylus)) {
    return .72;
  }
  final range = event.pressureMax - event.pressureMin;
  final valid =
      range.isFinite &&
      range > 0 &&
      event.pressure.isFinite &&
      event.pressure >= event.pressureMin &&
      event.pressure <= event.pressureMax;
  final sample = valid ? (event.pressure - event.pressureMin) / range : null;
  // Flutter 未收到压力时会使用 1.0；此时优先用有效的原生后备值。
  final sentinel = event.pressure == 1 && event.pressureMax == 1;
  final raw =
      (sentinel ? null : sample) ??
      (native != null && native.isFinite ? native : null) ??
      sample ??
      .5;
  return mapPenPressure(raw, curve, sensitivity);
}

/// 将输入压力按灵敏度与曲线映射到受限有效范围，返回值供输入层保存到 InkPoint；显示和导出不能再次套用用户曲线。
double mapPenPressure(
  double rawPressure,
  PressureCurve curve,
  double sensitivity,
) {
  final double raw = rawPressure.clamp(0.05, 1.0);
  final double curved = switch (curve) {
    PressureCurve.linear => raw,
    PressureCurve.gentle => math.sqrt(raw),
    PressureCurve.firm => raw * raw,
  };
  final double response = sensitivity.clamp(0.5, 2.0);
  // 平方扩大灵敏度两端的差异，1.0 仍使用原曲线，满压力仍为 1。
  return math.pow(curved, 1 / (response * response)).toDouble();
}

/// 按有效压力返回笔宽倍率。设置示例和画布使用同一套笔型响应。
double penPressureWidthFactor(PenStyle style, double pressure) =>
    switch (style) {
      PenStyle.ball => 1.0,
      PenStyle.fountain => 0.20 + pressure * 1.35,
      PenStyle.brush => 0.10 + pressure * 1.85,
      PenStyle.pencil => 0.22 + pressure * 0.82,
    };
