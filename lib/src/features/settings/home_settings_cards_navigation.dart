part of '../../app/fastink_app.dart';

extension _FastInkNavigationSettingsCards on _FastInkHomeState {
  /// 构建与导航交互有关的推荐设置，旧高级偏好仍兼容但不额外堆叠无必要开关。
  Widget _gesturePerformanceSettingsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.gesture_rounded),
              title: Text(
                tr('页面导航与手势', 'Page navigation and gestures'),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              trailing: TextButton(
                onPressed: _restoreNavigationPerformanceDefaults,
                child: Text(tr('恢复推荐值')),
              ),
            ),
            SwitchListTile.adaptive(
              secondary: const Icon(Icons.touch_app_outlined),
              title: Text(tr('双击缩放')),
              subtitle: Text(tr('用手指双击页面时在 100% 和 200% 间切换')),
              value: _settings.doubleTapZoomEnabled,
              onChanged: _setDoubleTapZoomEnabled,
            ),
            ListTile(
              leading: const Icon(Icons.swipe_vertical_rounded),
              title: Text(
                _settings.touchInertiaStrength == 0
                    ? tr('手指滑动惯性：关闭', 'Touch scroll inertia: Off')
                    : tr(
                        '手指滑动惯性：${_settings.touchInertiaStrength.toStringAsFixed(1)}×',
                        'Touch scroll inertia: ${_settings.touchInertiaStrength.toStringAsFixed(1)}×',
                      ),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    tr(
                      '松手后的减速滑行强度；关闭后仍保持手指跟手滚动',
                      'Controls coast after release; finger tracking remains smooth when Off',
                    ),
                  ),
                  Slider(
                    value: _settings.touchInertiaStrength,
                    min: 0,
                    max: 2,
                    divisions: 8,
                    label: _settings.touchInertiaStrength == 0
                        ? tr('关闭', 'Off')
                        : '${_settings.touchInertiaStrength.toStringAsFixed(1)}×',
                    onChanged: (double value) => _updateState(
                      () => _settings.touchInertiaStrength = value,
                    ),
                    onChangeEnd: _setTouchInertiaStrength,
                  ),
                ],
              ),
            ),
            SwitchListTile.adaptive(
              secondary: const Icon(Icons.zoom_in_map_rounded),
              title: Text(tr('切页保持缩放')),
              subtitle: Text(
                tr(
                  _settings.keepZoomOnPageChange
                      ? '用页码、目录或按钮跳页时保持比例；连续滑动不改变缩放'
                      : '用页码、目录或按钮跳页时恢复到 100%；连续滑动不改变缩放',
                ),
              ),
              value: _settings.keepZoomOnPageChange,
              onChanged: _setKeepZoomOnPageChange,
            ),
          ],
        ),
      ),
    );
  }
}
