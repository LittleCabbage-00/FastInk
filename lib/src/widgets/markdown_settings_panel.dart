import 'package:flutter/material.dart';
import '../core/app_localizations.dart';
import '../core/markdown_preferences.dart';

/// 资料库与活动编辑器复用同一个设置界面。
class MarkdownSettingsPanel extends StatefulWidget {
  /// 创建不可变的 MarkdownSettingsPanel 参数对象；各参数保存在对应字段中，不在构造时执行外部读写。
  /// value：宿主传入的 Markdown 配置快照，面板变化后通过 onChanged 通知宿主。
  /// 将控件的新值传给宿主。
  const MarkdownSettingsPanel({
    super.key,
    required this.value,
    required this.onChanged,
  });

  /// value：宿主传入的 Markdown 配置快照，面板变化后通过 onChanged 通知宿主。
  final MarkdownPreferences value;

  /// 将控件的新值传给宿主。
  final ValueChanged<MarkdownPreferences> onChanged;

  @override
  State<MarkdownSettingsPanel> createState() => _MarkdownSettingsPanelState();
}

class _MarkdownSettingsPanelState extends State<MarkdownSettingsPanel> {
  /// _value：面板内正在显示的配置副本，外部配置变化时由 didUpdateWidget 同步。
  late MarkdownPreferences _value = widget.value;

  /// 宿主配置快照变化时更新面板副本，避免编辑器与资料库设置显示不一致。
  @override
  void didUpdateWidget(covariant MarkdownSettingsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) _value = widget.value;
  }

  /// 更新面板当前值并通知宿主保存，独立于手写配置。
  void _commit(MarkdownPreferences value) {
    setState(() => _value = value);
    widget.onChanged(value);
  }

  /// 构建五个 Markdown 设置分组，各组使用独立 PageStorageKey，不能与父滚动位置共用类型。
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          const Icon(Icons.edit_document),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              tr('Markdown 编辑器', 'Markdown editor'),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ),
          IconButton(
            tooltip: tr('恢复 Markdown 默认设置', 'Reset Markdown defaults'),
            onPressed: () => _commit(const MarkdownPreferences()),
            icon: const Icon(Icons.restart_alt),
          ),
        ],
      ),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(
          tr(
            '以下设置仅用于 Markdown，修改后自动保存。',
            'These settings apply only to Markdown and are saved automatically.',
          ),
        ),
      ),
      // 每组独立保存展开状态，避免与外层滚动位置共用存储键而发生类型冲突。
      ExpansionTile(
        key: const PageStorageKey<String>('markdown-settings-editing'),
        initiallyExpanded: true,
        tilePadding: EdgeInsets.zero,
        title: Text(tr('编辑与输入', 'Editing and input')),
        children: [
          _toggle(
            'showWordCount',
            '显示字数与选区统计',
            _value.showWordCount,
            (v) => _value.copyWith(showWordCount: v),
          ),
          _choice(
            'defaultMode',
            '默认打开方式',
            _value.defaultMode,
            {'live': '实时编辑', 'edit': '仅编辑', 'split': '分栏预览', 'read': '仅阅读'},
            (v) => _value.copyWith(defaultMode: v),
          ),
          _toggle(
            'lineNumbers',
            '显示行号',
            _value.lineNumbers,
            (v) => _value.copyWith(lineNumbers: v),
          ),
          _toggle(
            'syntaxHighlight',
            '源码与代码块高亮',
            _value.syntaxHighlight,
            (v) => _value.copyWith(syntaxHighlight: v),
          ),
          _toggle(
            'autoPair',
            '自动配对括号、引号和反引号',
            _value.autoPair,
            (v) => _value.copyWith(autoPair: v),
          ),
          _toggle(
            'continueLists',
            '回车续写列表、待办和引用',
            _value.continueLists,
            (v) => _value.copyWith(continueLists: v),
            subtitle: '空列表项再次回车会退出列表',
          ),
          _toggle(
            'autoSave',
            'Markdown 自动保存',
            _value.autoSave,
            (v) => _value.copyWith(autoSave: v),
            subtitle: '关闭后仍会在返回资料库时保存；编辑外部原文件始终需要手动保存',
          ),
        ],
      ),
      ExpansionTile(
        key: const PageStorageKey<String>('markdown-settings-reading'),
        tilePadding: EdgeInsets.zero,
        title: Text(tr('排版与阅读', 'Typography and reading')),
        children: [
          _choice(
            'editorFont',
            '源码字体',
            _value.editorFont,
            {
              'Consolas': 'Consolas（等宽）',
              'Microsoft YaHei UI': '微软雅黑',
              'Segoe UI': 'Segoe UI',
            },
            (v) => _value.copyWith(editorFont: v),
          ),
          _slider(
            'fontSize',
            '源码字号',
            _value.fontSize,
            11,
            26,
            15,
            '${_value.fontSize.round()} px',
            (v) => _value.copyWith(fontSize: v),
          ),
          _slider(
            'lineHeight',
            '源码行距',
            _value.lineHeight,
            1.2,
            2.2,
            10,
            '${_value.lineHeight.toStringAsFixed(1)}×',
            (v) => _value.copyWith(lineHeight: v),
          ),
          _slider(
            'previewFontSize',
            '实时编辑与预览字号',
            _value.previewFontSize,
            12,
            26,
            14,
            '${_value.previewFontSize.round()} px',
            (v) => _value.copyWith(previewFontSize: v),
          ),
          _slider(
            'previewWidth',
            '预览正文宽度',
            _value.previewWidth,
            600,
            1200,
            12,
            '${_value.previewWidth.round()} px',
            (v) => _value.copyWith(previewWidth: v),
          ),
        ],
      ),
      ExpansionTile(
        key: const PageStorageKey<String>('markdown-settings-preview'),
        tilePadding: EdgeInsets.zero,
        title: Text(tr('预览', 'Preview')),
        children: [
          _toggle(
            'diagramEnabled',
            '渲染 Mermaid 图表',
            _value.diagramEnabled,
            (v) => _value.copyWith(diagramEnabled: v),
            subtitle: '离线显示流程图、时序图等；需要电脑上已安装 Edge 或 Chrome',
          ),

          _toggle(
            'mathEnabled',
            '渲染 LaTeX 公式',
            _value.mathEnabled,
            (v) => _value.copyWith(mathEnabled: v),
          ),
          _toggle(
            'remoteImages',
            '加载网络图片',
            _value.remoteImages,
            (v) => _value.copyWith(remoteImages: v),
            subtitle: '关闭后仅显示本地图片，网络图片显示占位提示',
          ),
        ],
      ),
      ExpansionTile(
        key: const PageStorageKey<String>('markdown-settings-export'),
        tilePadding: EdgeInsets.zero,
        title: Text(tr('导出', 'Export')),
        children: [
          _choice(
            'exportFormat',
            '快捷导出默认格式',
            _value.exportFormat,
            {
              'pdf': 'PDF',
              'png': 'PNG',
              'jpg': 'JPG',
              'md': 'Markdown + 图片资源',
              'html': 'HTML + 图片资源',
              'docx': 'Word（DOCX）',
              'txt': '纯文本（TXT）',
            },
            (v) => _value.copyWith(exportFormat: v),
          ),
          _slider(
            'exportScale',
            'PDF 与图片清晰度',
            _value.exportScale,
            1,
            2,
            2,
            '${_value.exportScale.toStringAsFixed(1)}×',
            (v) => _value.copyWith(exportScale: v),
          ),

          _toggle(
            'exportDark',
            '导出时跟随当前深浅色',
            _value.exportDark,
            (v) => _value.copyWith(exportDark: v),
            subtitle: '关闭时始终使用白底；不改变编辑器主题',
          ),
        ],
      ),
      ExpansionTile(
        key: const PageStorageKey<String>('markdown-settings-history'),
        tilePadding: EdgeInsets.zero,
        title: Text(tr('本地历史', 'Local history')),
        children: [
          _toggle(
            'historyEnabled',
            '自动保留 Markdown 历史版本',
            _value.historyEnabled,
            (v) => _value.copyWith(historyEnabled: v),
            subtitle: '保存更改前保留旧正文；恢复时先备份当前内容，不需要 Git 或账号',
          ),
        ],
      ),
    ],
  );

  /// 创建布尔设置项，参数给出字段键、文案、当前值和生成新配置的函数。
  Widget _toggle(
    String key,
    String title,
    bool value,
    MarkdownPreferences Function(bool) change, {
    String? subtitle,
  }) => SwitchListTile(
    key: ValueKey('markdown-setting-$key'),
    contentPadding: EdgeInsets.zero,
    title: Text(tr(title)),
    subtitle: subtitle == null ? null : Text(tr(subtitle)),
    value: value,
    onChanged: (v) => _commit(change(v)),
  );

  /// 创建限定字符串选项选择器，保存稳定选项值而不是翻译标签。
  Widget _choice(
    String key,
    String title,
    String value,
    Map<String, String> options,
    MarkdownPreferences Function(String) change,
  ) => ListTile(
    key: ValueKey('markdown-setting-$key'),
    contentPadding: EdgeInsets.zero,
    title: Text(tr(title)),
    subtitle: DropdownButton<String>(
      value: value,
      isExpanded: true,
      items: [
        for (final entry in options.entries)
          DropdownMenuItem(
            value: entry.key,
            child: Text(tr(entry.value), overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: (v) {
        if (v != null) _commit(change(v));
      },
    ),
  );

  /// 创建有范围约束的数值设置控件，变化后通过统一配置提交入口通知宿主。
  Widget _slider(
    String key,
    String title,
    double value,
    double min,
    double max,
    int divisions,
    String label,
    MarkdownPreferences Function(double) change,
  ) => Column(
    key: ValueKey('markdown-setting-$key'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('${tr(title)} · $label'),
      Slider(
        value: value.clamp(min, max),
        min: min,
        max: max,
        divisions: divisions,
        onChanged: (v) => setState(() => _value = change(v)),
        onChangeEnd: (v) => _commit(change(v)),
      ),
    ],
  );
}
