part of '../../app/fastink_app.dart';

extension _FastInkMemorySettingsCard on _FastInkHomeState {
  /// 展示设备内存档位和对应资源预算，变更通过统一策略应用到各仓库与缓存。
  Widget _memoryStrategySettingsCard() {
    final MemoryPolicy policy = _memoryPolicy;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.memory_rounded),
              title: Text(
                tr('设备内存', 'Device memory'),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                tr(
                  '选择电脑的内存容量，自动平衡长文稿的速度与内存占用',
                  'Choose your computer’s memory capacity to balance large-document speed and memory use',
                ),
              ),
              trailing: DropdownButton<int>(
                value: policy.deviceMemoryGb,
                underline: const SizedBox.shrink(),
                items: MemoryPolicyCatalog.profiles
                    .map(
                      (MemoryPolicy profile) => DropdownMenuItem<int>(
                        value: profile.deviceMemoryGb,
                        child: Text('${profile.deviceMemoryGb} GB'),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (int? value) {
                  if (value != null) unawaited(_setDeviceMemoryGb(value));
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(72, 0, 20, 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    ActionChip(
                      avatar: const Icon(
                        Icons.cleaning_services_outlined,
                        size: 18,
                      ),
                      label: Text(tr('清理临时缓存', 'Clear temporary caches')),
                      tooltip: tr(
                        '保留当前页与未保存内容',
                        'Keep the current page and unsaved content',
                      ),
                      onPressed: () =>
                          _releaseTransientMemory(notify: true, force: true),
                    ),
                  ],
                ),
              ),
            ),
            SwitchListTile.adaptive(
              secondary: const Icon(Icons.query_stats_outlined),
              title: Text(tr('显示页面性能信息')),
              subtitle: Text(
                tr(
                  '在当前页面右上角显示加载耗时、分辨率和总页数',
                  'Show load time, resolution and total pages in the upper-right of the current page',
                ),
              ),
              value: _settings.showPerformance,
              onChanged: _setShowPerformance,
            ),
          ],
        ),
      ),
    );
  }
}
