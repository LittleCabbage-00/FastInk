import 'package:flutter/services.dart';

class MarkdownTask {
  /// 记录源文中一个待办项的位置、标记和完成状态，便于原位修改而不重写全文。
  const MarkdownTask(
    this.offset,
    this.marker,
    this.line,
    this.label,
    this.done,
  );

  /// offset：任务在 Markdown 全文中的字符偏移，用于定位和原位编辑；marker：任务勾选标记在源文中的字符偏移，更新时只替换对应标记；line：任务所在逻辑行编号，用于列表显示与跳转。
  final int offset, marker, line;

  /// label：任务或控件的显示标签，保留完整内容并由界面决定是否截断。
  final String label;

  /// done：该待办是否已勾选完成。
  final bool done;

  /// 扫描 Markdown 待办条目；跳过代码围栏与文稿属性中的示例，记录可定位的源文偏移。
  static List<MarkdownTask> parse(String content) {
    final result = <MarkdownTask>[];
    int offset = 0, lineNumber = 0;
    String? fence;
    int fenceLength = 0;
    final yamlEnd =
        RegExp(
          r'^\uFEFF?---\r?\n[\s\S]*?\r?\n(?:---|\.\.\.)[ \t]*(?:\r?\n|$)',
        ).firstMatch(content)?.end ??
        0;
    for (final rawLine in content.split('\n')) {
      final line = rawLine.endsWith('\r')
          ? rawLine.substring(0, rawLine.length - 1)
          : rawLine;
      lineNumber++;
      if (offset >= yamlEnd) {
        final boundary = RegExp(r'^ {0,3}(`{3,}|~{3,})(.*)$').firstMatch(line);
        if (boundary != null) {
          final token = boundary.group(1)!;
          if (fence == null) {
            fence = token[0];
            fenceLength = token.length;
          } else if (token[0] == fence &&
              token.length >= fenceLength &&
              boundary.group(2)!.trim().isEmpty) {
            fence = null;
          }
        } else if (fence == null) {
          final match = RegExp(
            r'^[ \t]*(?:>[ \t]*)*(?:[-+*]|\d+[.)])[ \t]+\[([ xX])\][ \t]+(.*)$',
          ).firstMatch(line);
          if (match != null) {
            final marker = line.indexOf('[', match.start) + 1;
            result.add(
              MarkdownTask(
                offset,
                offset + marker,
                lineNumber,
                match.group(2)!.trim(),
                match.group(1)!.toLowerCase() == 'x',
              ),
            );
          }
        }
      }
      offset += rawLine.length + 1;
    }
    return result;
  }
}

enum MarkdownLineAction { duplicate, moveUp, moveDown, delete, toggleTask }

/// 对选中行执行复制、删除、移动或待办切换，返回含更新光标的编辑值；保留非目标区域。
TextEditingValue editMarkdownLines(
  TextEditingValue value,
  MarkdownLineAction action,
) {
  if (!value.selection.isValid || !value.composing.isCollapsed) return value;
  // 保留 Windows 换行符，并根据本次操作换算选区位置。
  if (value.text.contains('\r\n') &&
      !value.text.replaceAll('\r\n', '').contains('\n')) {
    // 把原始文本偏移映射到统一换行后的索引，供行操作定位。
    int normalizedOffset(int offset) =>
        offset - '\r\n'.allMatches(value.text.substring(0, offset)).length;
    final normalized = value.copyWith(
      text: value.text.replaceAll('\r\n', '\n'),
      selection: TextSelection(
        baseOffset: normalizedOffset(value.selection.baseOffset),
        extentOffset: normalizedOffset(value.selection.extentOffset),
      ),
    );
    final changed = editMarkdownLines(normalized, action);
    // 把标准化文本索引映射回原始源文偏移，防止 CRLF 造成光标错位。
    int originalOffset(int offset) =>
        offset + '\n'.allMatches(changed.text.substring(0, offset)).length;
    return changed.copyWith(
      text: changed.text.replaceAll('\n', '\r\n'),
      selection: TextSelection(
        baseOffset: originalOffset(changed.selection.baseOffset),
        extentOffset: originalOffset(changed.selection.extentOffset),
      ),
    );
  }
  final text = value.text;
  final selection = value.selection;
  final start = selection.start == 0
      ? 0
      : text.lastIndexOf('\n', selection.start - 1) + 1;
  final tail = selection.end > start && text[selection.end - 1] == '\n'
      ? selection.end - 1
      : selection.end;
  final next = text.indexOf('\n', tail);
  final end = next < 0 ? text.length : next;
  final block = text.substring(start, end);
  // 构造替换目标范围后的 TextEditingValue，并设置对应选区。
  TextEditingValue replace(
    int from,
    int to,
    String replacement,
    int newStart,
    int newEnd,
  ) => TextEditingValue(
    text: text.replaceRange(from, to, replacement),
    selection: TextSelection(baseOffset: newStart, extentOffset: newEnd),
  );
  switch (action) {
    case MarkdownLineAction.duplicate:
      final shift = block.length + 1;
      return replace(
        end,
        end,
        '\n$block',
        selection.start + shift,
        selection.end + shift,
      );
    case MarkdownLineAction.moveUp:
      if (start == 0) return value;
      final previous = start < 2 ? 0 : text.lastIndexOf('\n', start - 2) + 1;
      final shift = start - previous;
      return replace(
        previous,
        end,
        '$block\n${text.substring(previous, start - 1)}',
        selection.start - shift,
        selection.end - shift,
      );
    case MarkdownLineAction.moveDown:
      if (end == text.length) return value;
      final following = text.indexOf('\n', end + 1);
      final last = following < 0 ? text.length : following;
      final shift = last - end;
      return replace(
        start,
        last,
        '${text.substring(end + 1, last)}\n$block',
        selection.start + shift,
        (selection.end + shift).clamp(0, text.length),
      );
    case MarkdownLineAction.delete:
      final from = end == text.length && start > 0 ? start - 1 : start;
      final to = end < text.length ? end + 1 : end;
      return replace(from, to, '', from, from);
    case MarkdownLineAction.toggleTask:
      final tasks = MarkdownTask.parse(
        text,
      ).where((task) => task.offset >= start && task.offset <= end).toList();
      if (tasks.isEmpty) return value;
      final done = tasks.any((task) => !task.done);
      var result = text;
      for (final task in tasks.reversed) {
        result = result.replaceRange(
          task.marker,
          task.marker + 1,
          done ? 'x' : ' ',
        );
      }
      return value.copyWith(text: result, composing: TextRange.empty);
  }
}

/// 统计中文字符与英文/数字词，忽略空白和标点；用于缓存后的字数显示。
int markdownWordCount(String text) {
  final cjk = RegExp(r'[\u3400-\u4DBF\u4E00-\u9FFF\uF900-\uFAFF]');
  return cjk.allMatches(text).length +
      RegExp(
        r'[\p{L}\p{N}]+(?:[’\x27-][\p{L}\p{N}]+)*',
        unicode: true,
      ).allMatches(text.replaceAll(cjk, ' ')).length;
}
