// 创建当前进程拥有的隐藏窗口，不操作其他应用。
import 'dart:ffi' as ffi;
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:fastink_flutter/src/platform/windows_fullscreen.dart';

/// 用自有隐藏窗口验证全屏进入/恢复与重复清理，结束后销毁测试窗口和原生字符串；不接管用户窗口。
void main() {
  if (!Platform.isWindows) return;
  final api = ffi.DynamicLibrary.open('user32.dll');
  final className = 'STATIC'.toNativeUtf16();
  final title = 'FastInk fullscreen test (hidden)'.toNativeUtf16();
  final create = api
      .lookupFunction<
        ffi.Pointer<ffi.Void> Function(
          ffi.Uint32,
          ffi.Pointer<Utf16>,
          ffi.Pointer<Utf16>,
          ffi.Uint32,
          ffi.Int32,
          ffi.Int32,
          ffi.Int32,
          ffi.Int32,
          ffi.Pointer<ffi.Void>,
          ffi.Pointer<ffi.Void>,
          ffi.Pointer<ffi.Void>,
          ffi.Pointer<ffi.Void>,
        ),
        ffi.Pointer<ffi.Void> Function(
          int,
          ffi.Pointer<Utf16>,
          ffi.Pointer<Utf16>,
          int,
          int,
          int,
          int,
          int,
          ffi.Pointer<ffi.Void>,
          ffi.Pointer<ffi.Void>,
          ffi.Pointer<ffi.Void>,
          ffi.Pointer<ffi.Void>,
        )
      >('CreateWindowExW');
  final window = create(
    0,
    className,
    title,
    0x00cf0000,
    100,
    100,
    640,
    480,
    ffi.nullptr,
    ffi.nullptr,
    ffi.nullptr,
    ffi.nullptr,
  );
  if (window == ffi.nullptr) {
    throw StateError('Could not create hidden test window');
  }
  final fullscreen = WindowsFullscreen(windowHandle: window.address);
  final getStyle = api
      .lookupFunction<
        ffi.IntPtr Function(ffi.Pointer<ffi.Void>, ffi.Int32),
        int Function(ffi.Pointer<ffi.Void>, int)
      >('GetWindowLongPtrW');
  final visible = api
      .lookupFunction<
        ffi.Int32 Function(ffi.Pointer<ffi.Void>),
        int Function(ffi.Pointer<ffi.Void>)
      >('IsWindowVisible');
  // 读取测试窗口的屏幕坐标边界，顺序为左、上、右、下；临时原生缓冲区在失败时也必须释放。
  List<int> rect() {
    final memory = calloc<ffi.Int32>(4);
    try {
      final ok = api
          .lookupFunction<
            ffi.Int32 Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Int32>),
            int Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Int32>)
          >('GetWindowRect')(window, memory);
      if (ok == 0) throw StateError('GetWindowRect failed');
      return List.generate(4, (index) => memory[index]);
    } finally {
      calloc.free(memory);
    }
  }

  try {
    final before = rect(), style = getStyle(window, -16);
    for (int iteration = 0; iteration < 3; iteration++) {
      fullscreen.setEnabled(true);
      final during = rect();
      if ((getStyle(window, -16) & 0x00cf0000) != 0) {
        throw StateError('Frame not removed');
      }
      if (during[2] - during[0] <= 640 || during[3] - during[1] <= 480) {
        throw StateError('Window did not fill monitor');
      }
      if (visible(window) != 0) throw StateError('Hidden probe became visible');
      fullscreen.setEnabled(false);
      if (rect().join(',') != before.join(',') ||
          getStyle(window, -16) != style) {
        throw StateError(
          'Original window not restored: before=$before after=${rect()}, style=${style.toRadixString(16)} afterStyle=${getStyle(window, -16).toRadixString(16)}',
        );
      }
    }
    stdout.writeln(
      'PASS: native borderless fullscreen and exact bounds/style restoration, 3 cycles; probe stayed hidden.',
    );
  } finally {
    fullscreen.dispose();
    api.lookupFunction<
      ffi.Int32 Function(ffi.Pointer<ffi.Void>),
      int Function(ffi.Pointer<ffi.Void>)
    >('DestroyWindow')(window);
    calloc.free(className);
    calloc.free(title);
  }
}
