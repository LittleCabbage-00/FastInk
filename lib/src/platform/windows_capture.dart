import 'dart:ffi' as ffi;
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'package:image/image.dart' as raster;

typedef _Handle = ffi.Pointer<ffi.Void>;

class DesktopPixels {
  /// 保存捕获图像的物理像素宽高与 BGRA 字节，不在构造时操作窗口或剪贴板。
  DesktopPixels(this.width, this.height, this.bgra);

  /// width：捕获图像宽度，单位物理像素；height：捕获图像高度，单位物理像素。
  final int width, height;

  /// bgra：截图原始 BGRA 字节缓冲，通道顺序与普通 RGBA 解码不能混用。
  final Uint8List bgra;
}

/// 使用 Win32 GDI 截屏及图像剪贴板，无需更新启动器或插件。
class WindowsCapture {
  /// _user：user32.dll 动态库引用，窗口与剪贴板 API 从该句柄查找。
  late final _user = ffi.DynamicLibrary.open('user32.dll');

  /// _gdi：gdi32.dll 动态库引用，用于屏幕位图和图形对象操作。
  late final _gdi = ffi.DynamicLibrary.open('gdi32.dll');

  /// _kernel：kernel32.dll 动态库引用，用于内存与系统资源 API。
  late final _kernel = ffi.DynamicLibrary.open('kernel32.dll');

  /// _hiddenWindow：截图前暂时隐藏的应用窗口句柄，结束后恢复，不是任意前台窗口。
  _Handle _hiddenWindow = ffi.nullptr;

  /// _placement：保存原窗口位置/状态的原生缓冲，恢复后由所属桥释放。
  ffi.Pointer<ffi.Uint8> _placement = ffi.nullptr;

  /// _show：ShowWindow 的 FFI 调用入口，用于隐藏和恢复所属窗口。
  late final _show = _user
      .lookupFunction<
        ffi.Int32 Function(_Handle, ffi.Int32),
        int Function(_Handle, int)
      >('ShowWindow');

  /// _deleteObject：DeleteObject 的 FFI 入口，用于释放本次创建的 GDI 对象。
  late final _deleteObject = _gdi
      .lookupFunction<ffi.Int32 Function(_Handle), int Function(_Handle)>(
        'DeleteObject',
      );

  /// _selectObject：SelectObject 的 FFI 入口，替换绘图 DC 中的对象后需恢复旧对象。
  late final _selectObject = _gdi
      .lookupFunction<
        _Handle Function(_Handle, _Handle),
        _Handle Function(_Handle, _Handle)
      >('SelectObject');

  /// _globalLock：GlobalLock 的 FFI 入口，读取剪贴板内存前取得可访问地址。
  late final _globalLock = _kernel
      .lookupFunction<_Handle Function(_Handle), _Handle Function(_Handle)>(
        'GlobalLock',
      );

  /// _globalUnlock：GlobalUnlock 的 FFI 入口，与成功的全局内存锁定配对。
  late final _globalUnlock = _kernel
      .lookupFunction<ffi.Int32 Function(_Handle), int Function(_Handle)>(
        'GlobalUnlock',
      );

  /// _globalFree：GlobalFree 的 FFI 入口，释放仍由本进程拥有的原生全局缓冲。
  late final _globalFree = _kernel
      .lookupFunction<_Handle Function(_Handle), _Handle Function(_Handle)>(
        'GlobalFree',
      );

  /// _closeClipboard：CloseClipboard 的 FFI 入口，与成功打开剪贴板配对执行。
  late final _closeClipboard = _user
      .lookupFunction<ffi.Int32 Function(), int Function()>('CloseClipboard');

  /// 读取系统剪贴板变化序列，判断应用内选区复制后是否又发生外部复制。
  int get clipboardSequence =>
      _user.lookupFunction<ffi.Uint32 Function(), int Function()>(
        'GetClipboardSequenceNumber',
      )();

  /// 只隐藏指定的本应用窗口并保存其位置/状态，用于外部截图，不结束前台程序。
  void hideWindow(int handle) {
    if (_placement != ffi.nullptr) throw StateError('Capture already active');
    final window = ffi.Pointer<ffi.Void>.fromAddress(handle);
    final data = calloc<ffi.Uint8>(44);
    data.cast<ffi.Uint32>().value = 44;
    final result = _user
        .lookupFunction<
          ffi.Int32 Function(_Handle, ffi.Pointer<ffi.Uint8>),
          int Function(_Handle, ffi.Pointer<ffi.Uint8>)
        >('GetWindowPlacement')(window, data);
    if (result == 0) {
      calloc.free(data);
      throw StateError('GetWindowPlacement failed');
    }
    if (_user
            .lookupFunction<ffi.Int32 Function(_Handle), int Function(_Handle)>(
              'IsWindowVisible',
            )(window) ==
        0) {
      data.cast<ffi.Uint32>()[2] = 0;
    }
    _placement = data;
    _hiddenWindow = window;
    _show(window, 0);
  }

  /// 恢复本桥先前隐藏的窗口并释放位置缓冲，没有保存目标时不操作任意窗口。
  void restoreWindow() {
    if (_placement == ffi.nullptr) return;
    try {
      final result = _user
          .lookupFunction<
            ffi.Int32 Function(_Handle, ffi.Pointer<ffi.Uint8>),
            int Function(_Handle, ffi.Pointer<ffi.Uint8>)
          >('SetWindowPlacement')(_hiddenWindow, _placement);
      if (result == 0) {
        _show(_hiddenWindow, 5);
        throw StateError('SetWindowPlacement failed');
      }
      if (_placement.cast<ffi.Uint32>()[2] != 0) {
        _user
            .lookupFunction<ffi.Int32 Function(_Handle), int Function(_Handle)>(
              'SetForegroundWindow',
            )(_hiddenWindow);
      }
    } finally {
      calloc.free(_placement);
      _placement = ffi.nullptr;
      _hiddenWindow = ffi.nullptr;
    }
  }

  /// 捕获虚拟桌面物理像素范围，交给矩形捕获路径处理多显示器边界。
  DesktopPixels captureDesktop() {
    final metric = _user
        .lookupFunction<ffi.Int32 Function(ffi.Int32), int Function(int)>(
          'GetSystemMetrics',
        );
    return captureRect(
      metric(76),
      metric(77),
      metric(78),
      metric(79),
    ); // virtual desktop, including negative monitor origins
  }

  /// 按物理坐标捕获指定矩形并返回 BGRA 缓冲，DC 和位图等临时 GDI 资源在结束后配对释放。
  DesktopPixels captureRect(int x, int y, int width, int height) {
    if (width < 1 || height < 1 || width * height > 64000000) {
      throw StateError('Unsupported screen size');
    }
    final dc = _user
        .lookupFunction<_Handle Function(_Handle), _Handle Function(_Handle)>(
          'GetDC',
        )(ffi.nullptr);
    if (dc == ffi.nullptr) throw StateError('GetDC failed');
    var memory = ffi.nullptr.cast<ffi.Void>(),
        bitmap = ffi.nullptr.cast<ffi.Void>(),
        previous = ffi.nullptr.cast<ffi.Void>();
    final info = calloc<ffi.Uint8>(40),
        pixels = calloc<ffi.Uint8>(width * height * 4);
    try {
      memory = _gdi
          .lookupFunction<_Handle Function(_Handle), _Handle Function(_Handle)>(
            'CreateCompatibleDC',
          )(dc);
      if (memory == ffi.nullptr) throw StateError('CreateCompatibleDC failed');
      bitmap = _gdi
          .lookupFunction<
            _Handle Function(_Handle, ffi.Int32, ffi.Int32),
            _Handle Function(_Handle, int, int)
          >('CreateCompatibleBitmap')(dc, width, height);
      if (bitmap == ffi.nullptr) {
        throw StateError('CreateCompatibleBitmap failed');
      }
      previous = _selectObject(memory, bitmap);
      if (previous == ffi.nullptr || previous.address == -1) {
        throw StateError('SelectObject failed');
      }
      final copied = _gdi
          .lookupFunction<
            ffi.Int32 Function(
              _Handle,
              ffi.Int32,
              ffi.Int32,
              ffi.Int32,
              ffi.Int32,
              _Handle,
              ffi.Int32,
              ffi.Int32,
              ffi.Uint32,
            ),
            int Function(_Handle, int, int, int, int, _Handle, int, int, int)
          >('BitBlt')(memory, 0, 0, width, height, dc, x, y, 0x40cc0020);
      if (copied == 0) throw StateError('BitBlt failed');
      _selectObject(memory, previous);
      previous = ffi.nullptr;
      final header = ByteData.sublistView(info.asTypedList(40));
      header.setUint32(0, 40, Endian.little);
      header.setInt32(4, width, Endian.little);
      header.setInt32(8, -height, Endian.little);
      header.setUint16(12, 1, Endian.little);
      header.setUint16(14, 32, Endian.little);
      final lines = _gdi
          .lookupFunction<
            ffi.Int32 Function(
              _Handle,
              _Handle,
              ffi.Uint32,
              ffi.Uint32,
              ffi.Pointer<ffi.Uint8>,
              ffi.Pointer<ffi.Uint8>,
              ffi.Uint32,
            ),
            int Function(
              _Handle,
              _Handle,
              int,
              int,
              ffi.Pointer<ffi.Uint8>,
              ffi.Pointer<ffi.Uint8>,
              int,
            )
          >('GetDIBits')(dc, bitmap, 0, height, pixels, info, 0);
      if (lines != height) throw StateError('GetDIBits failed');
      final bytes = Uint8List.fromList(pixels.asTypedList(width * height * 4));
      for (var i = 3; i < bytes.length; i += 4) {
        bytes[i] = 255;
      }
      return DesktopPixels(width, height, bytes);
    } finally {
      if (previous != ffi.nullptr) _selectObject(memory, previous);
      if (bitmap != ffi.nullptr) _deleteObject(bitmap);
      if (memory != ffi.nullptr) {
        _gdi.lookupFunction<ffi.Int32 Function(_Handle), int Function(_Handle)>(
          'DeleteDC',
        )(memory);
      }
      _user.lookupFunction<
        ffi.Int32 Function(_Handle, _Handle),
        int Function(_Handle, _Handle)
      >('ReleaseDC')(ffi.nullptr, dc);
      calloc.free(info);
      calloc.free(pixels);
    }
  }

  /// 取得系统注册的 PNG 剪贴板格式编号。
  int _pngFormat() {
    final name = 'PNG'.toNativeUtf16();
    try {
      return _user.lookupFunction<
        ffi.Uint32 Function(ffi.Pointer<Utf16>),
        int Function(ffi.Pointer<Utf16>)
      >('RegisterClipboardFormatW')(name);
    } finally {
      calloc.free(name);
    }
  }

  /// 尝试打开剪贴板，短暂占用时有限重试，最终失败抛出错误供界面提示。
  Future<void> _openClipboard(int handle) async {
    final open = _user
        .lookupFunction<ffi.Int32 Function(_Handle), int Function(_Handle)>(
          'OpenClipboard',
        );
    for (var attempt = 0; attempt < 10; attempt++) {
      if (open(ffi.Pointer.fromAddress(handle)) != 0) return;
      await Future<void>.delayed(const Duration(milliseconds: 30));
    }
    throw StateError('Clipboard is in use');
  }

  /// 读取指定剪贴板格式并复制出 Dart 字节，原生句柄仍遵守剪贴板所有权。
  Uint8List? _readFormat(int format) {
    if (format == 0) return null;
    final data = _user
        .lookupFunction<_Handle Function(ffi.Uint32), _Handle Function(int)>(
          'GetClipboardData',
        )(format);
    if (data == ffi.nullptr) return null;
    final size = _kernel
        .lookupFunction<ffi.UintPtr Function(_Handle), int Function(_Handle)>(
          'GlobalSize',
        )(data);
    if (size < 1 || size > 256000000) return null;
    final bytes = _globalLock(data);
    if (bytes == ffi.nullptr) throw StateError('GlobalLock failed');
    try {
      return Uint8List.fromList(bytes.cast<ffi.Uint8>().asTypedList(size));
    } finally {
      _globalUnlock(data);
    }
  }

  /// 按可用 PNG/DIB 等格式读取系统图片，缺少图片时返回 null，所有打开/锁定操作配对关闭。
  Future<Uint8List?> readImage(int windowHandle) async {
    await _openClipboard(windowHandle);
    try {
      final png = _readFormat(_pngFormat());
      if (png != null) return png;
      final dib = _readFormat(17) ?? _readFormat(8);
      return dib == null ? null : dibToPng(dib);
    } finally {
      _closeClipboard();
    }
  }

  /// 为指定格式分配并提交剪贴板数据，转交系统后的缓冲不得再次由本进程释放。
  void _writeFormat(int format, Uint8List bytes) {
    if (format == 0) throw StateError('RegisterClipboardFormat failed');
    final memory = _kernel
        .lookupFunction<
          _Handle Function(ffi.Uint32, ffi.UintPtr),
          _Handle Function(int, int)
        >('GlobalAlloc')(2, bytes.length);
    if (memory == ffi.nullptr) throw StateError('GlobalAlloc failed');
    var transferred = false;
    try {
      final pointer = _globalLock(memory);
      if (pointer == ffi.nullptr) throw StateError('GlobalLock failed');
      try {
        pointer.cast<ffi.Uint8>().asTypedList(bytes.length).setAll(0, bytes);
      } finally {
        _globalUnlock(memory);
      }
      transferred =
          _user.lookupFunction<
            _Handle Function(ffi.Uint32, _Handle),
            _Handle Function(int, _Handle)
          >('SetClipboardData')(format, memory) !=
          ffi.nullptr;
      if (!transferred) throw StateError('SetClipboardData failed');
    } finally {
      if (!transferred) _globalFree(memory);
    }
  }

  /// 将 PNG 及兼容图像格式写入剪贴板，先后正确处理所有权和关闭，失败回收仍归本进程的内存。
  Future<void> writeImage(int windowHandle, Uint8List png) async {
    // 取得剪贴板所有权前，先准备好所有图像格式。
    final dib = pngToDib(png), format = _pngFormat();
    await _openClipboard(windowHandle);
    try {
      if (_user.lookupFunction<ffi.Int32 Function(), int Function()>(
            'EmptyClipboard',
          )() ==
          0) {
        throw StateError('EmptyClipboard failed');
      }
      _writeFormat(format, png);
      _writeFormat(8, dib);
    } finally {
      _closeClipboard();
    }
  }
}

/// 将 PNG 转成 Windows DIB 字节，处理通道顺序、行方向和头部布局。
Uint8List pngToDib(Uint8List png) {
  final image = raster.decodePng(png);
  if (image == null) throw FormatException('Invalid PNG');
  final bytes = Uint8List(40 + image.width * image.height * 4),
      data = ByteData(40);
  data.setUint32(0, 40, Endian.little);
  data.setInt32(4, image.width, Endian.little);
  data.setInt32(8, -image.height, Endian.little);
  data.setUint16(12, 1, Endian.little);
  data.setUint16(14, 32, Endian.little);
  bytes.setAll(0, data.buffer.asUint8List());
  bytes.setAll(40, image.getBytes(order: raster.ChannelOrder.bgra));
  return bytes;
}

/// 校验并转换 Windows DIB 为 PNG，不能把未验证的尺寸直接作为缓冲访问范围。
Uint8List dibToPng(Uint8List dib) {
  if (dib.length < 40) throw FormatException('Invalid DIB');
  final data = ByteData.sublistView(dib),
      header = ByteData.sublistView(dib).getUint32(0, Endian.little);
  if (header < 40 || header > dib.length) {
    throw FormatException('Unsupported DIB header');
  }
  final width = data.getInt32(4, Endian.little),
      height = data.getInt32(8, Endian.little).abs();
  if (width < 1 || height < 1 || width * height > 64000000) {
    throw FormatException('Invalid DIB dimensions');
  }
  final bits = data.getUint16(14, Endian.little),
      compression = data.getUint32(16, Endian.little),
      used = data.getUint32(32, Endian.little);
  final palette = used > 0
      ? used
      : bits <= 8
      ? 1 << bits
      : 0;
  final offset =
      header +
      palette * 4 +
      (header == 40 && compression == 3
          ? 12
          : header == 40 && compression == 6
          ? 16
          : 0);
  if (offset > dib.length) throw FormatException('Truncated DIB');
  final bmp = Uint8List(14 + dib.length), file = ByteData.sublistView(bmp);
  file.setUint16(0, 0x4d42, Endian.little);
  file.setUint32(2, bmp.length, Endian.little);
  file.setUint32(10, 14 + offset, Endian.little);
  bmp.setAll(14, dib);
  final image = raster.decodeBmp(bmp);
  if (image == null) throw FormatException('Unsupported clipboard bitmap');
  return raster.encodePng(image);
}
