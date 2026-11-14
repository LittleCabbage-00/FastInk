part of '../../app/fastink_app.dart';

extension _FastInkPenSettingsCards on _FastInkHomeState {
  /// 构建普通笔、荧光笔的默认样式及快速档位设置，二者分别保存。
  Widget _penDefaultsSettingsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.edit_rounded),
              title: Text(
                tr('默认笔型', 'Default pen'),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(tr('新打开的文档使用此笔型；工具栏仍可随时切换')),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                for (final (PenStyle style, String label)
                    in <(PenStyle, String)>[
                      (PenStyle.fountain, '钢笔'),
                      (PenStyle.ball, '圆珠笔'),
                      (PenStyle.brush, '画笔'),
                      (PenStyle.pencil, '铅笔'),
                    ])
                  ChoiceChip(
                    label: Text(tr(label)),
                    selected: style.name == _settings.penStyle,
                    onSelected: (_) => _setDefaultPenStyle(style),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            ListTile(
              key: const ValueKey('settings-default-pen-color'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.palette_outlined),
              title: Text(tr('默认墨水颜色', 'Default ink color')),
              subtitle: Text(
                tr(
                  '#${_settings.penColor.toRadixString(16).substring(2).toUpperCase()} · 中性色会适应纸张明暗',
                  '#${_settings.penColor.toRadixString(16).substring(2).toUpperCase()} · Neutral ink adapts to paper brightness',
                ),
              ),
              trailing: CircleAvatar(
                radius: 15,
                backgroundColor: Color(_settings.penColor),
              ),
              onTap: () => unawaited(_showColorPalette(penDefaults: true)),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                tr('工具栏快捷颜色（三格独立保存）'),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(height: 7),
            Wrap(
              spacing: 10,
              children: <Widget>[
                for (
                  int index = 0;
                  index < _settings.penColorPresets.length;
                  index++
                )
                  Tooltip(
                    message: tr(
                      '点击重设第 ${index + 1} 格',
                      'Click to change slot ${index + 1}',
                    ),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => unawaited(
                        _showColorPalette(slotIndex: index, penDefaults: true),
                      ),
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: Color(_settings.penColorPresets[index]),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Theme.of(context).colorScheme.primary,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.line_weight_rounded),
              title: Text(tr('钢笔三档粗细')),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    for (
                      int index = 0;
                      index < _settings.penWidthPresets.length;
                      index++
                    )
                      Builder(
                        builder: (BuildContext anchorContext) => ChoiceChip(
                          selected:
                              (_settings.penWidth -
                                      _settings.penWidthPresets[index])
                                  .abs() <
                              0.1,
                          label: Text(
                            '${_settings.penWidthPresets[index].toStringAsFixed(1)} px',
                          ),
                          onSelected: (_) => unawaited(
                            _showWidthPresetEditor(
                              anchorContext,
                              index,
                              highlighter: false,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.border_color_rounded),
              title: Text(tr('荧光笔三档粗细')),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    for (
                      int index = 0;
                      index < _settings.highlighterWidthPresets.length;
                      index++
                    )
                      Builder(
                        builder: (BuildContext anchorContext) => ChoiceChip(
                          selected:
                              (_settings.highlighterWidth -
                                      _settings.highlighterWidthPresets[index])
                                  .abs() <
                              0.1,
                          label: Text(
                            '${_settings.highlighterWidthPresets[index].toStringAsFixed(1)} px',
                          ),
                          onSelected: (_) => unawaited(
                            _showWidthPresetEditor(
                              anchorContext,
                              index,
                              highlighter: true,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
