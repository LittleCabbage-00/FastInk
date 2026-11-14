part of '../../app/fastink_app.dart';

extension _FastInkPrimarySettingsCards on _FastInkHomeState {
  /// 用固定的轻、中、重压力样本比较设置效果，线宽按实际笔型公式绘制。
  Widget _pressureWidthPreview() {
    final colors = Theme.of(context).colorScheme;
    final style = PenStyle.values.firstWhere(
      (value) => value.name == _settings.penStyle,
      orElse: () => PenStyle.fountain,
    );
    final curve = PressureCurve.values.firstWhere(
      (value) => value.name == _settings.pressureCurve,
      orElse: () => PressureCurve.linear,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            style == PenStyle.ball
                ? tr(
                    '圆珠笔为固定粗细。切换钢笔、画笔或铅笔可体验压感。',
                    'Ballpoint has a fixed width. Try fountain pen, brush or pencil for pressure.',
                  )
                : tr('当前笔型的压感预览', 'Pressure preview for the current pen'),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              for (final (label, pressure) in [
                (tr('轻', 'Light'), 0.2),
                (tr('中', 'Medium'), 0.5),
                (tr('重', 'Heavy'), 0.8),
              ])
                Expanded(
                  child: Column(
                    children: [
                      SizedBox(
                        height: 24,
                        child: Center(
                          child: Container(
                            width: 48,
                            height:
                                10 *
                                penPressureWidthFactor(
                                  style,
                                  mapPenPressure(
                                    pressure,
                                    curve,
                                    _settings.pressureSensitivity,
                                  ),
                                ),
                            decoration: ShapeDecoration(
                              color: colors.onSurface,
                              shape: const StadiumBorder(),
                            ),
                          ),
                        ),
                      ),
                      Text(
                        label,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// 显示实际数据/配置目录及迁移、备份、恢复入口，操作范围与目录类型明确区分。
  Widget _storageSettingsCard() {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.folder_special_outlined, color: colors.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    tr('资料库存储'),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              tr('当前保存位置'),
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 5),
            SelectableText(
              _displayLocalPath(_dataRoot),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              tr(
                '笔迹按文档独立目录保存，导入页面也按每次导入独立建目录；不会散放到你选择的文件夹根部。更改位置会迁移整个资料库。',
                'Each document keeps its ink in a separate folder, and every import gets its own folder. Changing this location migrates the entire library.',
              ),
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: <Widget>[
                FilledButton.icon(
                  onPressed: _libraryBusy ? null : _chooseStorageLocation,
                  icon: const Icon(Icons.drive_file_move_outline),
                  label: Text(tr('更改保存位置')),
                ),
                OutlinedButton.icon(
                  onPressed: _openStorageLocation,
                  icon: const Icon(Icons.folder_open_outlined),
                  label: Text(tr('打开文件夹')),
                ),
              ],
            ),

            const Divider(),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.backup_outlined),
              title: Text(tr('创建可编辑备份', 'Create editable backup')),
              subtitle: Text(
                tr(
                  '保存原稿、独立笔迹、图片资源、模板、目录和书签',
                  'Preserve pages, ink, assets, templates and bookmarks',
                ),
              ),
              onTap: _libraryBusy ? null : () => _backupLibrary(),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.restore_outlined),
              title: Text(tr('从备份恢复', 'Restore backup')),
              subtitle: Text(
                tr(
                  '校验文件后恢复到新资料库，保留当前资料库',
                  'Verify and restore to a new library; keep the current library',
                ),
              ),
              onTap: _libraryBusy ? null : () => _backupLibrary(restore: true),
            ),
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Icon(Icons.settings_suggest_outlined, color: colors.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    tr('配置保存位置'),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  tooltip: tr('打开配置文件夹'),
                  onPressed: _openConfigStorageLocation,
                  icon: const Icon(Icons.folder_open_outlined),
                ),
              ],
            ),
            Text(
              tr(
                '颜色槽、粗细、侧键、外观和其他设置都保存在这里。切换后立即生效。',
                'Color slots, widths, pen buttons, appearance, and other preferences are stored here. Changes take effect immediately.',
              ),
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                for (final (String value, String label, IconData icon)
                    in const <(String, String, IconData)>[
                      ('document', '文档目录', Icons.description_outlined),
                      ('program', '程序安装目录', Icons.apps_outlined),
                      ('user', '用户 .fastink', Icons.person_outline_rounded),
                    ])
                  ChoiceChip(
                    avatar: Icon(icon, size: 18),
                    label: Text(tr(label)),
                    selected: _settings.configStorageLocation == value,
                    onSelected: _libraryBusy
                        ? null
                        : (_) => unawaited(_setConfigStorageLocation(value)),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            SelectableText(
              _displayLocalPath(SettingsRepository.activeConfigRoot),
              style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建橡皮默认模式和范围，临时侧键橡皮不应覆盖这些默认项。
  Widget _eraserSettingsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.auto_fix_normal_rounded),
              title: Text(
                tr('橡皮擦默认值'),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                tr(
                  '工具栏与“跟随设置”的侧键橡皮使用此模式；“局部橡皮擦”侧键固定为局部模式',
                  'Used by the toolbar and Use settings eraser action; Partial eraser always stays partial',
                ),
              ),
            ),
            SegmentedButton<EraserMode>(
              segments: <ButtonSegment<EraserMode>>[
                ButtonSegment<EraserMode>(
                  value: EraserMode.stroke,
                  icon: const Icon(Icons.auto_fix_normal_rounded),
                  label: Text(tr('整笔')),
                ),
                ButtonSegment<EraserMode>(
                  value: EraserMode.point,
                  icon: const Icon(Icons.blur_circular_rounded),
                  label: Text(tr('局部')),
                ),
              ],
              selected: <EraserMode>{
                EraserMode.values.firstWhere(
                  (v) => v.name == _settings.eraserMode,
                  orElse: () => EraserMode.stroke,
                ),
              },
              onSelectionChanged: (Set<EraserMode> value) {
                unawaited(_setEraserDefaults(mode: value.first));
              },
            ),
            if (_settings.eraserMode == 'point')
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.radio_button_checked),
                title: Text(
                  tr(
                    '局部范围 ${(_settings.eraserSize * 2).round()} px',
                    'Partial eraser size ${(_settings.eraserSize * 2).round()} px',
                  ),
                ),
                subtitle: Slider(
                  value: _settings.eraserSize,
                  min: 6,
                  max: 60,
                  divisions: 18,
                  label: '${(_settings.eraserSize * 2).round()} px',
                  onChanged: (double value) =>
                      _updateState(() => _settings.eraserSize = value),
                  onChangeEnd: (double value) =>
                      _setEraserDefaults(size: value),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 构建触笔压感、输入设备限制和侧键映射选项，当前值与运行时处理同步。
  Widget _penInputSettingsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.draw_rounded),
              title: Text(
                tr('手写笔与侧键'),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                tr(
                  '修改后立即生效 · $_lastPenEvent',
                  'Changes apply immediately · $_lastPenEvent',
                ),
                maxLines: 2,
              ),
            ),
            _penButtonActionTile(
              logicalButton: 1,
              action: _decodePenButtonAction(
                _settings.penButtonOneAction,
                PenButtonAction.eraser,
              ),
            ),
            _penButtonActionTile(
              logicalButton: 2,
              action: _decodePenButtonAction(
                _settings.penButtonTwoAction,
                PenButtonAction.lasso,
              ),
            ),
            SwitchListTile.adaptive(
              secondary: const Icon(Icons.touch_app_rounded),
              title: Text(tr('按住临时切换')),
              subtitle: Text(
                tr(
                  _settings.penButtonMomentary
                      ? '松开侧键后自动恢复原工具'
                      : '按一次直接切换工具，松开后保持',
                ),
              ),
              value: _settings.penButtonMomentary,
              onChanged: _setPenButtonMomentary,
            ),
            SwitchListTile.adaptive(
              secondary: const Icon(Icons.swap_vert_rounded),
              title: Text(tr('交换一键/二键识别')),
              subtitle: Text(tr('部分 Surface、HP 或 Wacom 笔会把两个侧键上报为相反顺序')),
              value: _settings.swapPenButtons,
              onChanged: _setSwapPenButtons,
            ),
            const Divider(height: 20),
            SwitchListTile.adaptive(
              secondary: const Icon(Icons.touch_app_outlined),
              title: Text(tr('笔尖压感')),
              subtitle: Text(tr('根据压力实时改变钢笔、画笔和铅笔粗细')),
              value: _settings.pressureEnabled,
              onChanged: _setPressureEnabled,
            ),
            AnimatedSize(
              duration: appMotionDuration(context, 180),
              curve: Curves.easeOutCubic,
              child: _settings.pressureEnabled
                  ? ListTile(
                      key: const ValueKey<String>('pressure-sensitivity'),
                      leading: const Icon(Icons.tune_rounded),
                      title: Text(
                        '${tr('压感灵敏度')} · '
                        '${_settings.pressureSensitivity.toStringAsFixed(1)}',
                      ),
                      subtitle: Slider(
                        value: _settings.pressureSensitivity,
                        min: 0.5,
                        max: 2.0,
                        divisions: 15,
                        label: _settings.pressureSensitivity.toStringAsFixed(1),
                        onChanged: (double value) {
                          _updateState(
                            () => _settings.pressureSensitivity = value,
                          );
                        },
                        onChangeEnd: _setPressureSensitivity,
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            if (_settings.pressureEnabled)
              ListTile(
                leading: const Icon(Icons.show_chart_rounded),
                title: Text(tr('压感曲线', 'Pressure curve')),
                subtitle: Text(
                  tr(
                    '柔和：轻按就变粗。硬朗：用力后才变粗。',
                    'Gentle thickens with a light press. Firm requires more pressure.',
                  ),
                ),
                trailing: DropdownButtonHideUnderline(
                  child: DropdownButton<PressureCurve>(
                    value: PressureCurve.values.firstWhere(
                      (v) => v.name == _settings.pressureCurve,
                      orElse: () => PressureCurve.linear,
                    ),
                    onChanged: (PressureCurve? value) {
                      if (value != null) unawaited(_setPressureCurve(value));
                    },
                    items: <DropdownMenuItem<PressureCurve>>[
                      DropdownMenuItem(
                        value: PressureCurve.linear,
                        child: Text(tr('线性', 'Linear')),
                      ),
                      DropdownMenuItem(
                        value: PressureCurve.gentle,
                        child: Text(tr('柔和', 'Gentle')),
                      ),
                      DropdownMenuItem(
                        value: PressureCurve.firm,
                        child: Text(tr('硬朗', 'Firm')),
                      ),
                    ],
                  ),
                ),
              ),
            if (_settings.pressureEnabled) _pressureWidthPreview(),
            SwitchListTile.adaptive(
              secondary: const Icon(Icons.edit_outlined),
              title: Text(tr('仅允许笔书写')),
              subtitle: Text(
                tr(
                  '鼠标仍可滚轮浏览、使用框选与选区手柄，但不能写字或擦除',
                  'Mouse scrolling, selection and handles still work; mouse drawing and erasing are disabled',
                ),
              ),
              value: _settings.stylusOnly,
              onChanged: _setStylusOnly,
            ),
          ],
        ),
      ),
    );
  }
}
