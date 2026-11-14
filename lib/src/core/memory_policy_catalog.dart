import 'memory_policy.dart';

/// 内存档位的唯一配置入口。
///
/// 新增档位时只需按内存从小到大插入一项。设置页会自动生成选项，
/// 设置解析、页面预读和导出流程也会通过 [resolve] 使用同一项配置。
class MemoryPolicyCatalog {
  /// 资源档位为静态配置，不需要创建目录实例。
  const MemoryPolicyCatalog._();

  /// defaultDeviceMemoryGb：未知或非法配置回退采用的设备内存档位，单位 GB。
  static const int defaultDeviceMemoryGb = 8;

  /// profiles：预定义设备资源档位，统一约束图像、预取和导出开销。
  static const List<MemoryPolicy> profiles = <MemoryPolicy>[
    MemoryPolicy(
      deviceMemoryGb: 4,
      imageCacheEntries: 20,
      imageCacheMegabytes: 32,
      maximumPrefetchPages: 1,
      exportPrefetchPages: 1,
      exportPagesPerPart: 4,
      currentPageWidth: 1800,
      previewPageWidth: 1400,
      workingSetLimitMegabytes: 384,
      sidebarThumbnailBudget: 2,
      sidebarInkCachePages: 8,
    ),
    MemoryPolicy(
      deviceMemoryGb: 8,
      imageCacheEntries: 32,
      imageCacheMegabytes: 48,
      maximumPrefetchPages: 2,
      exportPrefetchPages: 1,
      exportPagesPerPart: 6,
      currentPageWidth: 2200,
      previewPageWidth: 1800,
      workingSetLimitMegabytes: 512,
      sidebarThumbnailBudget: 3,
      sidebarInkCachePages: 16,
    ),
    MemoryPolicy(
      deviceMemoryGb: 16,
      imageCacheEntries: 48,
      imageCacheMegabytes: 64,
      maximumPrefetchPages: 3,
      exportPrefetchPages: 2,
      exportPagesPerPart: 8,
      currentPageWidth: 2600,
      previewPageWidth: 2200,
      workingSetLimitMegabytes: 768,
      sidebarThumbnailBudget: 5,
      sidebarInkCachePages: 32,
    ),
    MemoryPolicy(
      deviceMemoryGb: 24,
      imageCacheEntries: 56,
      imageCacheMegabytes: 80,
      maximumPrefetchPages: 4,
      exportPrefetchPages: 2,
      exportPagesPerPart: 10,
      currentPageWidth: 2880,
      previewPageWidth: 2500,
      workingSetLimitMegabytes: 896,
      sidebarThumbnailBudget: 6,
      sidebarInkCachePages: 40,
    ),
    MemoryPolicy(
      deviceMemoryGb: 32,
      imageCacheEntries: 64,
      imageCacheMegabytes: 96,
      maximumPrefetchPages: 4,
      exportPrefetchPages: 2,
      exportPagesPerPart: 12,
      currentPageWidth: 3200,
      previewPageWidth: 2800,
      workingSetLimitMegabytes: 1024,
      sidebarThumbnailBudget: 8,
      sidebarInkCachePages: 48,
    ),
    MemoryPolicy(
      deviceMemoryGb: 48,
      imageCacheEntries: 72,
      imageCacheMegabytes: 112,
      maximumPrefetchPages: 5,
      exportPrefetchPages: 3,
      exportPagesPerPart: 14,
      currentPageWidth: 3400,
      previewPageWidth: 3000,
      workingSetLimitMegabytes: 1280,
      sidebarThumbnailBudget: 8,
      sidebarInkCachePages: 64,
    ),
    MemoryPolicy(
      deviceMemoryGb: 64,
      imageCacheEntries: 80,
      imageCacheMegabytes: 128,
      maximumPrefetchPages: 6,
      exportPrefetchPages: 3,
      exportPagesPerPart: 16,
      currentPageWidth: 3600,
      previewPageWidth: 3200,
      workingSetLimitMegabytes: 1536,
      sidebarThumbnailBudget: 10,
      sidebarInkCachePages: 80,
    ),
  ];

  /// 返回支持的设备内存档位值，供设置界面展示。
  static List<int> get options => profiles
      .map((MemoryPolicy policy) => policy.deviceMemoryGb)
      .toList(growable: false);

  /// 对旧配置中的任意数值向下匹配最近档位，避免高估可用内存。
  static MemoryPolicy resolve(int gigabytes) {
    MemoryPolicy selected = profiles.first;
    for (final MemoryPolicy profile in profiles) {
      if (profile.deviceMemoryGb > gigabytes) break;
      selected = profile;
    }
    return selected;
  }

  /// 把未知或非法内存档位归一到受支持选项，避免读取不到资源策略。
  static int normalize(int? gigabytes) =>
      resolve(gigabytes ?? defaultDeviceMemoryGb).deviceMemoryGb;
}
