part of 'markdown_editor.dart';

extension _MarkdownPreview on _MarkdownEditorViewState {
  /// 建立阅读区域并接入滚动同步，宽度、字体、图像和代码样式由独立 Markdown 偏好决定。
  Widget _reader() => NotificationListener<ScrollUpdateNotification>(
    onNotification: (_) {
      _sync(_previewScroll, _editorScroll);
      return false;
    },
    child: SingleChildScrollView(
      key: const ValueKey('markdown-preview'),
      controller: _previewScroll,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: _prefs.previewWidth),
          child: _markdownBody(_preview, dark: widget.darkMode),
        ),
      ),
    ),
  );

  /// 取得当前 Markdown 所在目录的文件 URI，解析相对图片和资源引用。
  Uri get _imageBase => File(
    _externalPath ?? _file?.path ?? '${widget.dataRoot}/untitled.md',
  ).absolute.uri;

  /// 区分 data、本地相对/绝对路径和可允许的远程图片，无法支持或策略禁止时返回 null。
  ImageProvider? _imageProvider(String source) {
    final uri = _imageBase.resolve(source);
    if (uri.scheme == 'data') {
      try {
        final data = uri.data;
        if (data != null &&
            data.mimeType.startsWith('image/') &&
            source.length < 28000000) {
          return ResizeImage(
            MemoryImage(data.contentAsBytes()),
            width: 1600,
            allowUpscaling: false,
          );
        }
      } catch (_) {
        return null;
      }
    }
    if (uri.scheme == 'file') {
      return ResizeImage(
        FileImage(File.fromUri(uri)),
        width: 1600,
        allowUpscaling: false,
      );
    }
    if ((uri.scheme == 'http' || uri.scheme == 'https') &&
        _prefs.remoteImages) {
      return ResizeImage(
        NetworkImage(uri.toString()),
        width: 1600,
        allowUpscaling: false,
      );
    }
    return null;
  }

  /// 为即将显示的 Markdown 内容提前解码受支持图片，避免导出/预览捕获时图片仍未准备好。
  Future<void> _precacheImages(String content) async {
    if (_prefs.diagramEnabled) {
      for (final match in MarkdownDiagrams.blocks(content)) {
        final file = await MarkdownDiagrams.render(
          match.$3,
          dark: _prefs.exportDark && widget.darkMode,
        );
        if (mounted) await precacheImage(FileImage(file), context);
      }
    }
    for (final match in RegExp(
      r'!\[[^\]]*\]\(<?([^\n>]+?)>?\)',
    ).allMatches(content)) {
      final provider = _imageProvider(match.group(1)!);
      if (provider == null || !mounted) continue;
      try {
        await precacheImage(
          provider,
          context,
          onError: (_, _) {},
        ).timeout(const Duration(seconds: 8));
      } catch (_) {
        /* 预览改为显示错误占位块。 */
      }
    }
  }

  /// 复用内容与主题/偏好/基址相同的解析组件，真正输入改变才重建阅读正文。
  Widget _markdownBody(
    String content, {
    required bool dark,
    bool exporting = false,
    int? liveOffset,
    double? fontSizeOverride,
  }) {
    final cacheKey = (content, dark, _prefs, _imageBase.toString());
    final fontSize = fontSizeOverride ?? _prefs.previewFontSize;
    if (!exporting &&
        liveOffset == null &&
        cacheKey == _readerBodyKey &&
        _readerBodyCache != null) {
      return _readerBodyCache!;
    }
    final foreground = dark ? const Color(0xffe6edf3) : const Color(0xff1f2328);
    final headings = MarkdownEditorService.extractToc(content);
    final bodyContent = MarkdownWorkspace.plainBody(content);
    final tasks = MarkdownEditorService.taskOffsets(content);
    int task = 0;
    int heading = 0;
    final headingBuilder = _HeadingBuilder((element, style) {
      if (heading >= headings.length) heading = 0;
      final index = heading++;
      final offset = index < headings.length ? headings[index].offset : -1;
      return Container(
        key: exporting || liveOffset != null || offset < 0
            ? null
            : _headingKeys.putIfAbsent(offset, GlobalKey.new),
        alignment: Alignment.centerLeft,
        child: Text(element.textContent, style: style),
      );
    });
    final body = MarkdownBody(
      key: ValueKey((liveOffset, content, dark, _prefs)),
      data: bodyContent,
      selectable: !exporting && liveOffset == null,
      extensionSet: md.ExtensionSet.gitHubWeb,
      blockSyntaxes: [md.FootnoteDefSyntax()],
      syntaxHighlighter: _prefs.syntaxHighlight
          ? MarkdownCodeHighlighter(dark: dark)
          : null,
      sizedImageBuilder: (config) {
        final uri = config.uri;
        final alt = config.alt;
        final provider = _imageProvider(uri.toString());
        if (provider == null) return Text(alt ?? tr('网络图片已关闭或地址不受支持'));
        return Image(
          image: provider,
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => Text('${tr('无法加载图片')}: ${alt ?? uri}'),
        );
      },
      onTapLink: (_, href, _) {
        if (href == null) return;
        if (href.startsWith('fastink-wiki:')) {
          unawaited(_followWiki(Uri.decodeComponent(href.substring(13))));
          return;
        }
        if (href.startsWith('#')) {
          final slug = Uri.decodeComponent(href.substring(1));
          final item = headings
              .where(
                (item) =>
                    item.title.toLowerCase().replaceAll(' ', '-') ==
                    slug.toLowerCase(),
              )
              .firstOrNull;
          if (item != null) _jumpToOffset(item.offset);
        } else {
          final uri = Uri.tryParse(href);
          if (uri != null && (uri.scheme.isEmpty || uri.scheme == 'file')) {
            final local = _imageBase.resolveUri(uri);
            if (local.path.toLowerCase().endsWith('.md')) {
              unawaited(
                _openWorkspaceNote(
                  File.fromUri(local.replace(fragment: '')).path,
                  anchor: local.fragment,
                ),
              );
              return;
            }
          }
          if (uri != null &&
              (uri.scheme == 'https' ||
                  uri.scheme == 'http' ||
                  uri.scheme == 'mailto')) {
            // 使用 Windows 文件关联打开文件，不拼接 shell 命令。
            Process.run('rundll32.exe', [
              'url.dll,FileProtocolHandler',
              uri.toString(),
            ]);
          }
        }
      },
      checkboxBuilder: (checked) {
        if (task >= tasks.length) task = 0;
        final offset = task < tasks.length ? tasks[task++] : -1;
        return InkWell(
          onTap: _readOnly || exporting || offset < 0
              ? null
              : () {
                  final base = liveOffset ?? 0;
                  if (base + content.length > _text.text.length ||
                      _text.text.substring(base, base + content.length) !=
                          content) {
                    return;
                  }
                  final selection = _text.selection;
                  _text.value = TextEditingValue(
                    text: _text.text.replaceRange(
                      (liveOffset ?? 0) + offset,
                      (liveOffset ?? 0) + offset + 1,
                      checked ? ' ' : 'x',
                    ),
                    selection: selection,
                  );
                },
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: Icon(
              checked
                  ? Icons.check_box_outlined
                  : Icons.check_box_outline_blank,
              size: 18,
              color: foreground,
            ),
          ),
        );
      },
      styleSheet: MarkdownStyleSheet(
        p: TextStyle(fontSize: fontSize, height: 1.7, color: foreground),
        h1: TextStyle(
          fontSize: fontSize + 13,
          fontWeight: FontWeight.w700,
          color: foreground,
        ),
        h2: TextStyle(
          fontSize: fontSize + 8,
          fontWeight: FontWeight.w700,
          color: foreground,
        ),
        h3: TextStyle(
          fontSize: fontSize + 4,
          fontWeight: FontWeight.w600,
          color: foreground,
        ),
        h4: TextStyle(
          fontSize: fontSize + 2,
          fontWeight: FontWeight.w600,
          color: foreground,
        ),
        h5: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
          color: foreground,
        ),
        h6: TextStyle(fontSize: fontSize, color: foreground),
        code: TextStyle(
          fontFamily: 'Consolas',
          fontSize: fontSize - 1,
          color: foreground,
          backgroundColor: dark
              ? const Color(0xff23272f)
              : const Color(0xffeff1f3),
        ),
        codeblockDecoration: BoxDecoration(
          color: dark ? const Color(0xff23272f) : const Color(0xffeff1f3),
          borderRadius: BorderRadius.circular(8),
        ),
        blockquoteDecoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              color: dark ? Colors.white30 : Colors.black26,
              width: 3,
            ),
          ),
        ),
        tableBorder: TableBorder.all(
          color: dark ? Colors.white24 : Colors.black26,
        ),
        tableHead: TextStyle(fontWeight: FontWeight.w700, color: foreground),
        tableBody: TextStyle(color: foreground, fontSize: fontSize),
        horizontalRuleDecoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: dark ? Colors.white24 : Colors.black26),
          ),
        ),
      ),
      builders: {
        'pre': _MarkdownCodeBlockBuilder(
          dark: dark,
          preferences: _prefs.copyWith(previewFontSize: fontSize),
          exporting: exporting,
          slotPrefix:
              '${_file?.path ?? 'new'}:${exporting ? 'export' : liveOffset?.toString() ?? 'preview'}',
        ),
        for (int i = 1; i <= 6; i++) 'h$i': headingBuilder,
        'math': _MathBuilder(dark: dark, size: fontSize),
      },
      inlineSyntaxes: [
        _WikiLinkSyntax(),
        if (_prefs.mathEnabled) _LatexInlineSyntax(),
      ],
    );
    if (liveOffset != null) return body;
    if (exporting) {
      return Padding(padding: const EdgeInsets.all(36), child: body);
    }
    final offsets = headings.map((item) => item.offset).toSet();
    _headingKeys.removeWhere((offset, _) => !offsets.contains(offset));
    _readerBodyKey = cacheKey;
    _readerBodyCache = body;
    return body;
  }

  /// 切换目录显示，窄窗口使用适当侧栏/弹层，实际状态与偏好同步。
  void _toggleToc() {
    if (MediaQuery.sizeOf(context).width < 900) {
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (sheetContext) => SizedBox(
          height: MediaQuery.sizeOf(context).height * .65,
          child: _toc(onSelected: () => Navigator.pop(sheetContext)),
        ),
      );
    } else {
      _setPreferences(_prefs.copyWith(openOutline: !_showToc));
    }
  }

  /// 构建真实标题目录，选择后按源文偏移定位，必要时通知窄窗口关闭目录。
  Widget _toc({VoidCallback? onSelected}) {
    final items = _file?.tocItems ?? const <TocItem>[];
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Column(
        children: [
          ListTile(
            dense: true,
            title: Text(tr('目录')),
            trailing: onSelected == null
                ? IconButton(
                    tooltip: tr('关闭目录'),
                    onPressed: () => _change(() => _showToc = false),
                    icon: const Icon(Icons.close, size: 18),
                  )
                : null,
          ),
          Expanded(
            child: items.isEmpty
                ? Center(child: Text(tr('使用标题即可生成目录')))
                : ListView.builder(
                    itemCount: items.length,
                    itemBuilder: (_, index) {
                      final item = items[index];
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.only(
                          left: 12 + (item.level - 1) * 12,
                          right: 12,
                        ),
                        title: Text(
                          item.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () {
                          onSelected?.call();
                          _jumpToOffset(item.offset);
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  /// 把全文源偏移映射到源码或实时块/预览标题位置，保证模式变化后仍定位同一内容。
  void _jumpToOffset(int offset) {
    _text.selection = TextSelection.collapsed(
      offset: offset.clamp(0, _text.text.length),
    );
    // 由 EditableText 定位准确的光标位置，包含自动换行后的行。
    if (_mode != _MarkdownMode.read) _focusEditing();
    final anchor = _headingKeys[offset]?.currentContext;
    if (anchor != null && _previewScroll.hasClients) {
      _syncing = true;
      Scrollable.ensureVisible(
        anchor,
        alignment: .05,
        duration: appMotionDuration(context, 180),
      ).whenComplete(() => _syncing = false);
    }
  }
}

class _HeadingBuilder extends MarkdownElementBuilder {
  /// 保存标题组件构建回调，解析完成后附加定位键和样式。
  _HeadingBuilder(this.build);

  /// build：把解析后的标题元素与样式转换为组件的回调，用于附加目录定位键。
  final Widget Function(md.Element, TextStyle?) build;

  /// 保留标题或公式节点的文本，交给对应元素完成回调统一生成组件。
  @override
  Widget? visitText(md.Text text, TextStyle? preferredStyle) =>
      Text(text.text, style: preferredStyle);

  /// 根据元素类型生成可定位标题或数学组件，使用当前深浅主题确保阅读对比。
  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) =>
      build(element, preferredStyle);
}

class _LatexInlineSyntax extends md.InlineSyntax {
  /// 注册支持的单/双美元数学语法，普通段落换行与围栏规则仍由 Markdown 解析器处理。
  _LatexInlineSyntax() : super(r'\$\$([\s\S]+?)\$\$|\$([^\n$]+?)\$');

  /// 将匹配到的 LaTeX 源片段包装为数学元素并消费该片段，不直接修改源文件。
  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(md.Element.text('math', match.group(1) ?? match.group(2)!));
    return true;
  }
}

class _MathBuilder extends MarkdownElementBuilder {
  /// 绑定数学显示主题与逻辑字号，公式源文仍保持可编辑字符串。
  _MathBuilder({required this.dark, this.size = 15});

  /// dark：当前预览是否使用深色配色，不改写源 Markdown 或纸张数据。
  final bool dark;

  /// size：公式显示逻辑字号，不修改 LaTeX 源文。
  final double size;

  /// 根据元素类型生成可定位标题或数学组件，使用当前深浅主题确保阅读对比。
  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) =>
      Math.tex(
        element.textContent,
        textStyle: TextStyle(
          color: dark ? const Color(0xffe6edf3) : const Color(0xff1f2328),
          fontSize: size,
        ),
        onErrorFallback: (_) => Text(
          '\$${element.textContent}\$',
          style: const TextStyle(color: Colors.red),
        ),
      );
}
