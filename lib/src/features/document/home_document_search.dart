part of '../../app/fastink_app.dart';

extension _FastInkDocumentSearch on _FastInkHomeState {
  /// 打开当前文稿的文字搜索窗口，收集键入文本、章节与 PDF 文本层结果；不执行手写 OCR。
  Future<void> _showDocumentSearch() async {
    final NoteDocument? document = _doc.document;
    if (document == null) return;
    _commitInlineText();
    await _saveNow();
    if (!mounted || _doc.document?.id != document.id) return;
    final Map<int, String> titles = Map<int, String>.of(
      _currentLibraryDocument?.pageTitles ?? <int, String>{},
    );
    final int? page = await showDialog<int>(
      context: context,
      animationStyle: appMotionStyle(context),
      builder: (_) => _DocumentSearchDialog(
        document: document,
        repository: _repository,
        titles: titles,
      ),
    );
    if (page != null && mounted && _doc.document?.id == document.id) {
      _goToPage(page);
    }
  }
}

class _DocumentSearchDialog extends StatefulWidget {
  /// 接收待搜索的文稿、内容仓库和手工章节标题。
  /// document：当前文稿元数据对象，页面和笔迹分别按需装载。
  /// repository：搜索窗口读取文本层与页面笔迹所用的文稿仓库。
  /// titles：手工章节标题映射，用于补充文稿内容搜索，不修改 PDF 原生目录。
  const _DocumentSearchDialog({
    required this.document,
    required this.repository,
    required this.titles,
  });

  /// document：当前文稿元数据对象，页面和笔迹分别按需装载。
  final NoteDocument document;

  /// repository：搜索窗口读取文本层与页面笔迹所用的文稿仓库。
  final NoteRepository repository;

  /// titles：手工章节标题映射，用于补充文稿内容搜索，不修改 PDF 原生目录。
  final Map<int, String> titles;

  /// 维护查询、索引加载状态和命中列表。
  @override
  State<_DocumentSearchDialog> createState() => _DocumentSearchDialogState();
}

class _DocumentSearchDialogState extends State<_DocumentSearchDialog> {
  /// _query：当前选择器的过滤查询，空串表示不做文字过滤。
  final TextEditingController _query = TextEditingController();

  /// _pages：搜索已建立的零基页索引到可搜索文字映射。
  final Map<int, String> _pages = <int, String>{};

  /// _indexed：搜索索引已经完成的页面数量，用于进度反馈。
  int _indexed = 0;

  /// _loading：搜索窗口是否仍在建立索引，和文稿换页状态分开。
  bool _loading = true;

  /// _error：搜索窗口当前错误说明，失败时保留已获得的可用结果。
  String? _error;

  /// 窗口挂载后开始建立文稿搜索索引，索引进度和查询分别更新。
  @override
  void initState() {
    super.initState();
    unawaited(_index());
  }

  /// 异步建立搜索索引并更新对话框状态；失败显示错误，卸载后不向旧窗口提交结果。
  Future<void> _index() async {
    try {
      Map<int, String> pdf = <int, String>{};
      try {
        pdf = await widget.repository.extractPdfSearchText(widget.document);
      } catch (error) {
        _error = '$error';
      }
      for (final NotePage page in widget.document.pages) {
        if (!mounted) return;
        final PageInk ink = await widget.repository.loadPageInk(
          widget.document,
          page,
        );
        if (!mounted) return;
        _pages[page.index] = <String>[
          widget.titles[page.index] ?? '',
          widget.repository.isOriginalPdfPage(widget.document, page)
              ? pdf[page.originalPage] ?? ''
              : '',
          ...ink.strokes.map((stroke) => stroke.text ?? ''),
        ].where((text) => text.trim().isNotEmpty).join('\n');
        _indexed++;
        if (_indexed % 12 == 0) setState(() {});
      }
    } catch (error) {
      _error = '$error';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 关闭文稿搜索时释放查询输入控制器。
  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  /// 显示查询输入、索引进度、错误和可跳转结果，选择返回目标页，取消不改变文稿。
  @override
  Widget build(BuildContext context) {
    final String query = _query.text.trim().toLowerCase();
    final List<MapEntry<int, String>> matches = query.isEmpty
        ? <MapEntry<int, String>>[]
        : _pages.entries
              .where((entry) => entry.value.toLowerCase().contains(query))
              .toList();
    return AlertDialog(
      title: Text(tr('搜索本文稿', 'Search this document')),
      content: SizedBox(
        width: 540,
        height: 420,
        child: Column(
          children: <Widget>[
            TextField(
              controller: _query,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) {
                if (matches.isNotEmpty) {
                  Navigator.pop(context, matches.first.key);
                }
              },
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: tr(
                  '搜索文字、PDF 正文或章节标题',
                  'Find text, PDF content or outline titles',
                ),
                suffixIcon: IconButton(
                  onPressed: () {
                    _query.clear();
                    setState(() {});
                  },
                  icon: const Icon(Icons.close),
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (_loading) const LinearProgressIndicator(),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _loading
                    ? tr(
                        '正在索引 $_indexed / ${widget.document.pages.length} 页',
                        'Indexing $_indexed / ${widget.document.pages.length} pages',
                      )
                    : tr(
                        '找到 ${matches.length} 页 · 手写和扫描图片尚不支持识别',
                        '${matches.length} matching pages · handwriting and scanned images are not indexed',
                      ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            if (_error != null)
              Text(tr('索引未完成：$_error', 'Index incomplete: $_error')),
            Expanded(
              child: query.isEmpty
                  ? Center(
                      child: Text(
                        tr(
                          '输入关键词，点击结果跳转到对应页面',
                          'Type a keyword, then choose a page',
                        ),
                      ),
                    )
                  : matches.isEmpty
                  ? Center(child: Text(tr('未找到匹配内容', 'No matches')))
                  : ListView.builder(
                      itemCount: matches.length,
                      itemBuilder: (context, index) {
                        final MapEntry<int, String> match = matches[index];
                        final int hit = match.value.toLowerCase().indexOf(
                          query,
                        );
                        final int start = math.max(0, hit - 35);
                        final String snippet = match.value
                            .substring(
                              start,
                              math.min(
                                match.value.length,
                                hit + query.length + 100,
                              ),
                            )
                            .replaceAll('\n', ' ');
                        return ListTile(
                          leading: const Icon(Icons.find_in_page_outlined),
                          title: Text(
                            widget.titles[match.key] ??
                                tr(
                                  '第 ${match.key + 1} 页',
                                  'Page ${match.key + 1}',
                                ),
                          ),
                          subtitle: Text(
                            snippet,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: Text('${match.key + 1}'),
                          onTap: () => Navigator.pop(context, match.key),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr('关闭', 'Close')),
        ),
      ],
    );
  }
}
