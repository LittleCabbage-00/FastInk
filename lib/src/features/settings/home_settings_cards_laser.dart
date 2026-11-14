part of '../../app/fastink_app.dart';

extension _FastInkLaserSettingsCards on _FastInkHomeState {
  /// 构建激光点/尾迹、颜色、宽度与淡出时间选项，明确为临时显示工具。
  Widget _laserSettingsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.flashlight_on_outlined),
              title: Text(
                tr('激光笔默认值', 'Laser pointer defaults'),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                tr(
                  '设置页和工具栏中的修改都会立即保存',
                  'Changes from Settings or the toolbar are saved immediately',
                ),
              ),
            ),
            SegmentedButton<LaserMode>(
              showSelectedIcon: false,
              segments: <ButtonSegment<LaserMode>>[
                ButtonSegment(
                  value: LaserMode.dot,
                  icon: const Icon(Icons.circle, size: 12),
                  label: Text(tr('红点', 'Dot')),
                ),
                ButtonSegment(
                  value: LaserMode.trail,
                  icon: const Icon(Icons.gesture_rounded),
                  label: Text(tr('轨迹', 'Trail')),
                ),
              ],
              selected: <LaserMode>{
                LaserMode.values.firstWhere(
                  (v) => v.name == _settings.laserMode,
                  orElse: () => LaserMode.trail,
                ),
              },
              onSelectionChanged: (values) =>
                  unawaited(_setLaserDefaults(mode: values.first)),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 12,
              children: <Widget>[
                for (final Color color in const <Color>[
                  Color(0xffff3b30),
                  Color(0xff2f80ed),
                  Color(0xff34c759),
                ])
                  ChoiceChip(
                    label: Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    selected: _settings.laserColor == color.toARGB32(),
                    onSelected: (_) =>
                        unawaited(_setLaserDefaults(color: color)),
                  ),
              ],
            ),
            ListTile(
              leading: const Icon(Icons.line_weight_rounded),
              title: Text(
                tr(
                  '激光粗细 ${_settings.laserWidth.round()} px',
                  'Laser width: ${_settings.laserWidth.round()} px',
                ),
              ),
              subtitle: Slider(
                value: _settings.laserWidth,
                min: 3,
                max: 18,
                divisions: 15,
                label: '${_settings.laserWidth.round()} px',
                onChanged: (value) =>
                    _updateState(() => _settings.laserWidth = value),
                onChangeEnd: (value) => _setLaserDefaults(width: value),
              ),
            ),
            if (_settings.laserMode == 'trail')
              ListTile(
                leading: const Icon(Icons.timer_outlined),
                title: Text(
                  tr(
                    '轨迹消退 ${(_settings.laserFadeMs / 1000).toStringAsFixed(1)} 秒',
                    'Trail fade: ${(_settings.laserFadeMs / 1000).toStringAsFixed(1)} s',
                  ),
                ),
                subtitle: Slider(
                  value: _settings.laserFadeMs.toDouble(),
                  min: 300,
                  max: 1600,
                  divisions: 13,
                  label:
                      '${(_settings.laserFadeMs / 1000).toStringAsFixed(1)} s',
                  onChanged: (value) =>
                      _updateState(() => _settings.laserFadeMs = value.round()),
                  onChangeEnd: (value) =>
                      _setLaserDefaults(fadeMs: value.round()),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
