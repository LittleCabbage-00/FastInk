import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../core/runtime_environment.dart';

import '../models/models.dart';
import '../models/pdf_outline.dart';

enum LibraryScope { notes, markdown, legacy }

/// 首页资料库中的轻量文稿记录，不包含页面位图和笔迹正文。
class LibraryDocument {
  /// 记录文稿在资料库中的身份、封面、归属和废纸篓状态。
  /// id：对象的稳定身份编号，用于索引、关联和缓存键，不是显示标题。
  /// 保存和显示使用的完整标题。
  /// sourcePath：资料库记录定位源文稿的路径，不是临时预览缓存路径。
  /// coverPath：资料库卡片展示首页/封面的底图路径，不改变正文页序。
  /// pageCount：文稿或当前任务的页面数量，不是最大页索引。
  /// importedAt：文稿导入或创建时刻，用于记录来源时间。
  /// lastOpenedAt：最近打开文稿时刻，资料库排序可据此更新。
  /// folderId：所属资料库文件夹的稳定编号，null 表示根目录。
  /// favorite：是否在收藏列表中展示，不改变文稿所在文件夹。
  /// trashed：是否移入废纸篓；该状态不等于磁盘文件已永久删除。
  /// bookmarkedPages：带书签页面的零基索引集合，页序变化后需同步映射。
  /// pageTitles：零基页面索引到手工章节标题的映射，独立于 PDF 原生目录。
  /// lastPageIndex：最近阅读位置的零基页面索引，打开时约束到当前页数。
  /// pdfOutline：从 PDF 提取的层级目录节点，手工标题不写入该列表。
  /// pdfOutlineVersion：目录解析版本标记，解析能力变化时可据此要求重新读取。
  const LibraryDocument({
    required this.id,
    required this.title,
    required this.sourcePath,
    required this.coverPath,
    required this.pageCount,
    required this.importedAt,
    required this.lastOpenedAt,
    this.folderId,
    this.favorite = false,
    this.trashed = false,
    this.bookmarkedPages = const <int>[],
    this.pageTitles = const <int, String>{},
    this.lastPageIndex = 0,
    this.pdfOutline = const [],
    this.pdfOutlineVersion = 0,
  });

  /// id：对象的稳定身份编号，用于索引、关联和缓存键，不是显示标题。
  final String id;

  /// 保存和显示使用的完整标题。
  final String title;

  /// sourcePath：资料库记录定位源文稿的路径，不是临时预览缓存路径。
  final String sourcePath;

  /// coverPath：资料库卡片展示首页/封面的底图路径，不改变正文页序。
  final String coverPath;

  /// pageCount：文稿或当前任务的页面数量，不是最大页索引。
  final int pageCount;

  /// importedAt：文稿导入或创建时刻，用于记录来源时间。
  final DateTime importedAt;

  /// lastOpenedAt：最近打开文稿时刻，资料库排序可据此更新。
  final DateTime lastOpenedAt;

  /// folderId：所属资料库文件夹的稳定编号，null 表示根目录。
  final String? folderId;

  /// favorite：是否在收藏列表中展示，不改变文稿所在文件夹。
  final bool favorite;

  /// trashed：是否移入废纸篓；该状态不等于磁盘文件已永久删除。
  final bool trashed;

  /// bookmarkedPages：带书签页面的零基索引集合，页序变化后需同步映射。
  final List<int> bookmarkedPages;

  /// pageTitles：零基页面索引到手工章节标题的映射，独立于 PDF 原生目录。
  final Map<int, String> pageTitles;

  /// lastPageIndex：最近阅读位置的零基页面索引，打开时约束到当前页数。
  final int lastPageIndex;

  /// pdfOutline：从 PDF 提取的层级目录节点，手工标题不写入该列表。
  final List<PdfOutlineEntry> pdfOutline;

  /// pdfOutlineVersion：目录解析版本标记，解析能力变化时可据此要求重新读取。
  final int pdfOutlineVersion;

  /// scope：文件夹所属内容域，手写与 Markdown 的目录不能混用。
  LibraryScope get scope => sourcePath.toLowerCase().endsWith('.md')
      ? LibraryScope.markdown
      : LibraryScope.notes;

  /// 复制当前资料库文稿或文件夹记录，仅覆盖指定元数据；clearFolder 等显式标志处理可空字段清除。
  LibraryDocument copyWith({
    String? title,
    String? sourcePath,
    String? coverPath,
    int? pageCount,
    DateTime? importedAt,
    DateTime? lastOpenedAt,
    String? folderId,
    bool clearFolder = false,
    bool? favorite,
    bool? trashed,
    List<int>? bookmarkedPages,
    Map<int, String>? pageTitles,
    int? lastPageIndex,
    List<PdfOutlineEntry>? pdfOutline,
    int? pdfOutlineVersion,
  }) => LibraryDocument(
    id: id,
    title: title ?? this.title,
    sourcePath: sourcePath ?? this.sourcePath,
    coverPath: coverPath ?? this.coverPath,
    pageCount: pageCount ?? this.pageCount,
    importedAt: importedAt ?? this.importedAt,
    lastOpenedAt: lastOpenedAt ?? this.lastOpenedAt,
    folderId: clearFolder ? null : (folderId ?? this.folderId),
    favorite: favorite ?? this.favorite,
    trashed: trashed ?? this.trashed,
    bookmarkedPages: bookmarkedPages ?? this.bookmarkedPages,
    pageTitles: pageTitles ?? this.pageTitles,
    lastPageIndex: lastPageIndex ?? this.lastPageIndex,
    pdfOutline: pdfOutline ?? this.pdfOutline,
    pdfOutlineVersion: pdfOutlineVersion ?? this.pdfOutlineVersion,
  );

  /// 把轻量索引记录编码为 JSON，时间、书签和目录等按稳定字段保存，不包含解码位图。
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'title': title,
    'sourcePath': sourcePath,
    'coverPath': coverPath,
    'pageCount': pageCount,
    'importedAt': importedAt.toUtc().toIso8601String(),
    'lastOpenedAt': lastOpenedAt.toUtc().toIso8601String(),
    'folderId': folderId,
    'favorite': favorite,
    'trashed': trashed,
    'bookmarkedPages': bookmarkedPages,
    'pageTitles': pageTitles.map(
      (int key, String value) => MapEntry<String, String>('$key', value),
    ),
    'lastPageIndex': lastPageIndex,
    'pdfOutline': pdfOutline.map((entry) => entry.toJson()).toList(),
    'pdfOutlineVersion': pdfOutlineVersion,
  };

  /// 解码文稿索引并对缺失字段使用兼容默认值，保留稳定身份与阅读位置。
  factory LibraryDocument.fromJson(Map<String, Object?> json) {
    final DateTime now = DateTime.now();
    return LibraryDocument(
      id: json['id']! as String,
      title: json['title']! as String,
      sourcePath: json['sourcePath']! as String,
      coverPath: json['coverPath'] as String? ?? json['sourcePath']! as String,
      pageCount: (json['pageCount'] as num?)?.toInt() ?? 1,
      importedAt: DateTime.tryParse(json['importedAt'] as String? ?? '') ?? now,
      lastOpenedAt:
          DateTime.tryParse(json['lastOpenedAt'] as String? ?? '') ?? now,
      folderId: json['folderId'] as String?,
      favorite: json['favorite'] as bool? ?? false,
      trashed: json['trashed'] as bool? ?? false,
      bookmarkedPages:
          ((json['bookmarkedPages'] as List<Object?>?) ?? const <Object?>[])
              .map((Object? value) => (value! as num).toInt())
              .toList(),
      pageTitles:
          ((json['pageTitles'] as Map<String, Object?>?) ??
                  const <String, Object?>{})
              .map(
                (String key, Object? value) =>
                    MapEntry<int, String>(int.parse(key), value! as String),
              ),
      lastPageIndex: (json['lastPageIndex'] as num?)?.toInt() ?? 0,
      pdfOutline: (json['pdfOutline'] as List<Object?>? ?? [])
          .map(
            (entry) => PdfOutlineEntry.fromJson(entry as Map<String, Object?>),
          )
          .toList(),
      pdfOutlineVersion: (json['pdfOutlineVersion'] as num?)?.toInt() ?? 0,
    );
  }
}

/// 资料库文件夹。parentId 为空表示位于根目录。
class LibraryFolder {
  /// 记录文件夹身份、所属类别和父文件夹。
  /// id：对象的稳定身份编号，用于索引、关联和缓存键，不是显示标题。
  /// name：用户可读名称；用于显示或文件名解析，不应替代稳定编号。
  /// createdAt：该文件夹或记录的创建时刻，不随显示排序变化。
  /// colorValue：文件夹显示色，保存为 32 位 ARGB。
  /// trashed：是否移入废纸篓；该状态不等于磁盘文件已永久删除。
  /// parentId：父文件夹的稳定编号，null 表示顶层；路径遍历需防循环引用。
  /// scope：文件夹所属内容域，手写与 Markdown 的目录不能混用。
  const LibraryFolder({
    required this.id,
    required this.name,
    required this.createdAt,
    this.colorValue = 0xff6d7cff,
    this.trashed = false,
    this.parentId,
    this.scope = LibraryScope.notes,
  });

  /// id：对象的稳定身份编号，用于索引、关联和缓存键，不是显示标题。
  final String id;

  /// name：用户可读名称；用于显示或文件名解析，不应替代稳定编号。
  final String name;

  /// createdAt：该文件夹或记录的创建时刻，不随显示排序变化。
  final DateTime createdAt;

  /// colorValue：文件夹显示色，保存为 32 位 ARGB。
  final int colorValue;

  /// trashed：是否移入废纸篓；该状态不等于磁盘文件已永久删除。
  final bool trashed;

  /// parentId：父文件夹的稳定编号，null 表示顶层；路径遍历需防循环引用。
  final String? parentId;

  /// scope：文件夹所属内容域，手写与 Markdown 的目录不能混用。
  final LibraryScope scope;

  /// 复制当前资料库文稿或文件夹记录，仅覆盖指定元数据；clearFolder 等显式标志处理可空字段清除。
  LibraryFolder copyWith({
    String? name,
    int? colorValue,
    bool? trashed,
    String? parentId,
    bool clearParent = false,
    LibraryScope? scope,
  }) => LibraryFolder(
    id: id,
    name: name ?? this.name,
    createdAt: createdAt,
    colorValue: colorValue ?? this.colorValue,
    trashed: trashed ?? this.trashed,
    parentId: clearParent ? null : (parentId ?? this.parentId),
    scope: scope ?? this.scope,
  );

  /// 把轻量索引记录编码为 JSON，时间、书签和目录等按稳定字段保存，不包含解码位图。
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'colorValue': colorValue,
    'trashed': trashed,
    'parentId': parentId,
    'scope': scope.name,
  };

  /// 解码文件夹身份、父关系、颜色和内容域，兼容旧索引的缺省范围。
  factory LibraryFolder.fromJson(Map<String, Object?> json) => LibraryFolder(
    id: json['id']! as String,
    name: json['name']! as String,
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
    colorValue: (json['colorValue'] as num?)?.toInt() ?? 0xff6d7cff,
    trashed: json['trashed'] as bool? ?? false,
    parentId: json['parentId'] as String?,
    scope:
        LibraryScope.values
            .where((value) => value.name == json['scope'])
            .firstOrNull ??
        LibraryScope.legacy,
  );
}

/// 首页一次性持有的索引快照；修改后整体写回 library.json。
class LibraryState {
  /// 保存资料库的文稿与文件夹索引。
  /// documents：资料库或导入结果中的文稿记录集合，不直接包含全部解码图像。
  /// folders：资料库文件夹记录，父子关系用稳定编号关联。
  const LibraryState({
    this.documents = const <LibraryDocument>[],
    this.folders = const <LibraryFolder>[],
  });

  /// documents：资料库或导入结果中的文稿记录集合，不直接包含全部解码图像。
  final List<LibraryDocument> documents;

  /// folders：资料库文件夹记录，父子关系用稳定编号关联。
  final List<LibraryFolder> folders;
}

/// 读写资料库索引，不负责加载实际页面内容。
class LibraryRepository {
  /// 绑定指定资料库根目录，未指定时按运行环境选择默认位置。
  LibraryRepository({String? root}) : root = root ?? defaultRoot;

  /// root：所属仓库或缓存的本地根目录，所有相对资源定位以此为基准。
  final String root;

  /// _pendingSaves：按索引文件路径合并/串行的在途保存，防止旧索引覆盖新记录。
  static final _pendingSaves = <String, Future<void>>{};

  /// _writeSequence：同进程临时写入文件的递增编号，降低并发临时文件重名风险。
  static int _writeSequence = 0;

  /// 生成索引写入队列使用的规范化路径键，指向同一文件的不同拼写必须共用队列。
  String get _queueKey =>
      Directory(root).absolute.path.replaceAll('\\', '/').toLowerCase();

  /// 按便携/用户环境解析默认资料库根目录，不使用当前 shell 工作目录。
  static String get defaultRoot {
    final String? configured = Platform.environment['FASTINK_DATA'];
    if (configured != null && configured.trim().isNotEmpty) return configured;
    // Portable 包默认把资料库放在自身目录，整份文件夹可以直接迁移。
    if (RuntimeEnvironment.isPortable) {
      return RuntimeEnvironment.portableDataDirectory;
    }
    if (Directory(r'D:\ComputerProgram\path').existsSync()) {
      return r'D:\ComputerProgram\path\FastInk\data';
    }
    final String local =
        Platform.environment['LOCALAPPDATA'] ?? Directory.systemTemp.path;
    return '$local/FastInk';
  }

  /// 返回当前资料库的 library.json 索引位置。
  File get _indexFile => File('$root/library.json');

  /// 读取轻量索引并执行兼容解码/目录域迁移，缺失索引时返回可用空状态。
  Future<LibraryState> load() async {
    await _pendingSaves[_queueKey];
    LibraryState state;
    try {
      if (!await _indexFile.exists()) return const LibraryState();
      final Object? decoded = jsonDecode(await _indexFile.readAsString());
      final Map<String, Object?> json = decoded! as Map<String, Object?>;
      state = LibraryState(
        documents: ((json['documents'] as List<Object?>?) ?? const [])
            .map(
              (Object? item) =>
                  LibraryDocument.fromJson(item! as Map<String, Object?>),
            )
            .toList(),
        folders: ((json['folders'] as List<Object?>?) ?? const [])
            .map(
              (Object? item) =>
                  LibraryFolder.fromJson(item! as Map<String, Object?>),
            )
            .toList(),
      );
    } catch (_) {
      // 索引损坏不应阻止应用启动；界面以空资料库打开，原文件仍保留在磁盘。
      return const LibraryState();
    }
    final migrated = separateLibraryFolders(state);
    if (!identical(migrated, state)) {
      final backup = File('$root/library.before-folder-split.json');
      if (!await backup.exists()) await _indexFile.copy(backup.path);
      await save(migrated);
    }
    return migrated;
  }

  /// 将索引快照按目标路径串行入队，防止并发更新产生倒序覆盖。
  Future<void> save(LibraryState state) {
    final key = _queueKey;
    final write =
        _pendingSaves[key]?.then((_) => _write(state)) ?? _write(state);
    // 向调用方报告写入失败，但不影响后续保存任务。
    final settled = write.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _pendingSaves[key] = settled;
    unawaited(
      settled.then((_) {
        if (identical(_pendingSaves[key], settled)) _pendingSaves.remove(key);
      }),
    );
    return write;
  }

  /// 将完整索引写入独立临时文件后替换目标，临时名带进程序列避免冲突。
  Future<void> _write(LibraryState state) async {
    await Directory(root).create(recursive: true);
    // 临时文件完整落盘后再替换正式索引，避免异常退出破坏现有资料库。
    final File temporary = File(
      '${_indexFile.path}.$pid.${_writeSequence++}.tmp',
    );
    try {
      await temporary.writeAsString(
        jsonEncode(<String, Object?>{
          'version': 2,
          'documents': state.documents.map((item) => item.toJson()).toList(),
          'folders': state.folders.map((item) => item.toJson()).toList(),
        }),
        flush: true,
      );
      await temporary.rename(_indexFile.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  /// 从已建立的文稿元数据生成或更新资料库记录，携带目录归属而不复制页面内容。
  LibraryDocument fromDocument(NoteDocument document, {String? folderId}) {
    final DateTime now = DateTime.now();
    return LibraryDocument(
      id: document.id,
      title: document.title,
      sourcePath: document.pages.first.path,
      coverPath: document.pages.first.path,
      pageCount: document.pages.length,
      importedAt: now,
      lastOpenedAt: now,
      folderId: folderId,
    );
  }

  /// 创建具备新稳定编号、名称、时间、父目录和内容域的文件夹记录，保存由调用方执行。
  LibraryFolder newFolder(
    String name, {
    String? parentId,
    LibraryScope scope = LibraryScope.notes,
  }) => LibraryFolder(
    id: DateTime.now().microsecondsSinceEpoch.toRadixString(36),
    name: name,
    createdAt: DateTime.now(),
    parentId: parentId,
    scope: scope,
  );
}

/// 旧版共用目录树只拆分一次，保留嵌套结构与全部文稿元数据。
/// 旧版空文件夹同时保留在两个分类中，避免迁移丢失内容。
LibraryState separateLibraryFolders(LibraryState state) {
  final legacy = state.folders
      .where((f) => f.scope == LibraryScope.legacy)
      .toList();
  if (legacy.isEmpty) return state;
  final ids = state.folders.map((f) => f.id).toSet();
  final mdIds = <String, String>{};
  for (final folder in legacy) {
    var id = '${folder.id}-markdown';
    while (!ids.add(id)) {
      id = '$id-2';
    }
    mdIds[folder.id] = id;
  }
  final folders = <LibraryFolder>[
    for (final folder in state.folders)
      folder.scope == LibraryScope.legacy
          ? folder.copyWith(scope: LibraryScope.notes)
          : folder,
    for (final folder in legacy)
      LibraryFolder(
        id: mdIds[folder.id]!,
        name: folder.name,
        createdAt: folder.createdAt,
        colorValue: folder.colorValue,
        trashed: folder.trashed,
        scope: LibraryScope.markdown,
        parentId: mdIds[folder.parentId],
      ),
  ];
  return LibraryState(
    folders: folders,
    documents: [
      for (final doc in state.documents)
        doc.scope == LibraryScope.markdown && mdIds.containsKey(doc.folderId)
            ? doc.copyWith(folderId: mdIds[doc.folderId])
            : doc,
    ],
  );
}
