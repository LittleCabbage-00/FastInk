import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/app_localizations.dart';
import '../storage/library_repository.dart';

/// 文档内浏览资料库：保留文件夹层级，搜索可跨文件夹定位文稿。
class LibraryDocumentPicker extends StatefulWidget {
  /// 创建不可变的 LibraryDocumentPicker 参数对象；各参数保存在对应字段中，不在构造时执行外部读写。
  /// library：选稿窗口收到的轻量资料库快照，不直接修改索引。
  /// currentId：当前已打开文稿编号，选稿列表据此绘制勾选标记。
  const LibraryDocumentPicker({
    super.key,
    required this.library,
    this.currentId,
  });

  /// library：选稿窗口收到的轻量资料库快照，不直接修改索引。
  final LibraryState library;

  /// currentId：当前已打开文稿编号，选稿列表据此绘制勾选标记。
  final String? currentId;

  @override
  State<LibraryDocumentPicker> createState() => _LibraryDocumentPickerState();
}

class _LibraryDocumentPickerState extends State<LibraryDocumentPicker> {
  /// _search：选择器的查询文本控制器，关闭时释放，不与宿主资料库查询混用。
  final _search = TextEditingController();

  /// _folderId：当前选稿目录编号，null 为根目录；跨目录搜索不改写文稿归属。
  String? _folderId;

  /// 只返回有效手写文件夹，Markdown 域与废纸篓不会混入手写选稿树。
  List<LibraryFolder> get _folders => widget.library.folders
      .where((f) => !f.trashed && f.scope == LibraryScope.notes)
      .toList();

  /// 沿父编号构造可读完整目录路径，检测已访问编号避免坏索引形成无限循环。
  String _path(String? id) {
    final names = <String>[];
    final seen = <String>{};
    // 旧索引即使含循环父子关系也不能让路径计算卡住。
    while (id != null && seen.add(id)) {
      final folder = _folders.where((f) => f.id == id).firstOrNull;
      if (folder == null) break;
      names.insert(0, folder.name);
      id = folder.parentId;
    }
    return [tr('文稿', 'Documents'), ...names].join(' / ');
  }

  /// 切到指定目录并清除跨目录查询，null 表示资料库根目录。
  void _openFolder(String? id) => setState(() {
    _folderId = id;
    _search.clear();
  });

  /// 释放选稿窗口的搜索输入控制器。
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// 构建目录、根/上级导航、跨文件夹搜索与文稿结果；确认只返回索引记录，不在窗口内直接切换文稿。
  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final folders =
        _folders
            .where(
              (f) => query.isEmpty
                  ? f.parentId == _folderId
                  : f.name.toLowerCase().contains(query),
            )
            .toList()
          ..sort((a, b) => a.name.compareTo(b.name));
    final documents =
        widget.library.documents
            .where(
              (d) =>
                  !d.trashed &&
                  d.scope == LibraryScope.notes &&
                  (query.isEmpty
                      ? d.folderId == _folderId
                      : d.title.toLowerCase().contains(query)),
            )
            .toList()
          ..sort((a, b) => a.title.compareTo(b.title));
    final current = _folders.where((f) => f.id == _folderId).firstOrNull;
    return Dialog(
      child: SizedBox(
        width: 560,
        height: math.min(600, MediaQuery.sizeOf(context).height - 48),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      tr('按文件夹打开文稿', 'Browse document folders'),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    tooltip: tr('关闭', 'Close'),
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: TextField(
                key: const ValueKey('document-picker-search'),
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: tr(
                    '搜索全部文稿和文件夹',
                    'Search all documents and folders',
                  ),
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: tr('清除搜索', 'Clear search'),
                          onPressed: () => setState(_search.clear),
                          icon: const Icon(Icons.clear),
                        ),
                ),
              ),
            ),
            Row(
              children: [
                IconButton(
                  key: const ValueKey('document-picker-root'),
                  tooltip: tr('文稿根目录', 'Document root'),
                  onPressed: () => _openFolder(null),
                  icon: const Icon(Icons.home_outlined),
                ),
                IconButton(
                  key: const ValueKey('document-picker-up'),
                  tooltip: tr('返回上一级', 'Up one folder'),
                  onPressed: _folderId == null
                      ? null
                      : () => _openFolder(current?.parentId),
                  icon: const Icon(Icons.arrow_upward),
                ),
                Expanded(
                  child: Text(
                    _path(_folderId),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 16),
              ],
            ),
            const Divider(height: 1),
            Expanded(
              child: folders.isEmpty && documents.isEmpty
                  ? Center(
                      child: Text(
                        query.isEmpty
                            ? tr('文件夹中没有文稿', 'No documents in this folder')
                            : tr(
                                '没有匹配的文稿或文件夹',
                                'No matching documents or folders',
                              ),
                      ),
                    )
                  : ListView.builder(
                      // 文件夹切换回到列表顶端，搜索时不跨层级复用滚动状态。
                      key: ValueKey((_folderId, query.isNotEmpty)),
                      itemCount: folders.length + documents.length,
                      itemBuilder: (_, index) {
                        if (index < folders.length) {
                          final folder = folders[index];
                          return ListTile(
                            key: ValueKey('pick-folder-${folder.id}'),
                            leading: Icon(
                              Icons.folder,
                              color: Color(folder.colorValue),
                            ),
                            title: Text(folder.name),
                            subtitle: query.isEmpty
                                ? null
                                : Text(_path(folder.parentId)),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => _openFolder(folder.id),
                          );
                        }
                        final document = documents[index - folders.length];
                        return ListTile(
                          key: ValueKey('pick-document-${document.id}'),
                          leading: const Icon(Icons.description_outlined),
                          title: Text(
                            document.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: query.isEmpty
                              ? null
                              : Text(_path(document.folderId)),
                          trailing: document.id == widget.currentId
                              ? const Icon(Icons.check)
                              : null,
                          onTap: () => Navigator.pop(context, document),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
