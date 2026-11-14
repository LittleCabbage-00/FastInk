import 'dart:convert';
import 'dart:io';
import 'package:image/image.dart' as raster;
import 'note_repository.dart';

class TemplateLibrary {
  /// 绑定当前资料库的用户模板根位置，不修改内置模板资源。
  TemplateLibrary(this.dataRoot);

  /// dataRoot：当前资料库根目录，文稿、笔迹和本地资源都相对该目录定位。
  final String dataRoot;

  /// 返回用户模板索引文件位置。
  File get _index => File('$dataRoot/templates/templates.json');

  /// 读取用户保存的模板列表，忽略无效记录并保留可用模板。
  Future<List<PaperTemplate>> load() async {
    if (!await _index.exists()) return [];
    return (jsonDecode(await _index.readAsString()) as List)
        .map((v) => PaperTemplate.fromJson(Map<String, Object?>.from(v as Map)))
        .toList();
  }

  /// 更新用户模板索引；具体模板对象及资源由调用方提供。
  Future<void> save(
    PaperTemplate template,
    String name, {
    bool cover = false,
  }) async {
    if (name.trim().isEmpty) throw ArgumentError('模板名称不能为空。');
    final templates = await load();
    templates.add(template.copyWith(customName: name.trim(), isCover: cover));
    await _index.parent.create(recursive: true);
    final temporary = File('${_index.path}.tmp');
    await temporary.writeAsString(
      jsonEncode(templates.map((p) => p.toJson()).toList()),
      flush: true,
    );
    if (await _index.exists()) await _index.delete();
    await temporary.rename(_index.path);
  }

  /// 收集图像或 PDF 首页为自定义模板，记录真实尺寸和封面用途，原文件保留。
  Future<PaperTemplate> importFile(File source, {bool cover = false}) async {
    File image = source;
    Directory? temporaryImport;
    try {
      if (source.path.toLowerCase().endsWith('.pdf')) {
        final repo = NoteRepository(
          dataRoot: '$dataRoot/templates/import-work',
        );
        final doc = await repo.importPdf(source, onProgress: (_) {});
        temporaryImport = Directory(doc.directory);
        image = await repo.ensurePageImage(doc, doc.pages.first);
      }
      final decoded = raster.decodeImage(await image.readAsBytes());
      if (decoded == null) throw const FormatException('无法读取模板图片。');
      final output = File(
        '$dataRoot/templates/assets/${DateTime.now().microsecondsSinceEpoch}.png',
      );
      await output.parent.create(recursive: true);
      await output.writeAsBytes(raster.encodePng(decoded));
      final name = source.path
          .replaceAll('\\', '/')
          .split('/')
          .last
          .replaceFirst(RegExp(r'\.[^.]+$'), '');
      final template = PaperTemplate(
        backgroundAsset: output.path,
        customName: name,
        customWidth: decoded.width,
        customHeight: decoded.height,
        isCover: cover,
      );
      await save(template, name, cover: cover);
      return template;
    } finally {
      if (temporaryImport != null && await temporaryImport.exists()) {
        await temporaryImport.delete(recursive: true);
      }
    }
  }
}
