part of 'note_repository.dart';

extension NoteInkOperations on NoteRepository {
  /// 把外部图片复制进文稿自己的资源目录，并返回写入笔迹 JSON 的相对路径。
  /// 文稿迁移到新的资料库位置后，相对引用仍然有效。
  Future<String> importEmbeddedImage(NoteDocument document, File source) async {
    final String extension = _extension(source.path);
    if (!RegExp(
      r'^\.(png|jpe?g|webp)$',
      caseSensitive: false,
    ).hasMatch(extension)) {
      throw ArgumentError(
        tr('不支持的图片格式：$extension', 'Unsupported image format: $extension'),
      );
    }
    final Directory assets = Directory(
      '$dataRoot/documents/${document.id}/assets',
    );
    await assets.create(recursive: true);
    final String base = _safeName(_withoutExtension(_fileName(source.path)));
    final String stamp = DateTime.now().microsecondsSinceEpoch.toRadixString(
      36,
    );
    final String name = '${base}_$stamp$extension';
    await source.copy('${assets.path}/$name');
    return 'assets/$name';
  }

  /// 将持久化的相对资源名解析成当前资料库中的实际文件路径。
  String resolveEmbeddedImagePath(NoteDocument document, String asset) {
    if (File(asset).isAbsolute) return asset; // 兼容早期开发构建写入的绝对路径。
    final String normalized = asset.replaceAll('\\', '/');
    return '$dataRoot/documents/${document.id}/$normalized';
  }

  /// 读取一页笔迹。返回的 [PageInk] 一定已是当前版本：v2 及以前的像素
  /// 粗细在这里换算成归一化粗细，调用方拿到什么都能直接画。
  ///
  /// [legacyWidthReference] 是旧笔迹换算用的页面几何平均边长（`√(宽×高)`）。
  /// 无参可依的场合（测试、布局未建立）传
  /// [legacyInkWidthFallbackReference]。
  /// [background] 将翻页、缩略图或导出所需的 JSON 解析放到隔离线程，
  /// 不改变保存队列的等待顺序。
  Future<PageInk> loadPageInk(
    NoteDocument document,
    NotePage page, {
    double legacyWidthReference = legacyInkWidthFallbackReference,
    bool background = false,
  }) async {
    // 先等这笔迹键上在途的写入落地。保存是排队异步写的，"先读后写"的
    // 操作（旋转、复制页）如果读到旧内容，会把刚保存的笔迹覆盖掉。
    final Future<void>? pending =
        _saveQueues['${document.id}:${page.originalPage}'];
    if (pending != null) {
      try {
        await pending;
      } catch (_) {
        // 写失败也继续读：下面会走 .previous 备份或返回空页。
      }
    }
    final path = _inkPath(document, page);
    return background
        ? _readInkInBackground(path, legacyWidthReference)
        : _readSavedInk(path, legacyWidthReference);
  }

  /// [takeSnapshotOwnership] 仅用于已分离且由当前调用方独占的
  /// 快照；普通调用方仍会获得防御性副本。
  Future<void> savePageInk(
    NoteDocument document,
    NotePage page,
    PageInk ink, {
    bool takeSnapshotOwnership = false,
  }) {
    final String key = '${document.id}:${page.originalPage}';
    final Future<void> previous = _saveQueues[key] ?? Future<void>.value();
    final PageInk snapshot = PageInk(
      updatedAt: DateTime.now(),
      strokes: takeSnapshotOwnership
          ? ink.strokes
          : ink.strokes.map((stroke) => stroke.copy()).toList(),
    );
    late final Future<void> current;
    current = previous
        .catchError((Object _) {})
        .then((_) => _writeAtomically(_inkPath(document, page), snapshot))
        .whenComplete(() {
          if (identical(_saveQueues[key], current)) _saveQueues.remove(key);
        });
    _saveQueues[key] = current;
    return current;
  }
}

/// 只发送路径与旧格式换算基准；不捕获仓库实例或尚未完成的保存 Future。
Future<PageInk> _readInkInBackground(
  String path,
  double legacyWidthReference,
) => Isolate.run(() => _readSavedInk(path, legacyWidthReference));

/// 读取页面笔迹 JSON 并按旧宽度基准兼容转换；主文件不可用时尝试前一版本，不能用损坏数据覆盖有效版本。
Future<PageInk> _readSavedInk(String path, double legacyWidthReference) async {
  final File primary = File(path);
  final File backup = File('${primary.path}.previous');
  for (final File candidate in <File>[primary, backup]) {
    try {
      if (!await candidate.exists()) continue;
      final Object? decoded = jsonDecode(await candidate.readAsString());
      return PageInk.fromJson(
        decoded! as Map<String, Object?>,
      ).withNormalizedWidths(legacyWidthReference);
    } on FormatException {
      continue;
    }
  }
  return const PageInk(strokes: <InkStroke>[]);
}
