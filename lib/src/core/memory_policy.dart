/// 一档设备内存对应的运行预算。
///
/// 这里只保存策略结果，不负责选择档位。档位表放在
/// [MemoryPolicyCatalog] 中，避免界面、设置解析和导出逻辑各自维护一份规则。
class MemoryPolicy {
  /// 声明一个资源预算档位，各项只限制缓存、预取与导出批次，不改变保存精度。
  const MemoryPolicy({
    required this.deviceMemoryGb,
    required this.imageCacheEntries,
    required this.imageCacheMegabytes,
    required this.maximumPrefetchPages,
    required this.exportPrefetchPages,
    required this.exportPagesPerPart,
    required this.currentPageWidth,
    required this.previewPageWidth,
    required this.workingSetLimitMegabytes,
    required this.sidebarThumbnailBudget,
    required this.sidebarInkCachePages,
  });

  /// deviceMemoryGb：选择的设备内存档位，单位 GB，用于解析资源预算。
  final int deviceMemoryGb;

  /// imageCacheEntries：Flutter 图像缓存条目数量预算。
  final int imageCacheEntries;

  /// imageCacheMegabytes：Flutter 图像缓存容量预算，单位 MB。
  final int imageCacheMegabytes;

  /// 从图像缓存预算推导笔迹瓦片预算，限制在 24–64 MB，避免显示缓存无限增长。
  int get inkRasterCacheMegabytes => imageCacheMegabytes.clamp(24, 64);

  /// maximumPrefetchPages：自适应预取允许的最大页数。
  final int maximumPrefetchPages;

  /// exportPrefetchPages：逐页导出预先读取的页面数量预算。
  final int exportPrefetchPages;

  /// exportPagesPerPart：大型 PDF 分段处理的每段页面预算。
  final int exportPagesPerPart;

  /// currentPageWidth：当前页屏幕底图的最大解码宽度，单位像素。
  final int currentPageWidth;

  /// previewPageWidth：邻页低分辨率底图的最大解码宽度，单位像素。
  final int previewPageWidth;

  /// workingSetLimitMegabytes：触发瞬态缓存释放的工作集阈值，单位 MB。
  final int workingSetLimitMegabytes;

  /// 侧栏每次滚动停止后最多处理的页数，缩略图渲染和笔迹读取共用这一个
  /// 上限。低端设备少处理几页，避免 pdftoppm 打满 CPU、也避免一次性把
  /// 大量笔迹 JSON 读进内存。
  ///
  /// 两个流程各自串行（笔迹读一条队列，pdftoppm 渲染另一条），所以任意
  /// 时刻并发的 IO 最多是"一次笔迹读 + 一次 PDF 渲染"。分开排队的代价是
  /// 两者可能重叠，换来的是笔迹预览不用排在慢渲染后面。
  final int sidebarThumbnailBudget;

  /// 侧栏笔迹预览缓存保留的页数上限，按最近使用淘汰。
  ///
  /// 一页笔迹反序列化后是几百 KB 的 [InkStroke] 列表（点数越多越大），
  /// 所以不能按文档页数缓存——3000 页的 PDF 会直接把内存吃光。这里只
  /// 缓存侧栏实际翻看过的那些页，超出就淘汰最久未用的。
  final int sidebarInkCachePages;
}
