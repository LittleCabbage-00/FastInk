part of 'markdown_editor.dart';

extension _MarkdownProductivity on _MarkdownEditorViewState {
  /// 按名称筛选工作区 Markdown 并优先展示已打开项，选择后先检查当前文件能否离开。
  Future<void> _quickOpen() async {
    final paths = <String, String>{};
    for (final path in [
      ...widget.openedPaths.reversed,
      ...widget.workspacePaths,
    ]) {
      paths.putIfAbsent(MarkdownWorkspace.canonical(path), () => path);
    }
    final picked = await _pickItem(
      tr('快速打开文稿 · 搜索文件名', 'Quick open · Search filenames'),
      {
        for (final path in paths.values)
          path:
              '${File(path).uri.pathSegments.last}  ·  ${File(path).parent.uri.pathSegments.where((s) => s.isNotEmpty).lastOrNull ?? ''}',
      },
    );
    if (picked != null && mounted) await _openWorkspaceNote(picked);
  }

  /// 把复制/删除/移动/待办切换应用到当前选中行，输入法组词期间不强行改写。
  void _editLines(MarkdownLineAction action) {
    if (_readOnly || _file == null) return;
    final next = editMarkdownLines(_text.value, action);
    if (next == _text.value) return;
    _text.value = next;
    _focusEditing();
  }

  /// 显示全文真实待办、过滤和完成统计，勾选只修改对应源标记，可定位原文并保持撤销记录。
  Future<void> _tasksDialog() async {
    String query = '';
    await showDialog<void>(
      context: context,
      animationStyle: appMotionStyle(context),
      builder: (dialogContext) => StatefulBuilder(
        builder: (ctx, change) => ValueListenableBuilder<TextEditingValue>(
          valueListenable: _text,
          builder: (_, value, _) {
            final tasks = MarkdownTask.parse(value.text);
            final done = tasks.where((task) => task.done).length;
            final visible = tasks
                .where(
                  (task) =>
                      (!_prefs.hideCompletedTasks || !task.done) &&
                      task.label.toLowerCase().contains(query.toLowerCase()),
                )
                .toList();
            return Dialog(
              child: SizedBox(
                width: 720,
                height: MediaQuery.sizeOf(context).height * .8,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${tr('本文待办', 'Document tasks')} · $done / ${tasks.length}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: tr('关闭'),
                            onPressed: () => Navigator.pop(dialogContext),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: TextField(
                        key: const ValueKey('markdown-task-search'),
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.search),
                          hintText: tr('筛选待办', 'Filter tasks'),
                        ),
                        onChanged: (v) => change(() => query = v),
                      ),
                    ),
                    SwitchListTile(
                      title: Text(tr('隐藏已完成待办', 'Hide completed tasks')),
                      value: _prefs.hideCompletedTasks,
                      onChanged: (v) {
                        _setPreferences(_prefs.copyWith(hideCompletedTasks: v));
                        change(() {});
                      },
                    ),
                    Expanded(
                      child: visible.isEmpty
                          ? Center(
                              child: Text(tr('没有匹配的待办', 'No matching tasks')),
                            )
                          : ListView.builder(
                              itemCount: visible.length,
                              itemBuilder: (_, i) {
                                final task = visible[i];
                                return ListTile(
                                  leading: Checkbox(
                                    key: ValueKey(
                                      'markdown-task-${task.marker}',
                                    ),
                                    value: task.done,
                                    onChanged: _readOnly
                                        ? null
                                        : (v) {
                                            // 列表根据当前控制器内容重建；
                                            // 仅改变复选框标记，其余源文本保持不变。
                                            _text.value = value.copyWith(
                                              text: value.text.replaceRange(
                                                task.marker,
                                                task.marker + 1,
                                                v == true ? 'x' : ' ',
                                              ),
                                              composing: TextRange.empty,
                                            );
                                          },
                                  ),
                                  title: Text(
                                    task.label,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      decoration: task.done
                                          ? TextDecoration.lineThrough
                                          : null,
                                    ),
                                  ),
                                  subtitle: Text(
                                    '${tr('行', 'Line')} ${task.line}',
                                  ),
                                  trailing: const Icon(
                                    Icons.my_location,
                                    size: 18,
                                  ),
                                  onTap: () {
                                    Navigator.pop(dialogContext);
                                    if (_mode == _MarkdownMode.read) {
                                      _change(() => _mode = _MarkdownMode.edit);
                                    }
                                    _jumpToOffset(task.offset);
                                  },
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// 把选区或全文保存为个人模板，同名另存，原文图像/链接引用按模板约定保留。
  Future<void> _saveTemplate() async {
    if (_file == null) return;
    final selection = _selection;
    final content = selection.isCollapsed
        ? _text.text
        : selection.textInside(_text.text);
    if (content.trim().isEmpty) {
      _change(
        () => _status = tr(
          '先写一些内容再保存模板',
          'Write some content before saving a template',
        ),
      );
      return;
    }
    final name = TextEditingController(
      text: _file!.fileName.replaceFirst(
        RegExp(r'\.md$', caseSensitive: false),
        '',
      ),
    );
    final result = await showDialog<String>(
      context: context,
      animationStyle: appMotionStyle(context),
      builder: (ctx) => AlertDialog(
        scrollable: true,
        title: Text(tr('保存为自定义模板', 'Save as custom template')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr(
                selection.isCollapsed ? '保存当前整篇正文' : '保存当前选中文字',
                selection.isCollapsed
                    ? 'Save the entire document'
                    : 'Save the selected text',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('markdown-template-name'),
              controller: name,
              autofocus: true,
              maxLength: 80,
              decoration: InputDecoration(
                labelText: tr('模板名称', 'Template name'),
              ),
              onSubmitted: (v) {
                if (v.trim().isNotEmpty) Navigator.pop(ctx, v);
              },
            ),
            const Text('{{date}}  {{time}}  {{title}}'),
            Text(
              tr(
                '插入时自动填入日期、时间和文稿名。',
                'Date, time and document name are filled in when inserting.',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr('取消')),
          ),
          FilledButton(
            onPressed: () {
              if (name.text.trim().isNotEmpty) Navigator.pop(ctx, name.text);
            },
            child: Text(tr('保存')),
          ),
        ],
      ),
    );
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 300), name.dispose),
    );
    if (result == null || !mounted) return;
    try {
      await MarkdownTemplates(widget.dataRoot).save(result, content);
      _change(() => _status = tr('模板已保存', 'Template saved'));
    } catch (error) {
      _change(() => _status = '${tr('保存失败')}: $error');
    }
  }

  /// 展示个人模板预览、插入与归档入口，移除模板不立即销毁其文件内容。
  Future<void> _manageTemplates() async {
    try {
      final store = MarkdownTemplates(widget.dataRoot);
      final templates = await store.read();
      if (!mounted) return;
      final picked = await _pickItem(
        tr('自定义模板 · 选择后预览', 'Custom templates · Select to preview'),
        {for (final t in templates) t.id: t.name},
      );
      if (picked == null || !mounted) return;
      final template = templates.firstWhere((t) => t.id == picked);
      final action = await showDialog<String>(
        context: context,
        animationStyle: appMotionStyle(context),
        builder: (ctx) => AlertDialog(
          scrollable: true,
          title: Text(template.name),
          content: SizedBox(
            width: 600,
            child: SelectableText(template.content),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'archive'),
              child: Text(tr('移除模板', 'Remove template')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(tr('关闭')),
            ),
            if (!_readOnly)
              FilledButton(
                onPressed: () => Navigator.pop(ctx, 'insert'),
                child: Text(tr('插入', 'Insert')),
              ),
          ],
        ),
      );
      if (!mounted) return;
      if (action == 'archive') {
        await store.archive(template);
        _change(() => _status = tr('模板已移除', 'Template removed'));
      }
      if (action == 'insert') _insertTemplateContent(template.content);
    } catch (error) {
      _change(
        () => _status = '${tr('模板读取失败', 'Cannot read templates')}: $error',
      );
    }
  }

  /// 展开受支持日期/标题变量并插入当前选区，作为源文编辑进入正常历史和保存流程。
  void _insertTemplateContent(String content) {
    final selected = _selection;
    final expanded = MarkdownTemplates.expand(
      content,
      title:
          _file?.fileName.replaceFirst(
            RegExp(r'\.md$', caseSensitive: false),
            '',
          ) ??
          '',
    );
    final before = selected.start > 0 && _text.text[selected.start - 1] != '\n'
        ? '\n\n'
        : '';
    _replaceRange(selected.start, selected.end, '$before$expanded');
  }
}
