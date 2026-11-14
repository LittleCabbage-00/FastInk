import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';

/// 只调整屏幕缓存与装饰动画，不更改笔迹采样、压力、保存或导出精度。
class RenderPowerPolicy {
  /// 将当前 Windows 供电状态映射到渲染档位。
  /// onBattery：是否检测到电池供电，无电池设备与未知 AC 状态由解析规则单独处理。
  /// saver：Windows 系统节电模式标志，与是否接入电源不是同一件事。
  const RenderPowerPolicy({this.onBattery = false, this.saver = false});

  /// Windows 原始状态统一解码，无电池设备不误判为电池供电。
  factory RenderPowerPolicy.fromWindowsStatus({
    required int acLineStatus,
    required int batteryFlag,
    required int systemStatusFlag,
  }) => RenderPowerPolicy(
    onBattery:
        acLineStatus == 0 && (batteryFlag == 255 || (batteryFlag & 128) == 0),
    saver: systemStatusFlag == 1,
  );

  /// onBattery：是否检测到电池供电，无电池设备与未知 AC 状态由解析规则单独处理；saver：Windows 系统节电模式标志，与是否接入电源不是同一件事。
  final bool onBattery, saver;

  /// economical：是否使用经济显示策略，仅影响缓存和显示路径。
  bool get economical => onBattery || saver;

  /// 返回当前页屏幕底图解码宽度预算，电池/节电为 1600 像素，电源为 2600 像素。
  int get pageWidth => economical ? 1600 : 2600;

  /// 返回经济模式当前页最大解码高度 2400 像素；普通模式返回 null，不额外限制高度。
  int? get pageHeight => economical ? 2400 : null;

  /// previewWidth：邻页屏幕预览的最大解码宽度，单位像素；经济策略为 800，电源策略为 1800，不是 Markdown 正文排版宽度。
  int get previewWidth => economical ? 800 : 1800;

  /// 返回经济模式显示栅格密度上限 2；普通模式不额外限密度，原笔迹采样不变。
  double get rasterDensity => economical ? 2 : double.infinity;
}

final class _SystemPowerStatus extends ffi.Struct {
  /// ac：Windows SYSTEM_POWER_STATUS 的 AC 状态字节，0 离线、1 在线、255 未知。
  @ffi.Uint8()
  external int ac;

  /// flags：Windows 电池状态位掩码，128 表示无系统电池、255 表示未知。
  @ffi.Uint8()
  external int flags;

  /// percent：Windows 报告的电池百分比字节，255 代表未知而非 255%。
  @ffi.Uint8()
  external int percent;

  /// saver：Windows 系统节电模式标志，与是否接入电源不是同一件事。
  @ffi.Uint8()
  external int saver;

  /// life：Windows 估算的剩余电池寿命，单位秒，未知时使用原生哨兵值。
  @ffi.Uint32()
  external int life;

  /// fullLife：Windows 估算的满电寿命，单位秒，未知时使用原生哨兵值。
  @ffi.Uint32()
  external int fullLife;
}

/// 每两秒只读一次 Windows 电源状态，拔插电源后尽快切换显示策略。
/// 不调用外部程序，也不修改电源计划。
class RenderPowerMonitor extends ValueNotifier<RenderPowerPolicy> {
  /// 建立进程共享的供电策略通知器，初始普通策略，实际状态由轮询更新。
  RenderPowerMonitor._() : super(const RenderPowerPolicy());

  /// instance：进程共享的供电状态通知器，由活动应用客户端共同持有。
  static final instance = RenderPowerMonitor._();

  /// _timer：每两秒查询供电状态的周期计时器；首个客户端启动，最后一个客户端停止时取消并置空。
  Timer? _timer;

  /// _clients：供电监测使用者计数；首个客户端启动轮询，全部停止后取消计时器。
  int _clients = 0;

  /// 增加使用者计数，首个真实应用客户端启动 Windows 供电查询；测试环境不创建周期轮询。
  void start() {
    if (_clients++ > 0 || Platform.environment.containsKey('FLUTTER_TEST')) {
      return;
    }
    _poll();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _poll());
  }

  /// 减少使用者计数，最后一个客户端离开时取消供电查询计时器。
  void stop() {
    if (--_clients <= 0) {
      _clients = 0;
      _timer?.cancel();
      _timer = null;
    }
  }

  /// 读取 Windows AC、电池和节电状态并在变化时通知，查询失败保留当前策略，原生结构内存始终释放。
  void _poll() {
    if (!Platform.isWindows) return;
    final status = calloc<_SystemPowerStatus>();
    try {
      final read = ffi.DynamicLibrary.open('kernel32.dll')
          .lookupFunction<
            ffi.Int32 Function(ffi.Pointer<_SystemPowerStatus>),
            int Function(ffi.Pointer<_SystemPowerStatus>)
          >('GetSystemPowerStatus');
      if (read(status) == 0) return;
      final next = RenderPowerPolicy.fromWindowsStatus(
        acLineStatus: status.ref.ac,
        batteryFlag: status.ref.flags,
        systemStatusFlag: status.ref.saver,
      );
      if (next.onBattery != value.onBattery || next.saver != value.saver) {
        value = next;
      }
    } catch (_) {
      /* 电源信息不可用时保留当前策略，文稿操作继续工作。 */
    } finally {
      calloc.free(status);
    }
  }
}

/// 次要预览在电池模式下等待操作空隙；切回电源后不再额外等待。
/// 每次等待都复查任务归属，侧栏关闭、切页或退出后不继续启动读盘与渲染。
Future<bool> waitForPreviewTurn({
  required bool Function() active,
  required bool Function() busy,
}) async {
  while (active()) {
    if (!RenderPowerMonitor.instance.value.economical) return true;
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (!active()) return false;
    if (!RenderPowerMonitor.instance.value.economical || !busy()) return true;
  }
  return false;
}

/// 统一处理系统“减少动画”和电池模式，避免各个面板自行维护另一套开关。
bool reducedAppMotion(BuildContext context) =>
    RenderPowerMonitor.instance.value.economical ||
    MediaQuery.disableAnimationsOf(context);

/// 按系统减少动画与经济策略返回装饰动画时长，受抑制时返回零。
Duration appMotionDuration(BuildContext context, int milliseconds) =>
    reducedAppMotion(context)
    ? Duration.zero
    : Duration(milliseconds: milliseconds);

/// 受减少动画或经济策略约束时返回无动画样式，否则使用组件默认动画。
AnimationStyle? appMotionStyle(BuildContext context) =>
    reducedAppMotion(context) ? AnimationStyle.noAnimation : null;
