part of 'markdown_editor.dart';

extension _MarkdownWorkspaceUi on _MarkdownEditorViewState {
  /// 构建当前 Markdown 会话标签，切换和关闭先走保存/退出检查，路径身份由宿主维护。
  Widget _documentTabs() => Material(
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    child: SizedBox(
      height: 38,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        children: [
          for (final path in widget.openedPaths)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: InputChip(
                key: ValueKey(
                  'markdown-tab-${MarkdownWorkspace.canonical(path)}',
                ),
                selected:
                    _file != null &&
                    MarkdownWorkspace.canonical(_file!.path) ==
                        MarkdownWorkspace.canonical(path),
                label: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 180),
                  child: Text(
                    File(path).uri.pathSegments.last,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                onPressed: _exporting ? null : () => _openWorkspaceNote(path),
                onDeleted: _exporting || widget.onCloseTab == null
                    ? null
                    : () async {
                        final active =
                            _file != null &&
                            MarkdownWorkspace.canonical(_file!.path) ==
                                MarkdownWorkspace.canonical(path);
                        if (active && !await _canLeave()) return;
                        if (mounted) widget.onCloseTab!(path, active);
                      },
                deleteButtonTooltipMessage: tr('关闭文稿标签'),
              ),
            ),
          if (widget.onCreateMarkdown != null)
            IconButton(
              tooltip: tr('新建 Markdown 文稿'),
              onPressed: () async {
                if (await _canLeave() && mounted) {
                  widget.onCreateMarkdown?.call();
                }
              },
              icon: const Icon(Icons.add, size: 18),
            ),
        ],
      ),
    ),
  );

  /// 让用户选择编码并重新读取外部文件，脏状态先检查，避免错误重载覆盖未保存文本。
  Future<void> _reloadEncoding() async {
    if (_file == null) return;
    if (_file!.isDirty) {
      _change(() => _status = tr('请先保存当前修改，再重新选择编码'));
      return;
    }
    final selected = await _pickItem(tr('选择文件编码（保存时统一使用 UTF-8）'), {
      'auto': '自动识别',
      'utf-8': 'UTF-8',
      'gbk': 'GBK',
      'big5': 'Big5',
      'shift-jis': 'Shift-JIS',
    });
    if (selected == null || !mounted) return;
    try {
      final decoded = await MarkdownEncoding.read(
        File(_externalPath ?? _file!.path),
        encoding: selected,
      );
      if (!mounted) return;
      _text.removeListener(_onTextChanged);
      _text.value = TextEditingValue(
        text: decoded.$1,
        selection: const TextSelection.collapsed(offset: 0),
      );
      _lastText = _preview = decoded.$1;
      _file!.content = decoded.$1;
      _file!.lastSavedContent = decoded.$1;
      _file!.tocItems = MarkdownEditorService.extractToc(decoded.$1);
      _text.addListener(_onTextChanged);
      _change(() => _status = '${tr('已载入')} · ${decoded.$2}');
    } catch (error) {
      _change(() => _status = '${tr('编码转换失败')}: $error');
    }
  }

  /// 为 HTML 输出准备本地图像、图表等资源引用，完成后再生成可携带的正文。
  Future<String> _htmlPreparedContent(String content) async {
    if (!_prefs.diagramEnabled) return content;
    var result = content;
    for (final block in MarkdownDiagrams.blocks(content).reversed) {
      final file = await MarkdownDiagrams.render(
        block.$3,
        dark: _prefs.exportDark && widget.darkMode,
      );
      result = result.replaceRange(
        block.$1,
        block.$2,
        '<img alt="Mermaid" src="data:image/png;base64,${base64Encode(await file.readAsBytes())}">',
      );
    }
    return result;
  }

  /// 读取当前合法工作区文稿的轻量信息，复用按文件指纹缓存的解析结果。
  Future<List<MarkdownNoteInfo>> _workspaceNotes() => MarkdownWorkspace.read(
    widget.workspacePaths,
    currentPath: _externalPath ?? _file?.path,
    currentContent: _text.text,
  );

  /// 通过退出检查后请求宿主打开目标路径，可携带同篇标题锚点。
  Future<void> _openWorkspaceNote(String path, {String? anchor}) async {
    if (_file != null &&
        MarkdownWorkspace.canonical(_externalPath ?? _file!.path) ==
            MarkdownWorkspace.canonical(path)) {
      return;
    }
    if (widget.onOpenMarkdown == null) {
      _change(() => _status = tr('请从资料库打开链接的文稿'));
      return;
    }
    if (!await _canLeave()) return;
    if (mounted) {
      widget.onOpenMarkdown!(
        anchor?.isNotEmpty == true
            ? File(path).absolute.uri.replace(fragment: anchor).toString()
            : path,
      );
    }
  }

  /// 跨工作区搜索标题、标签和正文，展示上下文并可定位打开，废纸篓路径由宿主排除。
  Future<void> _workspaceSearch({String initialQuery = ''}) async {
    final notes = await _workspaceNotes();
    if (!mounted) return;
    String query = initialQuery;
    final controller = TextEditingController(text: query);
    final result = await showDialog<String>(
      context: context,
      animationStyle: appMotionStyle(context),
      builder: (dialogContext) => StatefulBuilder(
        builder: (ctx, change) {
          final lower = query.trim().toLowerCase();
          final matches = notes
              .where(
                (note) => lower.startsWith('tag:')
                    ? note.tags.any(
                        (tag) => tag.toLowerCase() == lower.substring(4).trim(),
                      )
                    : lower.isEmpty ||
                          note.title.toLowerCase().contains(lower) ||
                          note.content.toLowerCase().contains(lower),
              )
              .take(200)
              .toList();
          final tags = {for (final note in notes) ...note.tags}.toList()
            ..sort();
          return Dialog(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 850,
                maxHeight: MediaQuery.sizeOf(context).height * .85,
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: TextField(
                      key: const ValueKey('markdown-workspace-search'),
                      controller: controller,
                      autofocus: true,
                      onChanged: (value) => change(() => query = value),
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search),
                        hintText: tr('搜索全文，或输入 tag:标签'),
                        suffixIcon: IconButton(
                          tooltip: tr('关闭'),
                          onPressed: () => Navigator.pop(dialogContext),
                          icon: const Icon(Icons.close),
                        ),
                      ),
                    ),
                  ),
                  if (tags.isNotEmpty)
                    SizedBox(
                      height: 42,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        children: [
                          for (final tag in tags)
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: ActionChip(
                                label: Text('#$tag'),
                                onPressed: () => change(() {
                                  query = 'tag:$tag';
                                  controller.text = query;
                                }),
                              ),
                            ),
                        ],
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(
                      '${notes.length} ${tr('篇文稿')} · ${matches.length} ${tr('个结果')}',
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      children: [
                        for (final note in matches)
                          ListTile(
                            leading: const Icon(Icons.description_outlined),
                            title: Text(note.title),
                            subtitle: Text(
                              _searchSnippet(note.content, lower),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () =>
                                Navigator.pop(dialogContext, note.path),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    unawaited(
      Future<void>.delayed(
        const Duration(milliseconds: 300),
        controller.dispose,
      ),
    );
    if (result != null && mounted) {
      final current = _externalPath ?? _file?.path;
      if (current != null &&
          MarkdownWorkspace.canonical(current) ==
              MarkdownWorkspace.canonical(result)) {
        final needle = query.trim().toLowerCase();
        final offset = needle.startsWith('tag:')
            ? 0
            : _text.text.toLowerCase().indexOf(needle);
        if (_mode == _MarkdownMode.read) {
          _change(() => _mode = _MarkdownMode.edit);
        }
        _jumpToOffset(offset < 0 ? 0 : offset);
      } else {
        await _openWorkspaceNote(result);
      }
    }
  }

  /// 按查询首处匹配截取周围正文用于结果显示，截断只影响摘要而不修改文件。
  String _searchSnippet(String text, String query) {
    final body = MarkdownWorkspace.plainBody(text);
    final position = query.isEmpty || query.startsWith('tag:')
        ? 0
        : body.toLowerCase().indexOf(query);
    final start = (position - 45).clamp(0, body.length);
    final end = (start + 180).clamp(0, body.length);
    return '${start > 0 ? '…' : ''}${body.substring(start, end).replaceAll('\n', ' ')}';
  }

  /// 解析 Wiki 引用的目标与可选标题，按别名/标题/文件名查找候选后打开。
  Future<void> _followWiki(String reference) async {
    if (_file == null) return;
    final notes = await _workspaceNotes();
    if (!mounted) return;
    final matches = MarkdownWorkspace.resolve(
      notes,
      reference,
      _externalPath ?? _file!.path,
    );
    if (matches.isEmpty) {
      _change(() => _status = tr('未找到链接文稿：$reference；可在资料库新建同名 Markdown'));
      return;
    }
    String? path;
    if (matches.length == 1) {
      path = matches.single.path;
    } else {
      path = await _pickItem(tr('多个同名文稿，请选择'), {
        for (final note in matches) note.path: '${note.title} · ${note.path}',
      });
    }
    if (path == null || !mounted) return;
    final anchor = reference.split('|').first.split('#').skip(1).join('#');
    if (MarkdownWorkspace.canonical(path) ==
            MarkdownWorkspace.canonical(_externalPath ?? _file!.path) &&
        anchor.isNotEmpty) {
      final heading = MarkdownEditorService.extractToc(_text.text)
          .where((item) => item.title.toLowerCase() == anchor.toLowerCase())
          .firstOrNull;
      if (heading != null) _jumpToOffset(heading.offset);
    } else {
      await _openWorkspaceNote(path, anchor: anchor);
    }
  }

  /// 显示当前文稿的出链与反向链接，依据实际工作区索引而非只看已打开标签。
  Future<void> _linksDialog() async {
    if (_file == null) return;
    final notes = await _workspaceNotes();
    if (!mounted) return;
    final path = _externalPath ?? _file!.path;
    final current = MarkdownWorkspace.inspect(path, _text.text);
    final outgoing = <MarkdownNoteInfo>{
      for (final link in current.links)
        ...MarkdownWorkspace.resolve(notes, link, path),
    }.toList();
    final incoming = notes
        .where(
          (note) =>
              MarkdownWorkspace.canonical(note.path) !=
                  MarkdownWorkspace.canonical(path) &&
              note.links.any(
                (link) => MarkdownWorkspace.resolve(
                  [current],
                  link,
                  note.path,
                ).isNotEmpty,
              ),
        )
        .toList();
    final result = await showDialog<String>(
      context: context,
      animationStyle: appMotionStyle(context),
      builder: (ctx) => AlertDialog(
        title: Text(tr('双链与反向链接')),
        content: SizedBox(
          width: 640,
          height: MediaQuery.sizeOf(context).height * .55,
          child: ListView(
            children: [
              Text(
                tr('链接到其他文稿'),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              for (final note in outgoing)
                ListTile(
                  leading: const Icon(Icons.arrow_forward),
                  title: Text(note.title),
                  onTap: () => Navigator.pop(ctx, note.path),
                ),
              if (outgoing.isEmpty) Text(tr('使用 [[文稿名]] 或 [[文稿名|显示文字]] 建立链接')),
              const Divider(),
              Text(
                tr('链接到本文的文稿'),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              for (final note in incoming)
                ListTile(
                  leading: const Icon(Icons.arrow_back),
                  title: Text(note.title),
                  onTap: () => Navigator.pop(ctx, note.path),
                ),
              if (incoming.isEmpty) Text(tr('暂无反向链接')),
              const Divider(),
              Text(
                tr('标签'),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              Wrap(
                spacing: 6,
                children: [
                  for (final tag in current.tags)
                    ActionChip(
                      label: Text('#$tag'),
                      onPressed: () => Navigator.pop(ctx, 'tag:$tag'),
                    ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr('关闭')),
          ),
        ],
      ),
    );
    if (result == null || !mounted) return;
    if (result.startsWith('tag:')) {
      await _workspaceSearch(initialQuery: result);
    } else {
      await _openWorkspaceNote(result);
    }
  }

  /// 编辑受支持 YAML 属性，保留其他已有字段与注释，不整篇重写正文。
  Future<void> _propertiesDialog() async {
    if (_readOnly) return;
    final original = _text.text;
    final properties = MarkdownWorkspace.properties(original);
    final controllers = <String, TextEditingController>{};
    for (final key in ['title', 'type', 'status', 'tags', 'aliases']) {
      final value = properties[key];
      controllers[key] = TextEditingController(
        text: value is List ? value.join(', ') : value?.toString() ?? '',
      );
    }
    final result = await showDialog<bool>(
      context: context,
      animationStyle: appMotionStyle(context),
      builder: (ctx) => AlertDialog(
        title: Text(tr('文稿属性')),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(tr('属性保存为文稿顶部的 YAML。其他已有字段会保留。')),
                for (final key in controllers.keys)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: TextField(
                      key: ValueKey('markdown-property-$key'),
                      controller: controllers[key],
                      decoration: InputDecoration(
                        labelText: switch (key) {
                          'title' => tr('标题'),
                          'type' => tr('类型'),
                          'status' => tr('状态'),
                          'tags' => tr('标签（逗号分隔）'),
                          _ => tr('别名（逗号分隔）'),
                        },
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('应用属性')),
          ),
        ],
      ),
    );
    if (result == true && mounted && _text.text == original) {
      final updates = <String, Object?>{};
      for (final entry in controllers.entries) {
        final value = entry.value.text.trim();
        if (value.isEmpty && !properties.containsKey(entry.key)) continue;
        updates[entry.key] = entry.key == 'tags' || entry.key == 'aliases'
            ? value
                  .split(RegExp(r'[,，]'))
                  .map((value) => value.trim())
                  .where((value) => value.isNotEmpty)
                  .toList()
            : value;
      }
      _replaceRange(
        0,
        _text.text.length,
        MarkdownWorkspace.updateProperties(original, updates),
        caret: 0,
      );
    }
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 300), () {
        for (final controller in controllers.values) {
          controller.dispose();
        }
      }),
    );
  }

  /// 显示本地修订版本，预览或恢复前保留当前修改和正常撤销/保存语义。
  Future<void> _historyDialog() async {
    if (_file == null || _service.history == null) return;
    final path = _editingExternal ? _externalPath! : _file!.path;
    final revisions = await _service.history!.list(path);
    if (!mounted) return;
    File? selected = revisions.firstOrNull;
    String? preview;
    if (selected != null) preview = await selected.readAsString();
    if (!mounted) return;
    final restored = await showDialog<String>(
      context: context,
      animationStyle: appMotionStyle(context),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, change) => AlertDialog(
          title: Text(tr('本地版本历史')),
          content: SizedBox(
            width: 850,
            height: MediaQuery.sizeOf(context).height * .65,
            child: revisions.isEmpty
                ? Center(child: Text(tr('尚无历史版本。内容变更并保存后，旧版本会自动保留。')))
                : Row(
                    children: [
                      SizedBox(
                        width: 190,
                        child: ListView(
                          children: [
                            for (final file in revisions)
                              ListTile(
                                selected: file == selected,
                                title: Text(_revisionLabel(file)),
                                onTap: () async {
                                  change(() => selected = file);
                                  final value = await file.readAsString();
                                  if (ctx.mounted && selected == file) {
                                    change(() => preview = value);
                                  }
                                },
                              ),
                          ],
                        ),
                      ),
                      const VerticalDivider(width: 12),
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(12),
                          child: SelectableText(
                            preview ?? '',
                            style: const TextStyle(
                              fontFamily: 'Consolas',
                              fontFamilyFallback: ['Microsoft YaHei UI'],
                              fontSize: 13,
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
              child: Text(tr('关闭')),
            ),
            FilledButton(
              onPressed: preview == null || _readOnly
                  ? null
                  : () => Navigator.pop(ctx, preview),
              child: Text(tr('恢复此版本')),
            ),
          ],
        ),
      ),
    );
    if (restored == null || !mounted || restored == _text.text) return;
    await _service.history!.capture(
      path,
      _text.text,
      limit: _prefs.historyLimit,
    );
    if (mounted) _replaceRange(0, _text.text.length, restored, caret: 0);
  }

  /// 把修订文件的时间身份转成可读显示文本，不直接把文件名当正文内容。
  String _revisionLabel(File file) {
    final timestamp = int.tryParse(file.uri.pathSegments.last.split('-').first);
    final date = timestamp == null
        ? DateTime.now()
        : DateTime.fromMicrosecondsSinceEpoch(timestamp);
    return '${date.month}/${date.day} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}:${date.second.toString().padLeft(2, '0')}';
  }

  /// 将 Markdown 分隔内容转换为演示预览，按键导航页码，退出不改源文。
  Future<void> _slides() async {
    final slides = <String>[];
    final buffer = StringBuffer();
    bool fenced = false;
    for (final line in MarkdownWorkspace.plainBody(_text.text).split('\n')) {
      if (RegExp(r'^\s*(```|~~~)').hasMatch(line)) fenced = !fenced;
      if (!fenced && line.trim() == '---') {
        slides.add(buffer.toString());
        buffer.clear();
      } else {
        buffer.writeln(line);
      }
    }
    slides.add(buffer.toString());
    int page = 0;
    await showDialog<void>(
      context: context,
      animationStyle: appMotionStyle(context),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, change) => Dialog.fullscreen(
          child: CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
                  change(() => page = (page + 1).clamp(0, slides.length - 1)),
              const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
                  change(() => page = (page - 1).clamp(0, slides.length - 1)),
              const SingleActivator(LogicalKeyboardKey.escape): () =>
                  Navigator.pop(ctx),
            },
            child: Focus(
              autofocus: true,
              child: Column(
                children: [
                  Row(
                    children: [
                      IconButton(
                        tooltip: tr('退出演示'),
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close),
                      ),
                      const Spacer(),
                      Text('${page + 1} / ${slides.length}'),
                      const SizedBox(width: 16),
                      Text(tr('使用左右方向键翻页')),
                      const SizedBox(width: 16),
                    ],
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: _prefs.previewWidth,
                          ),
                          child: _markdownBody(
                            slides[page],
                            dark: widget.darkMode,
                            exporting: true,
                            fontSizeOverride: 24,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        tooltip: tr('上一页'),
                        onPressed: page > 0 ? () => change(() => page--) : null,
                        icon: const Icon(Icons.chevron_left),
                      ),
                      IconButton(
                        tooltip: tr('下一页'),
                        onPressed: page < slides.length - 1
                            ? () => change(() => page++)
                            : null,
                        icon: const Icon(Icons.chevron_right),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WikiLinkSyntax extends md.InlineSyntax {
  /// 注册双中括号引用语法，识别目标与别名但不在词法匹配阶段打开文件。
  _WikiLinkSyntax() : super(r'\[\[([^\]\n]+)\]\]');

  /// 把 Wiki 文本包装为受支持链接元素，实际路径解析交给工作区服务。
  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final parts = match.group(1)!.split('|');
    parser.addNode(
      md.Element.text(
          'a',
          parts.length > 1 ? parts.sublist(1).join('|') : parts.first,
        )
        ..attributes['href'] =
            'fastink-wiki:${Uri.encodeComponent(parts.first)}',
    );
    return true;
  }
}
