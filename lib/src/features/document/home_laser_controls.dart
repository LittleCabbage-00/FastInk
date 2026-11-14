part of '../../app/fastink_app.dart';

extension _FastInkLaserControls on _FastInkHomeState {
  /// 构建激光模式、颜色、宽度与淡出时长控件；这些参数只影响临时激光显示。
  Widget _laserToolOptions() => KeyedSubtree(
    key: const ValueKey<String>('laser-options'),
    child: _toolbarGroup(<Widget>[
      SegmentedButton<LaserMode>(
        showSelectedIcon: false,
        segments: <ButtonSegment<LaserMode>>[
          ButtonSegment<LaserMode>(
            value: LaserMode.dot,
            icon: const Icon(Icons.circle, size: 12),
            label: Text(tr('红点')),
          ),
          ButtonSegment<LaserMode>(
            value: LaserMode.trail,
            icon: const Icon(Icons.gesture_rounded, size: 18),
            label: Text(tr('轨迹')),
          ),
        ],
        selected: <LaserMode>{
          LaserMode.values.firstWhere(
            (v) => v.name == _settings.laserMode,
            orElse: () => LaserMode.trail,
          ),
        },
        onSelectionChanged: (Set<LaserMode> value) =>
            unawaited(_setLaserDefaults(mode: value.first)),
      ),
      for (final Color color in const <Color>[
        Color(0xffff3b30),
        Color(0xff2f80ed),
        Color(0xff34c759),
      ])
        Tooltip(
          message: tr('激光颜色'),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () => unawaited(_setLaserDefaults(color: color)),
            child: Container(
              width: 27,
              height: 27,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: _settings.laserColor == color.toARGB32()
                      ? Colors.white
                      : Colors.white38,
                  width: _settings.laserColor == color.toARGB32() ? 3 : 1,
                ),
              ),
            ),
          ),
        ),
      PopupMenuButton<double>(
        popUpAnimationStyle: appMotionStyle(context),
        tooltip: tr('激光粗细'),
        onSelected: (double value) =>
            unawaited(_setLaserDefaults(width: value)),
        itemBuilder: (_) => <PopupMenuEntry<double>>[
          for (final double width in const <double>[5, 7, 10, 14])
            PopupMenuItem<double>(
              value: width,
              child: Row(
                children: <Widget>[
                  Container(
                    width: width,
                    height: width,
                    decoration: BoxDecoration(
                      color: Color(_settings.laserColor),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text('${width.round()} px'),
                  const Spacer(),
                  if ((_settings.laserWidth - width).abs() < 0.1)
                    const Icon(Icons.check_rounded, size: 18),
                ],
              ),
            ),
        ],
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 10),
          child: Text('${_settings.laserWidth.round()} px'),
        ),
      ),
      if (_settings.laserMode == 'trail')
        PopupMenuButton<int>(
          popUpAnimationStyle: appMotionStyle(context),
          tooltip: tr('轨迹消退速度'),
          onSelected: (int value) =>
              unawaited(_setLaserDefaults(fadeMs: value)),
          itemBuilder: (_) => <PopupMenuEntry<int>>[
            PopupMenuItem(value: 500, child: Text(tr('快速消退 · 0.5 秒'))),
            PopupMenuItem(value: 800, child: Text(tr('标准消退 · 0.8 秒'))),
            PopupMenuItem(value: 1200, child: Text(tr('慢速消退 · 1.2 秒'))),
          ],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(Icons.timer_outlined, size: 17),
                const SizedBox(width: 4),
                Text('${(_settings.laserFadeMs / 1000).toStringAsFixed(1)} s'),
              ],
            ),
          ),
        ),
    ]),
  );
}
