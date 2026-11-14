// 仅测试本任务拥有的隐藏窗口，捕获的像素不保存到磁盘。
import 'dart:ffi' as ffi;
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:fastink_flutter/src/platform/windows_capture.dart';

/// 创建仅归本测试所有的隐藏窗口，验证捕获尺寸、像素和恢复流程；不保存屏幕图像、不操作其他应用。
void main() {
  if (!Platform.isWindows) return;
  final api = ffi.DynamicLibrary.open('user32.dll');
  final className = 'STATIC'.toNativeUtf16();
  final title = 'FastInk capture test (hidden)'.toNativeUtf16();
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
  if (window == ffi.nullptr) throw StateError('Could not create test window');
  final visible = api
      .lookupFunction<
        ffi.Int32 Function(ffi.Pointer<ffi.Void>),
        int Function(ffi.Pointer<ffi.Void>)
      >('IsWindowVisible');
  final getRect = api
      .lookupFunction<
        ffi.Int32 Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Int32>),
        int Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Int32>)
      >('GetWindowRect');
  final rect = calloc<ffi.Int32>(4), after = calloc<ffi.Int32>(4);
  final bridge = WindowsCapture();
  try {
    getRect(window, rect);
    for (var iteration = 0; iteration < 5; iteration++) {
      bridge.hideWindow(window.address);
      if (visible(window) != 0) {
        throw StateError('Capture did not hide test window');
      }
      final capture = bridge.captureRect(0, 0, 4, 3);
      if (capture.width != 4 ||
          capture.height != 3 ||
          capture.bgra.length != 48) {
        throw StateError('Capture dimensions incorrect');
      }
      for (var i = 3; i < capture.bgra.length; i += 4) {
        if (capture.bgra[i] != 255) throw StateError('Capture alpha incorrect');
      }
      bridge.restoreWindow();
      if (visible(window) != 0) {
        throw StateError('Hidden test window was shown');
      }
      getRect(window, after);
      for (var i = 0; i < 4; i++) {
        if (rect[i] != after[i]) {
          throw StateError('Window position was changed');
        }
      }
    }
    stdout.writeln(
      'PASS: GDI capture, opaque BGRA, hide/restore bounds and hidden state (5 cycles). Clipboard was not modified.',
    );
  } finally {
    bridge.restoreWindow();
    api.lookupFunction<
      ffi.Int32 Function(ffi.Pointer<ffi.Void>),
      int Function(ffi.Pointer<ffi.Void>)
    >('DestroyWindow')(window);
    calloc.free(className);
    calloc.free(title);
    calloc.free(rect);
    calloc.free(after);
  }
}
