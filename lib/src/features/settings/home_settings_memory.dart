part of '../../app/fastink_app.dart';

/// 应用内存档位，并把依赖该档位的运行策略一起更新。
extension _FastInkMemorySettings on _FastInkHomeState {
  /// 规范化内存档位并把预算应用到图像、PDF、笔迹缓存及导出，必要时释放可重建资源。
  Future<void> _setDeviceMemoryGb(int value) async {
    final MemoryPolicy policy = MemoryPolicyCatalog.resolve(value);
    final int activeEntries = math.min(
      _settings.imageCacheEntries,
      policy.imageCacheEntries,
    );
    final int activeMegabytes = math.min(
      _settings.imageCacheMegabytes,
      policy.imageCacheMegabytes,
    );

    // 先取消旧档位安排的后台任务，再切换限制，防止降档后仍残留
    // 较大的预取队列。当前页和未保存笔迹不受影响。
    _repository.cancelPdfPrefetch();
    _ink.rasterCacheMegabytes = policy.inkRasterCacheMegabytes;
    _exportRepository
      ..pdfPagesPerPart = policy.exportPagesPerPart
      ..exportPrefetchPages = policy.exportPrefetchPages;
    ImageCacheBudget.apply(entries: activeEntries, megabytes: activeMegabytes);
    _updateState(() {
      _settings.deviceMemoryGb = policy.deviceMemoryGb;
      _doc.status = tr(
        '已切换到 ${policy.deviceMemoryGb} GB 内存档位',
        'Memory profile changed to ${policy.deviceMemoryGb} GB',
      );
    });
    _checkWorkingSet();
    await _settingsRepository.update(
      (AppSettings current) =>
          current.copyWith(deviceMemoryGb: policy.deviceMemoryGb),
    );
  }
}
