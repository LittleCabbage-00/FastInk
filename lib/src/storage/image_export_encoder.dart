import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:image/image.dart' as raster;
import '../platform/windows_jpeg_encoder.dart';

/// 复用单个工作线程，同时最多处理一个编码请求。
class ImageExportEncoder {
  /// 创建后台编码服务的内部状态，端口握手由 start 完成后才暴露给调用方。
  ImageExportEncoder._();

  /// _responses：后台编码线程结果接收端口，按请求编号分发完成状态。
  final _responses = ReceivePort();

  /// _errors：后台线程异常接收端口，失败时需要结束等待中的请求。
  final _errors = ReceivePort();

  /// _exit：后台线程退出通知端口，用于确认关闭并清理通信资源。
  final _exit = ReceivePort();

  /// _ready：后台编码线程准备完成的信号，发送请求前必须等待。
  final _ready = Completer<void>();

  /// _pending：已经排队但尚未完成的任务，按键合并，避免重复创建同一结果。
  Completer<void>? _pending;

  /// _isolate：后台图像编码线程实例，负责把编码压力移离界面线程。
  late final Isolate _isolate;

  /// _requests：后台编码线程的请求发送端口，握手完成后才可使用。
  late SendPort _requests;

  /// _closed：对象是否已经结束，重复关闭不应再次释放原生或工作线程资源。
  bool _closed = false;

  /// _failed：当前预览/服务是否失败，用于显示失败标志或禁止继续提交。
  bool _failed = false;

  /// _stopped：编码服务完全停止的异步信号，关闭流程据此等待收尾。
  final _stopped = Completer<void>();

  /// 启动图像编码线程并等待请求端口握手，返回可提交工作的编码服务。
  static Future<ImageExportEncoder> start() async {
    final encoder = ImageExportEncoder._();
    encoder._responses.listen((message) {
      if (message is SendPort) {
        encoder._requests = message;
        encoder._ready.complete();
      } else {
        final pending = encoder._pending;
        encoder._pending = null;
        if (pending == null) return;
        if (message == null) {
          pending.complete();
        } else {
          pending.completeError(StateError('$message'));
        }
      }
    });
    // 把工作线程失败传播给尚在等待的请求，避免主线程永久等待无回复的编码。
    void fail(Object? message) {
      encoder._failed = true;
      if (!encoder._ready.isCompleted) {
        encoder._ready.completeError(StateError('$message'));
      }
      final pending = encoder._pending;
      encoder._pending = null;
      if (pending != null && !pending.isCompleted) {
        pending.completeError(StateError('$message'));
      }
    }

    encoder._errors.listen(fail);
    encoder._exit.listen((_) {
      if (!encoder._stopped.isCompleted) encoder._stopped.complete();
      if (!encoder._closed) fail('Image encoding worker exited unexpectedly.');
    });
    try {
      encoder._isolate = await Isolate.spawn(
        _encodeWorker,
        encoder._responses.sendPort,
        onError: encoder._errors.sendPort,
        onExit: encoder._exit.sendPort,
        errorsAreFatal: true,
      );
      await encoder._ready.future;
      return encoder;
    } catch (_) {
      encoder._closed = true;
      encoder._responses.close();
      encoder._errors.close();
      encoder._exit.close();
      rethrow;
    }
  }

  /// 把一页 RGBA 缓冲、尺寸、目标路径和质量发送到后台线程，等待该请求的成功或错误结果。
  Future<void> writeJpeg(
    Uint8List rgba,
    int width,
    int height,
    File target,
    int quality,
  ) {
    if (_closed || _failed || _pending != null) {
      throw StateError('Image encoder is closed or busy.');
    }
    if (width <= 0 || height <= 0 || rgba.lengthInBytes != width * height * 4) {
      throw ArgumentError('Invalid RGBA image dimensions.');
    }
    final pixels = TransferableTypedData.fromList([rgba]);
    final pending = Completer<void>();
    _pending = pending;
    _requests.send([pixels, width, height, target.path, quality]);
    return pending.future;
  }

  /// 请求后台编码线程停止，等待退出信号并关闭所有通信端口，重复关闭不重新释放。
  Future<void> dispose() async {
    if (_closed) return;
    final pending = _pending;
    if (pending != null) {
      try {
        await pending.future;
      } catch (_) {}
    }
    _closed = true;
    if (!_stopped.isCompleted) _requests.send(null);
    await _stopped.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        _isolate.kill(priority: Isolate.immediate);
      },
    );
    _responses.close();
    _errors.close();
    _exit.close();
  }
}

/// 后台线程编码循环，串行处理请求并优先使用可用原生 JPEG 编码，逐条回复结果，退出时释放编码器。
Future<void> _encodeWorker(SendPort replies) async {
  final requests = ReceivePort();
  WindowsJpegEncoder? native;
  try {
    if (Platform.isWindows) native = WindowsJpegEncoder();
    replies.send(requests.sendPort);
    await for (final message in requests) {
      if (message == null) break;
      final job = message as List<Object>;
      try {
        final bytes = (job[0] as TransferableTypedData)
            .materialize()
            .asUint8List();
        final width = job[1] as int, height = job[2] as int;
        final target = File(job[3] as String);
        final quality = job[4] as int;
        // 原生编码器可能存在旧路径长度限制，而 Dart 支持长路径；
        // 该少见情况使用后台后备编码，仍限制内存占用。
        if (native != null && target.absolute.path.length < 248) {
          native.write(bytes, width, height, target, quality);
        } else {
          final image = raster.Image.fromBytes(
            width: width,
            height: height,
            bytes: bytes.buffer,
            bytesOffset: bytes.offsetInBytes,
            numChannels: 4,
            order: raster.ChannelOrder.rgba,
          );
          await target.writeAsBytes(
            raster.encodeJpg(image, quality: quality),
            flush: true,
          );
        }
        replies.send(null);
      } catch (error) {
        replies.send(error.toString());
      }
    }
  } finally {
    native?.dispose();
    requests.close();
  }
}
