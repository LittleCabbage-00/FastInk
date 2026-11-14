part of 'markdown_editor.dart';

class _MarkdownCodeBlockBuilder extends MarkdownElementBuilder {
  /// 绑定当前主题、导出状态与图表槽位前缀，将代码围栏转为高亮或 Mermaid 组件。
  _MarkdownCodeBlockBuilder({
    required this.dark,
    required this.preferences,
    required this.exporting,
    required this.slotPrefix,
  });

  /// dark：当前预览是否使用深色配色，不改写源 Markdown 或纸张数据；exporting：当前 Markdown 内容是否为导出渲染，导出时隐藏交互型控件。
  final bool dark, exporting;

  /// slotPrefix：图表槽位身份前缀，同文档的多个代码围栏不能共享取消与折叠状态。
  final String slotPrefix;

  /// _diagramIndex：本次 Markdown 构建已分配的图表序号，用于生成独立槽位。
  int _diagramIndex = 0;

  /// preferences：当前 Markdown 配置快照，设置变化后由组件更新流程同步。
  final MarkdownPreferences preferences;

  /// 收集 Markdown 解析器传入的代码文本，保留完整围栏内容供后续渲染。
  @override
  Widget? visitText(md.Text text, TextStyle? preferredStyle) => Text(text.text);

  /// 完成代码块节点转换；支持的 Mermaid 使用独立槽位，其他语言代码保持源码高亮显示。
  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final code = element.textContent.trimRight();
    final child = element.children?.whereType<md.Element>().firstOrNull;
    final language =
        child?.attributes['class']?.replaceFirst('language-', '') ?? '';
    if (language == 'mermaid' && preferences.diagramEnabled) {
      return _MermaidBlock(
        code: code,
        dark: dark,
        exporting: exporting,
        slot: '$slotPrefix:${_diagramIndex++}',
      );
    }
    final style = TextStyle(
      fontFamily: 'Consolas',
      fontFamilyFallback: const ['Microsoft YaHei UI'],
      fontSize: preferences.previewFontSize - 1,
      color: dark ? const Color(0xffe6edf3) : const Color(0xff1f2328),
    );
    return Container(
      decoration: BoxDecoration(
        color: dark ? const Color(0xff23272f) : const Color(0xfff0f2f5),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!exporting)
            Row(
              children: [
                Text(
                  language.isEmpty ? 'Code' : language,
                  style: const TextStyle(fontSize: 11),
                ),
                const Spacer(),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: tr('复制代码'),
                  onPressed: () => Clipboard.setData(ClipboardData(text: code)),
                  icon: const Icon(Icons.copy, size: 16),
                ),
              ],
            ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: exporting
                ? Text.rich(
                    TextSpan(
                      style: style,
                      children: [
                        preferences.syntaxHighlight
                            ? MarkdownCodeHighlighter(dark: dark).format(code)
                            : TextSpan(text: code),
                      ],
                    ),
                  )
                : SelectableText.rich(
                    TextSpan(
                      style: style,
                      children: [
                        preferences.syntaxHighlight
                            ? MarkdownCodeHighlighter(dark: dark).format(code)
                            : TextSpan(text: code),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _MermaidBlock extends StatefulWidget {
  /// 接收图表源码、所属槽位与主题，供共享图表缓存定位。
  /// code：当前代码围栏的完整源内容，图表刷新与缓存签名都以它为依据。
  /// dark：当前预览是否使用深色配色，不改写源 Markdown 或纸张数据。
  /// exporting：当前 Markdown 内容是否为导出渲染，导出时隐藏交互型控件。
  /// slot：当前图表实例的稳定槽位标识，用于合并任务和取消过期内容。
  const _MermaidBlock({
    required this.code,
    required this.dark,
    required this.exporting,
    required this.slot,
  });

  /// code：当前代码围栏的完整源内容，图表刷新与缓存签名都以它为依据。
  final String code;

  /// slot：当前图表实例的稳定槽位标识，用于合并任务和取消过期内容。
  final String slot;

  /// dark：当前预览是否使用深色配色，不改写源 Markdown 或纸张数据；exporting：当前 Markdown 内容是否为导出渲染，导出时隐藏交互型控件。
  final bool dark, exporting;

  /// 跟踪本块的渲染请求及预览。
  @override
  State<_MermaidBlock> createState() => _MermaidBlockState();
}

class _MermaidBlockState extends State<_MermaidBlock> {
  /// _render：当前图表排队/渲染结果的 Future，更新后 FutureBuilder 只接纳本次结果。
  late Future<File> _render;

  /// _debounce：图表源码变化后的渲染防抖任务，快速输入不连续启动浏览器。
  Timer? _debounce;

  /// _requested：当前图表是否已向渲染服务登记请求，释放时据此取消槽位需求。
  bool _requested = false;

  /// 优先读取已完成图表缓存，再按防抖与槽位需求安排渲染，不在组件构造时直接启动外部进程。
  @override
  void initState() {
    super.initState();
    _schedule();
  }

  /// 取消旧延迟请求并合并快速源码修改，实际渲染前再次确认当前槽位仍需要该内容。
  void _schedule() {
    _debounce?.cancel();
    _requested = false;
    final ready = MarkdownDiagrams.cached(widget.code, widget.dark);
    if (ready != null) {
      _render = Future<File>.value(ready);
      return;
    }
    final completion = Completer<File>();
    _render = completion.future;
    _debounce = Timer(const Duration(milliseconds: 650), () {
      if (!mounted) return;
      _requested = true;
      MarkdownDiagrams.render(
        widget.code,
        dark: widget.dark,
        slot: widget.slot,
      ).then(completion.complete, onError: completion.completeError);
    });
  }

  /// 取消图表生成防抖，并释放本块对共享图表任务的引用。
  @override
  void dispose() {
    _debounce?.cancel();
    if (_requested) {
      MarkdownDiagrams.release(widget.slot, widget.code, widget.dark);
    }
    super.dispose();
  }

  /// 源码、主题或槽位变化时释放旧需求并重新安排渲染，旧 Future 不覆盖新图表。
  @override
  void didUpdateWidget(covariant _MermaidBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.code != widget.code ||
        oldWidget.dark != widget.dark ||
        oldWidget.slot != widget.slot) {
      if (_requested) {
        MarkdownDiagrams.release(
          oldWidget.slot,
          oldWidget.code,
          oldWidget.dark,
        );
      }
      _schedule();
    }
  }

  /// 用当前渲染 Future 展示图表结果、等待或错误信息，非导出模式另提供可独立折叠的源码。
  @override
  Widget build(BuildContext context) => FutureBuilder<File>(
    future: _render,
    initialData: MarkdownDiagrams.cached(widget.code, widget.dark),
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).colorScheme.error),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr('Mermaid 图表未能渲染'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              Text(
                '${snapshot.error}'.split('\n').take(4).join('\n'),
                maxLines: 5,
              ),
              SelectableText(
                widget.code,
                style: const TextStyle(fontFamily: 'Consolas'),
              ),
            ],
          ),
        );
      }
      if (!snapshot.hasData) {
        return const Padding(
          padding: EdgeInsets.all(20),
          child: Center(child: CircularProgressIndicator()),
        );
      }
      final image = Image.file(snapshot.data!, fit: BoxFit.contain);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            onDoubleTap: widget.exporting
                ? null
                : () => showDialog<void>(
                    context: context,
                    animationStyle: appMotionStyle(context),
                    builder: (ctx) => Dialog.fullscreen(
                      child: Column(
                        children: [
                          Align(
                            alignment: Alignment.centerRight,
                            child: IconButton(
                              tooltip: tr('关闭'),
                              onPressed: () => Navigator.pop(ctx),
                              icon: const Icon(Icons.close),
                            ),
                          ),
                          Expanded(
                            child: InteractiveViewer(
                              minScale: .2,
                              maxScale: 8,
                              child: Center(child: Image.file(snapshot.data!)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
            child: image,
          ),
          if (!widget.exporting)
            ExpansionTile(
              // 源码折叠状态按图表区分，不能复用文档滚动位置的存储键。
              key: PageStorageKey<String>('mermaid-source-${widget.slot}'),
              title: Text(
                tr('Mermaid 源码'),
                style: const TextStyle(fontSize: 12),
              ),
              children: [
                SelectableText(
                  widget.code,
                  style: const TextStyle(fontFamily: 'Consolas', fontSize: 12),
                ),
              ],
            ),
        ],
      );
    },
  );
}
