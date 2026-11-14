import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

/// 用于显示代码块的轻量词法分析器，绝不执行导入的代码。
class MarkdownCodeHighlighter extends SyntaxHighlighter {
  /// 绑定代码预览深浅配色，词法规则与源文独立，不修改代码内容。
  MarkdownCodeHighlighter({required this.dark});

  /// dark：当前预览是否使用深色配色，不改写源 Markdown 或纸张数据。
  final bool dark;

  /// _tokens：代码高亮使用的词法匹配规则，编辑内容变化后按新文本重新匹配。
  static final _tokens = RegExp(
    r'''(//[^\n]*|\#[^\n]*|/\*[\s\S]*?\*/)|("(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*')|\b(class|def|function|final|const|var|let|import|from|return|if|else|for|while|in|async|await|void|int|double|String|bool|true|false|null|None|True|False|public|private|static|new|try|catch|throw|SELECT|FROM|WHERE|AND|OR)\b|\b(\d+(?:\.\d+)?)\b''',
  );

  /// 按受支持词法片段生成带颜色 TextSpan，未匹配部分保留原文字与基础样式。
  @override
  TextSpan format(String source) {
    final spans = <TextSpan>[];
    int offset = 0;
    for (final match in _tokens.allMatches(source)) {
      if (match.start > offset) {
        spans.add(TextSpan(text: source.substring(offset, match.start)));
      }
      final color = match.group(1) != null
          ? (dark ? const Color(0xff8b949e) : const Color(0xff6a737d))
          : match.group(2) != null
          ? (dark ? const Color(0xffa5d6a7) : const Color(0xff237238))
          : match.group(3) != null
          ? (dark ? const Color(0xffce93d8) : const Color(0xff7950a3))
          : (dark ? const Color(0xffffcc80) : const Color(0xffa46100));
      spans.add(
        TextSpan(
          text: match.group(0),
          style: TextStyle(color: color),
        ),
      );
      offset = match.end;
    }
    if (offset < source.length) {
      spans.add(TextSpan(text: source.substring(offset)));
    }
    return TextSpan(children: spans);
  }
}
