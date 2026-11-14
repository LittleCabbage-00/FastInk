import 'package:flutter_test/flutter_test.dart';
import 'package:fastink_flutter/src/core/memory_policy.dart';
import 'package:fastink_flutter/src/core/memory_policy_catalog.dart';

void main() {
  test('memory profiles stay ordered and expose every settings option', () {
    final List<int> options = MemoryPolicyCatalog.options;

    expect(options, containsAll(<int>[4, 8, 16, 24, 32, 48, 64]));
    expect(options.toSet().length, options.length);
    for (int index = 1; index < options.length; index++) {
      expect(options[index], greaterThan(options[index - 1]));
    }
  });

  test('arbitrary and legacy values resolve without overstating memory', () {
    expect(MemoryPolicyCatalog.resolve(4).deviceMemoryGb, 4);
    expect(MemoryPolicyCatalog.resolve(12).deviceMemoryGb, 8);
    expect(MemoryPolicyCatalog.resolve(20).deviceMemoryGb, 16);
    expect(MemoryPolicyCatalog.resolve(40).deviceMemoryGb, 32);
    expect(MemoryPolicyCatalog.resolve(96).deviceMemoryGb, 64);
    expect(MemoryPolicyCatalog.normalize(null), 8);
  });

  test('larger profiles never reduce memory-dependent budgets', () {
    final List<MemoryPolicy> profiles = MemoryPolicyCatalog.profiles;
    for (int index = 1; index < profiles.length; index++) {
      final MemoryPolicy previous = profiles[index - 1];
      final MemoryPolicy current = profiles[index];
      expect(
        current.imageCacheEntries,
        greaterThanOrEqualTo(previous.imageCacheEntries),
      );
      expect(
        current.imageCacheMegabytes,
        greaterThanOrEqualTo(previous.imageCacheMegabytes),
      );
      expect(
        current.maximumPrefetchPages,
        greaterThanOrEqualTo(previous.maximumPrefetchPages),
      );
      expect(
        current.exportPagesPerPart,
        greaterThanOrEqualTo(previous.exportPagesPerPart),
      );
    }
  });
}
