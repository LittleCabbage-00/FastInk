import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import '../core/markdown_preferences.dart';
import '../core/app_localizations.dart';

/// 轻量语法高亮仅改变显示，源文本和输入法组合过程
/// 仍使用 Flutter 常规文字编辑流程。
class MarkdownTextController extends TextEditingController {
  /// highlighting：是否为当前源码绘制语法高亮，关闭后保留可编辑纯文本。
  bool highlighting = true;

  /// focusMode：是否隐藏 Markdown 编辑的次要界面元素。
  bool focusMode = false;

  /// 按当前高亮开关与组合输入区生成源码 TextSpan，未高亮内容仍使用完整原文。
  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    // 中日韩输入法组合期间由 EditableText 显示，不修改组合内容。
    if (withComposing &&
        value.composing.isValid &&
        !value.composing.isCollapsed) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }
    if (!highlighting && !focusMode) return TextSpan(style: style, text: text);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final base = style ?? const TextStyle();
    final active = selection.isValid
        ? selection.extentOffset.clamp(0, text.length)
        : 0;
    final before = active == 0 ? -1 : text.lastIndexOf('\n\n', active - 1);
    final next = text.indexOf('\n\n', active);
    final activeStart = before < 0 ? 0 : before + 2;
    final activeEnd = next < 0 ? text.length : next;
    final spans = <TextSpan>[];
    int offset = 0;
    bool fenced = false;
    for (final line in text.split('\n')) {
      Color? color;
      if (highlighting) {
        if (RegExp(r'^\s*(```|~~~)').hasMatch(line)) {
          fenced = !fenced;
          color = dark ? const Color(0xffd7ba7d) : const Color(0xff946000);
        } else if (fenced) {
          color = dark ? const Color(0xffb5cea8) : const Color(0xff276738);
        } else if (RegExp(r'^ {0,3}#{1,6}\s').hasMatch(line)) {
          color = dark ? const Color(0xffb8a6ff) : const Color(0xff6254a3);
        } else if (RegExp(r'^\s*(>|[-+*]\s|\d+\.\s)').hasMatch(line)) {
          color = dark ? const Color(0xff88c7db) : const Color(0xff176b7d);
        }
      }
      final dim =
          focusMode &&
          (offset + line.length < activeStart || offset > activeEnd);
      final lineStyle = base.copyWith(
        color: dim
            ? (color ?? base.color ?? Colors.grey).withValues(alpha: .34)
            : color,
      );
      spans.add(TextSpan(text: line, style: lineStyle));
      if (offset + line.length < text.length) {
        spans.add(TextSpan(text: '\n', style: lineStyle));
      }
      offset += line.length + 1;
    }
    return TextSpan(style: base, children: spans);
  }
}

class MarkdownInputFormatter extends TextInputFormatter {
  /// 创建不可变的 MarkdownInputFormatter 参数对象；各参数保存在对应字段中，不在构造时执行外部读写。
  /// preferences：当前 Markdown 配置快照，设置变化后由组件更新流程同步。
  const MarkdownInputFormatter(this.preferences);

  /// preferences：当前 Markdown 配置快照，设置变化后由组件更新流程同步。
  final MarkdownPreferences preferences;

  /// pairs：输入辅助的开闭符号配对表，用于插入、跳过与配对删除。
  static const pairs = {
    '(': ')',
    '[': ']',
    '{': '}',
    '"': '"',
    "'": "'",
    '`': '`',
  };

  /// 处理配对符号、列表续写等输入辅助，输入法组合期间保留系统编辑值，不强行改写半个词。
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (!oldValue.selection.isValid ||
        !newValue.selection.isValid ||
        (newValue.composing.isValid && !newValue.composing.isCollapsed) ||
        (oldValue.composing.isValid && !oldValue.composing.isCollapsed)) {
      return newValue;
    }
    final start = oldValue.selection.start;
    final end = oldValue.selection.end;
    final delta = newValue.text.length - (oldValue.text.length - (end - start));
    if (delta == 1 &&
        newValue.selection.isCollapsed &&
        newValue.selection.end == start + 1) {
      final inserted = newValue.text.substring(start, start + 1);
      if (inserted == '\n' && preferences.autoPair) {
        final lineStart = start == 0
            ? 0
            : oldValue.text.lastIndexOf('\n', start - 1) + 1;
        final opening = RegExp(
          r'^\s*(`{3,}|~{3,})[^\s]*$',
        ).firstMatch(oldValue.text.substring(lineStart, start));
        if (opening != null &&
            !newValue.text
                .substring(start + 1)
                .trimLeft()
                .startsWith(opening.group(1)!)) {
          return TextEditingValue(
            text: newValue.text.replaceRange(
              start + 1,
              start + 1,
              '\n${opening.group(1)}',
            ),
            selection: TextSelection.collapsed(offset: start + 1),
          );
        }
      }
      if (inserted == '\n' && preferences.continueLists) {
        final lineStart = start == 0
            ? 0
            : oldValue.text.lastIndexOf('\n', start - 1) + 1;
        final line = oldValue.text.substring(lineStart, start);
        final match = RegExp(
          r'^(\s*)(?:(\d+)([.)])|([-+*]))\s+(?:\[([ xX])\]\s*)?',
        ).firstMatch(line);
        final quote = RegExp(r'^(\s*>\s*)').firstMatch(line);
        String continuation = RegExp(r'^\s*').firstMatch(line)!.group(0)!;
        if (match != null) {
          if (line.substring(match.end).trim().isEmpty) {
            final text = newValue.text.replaceRange(
              lineStart,
              start + 1,
              match.group(1)!,
            );
            return TextEditingValue(
              text: text,
              selection: TextSelection.collapsed(
                offset: lineStart + match.group(1)!.length,
              ),
            );
          }
          final marker = match.group(2) != null
              ? '${int.parse(match.group(2)!) + 1}${match.group(3)}'
              : match.group(4)!;
          continuation =
              '${match.group(1)}$marker ${match.group(5) != null ? '[ ] ' : ''}';
        } else if (quote != null) {
          if (line.substring(quote.end).trim().isEmpty) {
            return TextEditingValue(
              text: newValue.text.replaceRange(lineStart, start + 1, ''),
              selection: TextSelection.collapsed(offset: lineStart),
            );
          }
          continuation = quote.group(0)!;
        }
        if (continuation.isNotEmpty) {
          return TextEditingValue(
            text: newValue.text.replaceRange(
              start + 1,
              start + 1,
              continuation,
            ),
            selection: TextSelection.collapsed(
              offset: start + 1 + continuation.length,
            ),
          );
        }
      }
      if (preferences.autoPair) {
        if (inserted == '`' &&
            start >= 2 &&
            oldValue.text.substring(start - 2, start) == '``') {
          return newValue;
        }
        // 输入已有的闭合符号时跨过它，避免重复插入。
        if (start == end &&
            start < oldValue.text.length &&
            oldValue.text[start] == inserted &&
            pairs.values.contains(inserted)) {
          return oldValue.copyWith(
            selection: TextSelection.collapsed(offset: start + 1),
          );
        }
        final close = pairs[inserted];
        final apostrophe =
            inserted == "'" &&
            start > 0 &&
            RegExp(
              r'[\p{L}\p{N}]',
              unicode: true,
            ).hasMatch(oldValue.text[start - 1]);
        if (close != null && !apostrophe) {
          final selected = oldValue.text.substring(start, end);
          final text = oldValue.text.replaceRange(
            start,
            end,
            '$inserted$selected$close',
          );
          return TextEditingValue(
            text: text,
            selection: selected.isEmpty
                ? TextSelection.collapsed(offset: start + 1)
                : TextSelection(
                    baseOffset: start + 1,
                    extentOffset: start + 1 + selected.length,
                  ),
          );
        }
      }
    }
    if (preferences.autoPair &&
        oldValue.selection.isCollapsed &&
        start > 0 &&
        start < oldValue.text.length &&
        newValue.text.length == oldValue.text.length - 1 &&
        newValue.selection.end == start - 1 &&
        pairs[oldValue.text[start - 1]] == oldValue.text[start]) {
      return TextEditingValue(
        text: oldValue.text.replaceRange(start - 1, start + 1, ''),
        selection: TextSelection.collapsed(offset: start - 1),
      );
    }
    return newValue;
  }
}

class MarkdownSourceEditor extends StatefulWidget {
  /// 创建不可变的 MarkdownSourceEditor 参数对象；各参数保存在对应字段中，不在构造时执行外部读写。
  /// controller：该组件或绘制层使用的控制器，由构造方传入，具体内容遵循声明类型。
  /// scroll：源文编辑区滚动控制器；行号与正文位置需统一读取。
  /// focus：该编辑区域的键盘焦点依赖，快捷键只在适当输入上下文处理。
  /// undo：文本编辑使用的撤销控制器，与手写画布历史完全分开。
  /// preferences：当前 Markdown 配置快照，设置变化后由组件更新流程同步。
  /// readOnly：当前文稿或组件是否禁止内容修改，导航和查看不受此标志直接阻止。
  /// onPasteImage：请求读取/导入剪贴板图片并插入源文引用的异步回调。
  const MarkdownSourceEditor({
    super.key,
    required this.controller,
    required this.scroll,
    required this.focus,
    required this.undo,
    required this.preferences,
    required this.readOnly,
    this.onPasteImage,
  });

  /// controller：该组件或绘制层使用的控制器，由构造方传入，具体内容遵循声明类型。
  final MarkdownTextController controller;

  /// scroll：源文编辑区滚动控制器；行号与正文位置需统一读取。
  final ScrollController scroll;

  /// focus：该编辑区域的键盘焦点依赖，快捷键只在适当输入上下文处理。
  final FocusNode focus;

  /// undo：文本编辑使用的撤销控制器，与手写画布历史完全分开。
  final UndoHistoryController undo;

  /// preferences：当前 Markdown 配置快照，设置变化后由组件更新流程同步。
  final MarkdownPreferences preferences;

  /// readOnly：当前文稿或组件是否禁止内容修改，导航和查看不受此标志直接阻止。
  final bool readOnly;

  /// onPasteImage：请求读取/导入剪贴板图片并插入源文引用的异步回调。
  final Future<void> Function()? onPasteImage;

  @override
  State<MarkdownSourceEditor> createState() => _MarkdownSourceEditorState();
}

class _MarkdownSourceEditorState extends State<MarkdownSourceEditor> {
  /// _fieldKey：源码输入组件的定位键，用于查询当前文字布局和屏幕位置。
  final _fieldKey = GlobalKey();

  /// _layout：源码行号/定位使用的 TextPainter 排版缓存，失效或关闭时释放。
  TextPainter? _layout;

  /// _layoutKey：排版缓存签名，组合源文、宽度、样式与比例，防止复用错误字号或换行结果。
  (String, double, TextStyle, double)? _layoutKey;

  /// _markers：源码逻辑行起点的布局位置缓存，供行号绘制使用。
  List<Offset> _markers = [];

  /// _lastText：最近参与同步/排版的源文快照，用于忽略仅光标变化的通知。
  String _lastText = '';

  /// 保留普通文本剪贴板行为，受支持情况下回退为图片插入回调。
  Future<void> _paste() async {
    if (widget.readOnly) return;
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return;
    if (data?.text?.isNotEmpty == true) {
      final selection = widget.controller.selection;
      if (!selection.isValid) return;
      widget.controller.value = TextEditingValue(
        text: widget.controller.text.replaceRange(
          selection.start,
          selection.end,
          data!.text!,
        ),
        selection: TextSelection.collapsed(
          offset: selection.start + data.text!.length,
        ),
      );
    } else {
      await widget.onPasteImage?.call();
    }
  }

  /// 订阅文字与滚动变化以缓存行号布局，关闭时释放排版器与订阅。
  @override
  void initState() {
    super.initState();
    _lastText = widget.controller.text;
    widget.controller.addListener(_changed);
  }

  /// 解除对共享文本控制器的监听，释放本视图的行号排版缓存。
  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _layout?.dispose();
    super.dispose();
  }

  /// 实际源文或布局条件变化时作废行号/定位缓存，光标变化不应重复扫描整篇。
  void _changed() {
    final typed = widget.controller.text != _lastText;
    _lastText = widget.controller.text;
    if (mounted) setState(() {});
    if (typed && widget.preferences.typewriter && widget.focus.hasFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !widget.scroll.hasClients) return;
        RenderEditable? editable;
        // 遍历渲染树定位 EditableText 的实际行布局，避免用固定字符宽度猜测换行位置。
        void visit(RenderObject object) {
          if (object is RenderEditable) {
            editable = object;
          } else {
            object.visitChildren(visit);
          }
        }

        final root = _fieldKey.currentContext?.findRenderObject();
        if (root == null) return;
        visit(root);
        final position = widget.controller.selection.extent;
        if (!position.offset.isNegative && editable != null) {
          final rect = editable!.getLocalRectForCaret(position);
          final scroll = widget.scroll.position;
          widget.scroll.jumpTo(
            (scroll.pixels + rect.center.dy - scroll.viewportDimension * .45)
                .clamp(0.0, scroll.maxScrollExtent),
          );
        }
      });
    }
  }

  /// 对选中逻辑行增加或移除一个配置缩进档位，保持有效选区和撤销。
  void _indent({bool outdent = false}) {
    if (!widget.readOnly) {
      indentMarkdown(
        widget.controller,
        widget.preferences.tabSize,
        outdent: outdent,
      );
    }
  }

  /// 构建源码输入、行号和快捷键入口，使用独立控制器/焦点，布局缓存依赖文字、宽度、样式与比例。
  @override
  Widget build(BuildContext context) {
    final prefs = widget.preferences;
    final style = DefaultTextStyle.of(context).style.copyWith(
      fontFamily: prefs.editorFont,
      fontFamilyFallback: const ['Microsoft YaHei UI', 'Segoe UI'],
      fontSize: prefs.fontSize,
      height: prefs.lineHeight,
    );
    widget.controller.highlighting = prefs.syntaxHighlight;
    widget.controller.focusMode = prefs.focusMode;
    return LayoutBuilder(
      builder: (context, constraints) {
        final gutter = prefs.lineNumbers && constraints.maxWidth > 100
            ? 44.0
            : 0.0;
        if (gutter > 0) {
          final width = (constraints.maxWidth - gutter - 40).clamp(
            1.0,
            double.infinity,
          );
          final scale = MediaQuery.textScalerOf(context).scale(1);
          final cacheKey = (widget.controller.text, width, style, scale);
          if (_layoutKey != cacheKey) {
            _layout?.dispose();
            _layout = TextPainter(
              text: widget.controller.buildTextSpan(
                context: context,
                style: style,
                withComposing: false,
              ),
              textDirection: TextDirection.ltr,
              textScaler: MediaQuery.textScalerOf(context),
            )..layout(maxWidth: width);
            _layoutKey = cacheKey;
            _markers = [const Offset(0, 0)];
            for (final match in '\n'.allMatches(widget.controller.text)) {
              _markers.add(
                _layout!.getOffsetForCaret(
                  TextPosition(offset: match.end),
                  Rect.zero,
                ),
              );
            }
          }
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (gutter > 0)
              SizedBox(
                width: gutter,
                child: AnimatedBuilder(
                  animation: widget.scroll,
                  builder: (_, _) => CustomPaint(
                    painter: _LineNumberPainter(
                      markers: _markers,
                      scroll: widget.scroll.hasClients
                          ? widget.scroll.offset
                          : 0,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      font: prefs.fontSize,
                      height: prefs.lineHeight,
                    ),
                  ),
                ),
              ),
            Expanded(
              child: Actions(
                actions: {
                  PasteTextIntent: CallbackAction<PasteTextIntent>(
                    onInvoke: (_) {
                      unawaited(_paste());
                      return null;
                    },
                  ),
                },
                child: CallbackShortcuts(
                  bindings: {
                    const SingleActivator(LogicalKeyboardKey.tab): () =>
                        _indent(),
                    const SingleActivator(
                      LogicalKeyboardKey.tab,
                      shift: true,
                    ): () =>
                        _indent(outdent: true),
                  },
                  child: KeyedSubtree(
                    key: _fieldKey,
                    child: TextField(
                      key: const ValueKey('markdown-source'),
                      controller: widget.controller,
                      scrollController: widget.scroll,
                      focusNode: widget.focus,
                      undoController: widget.undo,
                      readOnly: widget.readOnly,
                      inputFormatters: [MarkdownInputFormatter(prefs)],
                      maxLines: null,
                      expands: true,
                      textAlignVertical: TextAlignVertical.top,
                      style: style,
                      decoration: InputDecoration(
                        hintText: tr('在此输入 Markdown 内容…'),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.fromLTRB(
                          20,
                          20,
                          20,
                          prefs.typewriter ? constraints.maxHeight * .45 : 20,
                        ),
                      ),
                      keyboardType: TextInputType.multiline,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _LineNumberPainter extends CustomPainter {
  /// 绑定逻辑行位置、滚动偏移、字体与颜色，行号跟随正文实际排版而非固定高度猜测。
  _LineNumberPainter({
    required this.markers,
    required this.scroll,
    required this.color,
    required this.font,
    required this.height,
  });

  /// markers：待绘制行号对应的行起点坐标列表。
  final List<Offset> markers;

  /// scroll：源文编辑区滚动控制器；行号与正文位置需统一读取。
  final double scroll;

  /// 绘制颜色。
  final Color color;

  /// font：行号使用的逻辑字号，与正文设置对应但单独绘制。
  final double font;

  /// height：行号绘制的逻辑行高，随字体排版而非页面尺寸换算。
  final double height;

  /// 将行起点按当前滚动偏移绘制为可见行号，超出绘制范围的标记无需排版显示。
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    final painter = TextPainter(textDirection: TextDirection.ltr);
    for (int i = 0; i < markers.length; i++) {
      final y = 20 + markers[i].dy - scroll;
      if (y < -font * height) continue;
      if (y > size.height) break;
      painter.text = TextSpan(
        text: '${i + 1}',
        style: TextStyle(
          fontFamily: 'Consolas',
          fontSize: 11,
          color: color.withValues(alpha: .65),
        ),
      );
      painter.layout();
      painter.paint(
        canvas,
        Offset(
          size.width - painter.width - 8,
          y + (font * height - painter.height) / 2,
        ),
      );
    }
    painter.dispose();
    canvas.restore();
  }

  /// 行号位置、滚动源和文字样式变化后重绘行号栏。
  @override
  bool shouldRepaint(covariant _LineNumberPainter old) =>
      old.markers != markers ||
      old.scroll != scroll ||
      old.color != color ||
      old.font != font ||
      old.height != height;
}

/// 按 Tab 宽度处理选中逻辑行的缩进/反缩进，兼容跨行与行尾选择，不把正文整篇格式化。
void indentMarkdown(
  TextEditingController controller,
  int tabSize, {
  bool outdent = false,
}) {
  final selection = controller.selection;
  if (!selection.isValid) return;
  final text = controller.text;
  final spaces = ' ' * tabSize;
  if (selection.isCollapsed && !outdent) {
    controller.value = TextEditingValue(
      text: text.replaceRange(selection.start, selection.end, spaces),
      selection: TextSelection.collapsed(
        offset: selection.start + spaces.length,
      ),
    );
    return;
  }
  final start = selection.start == 0
      ? 0
      : text.lastIndexOf('\n', selection.start - 1) + 1;
  final selectedEnd = selection.end > start && text[selection.end - 1] == '\n'
      ? selection.end - 1
      : selection.end;
  final next = text.indexOf('\n', selectedEnd);
  final end = next < 0 ? text.length : next;
  final replacement = text
      .substring(start, end)
      .split('\n')
      .map(
        (line) => outdent
            ? line.replaceFirst(RegExp('^( {1,${spaces.length}}|\t)'), '')
            : '$spaces$line',
      )
      .join('\n');
  controller.value = TextEditingValue(
    text: text.replaceRange(start, end, replacement),
    selection: TextSelection(
      baseOffset: start,
      extentOffset: start + replacement.length,
    ),
  );
}
