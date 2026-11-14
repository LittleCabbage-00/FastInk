import 'dart:convert';
import 'dart:collection';
import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:filepicker_windows/filepicker_windows.dart';
import 'package:image/image.dart' as raster;

import '../models/models.dart';
import '../models/pdf_outline.dart';
import '../importing/pdf_outline_parser.dart';
import '../importing/onenote_page_parser.dart';
import '../platform/onenote_reader.dart';
import '../models/paper_template.dart';
import 'library_repository.dart';
import '../core/app_localizations.dart';

export '../models/paper_template.dart';

part 'note_document_operations.dart';
part 'note_page_operations.dart';
part 'note_pdf_operations.dart';
part 'note_ink_operations.dart';
part 'note_onenote_operations.dart';

/// 文稿内容仓库，负责页面、笔迹、PDF 懒渲染及其磁盘缓存。
///
/// 仓库只持有路径、任务和轻量索引，不长期持有解码后的 ui.Image；
/// 位图生命周期由页面加载器管理，超长 PDF 因此不会整本占用内存。
class NoteRepository {
  /// 绑定资料库、PDF 缓存数量与渲染 DPI，所有内容路径与运行时仓库必须使用同一根目录。
  NoteRepository({
    String? dataRoot,
    int maximumCachedPdfPages = 160,
    int pdfImportDpi = 132,
  }) : dataRoot = dataRoot ?? LibraryRepository.defaultRoot,
       _maximumCachedPdfPages = maximumCachedPdfPages.clamp(40, 320),
       _pdfImportDpi = pdfImportDpi.clamp(96, 180);

  /// dataRoot：当前资料库根目录，文稿、笔迹和本地资源都相对该目录定位。
  final String dataRoot;

  // Scrble 旧目录按内部规则识别；导入时保留标题和数字页序。
  /// _scrblePattern：识别 Scrble 页面文件名中笔记名称与页号的规则，用于兼容旧页面序列。
  final RegExp _scrblePattern = RegExp(
    r'^(.*) #(\d+)\.(png|jpe?g|webp)$',
    caseSensitive: false,
  );

  /// _imagePattern：识别可作为页面源的图像文件扩展名规则。
  final RegExp _imagePattern = RegExp(
    r'\.(png|jpe?g|webp)$',
    caseSensitive: false,
  );

  // 每页保存串行执行，防止旧快照晚于新快照写入。
  /// _saveQueues：按页面目标路径串行安排笔迹保存，避免异步快照倒序覆盖。
  final Map<String, Future<void>> _saveQueues = <String, Future<void>>{};

  // 同一路径共用渲染 Future，缩略图、画布和导出不重复转换。
  /// _pageRenderQueues：按页面路径合并正在生成的 PDF 位图任务，同页只启动一次渲染。
  final Map<String, Future<File>> _pageRenderQueues = <String, Future<File>>{};

  /// _pdfMetadataCache：缓存 PDF 源文件位置与渲染 DPI 的在途查询，减少反复读取清单。
  final Map<String, Future<({File source, int dpi})>> _pdfMetadataCache =
      <String, Future<({File source, int dpi})>>{};
  // 插入顺序作为 LRU 队列；这里只缓存路径，不持有页面位图。
  /// _pdfPageLru：已渲染 PDF 页面文件的最近使用顺序，淘汰时排除受保护页面。
  final LinkedHashMap<String, Object?> _pdfPageLru =
      LinkedHashMap<String, Object?>();

  /// _pdfProtectedPages：按文稿保存当前及必要邻页的保护路径，磁盘缓存清理不能删除仍在使用的页。
  final Map<String, Set<String>> _pdfProtectedPages = <String, Set<String>>{};

  /// _prefetchChain：PDF 邻页预取串行任务链，避免多个外部渲染进程并发争抢 CPU。
  Future<void> _prefetchChain = Future<void>.value();

  /// _prefetchGeneration：预取任务代次，新的阅读方向/文稿使旧排队任务失效。
  int _prefetchGeneration = 0;

  /// _maximumCachedPdfPages：当前 PDF 缓存页面数量预算，可随内存策略调整。
  int _maximumCachedPdfPages;

  /// _pdfImportDpi：PDF 生成页面位图时使用的当前 DPI 配置。
  int _pdfImportDpi;

  /// pdfImportDpi 用于 PDF 页面栅格化，单位为 DPI。
  int get pdfImportDpi => _pdfImportDpi;

  /// 更新后续 PDF 页面解码的分辨率，单位为 DPI。
  set pdfImportDpi(int value) => _pdfImportDpi = value.clamp(96, 180);

  /// 读取或更新 PDF 缓存页数预算，调整后按保护窗口淘汰多余缓存。
  int get maximumCachedPdfPages => _maximumCachedPdfPages;

  /// 读取或更新 PDF 缓存页数预算，调整后按保护窗口淘汰多余缓存。
  set maximumCachedPdfPages(int value) {
    _maximumCachedPdfPages = value.clamp(40, 320);
    unawaited(_trimPdfPageCache());
  }

  /// 放弃可重建的后台状态；当前页文件和已保存笔迹不受影响。
  void releaseTransientCaches() {
    _prefetchGeneration++;
    _pdfMetadataCache.clear();
  }

  /// 读取最新文稿清单并兼容旧结构，缺失时使用传入的可用文稿描述。
  Future<NoteDocument> _loadDocumentManifest(NoteDocument fallback) async {
    final File manifest = File(_manifestPath(fallback.id));
    if (!await manifest.exists()) return fallback;
    try {
      final Map<String, Object?> json =
          jsonDecode(await manifest.readAsString())! as Map<String, Object?>;
      // 懒 PDF 的页面文件允许尚未生成；普通图片文稿则跳过已丢失的文件。
      final bool lazyPdf = await File(
        '${fallback.directory}/.fastink-pdf.json',
      ).exists();
      final List<NotePage> pages = <NotePage>[];
      for (final Object? value
          in (json['pages'] as List<Object?>?) ?? const <Object?>[]) {
        final Map<String, Object?> page = value! as Map<String, Object?>;
        final String path = page['path']! as String;
        if (!lazyPdf && !await File(path).exists()) continue;
        pages.add(
          NotePage(
            index: pages.length,
            originalPage: (page['originalPage'] as num).toInt(),
            path: path,
            name: page['name'] as String? ?? _fileName(path),
          ),
        );
      }
      if (pages.isEmpty) return fallback;
      return NoteDocument(
        id: fallback.id,
        title: json['title'] as String? ?? fallback.title,
        directory: json['directory'] as String? ?? fallback.directory,
        pages: pages,
        initialIndex: fallback.initialIndex.clamp(0, pages.length - 1),
      );
    } catch (_) {
      return fallback;
    }
  }

  /// 按文稿合并 PDF 来源与 DPI 查询，返回原文件位置和渲染配置。
  Future<({File source, int dpi})> _pdfMetadata(NoteDocument document) =>
      _pdfMetadataCache.putIfAbsent(document.id, () async {
        // 同一文稿的元数据只读取一次，缩略图、正文和导出共享结果。
        final Map<String, Object?> metadata =
            jsonDecode(
                  await File(
                    '${document.directory}/.fastink-pdf.json',
                  ).readAsString(),
                )!
                as Map<String, Object?>;
        return (
          source: File(metadata['source']! as String),
          dpi: (metadata['dpi'] as num?)?.toInt() ?? 132,
        );
      });

  /// 把已使用的缓存页移动到 LRU 最近位置，读取顺序决定后续淘汰。
  void _touchPdfPage(String path) {
    // LinkedHashMap 的插入顺序就是 LRU 次序；命中时移到队尾。
    _pdfPageLru.remove(path);
    _pdfPageLru[path] = null;
    if (_pdfPageLru.length > _maximumCachedPdfPages) {
      unawaited(_trimPdfPageCache());
    }
  }

  /// 按当前页数预算清理最旧 PDF 缓存文件，跳过当前受保护页面，不删除原 PDF。
  Future<void> _trimPdfPageCache() async {
    // 当前页、邻页和正在生成的页面受保护；淘汰时越过它们继续找旧页。
    final Set<String> protected = _pdfProtectedPages.values
        .expand((paths) => paths)
        .toSet();
    int attempts = _pdfPageLru.length;
    while (_pdfPageLru.length > _maximumCachedPdfPages && attempts-- > 0) {
      final String oldest = _pdfPageLru.keys.first;
      _pdfPageLru.remove(oldest);
      if (protected.contains(oldest) || _pageRenderQueues.containsKey(oldest)) {
        _pdfPageLru[oldest] = null;
        continue;
      }
      final File cached = File(oldest);
      if (await cached.exists()) await cached.delete();
    }
  }

  /// 把纸张模板绘制为页面文件，临时图像在写入结束后释放。
  Future<void> _writePaperPage(File destination, PaperTemplate template) async {
    if (template.backgroundAsset != null) {
      await destination.parent.create(recursive: true);
      final temporary = File('${destination.path}.tmp');
      await File(template.backgroundAsset!).copy(temporary.path);
      if (await destination.exists()) await destination.delete();
      await temporary.rename(destination.path);
      await File(
        '${destination.path}.paper.json',
      ).writeAsString(jsonEncode(template.toJson()), flush: true);
      return;
    }
    final ui.Size dimensions = template.pixelSize;
    final int width = dimensions.width.toInt();
    final int height = dimensions.height.toInt();
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final ui.Canvas canvas = ui.Canvas(recorder);
    paintPaperTemplate(canvas, dimensions, template);
    // Picture 在 GPU/Skia 中绘制模板，再一次性编码 PNG，避免逐像素循环。
    final ui.Picture picture = recorder.endRecording();
    final ui.Image image;
    try {
      image = await picture.toImage(width, height);
    } finally {
      picture.dispose();
    }
    try {
      final ByteData? bytes = await image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      if (bytes == null) {
        throw StateError(tr('无法生成空白页面。', 'Could not create a blank page.'));
      }
      await destination.parent.create(recursive: true);
      final File temporary = File('${destination.path}.tmp');
      await temporary.writeAsBytes(Uint8List.view(bytes.buffer), flush: true);
      if (await destination.exists()) await destination.delete();
      await temporary.rename(destination.path);
      await File(
        '${destination.path}.paper.json',
      ).writeAsString(jsonEncode(template.toJson()), flush: true);
    } finally {
      image.dispose();
    }
  }

  /// 读取页面保存的模板配置，没有合法模板信息时返回 null。
  Future<PaperTemplate?> loadPaperTemplate(NotePage page) async {
    try {
      final File file = File('${page.path}.paper.json');
      if (!await file.exists()) return null;
      return PaperTemplate.fromJson(
        jsonDecode(await file.readAsString()) as Map<String, Object?>,
      );
    } on FileSystemException {
      return null;
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  /// 为新导入文稿创建不会覆盖已有目录的独立存储位置。
  Future<Directory> _newImportDirectory(String title) async {
    // 每次导入创建独立目录，重名文件不会覆盖已有文稿。
    final String stamp = DateTime.now().microsecondsSinceEpoch.toRadixString(
      36,
    );
    final Directory directory = Directory(
      '$dataRoot/imports/${_safeName(title)}_$stamp',
    );
    await directory.create(recursive: true);
    return directory;
  }

  /// 从受支持的运行时目录定位 PDF 工具，缺失时明确报错，不依赖任意工作目录。
  String _findPdfTool(String name) {
    final String appBundled =
        '${File(Platform.resolvedExecutable).parent.path}/tools/poppler/$name';
    // 开发构建可能从 Flutter 缓存启动，因此也检查项目旁的工具目录。
    final String projectBundled =
        '${Directory.current.path}/windows/tools/poppler/$name';
    for (final String candidate in <String>[appBundled, projectBundled]) {
      if (File(candidate).existsSync()) return candidate;
    }
    final String targetDirectory =
        '${File(Platform.resolvedExecutable).parent.path}/tools/poppler';
    throw StateError(
      tr(
        '缺少 PDF 组件：$name。请从 '
            'https://github.com/oschwartz10612/poppler-windows/releases/latest '
            '下载 Windows 版 Poppler，解压到“$targetDirectory”后重试。',
        'Missing PDF component: $name. Download Poppler for Windows from '
            'https://github.com/oschwartz10612/poppler-windows/releases/latest, '
            'extract it to “$targetDirectory”, and try again.',
      ),
    );
  }

  /// 将用户标题转换为合法本地文件名片段，过滤不可用于路径的字符。
  String _safeName(String value) {
    final String sanitized = value
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
        .replaceAll(RegExp(r'\s+$'), '');
    if (sanitized.isEmpty) return tr('无标题笔记');
    return sanitized.length > 80 ? sanitized.substring(0, 80) : sanitized;
  }

  /// 取文件名主体，不把父目录中的点误当成文件扩展名。
  String _withoutExtension(String value) =>
      value.replaceFirst(RegExp(r'\.[^.]+$'), '');

  /// 提取文件名扩展名并按解析流程规范化。
  String _extension(String value) {
    final RegExpMatch? match = RegExp(r'(\.[^.]+)$').firstMatch(value);
    return match?.group(1)?.toLowerCase() ?? '.png';
  }

  /// 将时间转换为适合目录命名的短字符串，避免冒号等非法文件名字符。
  String _shortDateTime(DateTime value) =>
      '${value.month.toString().padLeft(2, '0')}${value.day.toString().padLeft(2, '0')}_'
      '${value.hour.toString().padLeft(2, '0')}${value.minute.toString().padLeft(2, '0')}';

  /// 先写完整临时笔迹文件，再维护上一个有效版本并替换目标，失败不能把半份 JSON 当成保存成功。
  Future<void> _writeAtomically(String destination, PageInk ink) async {
    final String contents = await Isolate.run<String>(
      () => jsonEncode(ink.toJson()),
    );
    final File target = File(destination);
    final File temporary = File(
      '$destination.${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    final File previous = File('$destination.previous');
    await target.parent.create(recursive: true);
    await temporary.writeAsString(contents, flush: true);

    if (await previous.exists()) await previous.delete();
    if (await target.exists()) await target.rename(previous.path);
    try {
      await temporary.rename(target.path);
      if (await previous.exists()) await previous.delete();
    } catch (_) {
      if (!await target.exists() && await previous.exists()) {
        await previous.rename(target.path);
      }
      rethrow;
    }
  }

  /// 按文稿身份和稳定 originalPage 构造页面笔迹文件位置，不使用会重排的显示索引。
  String _inkPath(NoteDocument document, NotePage page) {
    return '$dataRoot/documents/${document.id}/pages/'
        '${page.originalPage.toString().padLeft(6, '0')}.json';
  }

  /// 构造指定文稿存储目录中的清单路径。
  String _manifestPath(String documentId) =>
      '$dataRoot/documents/$documentId/manifest.json';

  /// 比较规范化的本地路径是否表示相同文件位置。
  bool _samePath(String a, String b) =>
      a.toLowerCase().replaceAll('\\', '/') ==
      b.toLowerCase().replaceAll('\\', '/');

  /// 统一绝对路径、分隔符和比较大小写规则，供安全范围与身份判断。
  String _normalizedAbsolute(String path) => File(path).absolute.path
      .replaceAll('\\', '/')
      .replaceAll(RegExp(r'/+$'), '')
      .toLowerCase();

  /// 确认目标严格位于父目录内，不允许把父目录本身或相似前缀当作安全子目录。
  bool _isStrictChild(String path, String parent) {
    final String normalized = _normalizedAbsolute(path);
    return normalized.startsWith('$parent/') && normalized != parent;
  }

  /// 同时兼容斜杠和反斜杠，获取最后一个文件名片段。
  String _fileName(String path) => path.replaceAll('\\', '/').split('/').last;

  /// 按文件名中的数字序列自然排序，避免第 10 页排在第 2 页之前。
  int _naturalCompare(String a, String b) {
    final RegExp chunks = RegExp(r'\d+|\D+');
    final List<String> aa = chunks
        .allMatches(a)
        .map((m) => m.group(0)!)
        .toList();
    final List<String> bb = chunks
        .allMatches(b)
        .map((m) => m.group(0)!)
        .toList();
    for (int i = 0; i < aa.length && i < bb.length; i++) {
      final int? an = int.tryParse(aa[i]);
      final int? bn = int.tryParse(bb[i]);
      final int result = an != null && bn != null
          ? an.compareTo(bn)
          : aa[i].toLowerCase().compareTo(bb[i].toLowerCase());
      if (result != 0) return result;
    }
    return aa.length.compareTo(bb.length);
  }

  /// 由稳定输入生成文稿标识，同一路径重开时避免重复登记新文稿。
  String _stableId(String input) {
    const int offset = 0xcbf29ce484222325;
    const int prime = 0x100000001b3;
    int hash = offset;
    for (final int byte in utf8.encode(input.toLowerCase())) {
      hash ^= byte;
      hash = (hash * prime) & 0x7fffffffffffffff;
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }
}

class _IndexedFile {
  /// 用编号和路径绑定索引中的底图或笔迹文件。
  /// path：对象对应的本地文件路径；具体是否已存在由读取/创建入口校验。
  /// name：用户可读名称；用于显示或文件名解析，不应替代稳定编号。
  /// pageNumber：从 1 开始的源页面编号，用于文件名序列解析，不等同于零基列表索引。
  const _IndexedFile({
    required this.path,
    required this.name,
    required this.pageNumber,
  });

  /// path：对象对应的本地文件路径；具体是否已存在由读取/创建入口校验。
  final String path;

  /// name：用户可读名称；用于显示或文件名解析，不应替代稳定编号。
  final String name;

  /// pageNumber：从 1 开始的源页面编号，用于文件名序列解析，不等同于零基列表索引。
  final int pageNumber;

  /// 复制文件索引项并替换解析出的页号，原路径和名称保持不变。
  _IndexedFile withPageNumber(int value) =>
      _IndexedFile(path: path, name: name, pageNumber: value);
}
