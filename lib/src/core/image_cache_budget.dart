import 'package:flutter/painting.dart';

/// Flutter 图片预览的 LRU 缓存预算。当前页位图由 RawImage 单独持有。
class ImageCacheBudget {
  /// recommendedEntries：默认图像缓存条目预算。
  static const int recommendedEntries = 48;

  /// recommendedMegabytes：默认图像缓存容量预算，单位 MB。
  static const int recommendedMegabytes = 64;

  /// 把条目数与 MB 预算应用到 Flutter 图像缓存；只调整显示缓存，不重写原始图片。
  static void apply({required int entries, required int megabytes}) {
    final ImageCache cache = PaintingBinding.instance.imageCache;
    cache.maximumSize = entries.clamp(8, 96);
    cache.maximumSizeBytes = megabytes.clamp(32, 160) << 20;
  }

  /// 系统发出内存压力通知时进入保守模式，直到下次启动或用户重新调整设置。
  static void relieveMemoryPressure() {
    final ImageCache cache = PaintingBinding.instance.imageCache;
    cache
      ..clear()
      ..clearLiveImages()
      ..maximumSize = 12
      ..maximumSizeBytes = 32 << 20;
  }
}
