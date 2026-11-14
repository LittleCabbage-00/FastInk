part of 'markdown_editor.dart';

extension _MarkdownWorkbench on _MarkdownEditorViewState {
  /// 打开与资料库共用的独立 Markdown 设置面板，变更即时同步并保存。
  Future<void> _preferencesDialog() => showDialog<void>(
    context: context,
    animationStyle: appMotionStyle(context),
    builder: (_) => Dialog(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 700,
          maxHeight: MediaQuery.sizeOf(context).height * .85,
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      tr('Markdown 设置'),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    tooltip: tr('关闭'),
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: MarkdownSettingsPanel(
                  value: _prefs,
                  onChanged: _setPreferences,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  /// 调用 Windows 全屏桥切换 Markdown 书写布局，失败保留原可用界面并反馈。
  void _toggleFullscreen() {
    try {
      _window.setEnabled(!_window.enabled);
      _change(() {});
    } catch (error) {
      _change(() => _status = '${tr('全屏切换失败')}: $error');
    }
  }

  /// 打开可筛选通用选择器，确认返回稳定键，取消返回 null。
  Future<String?> _pickItem(String title, Map<String, String> items) =>
      showDialog<String>(
        context: context,
        animationStyle: appMotionStyle(context),
        builder: (_) => MarkdownItemPicker(title: title, items: items),
      );

  /// 整理当前可执行的 Markdown 命令并显示可筛选入口，选择后分派对应动作。
  Future<void> _commandPalette() async {
    final actions = <String, String>{
      if (widget.onCreateMarkdown != null) 'new': '新建 Markdown 文稿',
      'encoding': '以指定编码重新载入',
      'theme': '切换深浅色',
      'smaller': '缩小字号',
      'larger': '增大字号',
      'quick-open': '快速打开文稿 · Ctrl+P',
      'tasks': '本文待办总览',
      'save-template': '保存为自定义模板',
      'manage-templates': '管理自定义模板',
      'duplicate-line': '复制当前行 / 选中行 · Ctrl+Shift+D',
      'move-line-up': '上移当前行 / 选中行 · Alt+↑',
      'move-line-down': '下移当前行 / 选中行 · Alt+↓',
      'delete-line': '删除当前行 / 选中行 · Ctrl+Shift+K',
      'toggle-task': '完成 / 取消当前待办 · Ctrl+Enter',
      'insert-date': '插入当前日期和时间',
      'workspace': '全文搜索与标签',
      'links': '双链与反向链接',
      'properties': '文稿属性',
      'history': '本地版本历史',
      'slides': '幻灯片演示',
      'preferences': 'Markdown 设置',
      'heading': '快速跳转标题 · Ctrl+Shift+O',
      'line': '跳转到行 · Ctrl+L',
      'find': '查找 / 替换 · Ctrl+F',
      'save': '保存 · Ctrl+S',
      'templates': '从模板插入',
      'table': '编辑或插入表格',
      'paste-image': '粘贴剪贴板图片 · Ctrl+Alt+V',
      'image': '插入图片文件',
      'link': '插入链接',
      'bold': '粗体 · Ctrl+B',
      'italic': '斜体 · Ctrl+I',
      'list': '插入无序列表',
      'task': '插入待办列表',
      'quote': '插入引用',
      'code': '插入代码块',
      'math': '插入公式',
      'focus': '专注写作 · Ctrl+Shift+J',
      'typewriter': '打字机模式 · Ctrl+Shift+G',
      'fullscreen': '全屏 · F11',
      'sync': '切换同步滚动',
      'outline': '展开 / 收起目录',
      'copy-html': '复制为 HTML',
      'export': '快捷导出（${_prefs.exportFormat.toUpperCase()}）',
      'html': '导出 HTML',
      'pdf': '导出 PDF',
    };
    final picked = await _pickItem(tr('搜索命令 · 输入关键词'), {
      for (final entry in actions.entries) entry.key: tr(entry.value),
    });
    if (picked == null || !mounted) return;
    await Future<void>.delayed(const Duration(milliseconds: 180));
    if (!mounted) return;
    switch (picked) {
      case 'new':
        if (await _canLeave() && mounted) widget.onCreateMarkdown?.call();
      case 'find':
        _openFind();
      case 'save':
        await _save();
      case 'image':
        await _insertImage();
      case 'link':
        _wrap('[', '](https://)');
      case 'bold':
        _wrap('**', '**');
      case 'italic':
        _wrap('*', '*');
      case 'list':
        _prefix('- ');
      case 'task':
        _prefix('- [ ] ');
      case 'quote':
        _prefix('> ');
      case 'code':
        _block('```\n', '\n```');
      case 'math':
        _block('\$\$\n', '\n\$\$');
      case 'outline':
        _toggleToc();
      case 'export':
        await _export(_prefs.exportFormat);
      default:
        await _menuAction(picked);
    }
  }

  /// 从当前真实标题列表快速筛选并跳转到原文位置。
  Future<void> _quickHeading() async {
    final headings = MarkdownEditorService.extractToc(_text.text);
    final picked = await _pickItem(tr('搜索标题'), {
      for (int i = 0; i < headings.length; i++)
        '$i': '${'  ' * (headings[i].level - 1)}${headings[i].title}',
    });
    if (picked == null || !mounted) return;
    _jumpToOffset(headings[int.parse(picked)].offset);
  }

  /// 校验用户输入的一基行号，换算为全文字符偏移后在当前编辑模式揭示该行。
  Future<void> _goToLine() async {
    final controller = TextEditingController();
    final count = '\n'.allMatches(_text.text).length + 1;
    final value = await showDialog<int>(
      context: context,
      animationStyle: appMotionStyle(context),
      builder: (ctx) => AlertDialog(
        title: Text(tr('跳转到行')),
        content: TextField(
          key: const ValueKey('markdown-line-number'),
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(hintText: '1 – $count'),
          onSubmitted: (value) {
            final line = int.tryParse(value);
            if (line != null) Navigator.pop(ctx, line.clamp(1, count));
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr('取消')),
          ),
          FilledButton(
            onPressed: () {
              final line = int.tryParse(controller.text);
              if (line != null) Navigator.pop(ctx, line.clamp(1, count));
            },
            child: Text(tr('跳转')),
          ),
        ],
      ),
    );
    unawaited(
      Future<void>.delayed(
        const Duration(milliseconds: 300),
        controller.dispose,
      ),
    );
    if (value == null || !mounted) return;
    final offsets = [
      0,
      for (final match in '\n'.allMatches(_text.text)) match.end,
    ];
    _change(() => _mode = _MarkdownMode.edit);
    _jumpToOffset(offsets[value - 1]);
  }

  /// 读取剪贴板图片并通过资源服务保存，再插入对应 Markdown 引用，不把二进制直接塞进普通文本选区。
  Future<void> _pasteImage() async {
    if (_readOnly || _file == null) return;
    final selection = _selection;
    try {
      final bytes = widget.readClipboardImage != null
          ? await widget.readClipboardImage!()
          : await WindowsCapture().readImage(_window.windowHandle);
      if (bytes == null) {
        _change(() => _status = tr('剪贴板中没有图片'));
        return;
      }
      final path = await _service.insertImageBytes(bytes);
      if (!mounted) return;
      _replaceRange(selection.start, selection.end, '![](<$path>)');
    } catch (error) {
      _change(() => _status = '${tr('粘贴图片失败')}: $error');
    }
  }

  /// 显示内置与个人模板，选择后展开变量并插入当前编辑位置。
  Future<void> _insertTemplate() async {
    if (_readOnly) return;
    const templates = {
      'daily': ('每日记录', '# 每日记录\n\n## 今日重点\n- [ ] \n\n## 学习与记录\n\n## 今日回顾\n'),
      'meeting': (
        '会议记录',
        '# 会议记录\n\n- 日期：\n- 参会人：\n\n## 议题\n1. \n\n## 讨论记录\n\n## 决议与行动\n| 事项 | 负责人 | 截止时间 |\n| --- | --- | --- |\n|  |  |  |\n',
      ),
      'reading': (
        '阅读笔记',
        '# 阅读笔记\n\n- 书名：\n- 作者：\n\n## 核心观点\n\n## 摘录\n> \n\n## 思考与联系\n\n## 待查问题\n- [ ] \n',
      ),
      'project': (
        '项目计划',
        '# 项目计划\n\n## 目标\n\n## 里程碑\n| 阶段 | 交付物 | 日期 |\n| --- | --- | --- |\n|  |  |  |\n\n## 任务\n- [ ] \n\n## 风险与跟进\n',
      ),
      'research': (
        '实验记录',
        '# 实验记录\n\n## 目的与假设\n\n## 材料与方法\n\n## 数据\n| 项目 | 结果 | 备注 |\n| --- | --- | --- |\n|  |  |  |\n\n## 分析\n\n## 结论\n',
      ),
    };
    try {
      final custom = await MarkdownTemplates(widget.dataRoot).read();
      if (!mounted) return;
      final picked = await _pickItem(tr('选择模板 · 插入当前光标处'), {
        for (final entry in templates.entries) entry.key: tr(entry.value.$1),
        for (final item in custom)
          item.id: '${tr('自定义', 'Custom')} · ${item.name}',
      });
      if (picked == null || !mounted) return;
      _insertTemplateContent(
        templates[picked]?.$2 ??
            custom.firstWhere((t) => t.id == picked).content,
      );
    } catch (error) {
      _change(
        () => _status = '${tr('模板读取失败', 'Cannot read templates')}: $error',
      );
    }
  }

  /// 识别选区附近的表格或创建新表格，用单元格控制器编辑并转回 Markdown，保留转义竖线与对齐。
  Future<void> _editTable() async {
    if (_readOnly) return;
    final selection = _selection;
    final source = _text.text;
    final range = MarkdownTableData.around(source, selection.start);
    var table = range?.$3 ?? MarkdownTableData.empty(3, 2);
    final controllers = <TextEditingController>[];
    // 为当前表格各单元格建立文本控制器矩阵，行列操作后要配对释放旧控制器。
    List<List<TextEditingController>> cells() {
      final rows = [
        for (final row in table.rows)
          [for (final cell in row) TextEditingController(text: cell)],
      ];
      controllers.addAll(rows.expand((row) => row));
      return rows;
    }

    var fields = cells();
    // 将表格输入控制器的当前全文收集回临时数据，结构调整前不丢失未确认文字。
    void capture() {
      table = MarkdownTableData([
        for (final row in fields) [for (final field in row) field.text],
      ], table.alignments);
    }

    final result = await showDialog<String>(
      context: context,
      animationStyle: appMotionStyle(context),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, change) => AlertDialog(
          title: Text(tr(range == null ? '插入表格' : '编辑表格')),
          content: SizedBox(
            width: 700,
            height: MediaQuery.sizeOf(context).height * .5,
            child: Column(
              children: [
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton.icon(
                      onPressed: table.rows.length >= 51
                          ? null
                          : () => change(() {
                              capture();
                              table = table.withRow();
                              fields = cells();
                            }),
                      icon: const Icon(Icons.add),
                      label: Text(tr('添加行')),
                    ),
                    TextButton.icon(
                      onPressed: table.rows.first.length >= 10
                          ? null
                          : () => change(() {
                              capture();
                              table = table.withColumn();
                              fields = cells();
                            }),
                      icon: const Icon(Icons.add),
                      label: Text(tr('添加列')),
                    ),
                    TextButton(
                      onPressed: table.rows.length <= 2
                          ? null
                          : () => change(() {
                              capture();
                              table = MarkdownTableData(
                                table.rows.sublist(0, table.rows.length - 1),
                                table.alignments,
                              );
                              fields = cells();
                            }),
                      child: Text(tr('删除末行')),
                    ),
                    TextButton(
                      onPressed: table.rows.first.length <= 1
                          ? null
                          : () => change(() {
                              capture();
                              table = MarkdownTableData(
                                [
                                  for (final row in table.rows)
                                    row.sublist(0, row.length - 1),
                                ],
                                table.alignments.sublist(
                                  0,
                                  table.alignments.length - 1,
                                ),
                              );
                              fields = cells();
                            }),
                      child: Text(tr('删除末列')),
                    ),
                  ],
                ),
                Expanded(
                  child: SingleChildScrollView(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Column(
                        children: [
                          Row(
                            children: [
                              for (
                                int col = 0;
                                col < table.rows.first.length;
                                col++
                              )
                                SizedBox(
                                  width: 150,
                                  child: DropdownButton<String>(
                                    value: table.alignments[col],
                                    items: [
                                      for (final value in [
                                        'left',
                                        'center',
                                        'right',
                                      ])
                                        DropdownMenuItem(
                                          value: value,
                                          child: Text(
                                            tr(switch (value) {
                                              'left' => '左对齐',
                                              'center' => '居中',
                                              _ => '右对齐',
                                            }),
                                          ),
                                        ),
                                    ],
                                    onChanged: (value) => change(() {
                                      capture();
                                      table.alignments[col] = value!;
                                    }),
                                  ),
                                ),
                            ],
                          ),
                          for (int row = 0; row < fields.length; row++)
                            Row(
                              children: [
                                for (
                                  int col = 0;
                                  col < fields[row].length;
                                  col++
                                )
                                  SizedBox(
                                    width: 150,
                                    child: Padding(
                                      padding: const EdgeInsets.all(3),
                                      child: TextField(
                                        key: ValueKey(
                                          'markdown-cell-$row-$col',
                                        ),
                                        controller: fields[row][col],
                                        decoration: InputDecoration(
                                          isDense: true,
                                          border: const OutlineInputBorder(),
                                          hintText: row == 0 ? tr('表头') : null,
                                        ),
                                        style: row == 0
                                            ? const TextStyle(
                                                fontWeight: FontWeight.w600,
                                              )
                                            : null,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(tr('取消')),
            ),
            FilledButton(
              onPressed: () {
                capture();
                Navigator.pop(ctx, table.toMarkdown());
              },
              child: Text(tr('应用表格')),
            ),
          ],
        ),
      ),
    );
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 300), () {
        for (final controller in controllers) {
          controller.dispose();
        }
      }),
    );
    if (result == null || !mounted) return;
    if (_text.text != source) {
      _change(() => _status = tr('正文已变化，请重新打开表格'));
      return;
    }
    if (range != null) {
      _replaceRange(range.$1, range.$2, result);
    } else {
      _replaceRange(
        selection.start,
        selection.end,
        '${selection.start > 0 ? '\n\n' : ''}$result\n',
      );
    }
  }

  /// 把 Markdown 正文转换为独立 HTML 文档，整理样式、资源引用及允许的结构用于导出。
  String _htmlDocument(String content) {
    final fragment = html_parser.parseFragment(
      md.markdownToHtml(
        content,
        extensionSet: md.ExtensionSet.gitHubWeb,
        blockSyntaxes: [md.FootnoteDefSyntax()],
      ),
    );
    // 递归整理输出 DOM 中不适用于导出的节点/属性，不能把 UI 交互容器原样当正文。
    void clean(html_dom.Node node) {
      for (final child in node.nodes.toList()) {
        if (child is html_dom.Element) {
          if (const {
            'script',
            'iframe',
            'object',
            'embed',
            'style',
            'link',
            'meta',
          }.contains(child.localName)) {
            child.remove();
            continue;
          }
          child.attributes.removeWhere(
            (key, value) =>
                key.toString().toLowerCase().startsWith('on') ||
                (const {'href', 'src'}.contains(key) &&
                    RegExp(
                      r'^\s*(javascript|vbscript):',
                      caseSensitive: false,
                    ).hasMatch(value)),
          );
        }
        clean(child);
      }
    }

    clean(fragment);
    final dark = _prefs.exportDark && widget.darkMode;
    return '<!doctype html>\n<html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${const HtmlEscape().convert(_file?.fileName ?? 'Markdown')}</title>'
        '<style>body{max-width:${_prefs.previewWidth}px;margin:32px auto;padding:0 24px;font: ${_prefs.previewFontSize}px/1.7 "Segoe UI","Microsoft YaHei",sans-serif;background:${dark ? '#101217' : '#fff'};color:${dark ? '#e6edf3' : '#1f2328'}}img{max-width:100%;height:auto}pre{padding:16px;overflow:auto;background:${dark ? '#23272f' : '#f0f2f5'};border-radius:8px}code{font-family:Consolas,monospace}table{border-collapse:collapse;width:100%}th,td{border:1px solid #888;padding:8px}blockquote{border-left:3px solid #999;margin-left:0;padding-left:16px}a{color:#6a80d8}</style></head><body>${fragment.outerHtml}</body></html>';
  }
}
