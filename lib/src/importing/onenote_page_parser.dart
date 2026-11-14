import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/painting.dart';
import 'package:html/parser.dart' as html;
import 'package:xml/xml.dart';
import '../models/models.dart';

class OneNoteEditablePage {
  /// 返回已转换的页面逻辑尺寸、可编辑笔画及图片资源字节，持久化由文稿仓库执行。
  OneNoteEditablePage(
    this.title,
    this.size,
    this.strokes,
    this.images,
    this.warnings,
  );

  /// 保存和显示使用的完整标题。
  final String title;

  /// size：OneNote 解析页的内容逻辑尺寸，原对象坐标按此换算到 FastInk 页面。
  final Size size;

  /// strokes：当前对象持有的笔画集合，元素坐标和宽度遵循 InkStroke 数据约定。
  final List<InkStroke> strokes;

  /// images：OneNote 解析出的嵌入图片字节，按资源身份收集以供导入持久化。
  final Map<String, Uint8List> images;

  /// warnings：转换中不能完整处理的内容提示，不能静默冒充完全无损导入。
  final List<String> warnings;
}

class _OneNoteObject {
  /// 保存原对象边界和按最终页面尺寸生成笔画的函数，推迟归一化避免页面基准未确定。
  _OneNoteObject(this.bounds, this.stroke);

  /// bounds：原 OneNote 对象的逻辑几何边界，用于确定页面尺寸与偏移。
  final Rect bounds;

  /// stroke：根据最终页面尺寸构造归一化笔画的延迟函数，避免过早固定错误页面比例。
  final InkStroke Function(Size) stroke;
}

/// 一次转换一页，所有几何数据先使用 OneNote 页面单位，
/// 归一化后再缩放，因此空白背景尺寸不会改变对象位置。
OneNoteEditablePage parseOneNotePage(String source, List<dynamic> decodedInk) {
  final document = XmlDocument.parse(source);
  final page = document.rootElement;
  // 在当前 XML 元素的直接子节点中按名称查找，找不到返回 null，不把深层同名元素误当直接属性。
  XmlElement? child(XmlElement element, String name) =>
      element.childElements.where((e) => e.name.local == name).firstOrNull;
  // 读取 XML 属性数值并使用 fallback 处理缺失或无法解析的值。
  double number(XmlElement? e, String name, [double fallback = 0]) {
    final value = double.tryParse(e?.getAttribute(name) ?? '');
    return value != null && value.isFinite ? value : fallback;
  }

  // 从源对象位置与尺寸构造页面逻辑矩形，后续再统一偏移/归一化。
  Rect bounds(
    XmlElement element, {
    Offset origin = Offset.zero,
    double width = 100,
    double height = 100,
  }) {
    final p = child(element, 'Position');
    final size = child(element, 'Size');
    return Rect.fromLTWH(
      origin.dx + number(p ?? element, 'x'),
      origin.dy + number(p ?? element, 'y'),
      math.max(.1, number(size ?? element, 'width', width)),
      math.max(.1, number(size ?? element, 'height', height)),
    );
  }

  // 把源矩形四角转换为相对最终页面尺寸的归一化 InkPoint。
  List<InkPoint> corners(Rect r, Size size) => [
    for (final p in [r.topLeft, r.topRight, r.bottomRight, r.bottomLeft])
      InkPoint(p.dx / size.width, p.dy / size.height, .5),
  ];
  final objects = <_OneNoteObject>[];
  final images = <String, Uint8List>{};
  final warnings = <String>[];
  final styles = <String, Map<String, String>>{};
  // 把受支持内联样式字符串解析为键值，用于还原字体与文字样式。
  Map<String, String> css(String value) => {
    for (final m in RegExp(r'([\w-]+)\s*:\s*([^;]+)').allMatches(value))
      m[1]!.toLowerCase(): m[2]!.trim().replaceAll(
        RegExp(r'''^["']|["']$'''),
        '',
      ),
  };
  // 解析源颜色为 32 位 ARGB，格式不支持或缺失时使用传入默认值。
  int color(String? value, [int fallback = 0xff202124]) {
    if (value == null || value == 'automatic') return fallback;
    final text = value.replaceFirst('#', '');
    if (RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(text)) {
      return 0xff000000 | int.parse(text, radix: 16);
    }
    return fallback;
  }

  for (final q in page.childElements.where(
    (e) => e.name.local == 'QuickStyleDef',
  )) {
    styles[q.getAttribute('index') ?? ''] = {
      'font-family': q.getAttribute('font') ?? 'Calibri',
      'font-size': q.getAttribute('fontSize') ?? '11',
      'color': q.getAttribute('fontColor') ?? 'automatic',
    };
  }
  // 从源富文本标记提取可编辑纯文字，保留段落结构而非显示 HTML 标签。
  String plain(String markup) {
    final fragment = html.parseFragment(
      markup
          .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
          .replaceAll(RegExp(r'</(?:p|div)>', caseSensitive: false), '\n'),
    );
    return (fragment.text ?? '').replaceAll('\u00a0', ' ');
  }

  // 将源文字、字体和边界转换为可编辑文本对象，并返回布局使用的有效尺寸。
  double addText(
    XmlElement oe,
    Offset position,
    double boxWidth, {
    double defaultSize = 11,
    String? overrideText,
  }) {
    final textNodes = oe.childElements.where((e) => e.name.local == 'T');
    final markup = textNodes.map((e) => e.innerText).join();
    var text = overrideText ?? plain(markup);
    if (text.isEmpty) return defaultSize * 1.3;
    final style = <String, String>{
      ...?styles[oe.getAttribute('quickStyleIndex')],
      ...css(oe.getAttribute('style') ?? ''),
    };
    final fragment = html.parseFragment(markup);
    // 整个段落保留为一个可编辑文本框，并保留基础样式；
    // 行内混合样式单独报告，避免把每个单词拆成独立文本框。
    final spans = fragment.querySelectorAll('[style]');
    if (spans.isNotEmpty &&
        spans.map((e) => e.attributes['style']).toSet().length == 1) {
      style.addAll(css(spans.first.attributes['style']!));
    }
    if (spans.map((e) => e.attributes['style']).toSet().length > 1 ||
        fragment.querySelector('b,strong,i,em,u') != null) {
      warnings.add(
        'Mixed inline formatting was simplified in an editable paragraph.',
      );
    }
    final fontSize =
        double.tryParse(
          (style['font-size'] ?? '$defaultSize').replaceAll(
            RegExp(r'[^\d.]'),
            '',
          ),
        ) ??
        defaultSize;
    final family = style['font-family'] ?? 'Calibri';
    final bold =
        style['font-weight'] == 'bold' ||
        (int.tryParse(style['font-weight'] ?? '') ?? 400) >= 600;
    final italic = style['font-style'] == 'italic';
    final underline = style['text-decoration']?.contains('underline') ?? false;
    final list = child(oe, 'List');
    if (list != null) {
      text = '${child(list, 'Number') != null ? '1.' : '•'} $text';
    }
    final tags = oe.childElements.where((e) => e.name.local == 'Tag');
    if (tags.any((e) => e.getAttribute('symbol') == '3')) {
      text =
          '${tags.any((e) => e.getAttribute('completed') == 'true') ? '☑' : '☐'} $text';
    }
    final align = switch (oe.getAttribute('alignment')) {
      'center' => TextAlign.center,
      'right' => TextAlign.right,
      _ => TextAlign.left,
    };
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: family,
          fontFamilyFallback: const ['Microsoft YaHei UI'],
          fontSize: fontSize,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
          fontStyle: italic ? FontStyle.italic : FontStyle.normal,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: align,
    )..layout(maxWidth: math.max(40, boxWidth));
    final rect = Rect.fromLTWH(
      position.dx,
      position.dy,
      math.max(40, boxWidth),
      math.max(fontSize, painter.height),
    );
    painter.dispose();
    objects.add(
      _OneNoteObject(
        rect,
        (size) => InkStroke(
          color: color(style['color']),
          width: 1,
          points: corners(rect, size),
          text: text,
          textSize: fontSize / size.height,
          textBoxWidth: rect.width / size.width,
          textFontFamily: family,
          textWeight: bold ? 700 : 400,
          textItalic: italic,
          textUnderline: underline,
          textAlign: align,
        ),
      ),
    );
    return rect.height;
  }

  // 收集源嵌入图片及几何信息，保存引用对象，实际资源文件由上层导入。
  void addImage(XmlElement image, Rect rect) {
    final data = child(image, 'Data');
    if (data == null) {
      warnings.add('An image has no embedded data.');
      return;
    }
    final id = 'onenote-image-${images.length}';
    images[id] = base64Decode(data.innerText.replaceAll(RegExp(r'\s'), ''));
    objects.add(
      _OneNoteObject(
        rect,
        (size) => InkStroke(
          color: 0xffffffff,
          width: 1,
          kind: StrokeKind.image,
          points: corners(rect, size),
          imageAsset: id,
        ),
      ),
    );
  }

  late double Function(XmlElement, Offset, double) outline;
  outline = (children, origin, width) {
    var y = origin.dy;
    for (final oe in children.childElements.where(
      (e) => e.name.local == 'OE',
    )) {
      final indent = number(oe, 'indent') * 18;
      final explicit = child(oe, 'Position');
      final x = explicit == null
          ? origin.dx + indent
          : origin.dx + number(explicit, 'x');
      if (explicit != null) y = origin.dy + number(explicit, 'y');
      final table = child(oe, 'Table');
      if (table != null) {
        final cols =
            child(
              table,
              'Columns',
            )?.childElements.where((e) => e.name.local == 'Column').toList() ??
            [];
        for (final row in table.childElements.where(
          (e) => e.name.local == 'Row',
        )) {
          var cellX = x;
          var rowHeight = 20.0;
          final cells = row.childElements
              .where((e) => e.name.local == 'Cell')
              .toList();
          for (var i = 0; i < cells.length; i++) {
            final cellWidth = i < cols.length
                ? number(cols[i], 'width', width / math.max(1, cells.length))
                : width / math.max(1, cells.length);
            final content = child(cells[i], 'OEChildren');
            if (content != null) {
              rowHeight = math.max(
                rowHeight,
                outline(
                      content,
                      Offset(cellX + 4, y + 4),
                      math.max(40, cellWidth - 8),
                    ) -
                    y +
                    4,
              );
            }
            cellX += cellWidth;
          }
          // 表格文字继续可编辑，简单边框转换成普通笔迹。
          final rect = Rect.fromLTWH(
            x,
            y,
            math.max(width, cellX - x),
            rowHeight,
          );
          objects.add(
            _OneNoteObject(
              rect,
              (size) => InkStroke(
                color: 0xffa0a0a0,
                width: .5 / math.sqrt(size.width * size.height),
                penStyle: PenStyle.ball,
                points: [...corners(rect, size), corners(rect, size).first],
              ),
            ),
          );
          y += rowHeight;
        }
      } else {
        final image = child(oe, 'Image');
        if (image != null) {
          final rect = bounds(image, origin: Offset(x, y));
          addImage(image, rect);
          y = math.max(y, rect.bottom);
        } else if (oe.childElements.any((e) => e.name.local == 'T')) {
          y += addText(oe, Offset(x, y), width - indent);
        }
        final nested = child(oe, 'OEChildren');
        if (nested != null) {
          y = outline(nested, Offset(x + 18, y), math.max(40, width - 18));
        }
      }
      y += 2;
    }
    return y;
  };
  final title = child(page, 'Title');
  if (title != null) {
    var y = 24.0;
    for (final oe in title.childElements.where((e) => e.name.local == 'OE')) {
      y += addText(oe, Offset(36, y), 520, defaultSize: 20);
    }
  }
  for (final object in page.childElements) {
    if (object.name.local == 'Outline') {
      final rect = bounds(object, width: 500);
      final content = child(object, 'OEChildren');
      if (content != null) outline(content, rect.topLeft, rect.width);
    } else if (object.name.local == 'Image') {
      addImage(object, bounds(object));
    }
  }
  final nodes = page.descendants
      .whereType<XmlElement>()
      .where((e) => e.name.local == 'InkDrawing' || e.name.local == 'InkWord')
      .toList();
  final importedInk = <int>{};
  for (final object in decodedInk.cast<Map<String, dynamic>>()) {
    final index = (object['index'] as num).toInt();
    if (index < 0 || index >= nodes.length) {
      throw const FormatException('Ink object index is invalid.');
    }
    importedInk.add(index);
    final node = nodes[index];
    final b = (object['bounds'] as List).cast<num>();
    final rect = bounds(node, width: b[2].toDouble(), height: b[3].toDouble());
    final sx = rect.width / math.max(.001, b[2].toDouble());
    final sy = rect.height / math.max(.001, b[3].toDouble());
    for (final ink
        in (object['strokes'] as List).cast<Map<String, dynamic>>()) {
      final points = (ink['points'] as List).map((value) {
        final p = (value as List).cast<num>();
        return [
          rect.left + (p[0] - b[0]) * sx,
          rect.top + (p[1] - b[1]) * sy,
          ink['ignorePressure'] == true ? .5 : p[2].toDouble(),
        ];
      }).toList();
      objects.add(
        _OneNoteObject(
          rect,
          (size) => InkStroke(
            color: (ink['color'] as num).toInt(),
            kind: ink['highlighter'] == true
                ? StrokeKind.highlighter
                : StrokeKind.pen,
            penStyle: ink['ignorePressure'] == true
                ? PenStyle.ball
                : PenStyle.fountain,
            width:
                (ink['width'] as num).toDouble() *
                math.sqrt(sx * sy) /
                math.sqrt(size.width * size.height),
            points: [
              for (final p in points)
                InkPoint(p[0] / size.width, p[1] / size.height, p[2]),
            ],
          ),
        ),
      );
    }
  }
  for (var i = 0; i < nodes.length; i++) {
    if (!importedInk.contains(i) && child(nodes[i], 'Data') != null) {
      warnings.add('An ink object could not be imported as editable strokes.');
    }
  }
  for (final object in page.descendants.whereType<XmlElement>().where(
    (e) => ['InsertedFile', 'MediaFile', 'Equation'].contains(e.name.local),
  )) {
    warnings.add(
      '${object.name.local} is preserved in the original file and import XML.',
    );
  }
  var right = 595.0, bottom = 842.0;
  for (final object in objects) {
    right = math.max(right, object.bounds.right + 36);
    bottom = math.max(bottom, object.bounds.bottom + 36);
  }
  var left = 0.0, top = 0.0;
  for (final object in objects) {
    left = math.min(left, object.bounds.left - 36);
    top = math.min(top, object.bounds.top - 24);
  }
  final size = Size(right - left, bottom - top);
  return OneNoteEditablePage(
    page.getAttribute('name') ?? 'OneNote page',
    size,
    [
      for (final object in objects)
        object
            .stroke(size)
            .copy(
              points: [
                for (final p in object.stroke(size).points)
                  InkPoint(
                    p.x - left / size.width,
                    p.y - top / size.height,
                    p.pressure,
                  ),
              ],
            ),
    ],
    images,
    warnings.toSet().toList(),
  );
}
