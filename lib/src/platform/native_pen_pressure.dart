import 'package:flutter/gestures.dart';

/// 为未提供 Flutter 笔压的 Windows 启动器提供兼容采样。
///
/// Windows 指针 ID、Flutter 设备 ID 和接触 ID 属于不同
/// 命名空间；活动笔只使用最新原生采样，绝不按
/// [PointerEvent.pointer] 查找。采样会过期，不能无限沿用到
/// 后续接触；鼠标输入绝不继承笔的压力。
class NativePenPressure {
  /// 建立原生压力时效桥，可注入单调时间函数以便确定性测试。
  NativePenPressure({this.now});

  /// maxAge：原生压力样本的最大可复用时限，超过 100 毫秒不再套用到新事件。
  static const Duration maxAge = Duration(milliseconds: 100);

  /// _clock：压力时效使用的单调计时器，不受系统墙钟调整影响。
  final Stopwatch _clock = Stopwatch()..start();

  /// now：可注入的单调时间来源，测试时用于确定性验证样本过期。
  final Duration Function()? now;

  /// _pressure：最近接收的原生压力；未接收或已清理时为空。
  double? _pressure;

  /// _receivedAt：最近原生压力样本的单调接收时刻，用于拒绝过期数据。
  Duration? _receivedAt;

  /// 优先读取测试注入的时间，否则使用本实例单调计时器。
  Duration get _time => now?.call() ?? _clock.elapsed;

  /// 保存原生压力和接收时间，供紧随其后的兼容触笔事件查询。
  void update(double pressure) {
    if (!pressure.isFinite || pressure <= 0 || pressure > 1) return;
    _pressure = pressure;
    _receivedAt = _time;
  }

  /// 只为匹配设备类型且尚未过期的触笔事件提供原生压力；鼠标或旧样本返回 null，交给事件自身压力处理。
  double? forEvent(PointerEvent event) {
    if (event.kind != PointerDeviceKind.stylus &&
        event.kind != PointerDeviceKind.invertedStylus) {
      if (event is PointerDownEvent) {
        _pressure = null;
        _receivedAt = null;
      }
      return null;
    }
    final Duration? received = _receivedAt;
    if (received == null) return null;
    final Duration age = _time - received;
    if (age.isNegative || age > maxAge) return null;
    return _pressure;
  }
}
