import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'library_repository.dart';
import 'note_repository.dart';

/// 可继续编辑、内容完整的文件夹备份；外部页面引用也会
/// 一并复制，恢复时不覆盖已经存在的资料库。
abstract final class LibraryBackup {
  /// marker：可编辑备份的清单标记文件名，恢复前校验该清单及文件哈希。
  static const marker = 'fastink-backup.json';

  /// _pathKeys：备份迁移中需要按路径处理的 JSON 字段集合，其他普通字符串不能误重写。
  static const _pathKeys = <String>{
    'sourcePath',
    'coverPath',
    'directory',
    'path',
    'source',
    'imageAsset',
    'backgroundAsset',
  };

  /// 把本地路径规范化为可比较的绝对路径形式。
  static String _norm(String p) => File(
    p,
  ).absolute.path.replaceAll('\\', '/').replaceAll(RegExp(r'/+$'), '');

  /// 判断目标是否位于给定根目录内，使用路径边界而非普通字符串前缀。
  static bool _inside(String p, String root) =>
      _norm(p).toLowerCase().startsWith('${_norm(root).toLowerCase()}/');

  /// 比较两条规范化路径是否表示同一位置。
  static bool _same(String a, String b) =>
      _norm(a).toLowerCase() == _norm(b).toLowerCase();

  /// 获取路径相对备份根目录的引用，供可移动备份使用。
  static String _relative(String p, String root) =>
      _norm(p).substring(_norm(root).length + 1);

  /// 校验源、目标不重叠且目标可安全创建，不覆盖已有非空资料库。
  static Future<void> _emptyTarget(String source, String target) async {
    if (_same(source, target) ||
        _inside(target, source) ||
        _inside(source, target)) {
      throw const FileSystemException('备份位置与资料库不能互相包含。');
    }
    if (await Directory(target).exists()) {
      throw const FileSystemException('请选择一个尚不存在的新备份/恢复目录。');
    }
  }

  /// 收集资料库文件、外部页面和必要资源，重写内部引用并生成 SHA-256 清单，保留原资料库。
  static Future<void> create(
    String sourceRoot,
    String destination, {
    void Function(String)? progress,
  }) async {
    await _emptyTarget(sourceRoot, destination);
    final index = File('$sourceRoot/library.json');
    if (!await index.exists()) throw const FormatException('没有可读取的资料库索引。');
    jsonDecode(await index.readAsString());
    await Directory(destination).create(recursive: true);
    try {
      await for (final entity in Directory(
        sourceRoot,
      ).list(recursive: true, followLinks: false)) {
        if (entity is Link) {
          throw const FileSystemException('资料库含链接，请先移入实际文件再备份。');
        }
        if (entity is! File || entity.path.endsWith('.tmp')) continue;
        final relative = _relative(entity.path, sourceRoot);
        if (relative.startsWith('.preview-cache/')) {
          continue;
        }
        if (relative == marker) continue;
        final output = File('$destination/$relative');
        await output.parent.create(recursive: true);
        await entity.copy(output.path);
      }
      // 外部图片文件夹笔记可能尚未建立应用清单。
      final library = await LibraryRepository(root: sourceRoot).load();
      if (library.documents.any(
        (d) => !RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(d.id),
      )) {
        throw const FormatException('资料库包含无效的文稿标识。');
      }
      final notes = NoteRepository(dataRoot: sourceRoot);
      final targetNotes = NoteRepository(dataRoot: destination);
      for (final item in library.documents) {
        if (item.id.startsWith('md-')) continue;
        final doc = await notes.indexFromSelectedPath(
          item.sourcePath,
          documentId: item.id,
        );
        await targetNotes.saveDocumentManifest(doc);
      }
      // 把源资料库或收集的外部资源路径映射为备份内位置，保持资源引用一致。
      String mapPath(String path) {
        if (_same(path, sourceRoot)) return _norm(destination);
        if (_inside(path, sourceRoot)) {
          return '${_norm(destination)}/${_relative(path, sourceRoot)}';
        }
        final isDirectory = Directory(path).existsSync();
        final parent = isDirectory ? path : File(path).parent.path;
        final bucket = sha256
            .convert(utf8.encode(_norm(parent).toLowerCase()))
            .toString()
            .substring(0, 20);
        final name = _norm(path).split('/').last;
        return '${_norm(destination)}/external/$bucket${isDirectory ? '' : '/$name'}';
      }

      // 递归遍历索引与清单中的路径字段，收集需要携带的文件，不把普通文本当作路径重写。
      Future<Object?> rewrite(Object? value, [String? key]) async {
        if (value is String &&
            _pathKeys.contains(key) &&
            value.isNotEmpty &&
            File(value).isAbsolute) {
          final mapped = mapPath(value);
          if (!_same(value, sourceRoot) && !_inside(value, sourceRoot)) {
            if (await File(value).exists()) {
              await File(mapped).parent.create(recursive: true);
              await File(value).copy(mapped);
            } else if (await Directory(value).exists()) {
              await Directory(mapped).create(recursive: true);
              final pdfMeta = File('$value/.fastink-pdf.json');
              if (await pdfMeta.exists()) {
                await File('$mapped/.fastink-pdf.json').writeAsString(
                  jsonEncode(
                    await rewrite(jsonDecode(await pdfMeta.readAsString())),
                  ),
                );
              }
            } else {
              throw FileSystemException('备份引用的文件不存在', value);
            }
          }
          return mapped;
        }
        if (value is List) return Future.wait(value.map((v) => rewrite(v)));
        if (value is Map<String, dynamic>) {
          final result = <String, Object?>{};
          for (final entry in value.entries) {
            result[entry.key] = await rewrite(entry.value, entry.key);
          }
          return result;
        }
        return value;
      }

      final jsonFiles = await Directory(destination)
          .list(recursive: true, followLinks: false)
          .where(
            (e) =>
                e is File &&
                (e.path.endsWith('.json') || e.path.endsWith('.json.previous')),
          )
          .cast<File>()
          .toList();
      for (final file in jsonFiles) {
        // 配置指针属于当前机器，恢复备份时不启用。
        await file.writeAsString(
          jsonEncode(await rewrite(jsonDecode(await file.readAsString()))),
        );
      }
      final files = <String, Object?>{};
      await for (final file
          in Directory(destination)
              .list(recursive: true, followLinks: false)
              .where((e) => e is File)
              .cast<File>()) {
        final relative = _relative(file.path, destination);
        progress?.call('正在校验备份：$relative');
        files[relative] = (await sha256.bind(file.openRead()).first).toString();
      }
      await File('$destination/$marker').writeAsString(
        jsonEncode({
          'format': 'FastInkEditableBackup',
          'version': 1,
          'root': _norm(destination),
          'createdAt': DateTime.now().toIso8601String(),
          'files': files,
        }),
        flush: true,
      );
    } catch (_) {
      await Directory(destination).delete(recursive: true);
      rethrow;
    }
  }

  /// 校验备份标记和所有文件哈希，再复制到新目标并重定位引用，失败不覆盖原资料库。
  static Future<void> restore(
    String backup,
    String destination, {
    void Function(String)? progress,
  }) async {
    await _emptyTarget(backup, destination);
    final meta =
        jsonDecode(await File('$backup/$marker').readAsString())
            as Map<String, dynamic>;
    if (meta['format'] != 'FastInkEditableBackup' ||
        meta['version'] != 1 ||
        meta['root'] is! String) {
      throw const FormatException('不支持的 FastInk 备份格式。');
    }
    final files = meta['files'] as Map<String, dynamic>;
    if (files.keys.map((p) => p.toLowerCase()).toSet().length != files.length) {
      throw const FormatException('备份包含重名文件。');
    }
    if (!files.containsKey('library.json')) {
      throw const FormatException('备份缺少资料库索引。');
    }
    // 写入前验证全部成员；链接、绝对路径、路径穿越以及
    // 未列入清单的文件均不得复制到恢复后的资料库。
    for (final entry in files.entries) {
      final path = entry.key;
      if (path.contains('\\') ||
          path.contains(':') ||
          path.startsWith('/') ||
          path.split('/').any((p) => p == '..' || p == '.' || p.isEmpty)) {
        throw const FormatException('备份包含不安全的文件路径。');
      }
      final file = File('$backup/$path');
      final resolved = await file.resolveSymbolicLinks();
      if (!_inside(resolved, await Directory(backup).resolveSymbolicLinks())) {
        throw const FormatException('备份文件指向目录外部。');
      }
      progress?.call('正在校验：$path');
      if ((await sha256.bind(file.openRead()).first).toString() !=
          entry.value) {
        throw FormatException('备份文件损坏或被修改：$path');
      }
    }
    // 将备份内的相对路径转换为恢复目标的实际位置，其他数据递归保持。
    Object? relocate(Object? value, [String? key]) {
      if (value is String &&
          _pathKeys.contains(key) &&
          value.isNotEmpty &&
          File(value).isAbsolute) {
        if (_same(value, meta['root'] as String)) return _norm(destination);
        if (_inside(value, meta['root'] as String)) {
          return '${_norm(destination)}/${_relative(value, meta['root'] as String)}';
        }
        throw const FormatException('备份中存在未包含的外部文件引用。');
      }
      if (value is List) return value.map((v) => relocate(v)).toList();
      if (value is Map<String, dynamic>) {
        return value.map((k, v) => MapEntry(k, relocate(v, k)));
      }
      return value;
    }

    await Directory(destination).create(recursive: true);
    try {
      for (final path in files.keys) {
        final output = File('$destination/$path');
        await output.parent.create(recursive: true);
        await File('$backup/$path').copy(output.path);
        if ((await sha256.bind(output.openRead()).first).toString() !=
            files[path]) {
          throw FormatException('备份在恢复期间发生变化：$path');
        }
        if (path.endsWith('.json') || path.endsWith('.json.previous')) {
          await output.writeAsString(
            jsonEncode(relocate(jsonDecode(await output.readAsString()))),
          );
        }
      }
      final index =
          jsonDecode(await File('$destination/library.json').readAsString())
              as Map<String, dynamic>;
      for (final item in (index['documents'] as List? ?? [])) {
        if (item is! Map ||
            item['id'] is! String ||
            !RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(item['id'] as String)) {
          throw const FormatException('备份包含无效的文稿标识。');
        }
      }
    } catch (_) {
      await Directory(destination).delete(recursive: true);
      rethrow;
    }
  }
}
