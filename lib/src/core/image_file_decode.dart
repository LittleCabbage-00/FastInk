import 'dart:math' as math;
import 'dart:ui' as ui;

/// 只读取图片文件头中的原始尺寸，不解码像素。
///
/// 邻页布局用它提前确定宽高比，避免页面进入视口后才从默认 A4 比例
/// 切换到真实比例。返回前会释放引擎侧描述符和文件缓冲区。
Future<({int width, int height})> readImageFileDimensions(String path) async {
  final ui.ImmutableBuffer buffer = await ui.ImmutableBuffer.fromFilePath(path);
  ui.ImageDescriptor? descriptor;
  try {
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    return (width: descriptor.width, height: descriptor.height);
  } finally {
    descriptor?.dispose();
    buffer.dispose();
  }
}

/// 从文件缓冲区解码图片，文件内容留在引擎管理的内存中。
Future<ui.Image> decodeImageFile(
  String path, {
  int? targetWidth,
  int? targetHeight,
  int? maximumHeight,
}) async {
  final ui.ImmutableBuffer buffer = await ui.ImmutableBuffer.fromFilePath(path);
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  try {
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    // 限高时同步收窄宽度；超长 OneNote 页面不能仅限宽后仍分配巨幅纹理。
    // 不传限高的导出、采样等调用维持原来的解码语义。
    int? decodeWidth = targetWidth == null
        ? null
        : math.min(targetWidth, descriptor.width);
    int? decodeHeight = targetHeight == null
        ? null
        : math.min(targetHeight, descriptor.height);
    if (maximumHeight != null) {
      final width =
          decodeWidth?.toDouble() ??
          (decodeHeight == null
              ? descriptor.width.toDouble()
              : descriptor.width * decodeHeight / descriptor.height);
      final height =
          decodeHeight?.toDouble() ??
          descriptor.height * width / descriptor.width;
      final ratio = math.min(1.0, maximumHeight / height);
      decodeWidth = math.max(1, (width * ratio).round());
      decodeHeight = math.max(1, (height * ratio).round());
    }
    codec = await descriptor.instantiateCodec(
      targetWidth: decodeWidth,
      targetHeight: decodeHeight,
    );
    return (await codec.getNextFrame()).image;
  } finally {
    codec?.dispose();
    descriptor?.dispose();
    buffer.dispose();
  }
}
