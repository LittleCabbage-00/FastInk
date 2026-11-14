import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/app_localizations.dart';

class MarkdownItemPicker extends StatefulWidget {
  /// 创建不可变的 MarkdownItemPicker 参数对象；各参数保存在对应字段中，不在构造时执行外部读写。
  /// 保存和显示使用的完整标题。
  /// items：选择器中的稳定键到显示文字映射，返回键而非截断的显示标题。
  const MarkdownItemPicker({
    super.key,
    required this.title,
    required this.items,
  });

  /// 保存和显示使用的完整标题。
  final String title;

  /// items：选择器中的稳定键到显示文字映射，返回键而非截断的显示标题。
  final Map<String, String> items;

  @override
  State<MarkdownItemPicker> createState() => _MarkdownItemPickerState();
}

class _MarkdownItemPickerState extends State<MarkdownItemPicker> {
  /// _query：当前选择器的过滤查询，空串表示不做文字过滤。
  String _query = '';

  /// _selected：当前键盘高亮的过滤结果索引，上下键与滚动定位共用。
  int _selected = 0;

  /// _scroll：当前组件持有的滚动控制器，关闭时释放，不与别的活动视图同时绑定。
  final _scroll = ScrollController();

  /// 按当前查询过滤稳定键和显示名，返回当前可见候选列表。
  List<MapEntry<String, String>> get _items => widget.items.entries
      .where((e) => e.value.toLowerCase().contains(_query.trim().toLowerCase()))
      .toList();

  /// 将键盘高亮位置按 delta 移动并约束到候选范围，同时滚动揭示目标。
  void _move(int delta) {
    final items = _items;
    if (items.isEmpty) return;
    setState(() => _selected = (_selected + delta) % items.length);
    if (_scroll.hasClients) {
      _scroll.jumpTo(
        (_selected * 56.0).clamp(0, _scroll.position.maxScrollExtent),
      );
    }
  }

  /// 确认当前有效高亮项并返回其稳定键，没有结果时不返回无效索引。
  void _accept() {
    final items = _items;
    if (items.isNotEmpty) {
      Navigator.pop(context, items[_selected.clamp(0, items.length - 1)].key);
    }
  }

  /// 释放选择列表的滚动控制器。
  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// 构建支持查询、上下键、Enter 和 Esc 的选择窗口，无结果时显示明确状态。
  @override
  Widget build(BuildContext context) {
    final items = _items;
    return Dialog(
      child: SizedBox(
        width: 620,
        height: MediaQuery.sizeOf(context).height * .7,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Focus(
                onKeyEvent: (_, event) {
                  if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
                    return KeyEventResult.ignored;
                  }
                  if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                    _move(1);
                    return KeyEventResult.handled;
                  }
                  if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                    _move(-1);
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: TextField(
                  key: const ValueKey('markdown-command-search'),
                  autofocus: true,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: widget.title,
                    suffixIcon: IconButton(
                      tooltip: tr('关闭'),
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ),
                  onChanged: (value) => setState(() {
                    _query = value;
                    _selected = 0;
                  }),
                  onSubmitted: (_) => _accept(),
                ),
              ),
            ),
            Expanded(
              child: items.isEmpty
                  ? Center(child: Text(tr('没有匹配结果', 'No matches')))
                  : ListView.builder(
                      controller: _scroll,
                      itemExtent: 56,
                      itemCount: items.length,
                      itemBuilder: (_, i) => ListTile(
                        selected: i == _selected,
                        title: Text(
                          items[i].value,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => Navigator.pop(context, items[i].key),
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                tr(
                  '↑ ↓ 选择 · Enter 打开 · Esc 关闭',
                  '↑ ↓ Select · Enter Open · Esc Close',
                ),
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
