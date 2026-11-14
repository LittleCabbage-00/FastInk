part of '../../app/fastink_app.dart';

extension _FastInkMemoryPressure on _FastInkHomeState {
  /// 保留当前页和未保存笔迹，只释放能从磁盘重新生成的内容。
  void _releaseTransientMemory({required bool notify, bool force = false}) {
    final DateTime now = DateTime.now();
    if (!force &&
        now.difference(_lastMemoryRelief) < const Duration(seconds: 5)) {
      return;
    }
    _lastMemoryRelief = now;
    ImageCacheBudget.relieveMemoryPressure();
    if (force) {
      ImageCacheBudget.apply(
        entries: math.min(
          _settings.imageCacheEntries,
          _memoryPolicy.imageCacheEntries,
        ),
        megabytes: math.min(
          _settings.imageCacheMegabytes,
          _memoryPolicy.imageCacheMegabytes,
        ),
      );
    }
    _repository.releaseTransientCaches();
    if (notify && mounted) {
      _updateState(
        () => _doc.status = tr(
          '已释放邻页预览和后台缓存；当前页和未保存内容已保留',
          'Preview and background caches released; the current page and unsaved content are retained',
        ),
      );
    }
  }

  /// 页面加载完成后检查一次工作集，不使用高频定时器，避免监控本身增加负载。
  void _checkWorkingSet() {
    final int limitBytes = _memoryPolicy.workingSetLimitMegabytes * 1024 * 1024;
    if (ProcessInfo.currentRss > limitBytes) {
      _releaseTransientMemory(notify: false);
    }
  }
}
