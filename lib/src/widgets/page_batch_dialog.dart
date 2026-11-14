import 'package:flutter/material.dart';
import '../models/models.dart';
import '../core/app_localizations.dart';
import '../storage/library_repository.dart';

class PageBatchChoice {
  /// 创建不可变的 PageBatchChoice 参数对象；各参数保存在对应字段中，不在构造时执行外部读写。
  /// indexes：批量管理结果中的零基页面索引集合，按源页序处理而非选择点击顺序。
  /// duplicate：批量管理确认是否执行复制操作，和删除/跨文稿复制分开表达。
  /// toOtherDocument：批量页面操作是否要复制到另一文稿。
  const PageBatchChoice(
    this.indexes, {
    required this.duplicate,
    this.toOtherDocument = false,
  });

  /// indexes：批量管理结果中的零基页面索引集合，按源页序处理而非选择点击顺序。
  final Set<int> indexes;

  /// duplicate：批量管理确认是否执行复制操作，和删除/跨文稿复制分开表达。
  final bool duplicate;

  /// toOtherDocument：批量页面操作是否要复制到另一文稿。
  final bool toOtherDocument;
}

class PageBatchDialog extends StatefulWidget {
  /// 创建不可变的 PageBatchDialog 参数对象；各参数保存在对应字段中，不在构造时执行外部读写。
  /// document：当前文稿元数据对象，页面和笔迹分别按需装载。
  /// currentIndex：当前活动页的零基索引，用于初始高亮或默认选择。
  const PageBatchDialog({
    super.key,
    required this.document,
    required this.currentIndex,
  });

  /// document：当前文稿元数据对象，页面和笔迹分别按需装载。
  final NoteDocument document;

  /// currentIndex：当前活动页的零基索引，用于初始高亮或默认选择。
  final int currentIndex;

  @override
  State<PageBatchDialog> createState() => _PageBatchDialogState();
}

class _PageBatchDialogState extends State<PageBatchDialog> {
  /// _selected：批量管理窗口的当前选择，类型由所属状态类决定：页索引集合或目标文稿编号。
  late final Set<int> _selected = {widget.currentIndex};

  /// 构建页面多选或目标文稿选择窗口，明确所选范围和复制/删除动作，至少一页等结构约束由确认流程检查。
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(tr('批量管理页面', 'Manage pages')),
    content: SizedBox(
      width: 560,
      height: 440,
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  tr(
                    '已选 ${_selected.length} / ${widget.document.pages.length} 页',
                    '${_selected.length} / ${widget.document.pages.length} selected',
                  ),
                ),
              ),
              TextButton(
                onPressed: () => setState(() {
                  if (_selected.length == widget.document.pages.length) {
                    _selected.clear();
                  } else {
                    _selected.addAll(
                      List.generate(widget.document.pages.length, (i) => i),
                    );
                  }
                }),
                child: Text(
                  _selected.length == widget.document.pages.length
                      ? tr('取消全选', 'Clear')
                      : tr('全选', 'All'),
                ),
              ),
            ],
          ),
          Expanded(
            child: ListView.builder(
              itemCount: widget.document.pages.length,
              itemBuilder: (context, index) => CheckboxListTile(
                key: ValueKey('batch-page-$index'),
                value: _selected.contains(index),
                title: Text(
                  '${index + 1}. ${widget.document.pages[index].name}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                secondary: Icon(
                  index == widget.currentIndex
                      ? Icons.description
                      : Icons.description_outlined,
                ),
                onChanged: (value) => setState(() {
                  if (value == true) {
                    _selected.add(index);
                  } else {
                    _selected.remove(index);
                  }
                }),
              ),
            ),
          ),
          if (_selected.length == widget.document.pages.length)
            Text(tr('至少保留一页，因此不能删除全部页面。', 'Keep at least one page.')),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(tr('取消', 'Cancel')),
      ),
      OutlinedButton(
        key: const ValueKey('copy-pages-to-document'),
        onPressed: _selected.isEmpty
            ? null
            : () => Navigator.pop(
                context,
                PageBatchChoice(
                  Set.of(_selected),
                  duplicate: true,
                  toOtherDocument: true,
                ),
              ),
        child: Text(tr('复制到其他文稿', 'Copy to another document')),
      ),
      OutlinedButton(
        onPressed:
            _selected.isEmpty ||
                _selected.length == widget.document.pages.length
            ? null
            : () => Navigator.pop(
                context,
                PageBatchChoice(Set.of(_selected), duplicate: false),
              ),
        child: Text(tr('删除所选页', 'Remove selected')),
      ),
      FilledButton(
        onPressed: _selected.isEmpty
            ? null
            : () => Navigator.pop(
                context,
                PageBatchChoice(Set.of(_selected), duplicate: true),
              ),
        child: Text(tr('复制所选页', 'Duplicate selected')),
      ),
    ],
  );
}

class PageCopyTargetDialog extends StatefulWidget {
  /// 创建不可变的 PageCopyTargetDialog 参数对象；各参数保存在对应字段中，不在构造时执行外部读写。
  /// documents：资料库或导入结果中的文稿记录集合，不直接包含全部解码图像。
  /// pageCount：文稿或当前任务的页面数量，不是最大页索引。
  const PageCopyTargetDialog({
    super.key,
    required this.documents,
    required this.pageCount,
  });

  /// documents：资料库或导入结果中的文稿记录集合，不直接包含全部解码图像。
  final List<LibraryDocument> documents;

  /// pageCount：文稿或当前任务的页面数量，不是最大页索引。
  final int pageCount;

  @override
  State<PageCopyTargetDialog> createState() => _PageCopyTargetDialogState();
}

class _PageCopyTargetDialogState extends State<PageCopyTargetDialog> {
  /// _query：当前选择器的过滤查询，空串表示不做文字过滤。
  String _query = '';

  /// _selected：批量管理窗口的当前选择，类型由所属状态类决定：页索引集合或目标文稿编号。
  String? _selected;

  /// 构建页面多选或目标文稿选择窗口，明确所选范围和复制/删除动作，至少一页等结构约束由确认流程检查。
  @override
  Widget build(BuildContext context) {
    final matches = widget.documents
        .where((item) => item.title.toLowerCase().contains(_query))
        .toList();
    return AlertDialog(
      title: Text(tr('复制到其他文稿', 'Copy to another document')),
      content: SizedBox(
        width: 520,
        height: 360,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              tr(
                '将 ${widget.pageCount} 页按原顺序追加到目标文稿末尾，原文稿保留。',
                'Append ${widget.pageCount} pages in source order. The source is kept.',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              key: const ValueKey('page-copy-target-search'),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: tr('搜索文稿', 'Search documents'),
                border: const OutlineInputBorder(),
              ),
              onChanged: (value) =>
                  setState(() => _query = value.trim().toLowerCase()),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: matches.isEmpty
                  ? Center(
                      child: Text(
                        widget.documents.isEmpty
                            ? tr(
                                '没有其他可用文稿，请先新建或导入文稿。',
                                'Create or import another document first.',
                              )
                            : tr('没有匹配的文稿', 'No matching documents'),
                      ),
                    )
                  : ListView.builder(
                      itemCount: matches.length,
                      itemBuilder: (context, index) {
                        final item = matches[index];
                        return ListTile(
                          key: ValueKey('page-copy-target-${item.id}'),
                          selected: _selected == item.id,
                          leading: Icon(
                            _selected == item.id
                                ? Icons.radio_button_checked
                                : Icons.radio_button_off,
                          ),
                          title: Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            tr(
                              '${item.pageCount} 页',
                              '${item.pageCount} pages',
                            ),
                          ),
                          onTap: () => setState(() => _selected = item.id),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr('取消', 'Cancel')),
        ),
        FilledButton(
          key: const ValueKey('page-copy-confirm'),
          onPressed: _selected == null
              ? null
              : () => Navigator.pop(
                  context,
                  widget.documents.firstWhere((item) => item.id == _selected),
                ),
          child: Text(tr('复制并打开', 'Copy and open')),
        ),
      ],
    );
  }
}
