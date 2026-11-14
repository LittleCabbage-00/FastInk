import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';

final class _Guid extends ffi.Struct {
  /// a：GUID 的 Data1 字段，按原生 32 位无符号布局保存。
  @ffi.Uint32()
  external int a;

  /// b：GUID 的 Data2 字段，按原生 16 位无符号布局保存。
  @ffi.Uint16()
  external int b;

  /// c：GUID 的 Data3 字段，按原生 16 位无符号布局保存。
  @ffi.Uint16()
  external int c;

  /// d：GUID 的 Data4 字段，固定 8 字节，不能随 Dart 对象布局改变。
  @ffi.Array(8)
  external ffi.Array<ffi.Uint8> d;
}

final class _Property extends ffi.Struct {
  /// type：原生属性袋描述中的属性类型字段，与 COM 结构布局保持一致。
  @ffi.Uint32()
  external int type;

  /// variantType：COM VARIANT 类型标记，决定联合存储区的实际解释方式。
  @ffi.Uint16()
  external int variantType;

  /// clipboardType：原生属性描述的剪贴板格式字段，按 Windows 结构布局保存。
  @ffi.Uint16()
  external int clipboardType;

  /// hint：原生属性描述的提示标志字段，不参与 Dart 界面提示。
  @ffi.Uint32()
  external int hint;

  /// name：原生属性名的 UTF-16 指针，分配与释放须遵循所属 COM 调用生命周期。
  external ffi.Pointer<Utf16> name;

  /// classId：原生属性描述中的类标识 GUID，必须保持 Windows 对齐布局。
  external _Guid classId;
}

typedef _Ptr = ffi.Pointer<ffi.Void>;

/// Windows 图像组件的 JPEG 编码器，仅由导出工作线程调用。
/// 明确采用 4:4:4 采样，保留旧编码器的色度分辨率。
/// COM 对象在同一次同步调用内创建、使用和释放；
/// 否则 Dart 隔离线程可能在异步消息间切换系统线程。
class WindowsJpegEncoder {
  /// 绑定 Windows 原生 JPEG/WIC 所需 COM 调用，初始化失败由调用方回退其他编码路径。
  WindowsJpegEncoder() {
    if (!Platform.isWindows) throw UnsupportedError('Windows JPEG encoder');
    final library = ffi.DynamicLibrary.open('ole32.dll');
    _initialize = library
        .lookupFunction<
          ffi.Int32 Function(_Ptr, ffi.Uint32),
          int Function(_Ptr, int)
        >('CoInitializeEx');
    _uninitialize = library
        .lookupFunction<ffi.Void Function(), void Function()>('CoUninitialize');
    _create = library
        .lookupFunction<
          ffi.Int32 Function(
            ffi.Pointer<_Guid>,
            _Ptr,
            ffi.Uint32,
            ffi.Pointer<_Guid>,
            ffi.Pointer<_Ptr>,
          ),
          int Function(
            ffi.Pointer<_Guid>,
            _Ptr,
            int,
            ffi.Pointer<_Guid>,
            ffi.Pointer<_Ptr>,
          )
        >('CoCreateInstance');
  }

  /// _initialize：CoInitializeEx 调用入口，用于初始化当前编码线程的 COM 环境。
  late final int Function(_Ptr, int) _initialize;

  /// _uninitialize：CoUninitialize 调用入口，仅与本对象成功持有的 COM 初始化配对。
  late final void Function() _uninitialize;

  /// _create：CoCreateInstance 调用入口，用于创建 Windows 原生编码组件。
  late final int Function(
    ffi.Pointer<_Guid>,
    _Ptr,
    int,
    ffi.Pointer<_Guid>,
    ffi.Pointer<_Ptr>,
  )
  _create;

  /// _closed：对象是否已经结束，重复关闭不应再次释放原生或工作线程资源。
  bool _closed = false;

  /// 按 COM 虚表索引获取函数地址，必须与接口声明的槽位和 ABI 一致。
  _Ptr _entry(_Ptr object, int index) =>
      object.cast<ffi.Pointer<_Ptr>>().value[index];

  /// 检查 HRESULT，失败时转成可诊断异常，不能继续使用未初始化输出指针。
  void _check(int result) {
    if (result < 0) {
      throw StateError(
        'Windows JPEG encoder failed (HRESULT 0x${(result & 0xffffffff).toRadixString(16)}).',
      );
    }
  }

  /// 把 GUID 字符串写入原生结构，字段顺序和字节布局遵循 Windows GUID 约定。
  void _guid(_Guid guid, String value) {
    final parts = value.split('-');
    guid.a = int.parse(parts[0], radix: 16);
    guid.b = int.parse(parts[1], radix: 16);
    guid.c = int.parse(parts[2], radix: 16);
    final tail = parts[3] + parts[4];
    for (var i = 0; i < 8; i++) {
      guid.d[i] = int.parse(tail.substring(i * 2, i * 2 + 2), radix: 16);
    }
  }

  /// 调用接口的 Release，非空且仍归本对象的 COM 引用才可释放。
  void _release(_Ptr object) {
    if (object != ffi.nullptr) {
      _entry(object, 2)
          .cast<ffi.NativeFunction<ffi.Uint32 Function(_Ptr)>>()
          .asFunction<int Function(_Ptr)>()(object);
    }
  }

  /// 调用只接收 this 指针的 COM 虚表方法，返回原始 HRESULT/数值供上层检查。
  int _one(_Ptr object, int slot) => _entry(object, slot)
      .cast<ffi.NativeFunction<ffi.Int32 Function(_Ptr)>>()
      .asFunction<int Function(_Ptr)>()(object);

  /// 调用带一个指针参数的 COM 虚表方法，参数内存由所属调用负责生存期。
  int _pointer(_Ptr object, int slot, _Ptr argument) => _entry(object, slot)
      .cast<ffi.NativeFunction<ffi.Int32 Function(_Ptr, _Ptr)>>()
      .asFunction<int Function(_Ptr, _Ptr)>()(object, argument);

  /// 调用带两个指针参数的 COM 方法，严格使用已声明的原生签名。
  int _twoPointers(_Ptr object, int slot, _Ptr a, _Ptr b) =>
      _entry(object, slot)
          .cast<ffi.NativeFunction<ffi.Int32 Function(_Ptr, _Ptr, _Ptr)>>()
          .asFunction<int Function(_Ptr, _Ptr, _Ptr)>()(object, a, b);

  /// 调用带三个指针参数的 COM 方法，不能按 Dart 对象地址传递托管数据。
  int _threePointers(
    _Ptr object,
    int slot,
    _Ptr a,
    _Ptr b,
    _Ptr c,
  ) => _entry(object, slot)
      .cast<ffi.NativeFunction<ffi.Int32 Function(_Ptr, _Ptr, _Ptr, _Ptr)>>()
      .asFunction<int Function(_Ptr, _Ptr, _Ptr, _Ptr)>()(object, a, b, c);

  /// 调用带指针和整数参数的 COM 方法，用于原生编码属性与缓冲设置。
  int _pointerAndInt(
    _Ptr object,
    int slot,
    _Ptr a,
    int value,
  ) => _entry(object, slot)
      .cast<ffi.NativeFunction<ffi.Int32 Function(_Ptr, _Ptr, ffi.Uint32)>>()
      .asFunction<int Function(_Ptr, _Ptr, int)>()(object, a, value);

  /// 把 RGBA 缓冲按给定像素宽高与质量写为 JPEG，编码流、属性与图像接口均按所有权释放。
  void write(Uint8List rgba, int width, int height, File target, int quality) {
    if (_closed) throw StateError('JPEG encoder was disposed.');
    if (width <= 0 || height <= 0 || rgba.lengthInBytes != width * height * 4) {
      throw ArgumentError('Invalid RGBA image dimensions.');
    }
    using((arena) {
      final classId = arena<_Guid>(),
          iid = arena<_Guid>(),
          format = arena<_Guid>(),
          vendor = arena<_Guid>();
      final factory = arena<_Ptr>(),
          stream = arena<_Ptr>(),
          encoder = arena<_Ptr>(),
          frame = arena<_Ptr>(),
          options = arena<_Ptr>();
      final path = target.absolute.path.toNativeUtf16(allocator: arena);
      final properties = arena<_Property>(2);
      final variants = arena<ffi.Uint8>(
        48,
      ); // Windows x64 和 ARM64 的 VARIANT 各占 24 字节。
      final pixels = arena<ffi.Uint8>(width * height * 3);
      factory.value = ffi.nullptr;
      stream.value = ffi.nullptr;
      encoder.value = ffi.nullptr;
      frame.value = ffi.nullptr;
      options.value = ffi.nullptr;
      final initialized = _initialize(ffi.nullptr, 0);
      // 线程已初始化为 STA 时仍可使用；只对成功的 CoInitializeEx
      // 调用（包含 S_FALSE）在同一线程上配对执行反初始化。
      if (initialized < 0 && (initialized & 0xffffffff) != 0x80010106) {
        _check(initialized);
      }
      try {
        _guid(classId.ref, 'cacaf262-9370-4615-a13b-9f5539da4c0a');
        _guid(iid.ref, 'ec5ec8a9-c395-4314-9c77-54d7a935ff70');
        _check(_create(classId, ffi.nullptr, 1, iid, factory));
        // 创建并初始化文件流：IWICImagingFactory::CreateStream；IWICStream::InitializeFromFilename。
        _check(_pointer(factory.value, 14, stream.cast()));
        _check(_pointerAndInt(stream.value, 15, path.cast(), 0x40000000));
        _guid(format.ref, '19e4a5aa-5662-4fc5-a0c0-1758028e1057');
        _guid(vendor.ref, 'f0e749ca-edef-4589-a73a-ee0e626a2a2b');
        _check(
          _threePointers(
            factory.value,
            8,
            format.cast(),
            vendor.cast(),
            encoder.cast(),
          ),
        );
        _check(
          _pointerAndInt(encoder.value, 3, stream.value, 2),
        ); // WICBitmapEncoderNoCache.
        _check(_twoPointers(encoder.value, 10, frame.cast(), options.cast()));
        properties[0].type = 1;
        properties[0].variantType = 4;
        properties[0].name = 'ImageQuality'.toNativeUtf16(allocator: arena);
        properties[1].type = 1;
        properties[1].variantType = 17;
        properties[1].name = 'JpegYCrCbSubsampling'.toNativeUtf16(
          allocator: arena,
        );
        final values = ByteData.sublistView(variants.asTypedList(48));
        values.setUint16(0, 4, Endian.little); // VT_R4.
        values.setFloat32(8, quality.clamp(0, 100) / 100, Endian.little);
        values.setUint16(24, 17, Endian.little); // VT_UI1.
        values.setUint8(32, 3); // WICJpegYCrCbSubsampling444.
        final writeOptions = _entry(options.value, 4)
            .cast<
              ffi.NativeFunction<
                ffi.Int32 Function(
                  _Ptr,
                  ffi.Uint32,
                  ffi.Pointer<_Property>,
                  ffi.Pointer<ffi.Uint8>,
                )
              >
            >()
            .asFunction<
              int Function(
                _Ptr,
                int,
                ffi.Pointer<_Property>,
                ffi.Pointer<ffi.Uint8>,
              )
            >();
        _check(writeOptions(options.value, 2, properties, variants));
        _check(_pointer(frame.value, 3, options.value));
        final setSize = _entry(frame.value, 4)
            .cast<
              ffi.NativeFunction<
                ffi.Int32 Function(_Ptr, ffi.Uint32, ffi.Uint32)
              >
            >()
            .asFunction<int Function(_Ptr, int, int)>();
        _check(setSize(frame.value, width, height));
        _guid(format.ref, '6fddc324-4e03-4bfe-b185-3d77768dc90c'); // 24bpp BGR.
        _check(_pointer(frame.value, 6, format.cast()));
        if (format.ref.a != 0x6fddc324 || format.ref.d[7] != 0x0c) {
          throw StateError(
            'JPEG codec did not accept the expected BGR pixel format.',
          );
        }
        final bgr = pixels.asTypedList(width * height * 3);
        for (
          var source = 0, dest = 0;
          source < rgba.length;
          source += 4, dest += 3
        ) {
          bgr[dest] = rgba[source + 2];
          bgr[dest + 1] = rgba[source + 1];
          bgr[dest + 2] = rgba[source];
        }
        final writePixels = _entry(frame.value, 10)
            .cast<
              ffi.NativeFunction<
                ffi.Int32 Function(
                  _Ptr,
                  ffi.Uint32,
                  ffi.Uint32,
                  ffi.Uint32,
                  ffi.Pointer<ffi.Uint8>,
                )
              >
            >()
            .asFunction<
              int Function(_Ptr, int, int, int, ffi.Pointer<ffi.Uint8>)
            >();
        _check(
          writePixels(
            frame.value,
            height,
            width * 3,
            width * height * 3,
            pixels,
          ),
        );
        _check(_one(frame.value, 12));
        _check(_one(encoder.value, 11));
      } finally {
        _release(frame.value);
        _release(options.value);
        _release(encoder.value);
        _release(stream.value);
        _release(factory.value);
        if (initialized >= 0) _uninitialize();
      }
    });
  }

  /// 将编码器标记为关闭，后续不得继续提交编码请求。
  void dispose() => _closed = true;
}
