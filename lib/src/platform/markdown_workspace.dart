import 'dart:convert';
import 'dart:io';
import 'package:yaml/yaml.dart';

class MarkdownNoteInfo {
  /// 保存 Markdown 文稿的标题、标签、属性和链接索引。
  /// path：对象对应的本地文件路径；具体是否已存在由读取/创建入口校验。
  /// 保存和显示使用的完整标题。
  /// content：模板或文稿的完整源文，预览和插入不应使用被截断的标题文本代替。
  /// tags：从文稿属性与正文整理出的标签，供工作台筛选和关联显示。
  /// aliases：文稿属性中保存的别名，Wiki 链接解析可用它定位目标。
  /// links：文稿中收集的引用目标，供反向链接与工作区关联使用。
  const MarkdownNoteInfo({
    required this.path,
    required this.title,
    required this.content,
    required this.tags,
    required this.aliases,
    required this.links,
  });

  /// path：对象对应的本地文件路径；具体是否已存在由读取/创建入口校验；title：当前项目的显示标题，列表可能截断显示但不截断保存内容；content：模板或文稿的完整源文，预览和插入不应使用被截断的标题文本代替。
  final String path, title, content;

  /// tags：从文稿属性与正文整理出的标签，供工作台筛选和关联显示；aliases：文稿属性中保存的别名，Wiki 链接解析可用它定位目标；links：文稿中收集的引用目标，供反向链接与工作区关联使用。
  final List<String> tags, aliases, links;
}

class MarkdownWorkspace {
  /// _cache：按规范路径保存修改时间、文件长度与已解析信息，文件变化才重新扫描源文。
  static final _cache = <String, (DateTime, int, MarkdownNoteInfo)>{};

  /// 把本地路径规范化为工作区比较键，避免大小写或分隔符导致同一文件重复登记。
  static String canonical(String path) =>
      File(path).absolute.uri.normalizePath().toString().toLowerCase();

  /// wiki：识别受支持 Wiki 链接的正则，目标与显示别名仍由解析方法进一步处理。
  static final wiki = RegExp(r'\[\[([^\]\n]+)\]\]');

  /// 解析开头的 YAML 文稿属性，无法识别的内容按解析规则处理，不将正文标签当整个属性对象。
  static Map<String, Object?> properties(String content) {
    final match = RegExp(
      r'^\uFEFF?---\r?\n([\s\S]*?)\r?\n(?:---|\.\.\.)[ \t]*(?:\r?\n|$)',
    ).firstMatch(content);
    if (match == null) return {};
    try {
      final parsed = loadYaml(match.group(1)!);
      if (parsed is! Map) return {};
      return {for (final entry in parsed.entries) '${entry.key}': entry.value};
    } catch (_) {
      return {};
    }
  }

  /// 移除开头属性块后返回正文，供搜索与文本片段提取使用。
  static String plainBody(String content) => content.replaceFirst(
    RegExp(r'^\uFEFF?---\r?\n[\s\S]*?\r?\n(?:---|\.\.\.)[ \t]*(?:\r?\n|$)'),
    '',
  );

  /// 从源文构建标题、标签、别名与链接等轻量索引信息。
  static MarkdownNoteInfo inspect(String path, String content) {
    final props = properties(content);
    // 把属性中的字符串或列表归一为非空字符串列表，便于统一处理 tags/aliases。
    List<String> values(Object? value) => value is List
        ? value.map((item) => '$item').toList()
        : value is String
        ? value
              .split(RegExp(r'[,，\s]+'))
              .where((value) => value.isNotEmpty)
              .toList()
        : [];
    final body = plainBody(content).replaceAll(
      RegExp(r'^\s*(```|~~~)[\s\S]*?^\s*\1\s*$', multiLine: true),
      '',
    );
    final tags = {
      ...values(props['tags']),
      for (final match in RegExp(
        r'(?:^|\s)#([\p{L}\p{N}_/-]+)',
        unicode: true,
        multiLine: true,
      ).allMatches(body))
        match.group(1)!,
    }.toList()..sort();
    return MarkdownNoteInfo(
      path: path,
      title: props['title'] is String
          ? props['title'] as String
          : File(path).uri.pathSegments.last.replaceFirst(
              RegExp(r'\.md$', caseSensitive: false),
              '',
            ),
      content: content,
      tags: tags,
      aliases: values(props['aliases']),
      links: [
        for (final match in wiki.allMatches(body))
          match.group(1)!.split('|').first.split('#').first.trim(),
      ],
    );
  }

  /// 读取工作区文件并按文件时间/长度复用解析缓存，单个文件失败不应阻止其他文稿检索。
  static Future<List<MarkdownNoteInfo>> read(
    Iterable<String> paths, {
    String? currentPath,
    String? currentContent,
  }) async {
    final notes = <MarkdownNoteInfo>[];
    final seen = <String>{};
    for (final path in [...paths, ?currentPath]) {
      final key = canonical(path);
      if (!seen.add(key)) continue;
      if (currentPath != null &&
          canonical(currentPath) == key &&
          currentContent != null) {
        notes.add(inspect(path, currentContent));
        continue;
      }
      try {
        final file = File(path);
        final stat = await file.stat();
        if (stat.type != FileSystemEntityType.file ||
            stat.size > 8 * 1024 * 1024) {
          continue;
        }
        final cached = _cache[key];
        if (cached != null &&
            cached.$1 == stat.modified &&
            cached.$2 == stat.size) {
          notes.add(cached.$3);
          continue;
        }
        final note = inspect(path, await file.readAsString());
        _cache[key] = (stat.modified, stat.size, note);
        // 限制索引容量，实际文件始终是权威数据源。
        while (_cache.length > 256) {
          _cache.remove(_cache.keys.first);
        }
        notes.add(note);
      } catch (_) {
        /* 文件缺失或被占用时，工作区导航仍可继续。 */
      }
    }
    return notes;
  }

  /// 按文件名、标题和别名查找 Wiki 引用目标，返回候选而非随意打开外部路径。
  static List<MarkdownNoteInfo> resolve(
    List<MarkdownNoteInfo> notes,
    String reference,
    String sourcePath,
  ) {
    final target = reference
        .split('|')
        .first
        .split('#')
        .first
        .trim()
        .replaceAll('\\', '/');
    if (target.isEmpty) {
      return notes
          .where((note) => canonical(note.path) == canonical(sourcePath))
          .toList();
    }
    final source = File(sourcePath).absolute.uri;
    final direct = source.resolve(
      target.toLowerCase().endsWith('.md') ? target : '$target.md',
    );
    final exact = notes
        .where(
          (note) =>
              File(note.path).absolute.uri.toString().toLowerCase() ==
              direct.toString().toLowerCase(),
        )
        .toList();
    if (exact.isNotEmpty) return exact;
    final basename = target
        .split('/')
        .last
        .replaceFirst(RegExp(r'\.md$', caseSensitive: false), '')
        .toLowerCase();
    return notes
        .where(
          (note) =>
              note.title.toLowerCase() == basename ||
              File(note.path).uri.pathSegments.last
                      .replaceFirst(RegExp(r'\.md$', caseSensitive: false), '')
                      .toLowerCase() ==
                  basename ||
              note.aliases.any((alias) => alias.toLowerCase() == basename),
        )
        .toList();
  }

  /// 仅修改指定的顶层属性，其他 YAML 字段与
  /// 注释原样保留，不重新序列化整个头部。
  static String updateProperties(String content, Map<String, Object?> updates) {
    final match = RegExp(
      r'^\uFEFF?---\r?\n([\s\S]*?)\r?\n(?:---|\.\.\.)[ \t]*(?:\r?\n|$)',
    ).firstMatch(content);
    final lines = match?.group(1)?.split('\n') ?? <String>[];
    for (final entry in updates.entries) {
      final key = entry.key;
      final start = lines.indexWhere(
        (line) => RegExp('^${RegExp.escape(key)}\\s*:').hasMatch(line),
      );
      final replacement = '$key: ${jsonEncode(entry.value)}';
      if (start < 0) {
        lines.add(replacement);
        continue;
      }
      int end = start + 1;
      while (end < lines.length &&
          (lines[end].startsWith(RegExp(r'\s')) || lines[end].trim().isEmpty)) {
        end++;
      }
      lines.replaceRange(start, end, [replacement]);
    }
    return '---\n${lines.join('\n')}\n---\n${match == null ? content : content.substring(match.end)}';
  }
}
