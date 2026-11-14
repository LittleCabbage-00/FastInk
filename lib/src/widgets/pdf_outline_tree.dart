import 'package:flutter/material.dart';
import '../core/app_localizations.dart';
import '../models/pdf_outline.dart';

class PdfOutlineTree extends StatelessWidget {
  /// 创建不可变的 PdfOutlineTree 参数对象；各参数保存在对应字段中，不在构造时执行外部读写。
  /// entries：PDF 原生目录的顶层节点列表，子节点保留在各节点内部。
  /// pageIndexes：原 PDF 页面身份到当前文稿零基索引的映射，重排或插页后用于正确跳转。
  /// currentIndex：当前活动页的零基索引，用于初始高亮或默认选择。
  /// onSelected：用户确认选择后的回调，传入值以声明类型为准，不把显示文本当稳定身份。
  const PdfOutlineTree({
    super.key,
    required this.entries,
    required this.pageIndexes,
    required this.currentIndex,
    required this.onSelected,
  });

  /// entries：PDF 原生目录的顶层节点列表，子节点保留在各节点内部。
  final List<PdfOutlineEntry> entries;

  /// pageIndexes：原 PDF 页面身份到当前文稿零基索引的映射，重排或插页后用于正确跳转。
  final Map<int, int> pageIndexes;

  /// currentIndex：当前活动页的零基索引，用于初始高亮或默认选择。
  final int currentIndex;

  /// onSelected：用户确认选择后的回调，传入值以声明类型为准，不把显示文本当稳定身份。
  final ValueChanged<int> onSelected;

  /// 构建可展开 PDF 目录树，原页身份通过 pageIndexes 映射到当前页，插页/重排后仍正确定位。
  @override
  Widget build(BuildContext context) {
    // 递归创建目录节点，path 用于独立保存展开状态，depth 用于缩进；无有效目标页的节点不错误跳转。
    Widget node(PdfOutlineEntry entry, String path, int depth) {
      final index = pageIndexes[entry.originalPage];
      final title = Text(
        entry.title,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      );
      final subtitle = index == null
          ? null
          : Text(tr('第 ${index + 1} 页', 'Page ${index + 1}'));
      if (entry.children.isEmpty) {
        return ListTile(
          dense: true,
          selected: index != null && index == currentIndex,
          contentPadding: EdgeInsets.only(left: 12 + depth * 10.0, right: 8),
          title: title,
          subtitle: subtitle,
          onTap: index == null ? null : () => onSelected(index),
        );
      }
      return ExpansionTile(
        key: PageStorageKey('pdf-outline-$path'),
        tilePadding: EdgeInsets.only(left: 12 + depth * 10.0, right: 8),
        title: InkWell(
          onTap: index == null ? null : () => onSelected(index),
          child: title,
        ),
        subtitle: subtitle,
        children: [
          for (int i = 0; i < entry.children.length; i++)
            node(entry.children[i], '$path-$i', depth + 1),
        ],
      );
    }

    return Column(
      children: [
        for (int i = 0; i < entries.length; i++) node(entries[i], '$i', 0),
      ],
    );
  }
}
