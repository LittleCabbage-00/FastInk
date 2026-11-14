import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:markdown/markdown.dart' as md;
import 'markdown_workspace.dart';
import 'markdown_diagrams.dart';
import 'package:image/image.dart' as raster;

class MarkdownDocumentExport {
  /// 把解析后的 Markdown 提取为纯文本，保留正文结构而非简单删除所有标点。
  static String plainText(String content) {
    final nodes = md.Document(
      extensionSet: md.ExtensionSet.gitHubWeb,
      blockSyntaxes: [md.FootnoteDefSyntax()],
    ).parseLines(MarkdownWorkspace.plainBody(content).split('\n'));
    return nodes.map((node) => node.textContent).join('\n\n');
  }

  /// 原生 OOXML 导出，无需安装 Word、Pandoc 或扩展插件。
  static Future<Uint8List> docx(
    String content, {
    required String sourcePath,
    bool renderDiagrams = true,
  }) async {
    final archive = Archive();
    final relationships = <String>[
      '<Relationship Id="styles" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>',
    ];
    final base = File(sourcePath).absolute.uri;
    int imageIndex = 0;
    int linkIndex = 0;
    // 对 XML 文本做实体转义，避免正文符号破坏生成的 DOCX 内容。
    String escape(String text) =>
        const HtmlEscape(HtmlEscapeMode.element).convert(text);
    // 把行内 Markdown 节点转换为可编辑的 Word 文本运行，保留支持的加粗、斜体等样式。
    String runs(
      md.Node node, {
      bool bold = false,
      bool italic = false,
      bool strike = false,
      bool code = false,
    }) {
      if (node is md.Element &&
          node.tag == 'a' &&
          node.attributes['href'] != null) {
        final id = 'link${++linkIndex}';
        final href = const HtmlEscape(
          HtmlEscapeMode.attribute,
        ).convert(node.attributes['href']!);
        relationships.add(
          '<Relationship Id="$id" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink" Target="$href" TargetMode="External"/>',
        );
        return '<w:hyperlink r:id="$id">${(node.children ?? []).map((child) => runs(child, bold: bold, italic: italic, strike: strike, code: code)).join()}</w:hyperlink>';
      }
      if (node is md.Element && node.tag != 'img' && node.tag != 'br') {
        return (node.children ?? [])
            .map(
              (child) => runs(
                child,
                bold: bold || node.tag == 'strong',
                italic: italic || node.tag == 'em',
                strike: strike || node.tag == 'del',
                code: code || node.tag == 'code',
              ),
            )
            .join();
      }
      if (node is md.Element && node.tag == 'br') return '<w:r><w:br/></w:r>';
      final value = node is md.Element && node.tag == 'img'
          ? '[${node.attributes['alt'] ?? '图片'}]'
          : node.textContent;
      return value
          .split('\n')
          .map(
            (line) =>
                '<w:r><w:rPr>${bold ? '<w:b/>' : ''}${italic ? '<w:i/>' : ''}${strike ? '<w:strike/>' : ''}${code ? '<w:rFonts w:ascii="Consolas" w:hAnsi="Consolas"/>' : ''}</w:rPr><w:t xml:space="preserve">${escape(line)}</w:t></w:r>',
          )
          .join('<w:r><w:br/></w:r>');
    }

    // 把段落正文包装为指定 Word 段落样式，默认使用 Normal。
    String paragraph(String body, {String style = 'Normal'}) =>
        '<w:p><w:pPr><w:pStyle w:val="$style"/></w:pPr>$body</w:p>';
    // 递归转换 Markdown 块为 Word 结构，图片等资源处理允许异步读取。
    Future<String> block(md.Node node) async {
      if (node is! md.Element) return paragraph(runs(node));
      if (node.tag == 'ul' || node.tag == 'ol') {
        int index = 0;
        return (await Future.wait(
          (node.children ?? []).map((child) async {
            index++;
            final prefix = node.tag == 'ol' ? '$index. ' : '• ';
            return paragraph(runs(md.Text(prefix)) + runs(child));
          }),
        )).join();
      }
      if (node.tag == 'table') {
        final rows = <md.Element>[];
        // 遍历 Markdown 节点收集纯文本/结构信息，行内与块级节点按各自语义处理。
        void walk(md.Node node) {
          if (node is md.Element) {
            if (node.tag == 'tr') {
              rows.add(node);
            } else {
              for (final child in node.children ?? []) {
                walk(child);
              }
            }
          }
        }

        walk(node);
        return '<w:tbl><w:tblPr><w:tblW w:w="0" w:type="auto"/><w:tblBorders>${['top', 'left', 'bottom', 'right', 'insideH', 'insideV'].map((edge) => '<w:$edge w:val="single" w:sz="4" w:color="999999"/>').join()}</w:tblBorders></w:tblPr>${rows.map((row) => '<w:tr>${(row.children ?? []).map((cell) => '<w:tc>${paragraph(runs(cell, bold: cell is md.Element && cell.tag == 'th'))}</w:tc>').join()}</w:tr>').join()}</w:tbl>';
      }
      if (node.tag == 'blockquote') {
        return paragraph(runs(node), style: 'Quote');
      }
      if (node.tag == 'pre' &&
          renderDiagrams &&
          node.children
                  ?.whereType<md.Element>()
                  .firstOrNull
                  ?.attributes['class'] ==
              'language-mermaid') {
        final image = await MarkdownDiagrams.render(
          node.textContent.trimRight(),
          dark: false,
        );
        return block(
          md.Element('p', [
            md.Element.empty('img')
              ..attributes['src'] = image.absolute.uri.toString(),
          ]),
        );
      }
      if (node.tag == 'pre') {
        return paragraph(runs(node, code: true), style: 'Code');
      }
      if (node.tag == 'hr') {
        return '<w:p><w:pPr><w:pBdr><w:bottom w:val="single" w:sz="6" w:color="999999"/></w:pBdr></w:pPr></w:p>';
      }
      final images = <md.Element>[];
      // 收集待导出的文档子节点，避免只处理顶层而丢失嵌套内容。
      void collect(md.Node value) {
        if (value is md.Element) {
          if (value.tag == 'img') images.add(value);
          for (final child in value.children ?? []) {
            collect(child);
          }
        }
      }

      collect(node);
      final output = StringBuffer(
        paragraph(
          runs(node),
          style: RegExp(r'^h[1-6]$').hasMatch(node.tag)
              ? 'Heading${node.tag.substring(1)}'
              : 'Normal',
        ),
      );
      for (final image in images) {
        final src = image.attributes['src'];
        if (src == null) continue;
        final uri = base.resolve(src);
        if (uri.scheme != 'file') continue;
        final file = File.fromUri(uri);
        if (!await file.exists() || await file.length() > 20 * 1024 * 1024) {
          continue;
        }
        final bytes = await file.readAsBytes();
        final png = bytes.length > 24 && bytes[0] == 137 && bytes[1] == 80;
        final jpg = bytes.length > 3 && bytes[0] == 255 && bytes[1] == 216;
        if (!png && !jpg) continue;
        final name = 'image${++imageIndex}.${png ? 'png' : 'jpg'}';
        archive.addFile(ArchiveFile('word/media/$name', bytes.length, bytes));
        relationships.add(
          '<Relationship Id="image$imageIndex" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/$name"/>',
        );
        double ratio = 1.5;
        if (png) {
          final data = ByteData.sublistView(bytes);
          ratio = data.getUint32(16) / data.getUint32(20);
        } else {
          final info = raster.JpegDecoder().startDecode(bytes);
          if (info != null && info.height > 0) ratio = info.width / info.height;
        }
        const width = 5486400;
        final height = (width / ratio).round().clamp(300000, 7000000);
        output.write(
          '<w:p><w:r><w:drawing><wp:inline><wp:extent cx="$width" cy="$height"/><wp:docPr id="$imageIndex" name="$name"/><a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture"><pic:pic><pic:nvPicPr><pic:cNvPr id="$imageIndex" name="$name"/><pic:cNvPicPr/></pic:nvPicPr><pic:blipFill><a:blip r:embed="image$imageIndex"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill><pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="$width" cy="$height"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr></pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing></w:r></w:p>',
        );
      }
      return output.toString();
    }

    final nodes = md.Document(
      extensionSet: md.ExtensionSet.gitHubWeb,
      blockSyntaxes: [md.FootnoteDefSyntax()],
    ).parseLines(MarkdownWorkspace.plainBody(content).split('\n'));
    final body = StringBuffer();
    for (final node in nodes) {
      body.write(await block(node));
    }
    // 向 DOCX 压缩包写入指定内部路径的 UTF-8 文本条目。
    void entry(String path, String text) {
      final bytes = utf8.encode(text);
      archive.addFile(ArchiveFile(path, bytes.length, bytes));
    }

    entry(
      '[Content_Types].xml',
      '<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Default Extension="png" ContentType="image/png"/><Default Extension="jpg" ContentType="image/jpeg"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/><Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/></Types>',
    );
    entry(
      '_rels/.rels',
      '<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="document" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>',
    );
    entry(
      'word/_rels/document.xml.rels',
      '<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">${relationships.join()}</Relationships>',
    );
    entry(
      'word/styles.xml',
      '<?xml version="1.0" encoding="UTF-8"?><w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:eastAsia="Microsoft YaHei"/><w:sz w:val="22"/></w:rPr></w:rPrDefault></w:docDefaults><w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/></w:style>${[for (int level = 1; level <= 6; level++) '<w:style w:type="paragraph" w:styleId="Heading$level"><w:name w:val="heading $level"/><w:basedOn w:val="Normal"/><w:pPr><w:outlineLvl w:val="${level - 1}"/></w:pPr><w:rPr><w:b/><w:sz w:val="${42 - level * 4}"/></w:rPr></w:style>'].join()}<w:style w:type="paragraph" w:styleId="Quote"><w:name w:val="Quote"/><w:pPr><w:ind w:left="420"/></w:pPr><w:rPr><w:i/></w:rPr></w:style><w:style w:type="paragraph" w:styleId="Code"><w:name w:val="Code"/><w:rPr><w:rFonts w:ascii="Consolas" w:hAnsi="Consolas"/><w:sz w:val="20"/></w:rPr></w:style></w:styles>',
    );
    entry(
      'word/document.xml',
      '<?xml version="1.0" encoding="UTF-8"?><w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture"><w:body>$body<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1134" w:right="1134" w:bottom="1134" w:left="1134"/></w:sectPr></w:body></w:document>',
    );
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }
}
