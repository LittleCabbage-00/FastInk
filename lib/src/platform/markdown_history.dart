import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';

class MarkdownHistory {
  /// 绑定资料库根目录，修订历史与当前源文件分开保存。
  MarkdownHistory(this.root);

  /// root：所属仓库或缓存的本地根目录，所有相对资源定位以此为基准。
  final String root;

  /// 将规范化源路径映射到稳定历史目录，重命名时由迁移流程协调。
  Directory _folder(String path) => Directory(
    '$root${Platform.pathSeparator}${sha256.convert(utf8.encode(File(path).absolute.uri.toString().toLowerCase()))}',
  );

  /// 内容变化前保存旧版本，避免重复相同快照并按 limit 淘汰超额修订。
  Future<void> capture(String path, String previous, {int limit = 50}) async {
    final directory = await _folder(path).create(recursive: true);
    final hash = sha256
        .convert(utf8.encode(previous))
        .toString()
        .substring(0, 12);
    final revisions = await list(path);
    if (revisions.isNotEmpty &&
        revisions.first.uri.pathSegments.last.contains(hash)) {
      return;
    }
    final file = File(
      '${directory.path}${Platform.pathSeparator}${DateTime.now().microsecondsSinceEpoch}-$hash.md',
    );
    await file.writeAsString(previous, flush: true);
    for (final stale in (await list(path)).skip(limit.clamp(10, 200))) {
      await stale.delete();
    }
  }

  /// 列出该文稿可用修订文件并按时间组织，文件缺失时返回现有结果。
  Future<List<File>> list(String path) async {
    final directory = _folder(path);
    if (!await directory.exists()) return [];
    final files = await directory
        .list()
        .where(
          (entry) =>
              entry is File &&
              RegExp(
                r'^\d+-[a-f0-9]{12}\.md$',
              ).hasMatch(entry.uri.pathSegments.last),
        )
        .cast<File>()
        .toList();
    files.sort((a, b) => b.path.compareTo(a.path));
    return files;
  }

  /// 重命名文稿时迁移其历史归属，防止新旧路径被当成两个无关历史。
  Future<void> renamed(String before, String after) async {
    final source = _folder(before), target = _folder(after);
    if (source.path == target.path || !await source.exists()) return;
    await target.create(recursive: true);
    for (final file in await list(before)) {
      final destination = File(
        '${target.path}${Platform.pathSeparator}${file.uri.pathSegments.last}',
      );
      if (!await destination.exists()) await file.copy(destination.path);
    }
  }
}
