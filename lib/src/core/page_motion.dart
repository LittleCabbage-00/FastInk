// ---------------------------------------------------------------------------
// 页面滚动运动模型。
//
// 本文件提供触摸惯性和滚轮意图识别的辅助函数。
//
// ## 惯性滑动物理模型
//
// 松手后页面继续滑动的距离由手指离开前的速度决定。这里使用"线性映射 + 夹紧"
// 而不是真正的物理模拟（匀减速/指数衰减），原因是：
// - 线性映射让距离与速度成正比，用户更容易预判停止位置。
// - 上限 1800px 防止一次快速甩动跨过太多页面。
// - 持续时间用 π/2 因子校正，使 easeOutSine 动画的起始速度与手指速度匹配。
//
// ## 速度新鲜度
//
// 松手前如果手指停顿超过 140ms，旧速度会被视为过期，防止已经停住的页面
// 在松手时突然继续滑动。
// ---------------------------------------------------------------------------

enum DocumentWheelIntent { verticalScroll, horizontalPan, zoom }

/// 键盘修饰键只决定滚轮意图，不改变普通滚轮的纵向滚动默认值。
DocumentWheelIntent documentWheelIntent({
  required bool controlPressed,
  required bool shiftPressed,
}) => controlPressed
    ? DocumentWheelIntent.zoom
    : shiftPressed
    ? DocumentWheelIntent.horizontalPan
    : DocumentWheelIntent.verticalScroll;

/// 两个平移轴共用惯性距离计算。
///
/// 距离与松手速度成正比，用户更容易预判停止位置；最大位移防止一次快速
/// 甩动跨过过多页面。持续时间单独计算，避免长距离仍在短时间内闪完。
///
/// 计算过程：
/// 1. 速度先夹到 [-5000, 5000] px/s，防止极端值（如调试器注入的超大速度）。
/// 2. 乘以 0.32 得到基础距离——经验值，使正常甩动约滑 200-600px。
/// 3. 乘以 strength（可配置的灵敏度因子，0-2），让不同场景微调惯性强度。
/// 4. 最终结果夹到 [-1800, 1800]，避免一次甩动跨过太多页面。
double touchPanCoastDistance(double velocityPixelsPerSecond, double strength) =>
    (velocityPixelsPerSecond.clamp(-5000, 5000) * 0.32 * strength.clamp(0, 2))
        .clamp(-1800.0, 1800.0);

/// 让 easeOutSine 动画的起始速度接近手指松开前的实际速度。
///
/// 数学推导：
/// easeOutSine(t) 在 t=0 时的导数为 π/2（归一化后）。
/// 动画总位移 = distance，总时长 = T 秒。
/// 起始速度 = distance * (π/2) / T。
/// 要让起始速度 ≈ speed（手指速度），则：
///   缓动时间：T = 距离 × (π/2) ÷ 速度，约为距离 × 1.5708 ÷ 速度。
///
/// 时长限制在 [260ms, 720ms]：太短看不出动画，太长感觉拖沓。
Duration touchPanCoastDuration(
  double velocityPixelsPerSecond,
  double strength,
) {
  final double speed = velocityPixelsPerSecond.abs().clamp(1, 5000);
  final double distance = touchPanCoastDistance(speed, strength).abs();
  // 1.5708 ≈ π/2，是 easeOutSine 在 t=0 处的归一化导数。
  final int milliseconds = (distance * 1.5708 / speed * 1000).round().clamp(
    260,
    720,
  );
  return Duration(milliseconds: milliseconds);
}

/// 松手前停顿会清除旧速度，避免用户已经停住页面却继续惯性滑动。
///
/// 判据：最后一次 move 事件距松手时间不超过 [maximumAge]（默认 140ms）。
/// - 如果手指还在快速移动时松开，lastMove 和 releaseTime 很接近 → 有效。
/// - 如果手指停住 200ms 后才松开，距离远超 140ms → 速度过期，不做惯性。
/// - 140ms 阈值是经验值：覆盖正常甩动的采样间隔（~16ms/帧），
///   又短于有意停顿（~200ms+）。
bool hasFreshTouchVelocity({
  required Duration? lastMove,
  required Duration releaseTime,
  Duration maximumAge = const Duration(milliseconds: 140),
}) => lastMove != null && releaseTime - lastMove <= maximumAge;
