part of '../../app/fastink_app.dart';

class _ColorPalettePopup extends PopupMenuEntry<Color> {
  /// 接收当前色板与颜色选择回调。
  /// colors：颜色面板可选择的 Color 列表，当前色通过 selected 独立标记。
  /// selected：颜色面板当前选中的 Color，用于展示选中态。
  const _ColorPalettePopup({required this.colors, required this.selected});

  /// colors：颜色面板可选择的 Color 列表，当前色通过 selected 独立标记。
  final List<Color> colors;

  /// selected：颜色面板当前选中的 Color，用于展示选中态。
  final Color selected;

  /// 色板行的菜单布局高度，单位为逻辑像素。
  @override
  double get height => 112;

  /// 由色板内的色块显示选中颜色。
  @override
  bool represents(Color? value) => false;

  /// 维护面板内的颜色选择交互。
  @override
  State<_ColorPalettePopup> createState() => _ColorPalettePopupState();
}

class _ColorPalettePopupState extends State<_ColorPalettePopup> {
  /// 排列快捷色块，点选后通知宿主。
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 272,
      height: widget.height,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (final Color color in widget.colors)
              Tooltip(
                message:
                    '#${color.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => Navigator.pop(context, color),
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: widget.selected.toARGB32() == color.toARGB32()
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.outlineVariant,
                        width: widget.selected.toARGB32() == color.toARGB32()
                            ? 3
                            : 1,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _EraserSettingsPopup extends PopupMenuEntry<void> {
  /// 接收当前橡皮模式、擦除范围和修改回调。
  /// initialMode：橡皮面板打开时的初始模式，取消/关闭不应误重置其他参数。
  /// initialSize：橡皮面板初始逻辑半径，与滑杆和光标预览保持一致。
  /// 将控件的新值传给宿主。
  /// highlighterOnly：橡皮是否仅处理荧光笔的初始配置。
  /// onHighlighterOnlyChanged：仅擦荧光笔开关变化通知宿主的回调。
  const _EraserSettingsPopup({
    required this.initialMode,
    required this.initialSize,
    required this.onChanged,
    required this.highlighterOnly,
    required this.onHighlighterOnlyChanged,
  });

  /// highlighterOnly：橡皮是否仅处理荧光笔的初始配置。
  final bool highlighterOnly;

  /// onHighlighterOnlyChanged：仅擦荧光笔开关变化通知宿主的回调。
  final ValueChanged<bool> onHighlighterOnlyChanged;

  /// initialMode：橡皮面板打开时的初始模式，取消/关闭不应误重置其他参数。
  final EraserMode initialMode;

  /// initialSize：橡皮面板初始逻辑半径，与滑杆和光标预览保持一致。
  final double initialSize;

  /// 将控件的新值传给宿主。
  final void Function(EraserMode mode, double size) onChanged;

  /// 橡皮模式和半径面板的菜单布局高度，单位为逻辑像素。
  @override
  double get height => 178;

  /// 由面板内的模式控件显示当前橡皮。
  @override
  bool represents(void value) => false;

  /// 维护面板内的擦除模式和范围。
  @override
  State<_EraserSettingsPopup> createState() => _EraserSettingsPopupState();
}

class _EraserSettingsPopupState extends State<_EraserSettingsPopup> {
  /// _mode：橡皮弹出面板当前暂选模式，变化时与范围一起通知宿主。
  late EraserMode _mode = widget.initialMode;

  /// _size：橡皮弹出面板当前逻辑半径，控件变动后即时预览。
  late double _size = widget.initialSize;

  /// _highlighterOnly：橡皮弹出面板当前是否仅擦荧光笔。
  late bool _highlighterOnly = widget.highlighterOnly;

  /// 把橡皮模式与范围的新组合通知宿主，面板即时状态和默认值持久化由上层协调。
  void _changed() => widget.onChanged(_mode, _size);

  /// 显示局部擦和整笔擦模式，以及局部擦半径。
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 310,
      height: widget.height,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SizedBox(
              height: 42,
              child: SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(tr('仅擦除荧光笔', 'Erase highlighter only')),
                value: _highlighterOnly,
                onChanged: (value) {
                  setState(() => _highlighterOnly = value);
                  widget.onHighlighterOnlyChanged(value);
                },
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
              selected: <EraserMode>{_mode},
              onSelectionChanged: (Set<EraserMode> value) {
                setState(() => _mode = value.first);
                _changed();
              },
            ),
            AnimatedSize(
              duration: appMotionDuration(context, 160),
              child: _mode == EraserMode.point
                  ? Row(
                      children: <Widget>[
                        Expanded(
                          child: Slider(
                            value: _size,
                            min: 6,
                            max: 60,
                            divisions: 18,
                            onChanged: (double value) {
                              setState(() => _size = value);
                              _changed();
                            },
                          ),
                        ),
                        SizedBox(
                          width: 58,
                          child: Text('${(_size * 2).round()} px'),
                        ),
                      ],
                    )
                  : const SizedBox(height: 46),
            ),
            Text(
              tr('点外部自动保存'),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WidthPresetPopup extends PopupMenuEntry<double> {
  /// 接收笔宽的初始值、可调范围、步数和预览颜色。
  /// initialValue：笔宽编辑面板初始数值，校验后再交回预设槽位。
  /// minimum：滑杆或数值编辑允许的最小值，与 maximum 一起限制有效范围。
  /// 可输入的笔宽上限，单位为逻辑像素。
  /// divisions：滑杆在最小与最大值之间划分的离散档数。
  /// 绘制颜色。
  /// 将控件的新值传给宿主。
  const _WidthPresetPopup({
    required this.initialValue,
    required this.minimum,
    required this.maximum,
    required this.divisions,
    required this.color,
    required this.onChanged,
  });

  /// initialValue：笔宽编辑面板初始数值，校验后再交回预设槽位。
  final double initialValue;

  /// minimum：滑杆或数值编辑允许的最小值，与 maximum 一起限制有效范围。
  final double minimum;

  /// 可输入的笔宽上限，单位为逻辑像素。
  final double maximum;

  /// divisions：滑杆在最小与最大值之间划分的离散档数。
  final int divisions;

  /// 绘制颜色。
  final Color color;

  /// 将控件的新值传给宿主。
  final ValueChanged<double> onChanged;

  /// 笔宽滑杆面板的菜单布局高度，单位为逻辑像素。
  @override
  double get height => 92;

  /// 由滑杆显示当前笔宽。
  @override
  bool represents(double? value) => false;

  /// 维护滑杆和圆点预览使用的笔宽。
  @override
  State<_WidthPresetPopup> createState() => _WidthPresetPopupState();
}

class _WidthPresetPopupState extends State<_WidthPresetPopup> {
  /// 滑杆和圆点预览使用的笔宽，拖动时同步给宿主。
  late double _value = widget.initialValue;

  /// 显示笔宽滑杆、圆点和数值。拖动时即时更新宿主。
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 270,
      height: widget.height,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              children: <Widget>[
                SizedBox(
                  width: 28,
                  height: 28,
                  child: Center(
                    child: Container(
                      width: math.max(4, math.min(26, _value)),
                      height: math.max(4, math.min(26, _value)),
                      decoration: BoxDecoration(
                        color: widget.color,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Slider(
                    value: _value,
                    min: widget.minimum,
                    max: widget.maximum,
                    divisions: widget.divisions,
                    onChanged: (double next) {
                      setState(() => _value = next);
                      widget.onChanged(next);
                    },
                  ),
                ),
                SizedBox(
                  width: 55,
                  child: Text(
                    '${_value.toStringAsFixed(1)} px',
                    textAlign: TextAlign.end,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
              ],
            ),
            Text(
              tr('拖动调节 · 点外部自动保存'),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
