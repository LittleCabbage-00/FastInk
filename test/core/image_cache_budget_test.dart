import 'package:fastink_flutter/src/core/image_cache_budget.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('preview cache settings apply immediately and clamp extremes', () {
    final ImageCache cache = PaintingBinding.instance.imageCache;
    final int previousEntries = cache.maximumSize;
    final int previousBytes = cache.maximumSizeBytes;
    try {
      ImageCacheBudget.apply(entries: 72, megabytes: 128);
      expect(cache.maximumSize, 72);
      expect(cache.maximumSizeBytes, 128 << 20);
      ImageCacheBudget.apply(entries: 1, megabytes: 500);
      expect(cache.maximumSize, 8);
      expect(cache.maximumSizeBytes, 160 << 20);
      ImageCacheBudget.relieveMemoryPressure();
      expect(cache.maximumSize, 12);
      expect(cache.maximumSizeBytes, 32 << 20);
    } finally {
      cache.maximumSize = previousEntries;
      cache.maximumSizeBytes = previousBytes;
    }
  });
}
