import 'package:xml/xml.dart';
import '../models/pdf_outline.dart';

/// Poppler XML 将子级 `<outline>` 放在所属 `<item>` 之后，二者为同级节点。
/// 解析时还原该层级，并保留指向同一页的多个标题。
List<PdfOutlineEntry> parsePdfOutlineXml(String source) {
  final document = XmlDocument.parse(source);
  final outline = document.rootElement.getElement('outline');
  if (outline == null) return [];
  // 递归读取目录元素并保留标题层级与目标页；depth 用于限制/记录递归深度，非法目标不冒充有效页面。
  List<PdfOutlineEntry> read(XmlElement parent, int depth) {
    if (depth > 128) {
      throw const FormatException('PDF outline nesting is too deep');
    }
    final result = <PdfOutlineEntry>[];
    for (final element in parent.childElements) {
      if (element.name.local == 'item') {
        final page = int.tryParse(element.getAttribute('page') ?? '');
        result.add(
          PdfOutlineEntry(
            title: element.innerText.trim(),
            originalPage: page != null && page > 0 ? page : null,
          ),
        );
      } else if (element.name.local == 'outline') {
        final children = read(element, depth + 1);
        if (result.isEmpty) {
          result.addAll(children);
        } else {
          final previous = result.removeLast();
          result.add(
            PdfOutlineEntry(
              title: previous.title,
              originalPage: previous.originalPage,
              children: [...previous.children, ...children],
            ),
          );
        }
      }
    }
    return result;
  }

  return read(outline, 0);
}
