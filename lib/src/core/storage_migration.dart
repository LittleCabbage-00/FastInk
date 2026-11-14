part of 'settings_repository.dart';

class StorageMigration {
  /// 把资料库复制到新根目录并报告进度；迁移后的内部路径需要重写，不能直接跨目录复用旧绝对路径。
  static Future<void> copyLibrary({
    required String sourceRoot,
    required String destinationRoot,
  }) async {
    final Directory source = Directory(sourceRoot);
    final Directory destination = Directory(destinationRoot);
    if (_samePath(source.path, destination.path)) return;
    if (_isChild(destination.path, source.path) ||
        _isChild(source.path, destination.path)) {
      throw FileSystemException(
        tr(
          '新旧资料库位置不能互相包含',
          'The old and new library locations cannot contain one another',
        ),
      );
    }
    if (!await source.exists()) {
      await destination.create(recursive: true);
      return;
    }
    if (await destination.exists() && !(await destination.list().isEmpty)) {
      throw FileSystemException(
        tr(
          '目标 FastInkData 文件夹不是空的',
          'The destination FastInkData folder is not empty',
        ),
        destination.path,
      );
    }
    await destination.create(recursive: true);
    try {
      await for (final FileSystemEntity entity in source.list(
        recursive: true,
        followLinks: false,
      )) {
        final String relative = entity.path.substring(source.path.length + 1);
        final String target = '${destination.path}/$relative';
        if (entity is Directory) {
          await Directory(target).create(recursive: true);
        } else if (entity is File) {
          await File(target).parent.create(recursive: true);
          await entity.copy(target);
        }
      }
      await _rewriteJsonPaths(destination, source.path, destination.path);
      final File sourceIndex = File('${source.path}/library.json');
      final File targetIndex = File('${destination.path}/library.json');
      if (await sourceIndex.exists() && !await targetIndex.exists()) {
        throw FormatException(
          tr('资料库索引迁移不完整', 'The migrated library index is incomplete'),
        );
      }
      if (await targetIndex.exists()) {
        jsonDecode(await targetIndex.readAsString());
      }
    } catch (_) {
      if (await destination.exists()) await destination.delete(recursive: true);
      rethrow;
    }
  }

  /// 载入指定 JSON 并把旧根目录引用重写为新根目录，保持其他字段不变。
  static Future<void> _rewriteJsonPaths(
    Directory root,
    String oldRoot,
    String newRoot,
  ) async {
    await for (final FileSystemEntity entity in root.list(recursive: true)) {
      if (entity is! File || !entity.path.toLowerCase().endsWith('.json')) {
        continue;
      }
      final Object? decoded = jsonDecode(await entity.readAsString());
      await entity.writeAsString(
        jsonEncode(_rewriteValue(decoded, oldRoot, newRoot)),
        flush: true,
      );
    }
  }

  /// 递归处理 JSON 字符串、列表和对象，仅替换属于旧资料库根目录的路径。
  static Object? _rewriteValue(Object? value, String oldRoot, String newRoot) {
    if (value is String) {
      final String oldNormalized = oldRoot.replaceAll('\\', '/');
      final String normalized = value.replaceAll('\\', '/');
      if (normalized.toLowerCase() == oldNormalized.toLowerCase()) {
        return newRoot;
      }
      final String prefix = '$oldNormalized/';
      if (normalized.toLowerCase().startsWith(prefix.toLowerCase())) {
        return '$newRoot/${normalized.substring(prefix.length)}';
      }
      return value;
    }
    if (value is List<Object?>) {
      return value
          .map((item) => _rewriteValue(item, oldRoot, newRoot))
          .toList();
    }
    if (value is Map<String, Object?>) {
      return value.map(
        (key, item) => MapEntry(key, _rewriteValue(item, oldRoot, newRoot)),
      );
    }
    return value;
  }

  /// 比较规范化后的路径是否相同，避免大小写或分隔符差异造成重复迁移。
  static bool _samePath(String a, String b) =>
      File(a).absolute.path.replaceAll('\\', '/').toLowerCase() ==
      File(b).absolute.path.replaceAll('\\', '/').toLowerCase();

  /// 判断目标路径是否位于 parent 内，使用目录边界防止把相似前缀误认为子目录。
  static bool _isChild(String path, String parent) {
    final String normalizedPath = File(path).absolute.path
        .replaceAll('\\', '/')
        .replaceAll(RegExp(r'/+$'), '')
        .toLowerCase();
    final String normalizedParent = File(parent).absolute.path
        .replaceAll('\\', '/')
        .replaceAll(RegExp(r'/+$'), '')
        .toLowerCase();
    return normalizedPath.startsWith('$normalizedParent/');
  }
}
