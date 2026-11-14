import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import '../core/markdown_preferences.dart';
import '../core/app_localizations.dart';
import 'markdown_source_editor.dart';

/// 非活动块仅渲染，选中块原地编辑；直接替换源文本片段，
/// 打开某个块不会重新生成整篇文稿。
class MarkdownLiveEditor extends StatefulWidget {
  /// 创建不可变的 MarkdownLiveEditor 参数对象；各参数保存在对应字段中，不在构造时执行外部读写。
  /// controller：该组件或绘制层使用的控制器，由构造方传入，具体内容遵循声明类型。
  /// preferences：当前 Markdown 配置快照，设置变化后由组件更新流程同步。
  /// undo：文本编辑使用的撤销控制器，与手写画布历史完全分开。
  /// renderBlock：把指定源文片段及其全文偏移渲染为预览组件的回调。
  /// onEditTable：请求编辑当前表格的回调，表格内容定位仍由宿主负责。
  /// onProperties：请求打开 Markdown 文稿属性面板的回调。
  /// onPasteImage：请求读取/导入剪贴板图片并插入源文引用的异步回调。
  const MarkdownLiveEditor({
    super.key,
    required this.controller,
    required this.preferences,
    required this.undo,
    required this.renderBlock,
    required this.onEditTable,
    required this.onProperties,
    required this.onPasteImage,
  });

  /// controller：该组件或绘制层使用的控制器，由构造方传入，具体内容遵循声明类型。
  final TextEditingController controller;

  /// preferences：当前 Markdown 配置快照，设置变化后由组件更新流程同步。
  final MarkdownPreferences preferences;

  /// undo：文本编辑使用的撤销控制器，与手写画布历史完全分开。
  final UndoHistoryController undo;

  /// renderBlock：把指定源文片段及其全文偏移渲染为预览组件的回调。
  final Widget Function(String content, int sourceOffset) renderBlock;

  /// onEditTable：请求编辑当前表格的回调，表格内容定位仍由宿主负责；onProperties：请求打开 Markdown 文稿属性面板的回调。
  final VoidCallback onEditTable, onProperties;

  /// onPasteImage：请求读取/导入剪贴板图片并插入源文引用的异步回调。
  final Future<void> Function() onPasteImage;

  @override
  State<MarkdownLiveEditor> createState() => MarkdownLiveEditorState();

  /// 解析 Markdown 块的全文起止偏移，保留原文范围以便只替换活动块而不重写整篇。
  static List<(int, int)> ranges(String text) {
    final result = <(int, int)>[];
    final lines = text.split('\n');
    int offset = 0, index = 0;
    while (index < lines.length) {
      if (lines[index].trim().isEmpty) {
        offset += lines[index++].length + 1;
        continue;
      }
      final start = offset;
      final opening = RegExp(r'^\s*(`{3,}|~{3,})').firstMatch(lines[index]);
      final frontmatter = index == 0 && lines[index].trim() == '---';
      offset += lines[index++].length + 1;
      if (opening != null || frontmatter) {
        while (index < lines.length) {
          final line = lines[index++];
          offset += line.length + 1;
          if (frontmatter
              ? line.trim() == '---'
              : line.trim().startsWith(opening!.group(1)!)) {
            break;
          }
        }
      } else if (!RegExp(r'^ {0,3}#{1,6}\s').hasMatch(lines[index - 1])) {
        while (index < lines.length &&
            lines[index].trim().isNotEmpty &&
            !RegExp(r'^ {0,3}(#{1,6}\s|`{3,}|~{3,})').hasMatch(lines[index])) {
          offset += lines[index++].length + 1;
        }
      }
      result.add((start, (offset - 1).clamp(start, text.length)));
    }
    if (result.isEmpty) result.add((0, text.length));
    return result;
  }
}

class MarkdownLiveEditorState extends State<MarkdownLiveEditor> {
  /// _blocks：实时编辑器各块在原始源文中的起止偏移，局部编辑必须按该范围替换。
  late List<(int, int)> _blocks = MarkdownLiveEditor.ranges(
    widget.controller.text,
  );

  /// _active：当前可编辑块的文本控制器，只暂存该块内容，不替代全文控制器。
  final _active = TextEditingController();

  /// _focus：当前组件持有的输入焦点，切块与关闭时按生命周期管理。
  final _focus = FocusNode();

  /// _scroll：当前组件持有的滚动控制器，关闭时释放，不与别的活动视图同时绑定。
  final _scroll = ScrollController();

  /// _blockKeys：块索引到组件 GlobalKey 的映射，用于定位活动块或滚动目标。
  final Map<int, GlobalKey> _blockKeys = {};

  /// _selected：当前正在编辑的块索引，null 表示没有活动输入块。
  int? _selected;

  /// _writing：是否正在从块编辑向全文回写，避免控制器监听相互触发；_syncing：当前是否在同步相关输入/滚动状态，防止双向监听递归回写。
  bool _writing = false, _syncing = false;

  /// 建立活动块控制器与全文监听，初始化块范围，关闭时解除监听并释放焦点/滚动资源。
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_parentChanged);
    _active.addListener(_edited);
  }

  /// 解除全文和当前块的监听，释放块编辑所用焦点及滚动状态。
  @override
  void dispose() {
    widget.controller.removeListener(_parentChanged);
    _active.removeListener(_edited);
    _active.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// 宿主全文变化后重算块范围并同步当前活动块，写入标志防止再次反向回写。
  void _parentChanged() {
    if (_writing || !mounted) return;
    final wasEditing = _selected != null;
    _blocks = MarkdownLiveEditor.ranges(widget.controller.text);
    if (wasEditing) {
      final position = widget.controller.selection.isValid
          ? widget.controller.selection.extentOffset
          : 0;
      final index = _blocks.indexWhere(
        (range) => position >= range.$1 && position <= range.$2,
      );
      if (index >= 0) {
        _activate(index, focus: false);
      } else {
        _selected = null;
      }
    }
    setState(() {});
  }

  /// 将活动块新文本替换回全文原范围，调整后续块偏移并保留整体撤销历史。
  void _edited() {
    if (_syncing || _selected == null || !mounted) return;
    final index = _selected!;
    final range = _blocks[index];
    final before = widget.controller.text;
    final typed = before.substring(range.$1, range.$2) != _active.text;
    final delta = _active.text.length - (range.$2 - range.$1);
    _blocks[index] = (range.$1, range.$2 + delta);
    for (int i = index + 1; i < _blocks.length; i++) {
      _blocks[i] = (_blocks[i].$1 + delta, _blocks[i].$2 + delta);
    }
    final selection = _active.selection;
    final composing = _active.value.composing;
    _writing = true;
    widget.controller.value = TextEditingValue(
      text: before.replaceRange(range.$1, range.$2, _active.text),
      selection: selection.isValid
          ? TextSelection(
              baseOffset: range.$1 + selection.baseOffset,
              extentOffset: range.$1 + selection.extentOffset,
            )
          : TextSelection.collapsed(offset: range.$1),
      composing: composing.isValid
          ? TextRange(
              start: range.$1 + composing.start,
              end: range.$1 + composing.end,
            )
          : TextRange.empty,
    );
    _writing = false;
    if (typed && widget.preferences.typewriter) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scroll.hasClients || !_focus.hasFocus) return;
        RenderEditable? editable;
        // 遍历当前渲染对象查找可定位的文本布局，用于按光标揭示活动编辑位置。
        void visit(RenderObject object) {
          if (object is RenderEditable) {
            editable = object;
          } else {
            object.visitChildren(visit);
          }
        }

        final root = _focus.context?.findRenderObject();
        if (root == null) return;
        visit(root);
        final viewport = _scroll.position.context.notificationContext
            ?.findRenderObject();
        if (editable == null ||
            viewport is! RenderBox ||
            !_active.selection.isValid) {
          return;
        }
        final caret = editable!
            .localToGlobal(
              editable!.getLocalRectForCaret(_active.selection.extent).center,
            )
            .dy;
        final top = viewport.localToGlobal(Offset.zero).dy;
        _scroll.jumpTo(
          (_scroll.offset +
                  caret -
                  top -
                  _scroll.position.viewportDimension * .45)
              .clamp(0.0, _scroll.position.maxScrollExtent),
        );
      });
    }
  }

  /// 切换可编辑块，先收集旧块内容，再建立目标块选区；focus 控制是否立即请求输入焦点。
  void _activate(int index, {bool focus = true}) {
    final range = _blocks[index];
    final source = widget.controller.text;
    final selection = widget.controller.selection;
    _selected = index;
    _syncing = true;
    _active.value = TextEditingValue(
      text: source.substring(range.$1, range.$2),
      selection:
          selection.isValid &&
              selection.start >= range.$1 &&
              selection.end <= range.$2
          ? TextSelection(
              baseOffset: selection.baseOffset - range.$1,
              extentOffset: selection.extentOffset - range.$1,
            )
          : TextSelection.collapsed(offset: range.$2 - range.$1),
    );
    _syncing = false;
    if (mounted) setState(() {});
    if (focus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focus.requestFocus();
      });
    }
  }

  /// 根据全文当前选区定位对应块并恢复编辑焦点，工具操作不另建无关文本历史。
  void focusSelection() {
    final offset = widget.controller.selection.isValid
        ? widget.controller.selection.extentOffset
        : widget.controller.text.length;
    final index = _blocks.indexWhere(
      (range) => offset >= range.$1 && offset <= range.$2,
    );
    final target = index < 0 ? _blocks.length - 1 : index;
    _activate(target, focus: false);
    _reveal(target);
  }

  /// 在布局准备后按范围逐步定位活动块，限制重试并按实际滚动区间约束目标。
  void _reveal(int index, {int attempts = 0, double lower = 0, double? upper}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final context = _blockKeys[index]?.currentContext;
      if (context != null) {
        Scrollable.ensureVisible(
          context,
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart,
        ).whenComplete(() {
          if (mounted) _focus.requestFocus();
        });
        return;
      }
      if (!_scroll.hasClients || attempts >= 14) return;
      final visible =
          _blockKeys.entries
              .where((entry) => entry.value.currentContext != null)
              .map((entry) => entry.key)
              .toList()
            ..sort();
      var bottom = lower, top = upper ?? _scroll.position.maxScrollExtent;
      if (visible.isNotEmpty && index > visible.last) bottom = _scroll.offset;
      if (visible.isNotEmpty && index < visible.first) top = _scroll.offset;
      _scroll.jumpTo(
        ((bottom + top) / 2).clamp(0.0, _scroll.position.maxScrollExtent),
      );
      _reveal(index, attempts: attempts + 1, lower: bottom, upper: top);
    });
  }

  /// 优先保留普通文本粘贴语义，没有可用文本时调用图片粘贴入口。
  Future<void> _paste() async {
    final value = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return;
    if (value?.text?.isNotEmpty == true) {
      final selection = _active.selection;
      if (!selection.isValid) return;
      _active.value = TextEditingValue(
        text: _active.text.replaceRange(
          selection.start,
          selection.end,
          value!.text!,
        ),
        selection: TextSelection.collapsed(
          offset: selection.start + value.text!.length,
        ),
      );
    } else {
      await widget.onPasteImage();
    }
  }

  /// 只把活动块变成输入框，其余块保留渲染预览；组件身份与源文范围共同保证局部编辑。
  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: widget.preferences.previewWidth),
      child: ListView.builder(
        key: const ValueKey('markdown-live-editor'),
        controller: _scroll,
        padding: EdgeInsets.fromLTRB(
          24,
          20,
          24,
          widget.preferences.typewriter
              ? MediaQuery.sizeOf(context).height * .45
              : 20,
        ),
        itemCount: _blocks.length + 1,
        itemBuilder: (context, index) {
          if (index == _blocks.length) {
            return TextButton.icon(
              onPressed: () {
                final text = widget.controller.text;
                _writing = true;
                final next =
                    '$text${text.endsWith('\n\n') || text.isEmpty ? '' : '\n\n'}';
                widget.controller.value = TextEditingValue(
                  text: next,
                  selection: TextSelection.collapsed(offset: next.length),
                );
                _writing = false;
                _blocks = MarkdownLiveEditor.ranges(widget.controller.text);
                if (next.isNotEmpty) _blocks.add((next.length, next.length));
                _activate(_blocks.length - 1);
              },
              icon: const Icon(Icons.add),
              label: Text(tr('添加段落')),
            );
          }
          final range = _blocks[index];
          final blockKey = _blockKeys.putIfAbsent(index, GlobalKey.new);
          final content = widget.controller.text.substring(range.$1, range.$2);
          if (index == 0 &&
              content.startsWith('---\n') &&
              content.trimRight().endsWith('---')) {
            return Align(
              alignment: Alignment.centerLeft,
              child: ActionChip(
                avatar: const Icon(Icons.data_object, size: 16),
                label: Text(tr('文稿属性')),
                onPressed: widget.onProperties,
              ),
            );
          }
          if (_selected == index) {
            return Padding(
              key: blockKey,
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Actions(
                actions: {
                  UndoTextIntent: CallbackAction<UndoTextIntent>(
                    onInvoke: (_) {
                      widget.undo.undo();
                      return null;
                    },
                  ),
                  RedoTextIntent: CallbackAction<RedoTextIntent>(
                    onInvoke: (_) {
                      widget.undo.redo();
                      return null;
                    },
                  ),
                  PasteTextIntent: CallbackAction<PasteTextIntent>(
                    onInvoke: (_) {
                      _paste();
                      return null;
                    },
                  ),
                },
                child: CallbackShortcuts(
                  bindings: {
                    const SingleActivator(LogicalKeyboardKey.tab): () =>
                        indentMarkdown(_active, widget.preferences.tabSize),
                    const SingleActivator(
                      LogicalKeyboardKey.tab,
                      shift: true,
                    ): () => indentMarkdown(
                      _active,
                      widget.preferences.tabSize,
                      outdent: true,
                    ),
                  },
                  child: TextField(
                    key: const ValueKey('markdown-live-block-input'),
                    controller: _active,
                    focusNode: _focus,
                    minLines: 1,
                    maxLines: null,
                    inputFormatters: [
                      MarkdownInputFormatter(widget.preferences),
                    ],
                    style: TextStyle(
                      fontSize: widget.preferences.previewFontSize,
                      height: 1.7,
                    ),
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      labelText: tr('编辑此段'),
                      suffixIcon: IconButton(
                        tooltip: tr('完成此段'),
                        onPressed: () {
                          _focus.unfocus();
                          setState(() {
                            _selected = null;
                            _blocks = MarkdownLiveEditor.ranges(
                              widget.controller.text,
                            );
                          });
                        },
                        icon: const Icon(Icons.check),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }
          return Padding(
            key: blockKey,
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: InkWell(
              key: ValueKey('markdown-live-block-$index'),
              borderRadius: BorderRadius.circular(6),
              onTap: () {
                widget.controller.selection = TextSelection.collapsed(
                  offset: range.$1,
                );
                _activate(index);
              },
              child: Opacity(
                opacity: widget.preferences.focusMode && _selected != null
                    ? .35
                    : 1,
                child: widget.renderBlock(content, range.$1),
              ),
            ),
          );
        },
      ),
    ),
  );
}
