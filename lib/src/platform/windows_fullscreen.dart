import 'dart:ffi' as ffi;
import 'dart:io';
import 'package:ffi/ffi.dart';

typedef _EnumWindow = ffi.Int32 Function(ffi.Pointer<ffi.Void>, ffi.IntPtr);

/// 保存并管理进入无边框全屏前的准确窗口位置与样式。
/// 无需修改原生启动器，也无需额外插件 DLL。
class WindowsFullscreen {
  /// 建立全屏桥，可显式指定目标窗口句柄；为空时只查找当前应用所属窗口。
  WindowsFullscreen({int? windowHandle}) : _explicitHandle = windowHandle;

  /// _explicitHandle：调用方指定的窗口句柄，为空时由桥查找当前应用窗口。
  final int? _explicitHandle;

  /// _user32：user32.dll 动态库引用，用于窗口样式与位置控制。
  late final _user32 = ffi.DynamicLibrary.open('user32.dll');

  /// _kernel32：kernel32.dll 动态库引用，用于进程/模块等系统查询。
  late final _kernel32 = ffi.DynamicLibrary.open('kernel32.dll');

  /// _window：当前全屏操作目标的原生窗口指针，尚未解析时为 nullptr。
  ffi.Pointer<ffi.Void> _window = ffi.nullptr;

  /// _placement：保存原窗口位置/状态的原生缓冲，恢复后由所属桥释放。
  ffi.Pointer<ffi.Uint8> _placement = ffi.nullptr;

  /// _style：进入全屏前保存的 Windows 窗口样式，退出时按原值恢复。
  int _style = 0;

  /// enabled：是否允许该组件接受当前操作；禁用不等于删除其显示内容。
  bool enabled = false;

  /// 返回本应用目标窗口地址，查找失败由平台入口明确报告。
  int get windowHandle => _findWindow().address;

  /// 根据目标布尔值进入或恢复全屏，避免同状态重复改写窗口。
  void setEnabled(bool value) {
    if (value == enabled) return;
    // 组件测试不得改变 flutter_tester 宿主窗口大小。
    if (_explicitHandle == null &&
        Platform.environment.containsKey('FLUTTER_TEST')) {
      enabled = value;
      return;
    }
    if (!Platform.isWindows) throw UnsupportedError('Windows fullscreen');
    if (value) {
      _enter();
    } else {
      _restore();
    }
    enabled = value;
  }

  /// 优先使用显式句柄，再识别当前进程所属窗口，不接管其他应用的前台窗口。
  ffi.Pointer<ffi.Void> _findWindow() {
    if (_explicitHandle != null) {
      return ffi.Pointer.fromAddress(_explicitHandle);
    }
    final getPid = _user32
        .lookupFunction<
          ffi.Uint32 Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Uint32>),
          int Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Uint32>)
        >('GetWindowThreadProcessId');
    final process = calloc<ffi.Uint32>();
    // 检查候选窗口是否归当前进程所有，过滤无关桌面窗口。
    bool own(ffi.Pointer<ffi.Void> window) {
      getPid(window, process);
      return process.value == pid;
    }

    try {
      final foreground = _user32
          .lookupFunction<
            ffi.Pointer<ffi.Void> Function(),
            ffi.Pointer<ffi.Void> Function()
          >('GetForegroundWindow')();
      if (foreground != ffi.nullptr && own(foreground)) return foreground;
      var found = ffi.nullptr.cast<ffi.Void>();
      final visible = _user32
          .lookupFunction<
            ffi.Int32 Function(ffi.Pointer<ffi.Void>),
            int Function(ffi.Pointer<ffi.Void>)
          >('IsWindowVisible');
      final owner = _user32
          .lookupFunction<
            ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Void>, ffi.Uint32),
            ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Void>, int)
          >('GetWindow');
      final callback = ffi.NativeCallable<_EnumWindow>.isolateLocal((
        ffi.Pointer<ffi.Void> window,
        int parameter,
      ) {
        if (own(window) &&
            visible(window) != 0 &&
            owner(window, 4) == ffi.nullptr) {
          found = window;
          return 0;
        }
        return 1;
      }, exceptionalReturn: 0);
      try {
        _user32.lookupFunction<
          ffi.Int32 Function(
            ffi.Pointer<ffi.NativeFunction<_EnumWindow>>,
            ffi.IntPtr,
          ),
          int Function(ffi.Pointer<ffi.NativeFunction<_EnumWindow>>, int)
        >('EnumWindows')(callback.nativeFunction, 0);
      } finally {
        callback.close();
      }
      if (found == ffi.nullptr) throw StateError('FastInk window not found');
      return found;
    } finally {
      calloc.free(process);
    }
  }

  /// 设置当前目标窗口样式并检查原生调用结果，后续刷新位置使样式生效。
  void _setStyle(int style) {
    _kernel32.lookupFunction<ffi.Void Function(ffi.Uint32), void Function(int)>(
      'SetLastError',
    )(0);
    final previous = _user32
        .lookupFunction<
          ffi.IntPtr Function(ffi.Pointer<ffi.Void>, ffi.Int32, ffi.IntPtr),
          int Function(ffi.Pointer<ffi.Void>, int, int)
        >('SetWindowLongPtrW')(_window, -16, style);
    final error = _kernel32
        .lookupFunction<ffi.Uint32 Function(), int Function()>(
          'GetLastError',
        )();
    if (previous == 0 && error != 0) throw OSError('SetWindowLongPtrW', error);
  }

  /// 按原生逻辑设置窗口位置、尺寸和刷新标志，参数由进入/恢复流程统一计算。
  void _position(int x, int y, int width, int height, int flags) {
    final result = _user32
        .lookupFunction<
          ffi.Int32 Function(
            ffi.Pointer<ffi.Void>,
            ffi.Pointer<ffi.Void>,
            ffi.Int32,
            ffi.Int32,
            ffi.Int32,
            ffi.Int32,
            ffi.Uint32,
          ),
          int Function(
            ffi.Pointer<ffi.Void>,
            ffi.Pointer<ffi.Void>,
            int,
            int,
            int,
            int,
            int,
          )
        >('SetWindowPos')(_window, ffi.nullptr, x, y, width, height, flags);
    if (result == 0) throw StateError('SetWindowPos failed');
  }

  /// 保存当前窗口位置与样式，再按目标显示器范围进入全屏，保留退出所需状态。
  void _enter() {
    _window = _findWindow();
    _placement = calloc<ffi.Uint8>(44); // WINDOWPLACEMENT: 11 DWORDs.
    final monitorInfo = calloc<ffi.Int32>(10); // MONITORINFO: 40 bytes.
    _placement.cast<ffi.Uint32>().value = 44;
    monitorInfo.value = 40;
    try {
      final getPlacement = _user32
          .lookupFunction<
            ffi.Int32 Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Uint8>),
            int Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Uint8>)
          >('GetWindowPlacement');
      if (getPlacement(_window, _placement) == 0) {
        throw StateError('GetWindowPlacement failed');
      }
      final visible = _user32
          .lookupFunction<
            ffi.Int32 Function(ffi.Pointer<ffi.Void>),
            int Function(ffi.Pointer<ffi.Void>)
          >('IsWindowVisible')(_window);
      if (visible == 0) {
        _placement.cast<ffi.Uint32>()[2] = 0; // preserve hidden state too
      }
      final monitor = _user32
          .lookupFunction<
            ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Void>, ffi.Uint32),
            ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Void>, int)
          >('MonitorFromWindow')(_window, 2);
      final info = _user32
          .lookupFunction<
            ffi.Int32 Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Int32>),
            int Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Int32>)
          >('GetMonitorInfoW');
      if (info(monitor, monitorInfo) == 0) {
        throw StateError('GetMonitorInfoW failed');
      }
      _style = _user32
          .lookupFunction<
            ffi.IntPtr Function(ffi.Pointer<ffi.Void>, ffi.Int32),
            int Function(ffi.Pointer<ffi.Void>, int)
          >('GetWindowLongPtrW')(_window, -16);
      _setStyle(_style & ~0x00cf0000); // WS_OVERLAPPEDWINDOW
      try {
        _position(
          monitorInfo[1],
          monitorInfo[2],
          monitorInfo[3] - monitorInfo[1],
          monitorInfo[4] - monitorInfo[2],
          0x0230,
        );
      } catch (_) {
        _restore();
        rethrow;
      }
    } catch (_) {
      if (_placement != ffi.nullptr) {
        calloc.free(_placement);
        _placement = ffi.nullptr;
      }
      rethrow;
    } finally {
      calloc.free(monitorInfo);
    }
  }

  /// 按进入前保存的样式和位置恢复窗口，不能用固定默认尺寸代替用户原布局。
  void _restore() {
    if (_placement == ffi.nullptr) return;
    _setStyle(_style);
    final restored = _user32
        .lookupFunction<
          ffi.Int32 Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Uint8>),
          int Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Uint8>)
        >('SetWindowPlacement')(_window, _placement);
    _position(
      0,
      0,
      0,
      0,
      0x0037,
    ); // refresh frame, preserve position and z-order
    if (restored == 0) throw StateError('SetWindowPlacement failed');
    calloc.free(_placement);
    _placement = ffi.nullptr;
  }

  /// 释放本桥持有的位置缓冲等原生内存，不结束窗口或进程。
  void dispose() {
    try {
      setEnabled(false);
    } catch (_) {
      // Flutter 释放组件树前，操作系统可能已经销毁窗口。
    } finally {
      enabled = false;
      if (_placement != ffi.nullptr) {
        calloc.free(_placement);
        _placement = ffi.nullptr;
      }
    }
  }
}
