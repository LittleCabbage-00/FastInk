import 'dart:convert';
import 'dart:io';
import 'dart:math';

class MarkdownTemplate {
  /// 保存模板的显示信息、正文和本地来源。
  /// id：对象的稳定身份编号，用于索引、关联和缓存键，不是显示标题。
  /// name：用户可读名称；用于显示或文件名解析，不应替代稳定编号。
  /// content：模板或文稿的完整源文，预览和插入不应使用被截断的标题文本代替。
  const MarkdownTemplate(this.id, this.name, this.content);

  /// id：对象的稳定身份编号，用于索引、关联和缓存键，不是显示标题；name：用户可读名称；用于显示或文件名解析，不应替代稳定编号；content：模板或文稿的完整源文，预览和插入不应使用被截断的标题文本代替。
  final String id, name, content;
}

class MarkdownTemplates {
  /// 将个人 Markdown 模板目录定位到当前资料库，和应用内置模板分开。
  MarkdownTemplates(String root)
    : directory = Directory(
        '$root${Platform.pathSeparator}.markdown-templates',
      );

  /// directory：该对象对应的本地目录；只表示路径，不保证目录已经创建。
  final Directory directory;

  /// 读取现有个人模板并跳过已归档项，返回可插入的名称与源文。
  Future<List<MarkdownTemplate>> read() async {
    if (!await directory.exists()) return [];
    final result = <MarkdownTemplate>[];
    await for (final entry in directory.list()) {
      if (entry is! File || !entry.path.endsWith('.json')) continue;
      try {
        final data = jsonDecode(await entry.readAsString()) as Map;
        final id = entry.uri.pathSegments.last.replaceFirst('.json', '');
        result.add(
          MarkdownTemplate(
            id,
            data['name'] as String,
            data['content'] as String,
          ),
        );
      } on FormatException {
        continue;
      } on TypeError {
        continue;
      }
    }
    result.sort((a, b) => a.name.compareTo(b.name));
    return result;
  }

  /// 以独立文件保存模板全文，同名模板不直接覆盖旧文件。
  Future<void> save(String name, String content) async {
    if (name.trim().isEmpty || content.trim().isEmpty) {
      throw ArgumentError('Empty template');
    }
    await directory.create(recursive: true);
    // 使用唯一文件名，避免同名模板覆盖既有内容；
    // 只有写入完整的文件才对用户可见。
    final random = Random.secure();
    final id = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final path = '${directory.path}${Platform.pathSeparator}$id';
    final temp = File('$path.tmp');
    await temp.writeAsString(
      jsonEncode({'name': name.trim(), 'content': content}),
      flush: true,
    );
    await temp.rename('$path.json');
  }

  /// 将模板改名归档为删除状态，不直接销毁其内容。
  Future<void> archive(MarkdownTemplate template) async {
    if (!RegExp(r'^[a-fA-F0-9-]+$').hasMatch(template.id)) {
      throw ArgumentError('Invalid template ID');
    }
    final file = File(
      '${directory.path}${Platform.pathSeparator}${template.id}.json',
    );
    if (await file.exists()) await file.rename('${file.path}.deleted');
  }

  /// 用标题和当前日期时间替换受支持模板变量，其他原始内容保持不变。
  static String expand(
    String content, {
    required String title,
    DateTime? date,
  }) {
    final now = date ?? DateTime.now();
    // 把日期/时间整数补齐为至少两位数字。
    String pad(int n) => '$n'.padLeft(2, '0');
    final values = {
      'date': '${now.year}-${pad(now.month)}-${pad(now.day)}',
      'time': '${pad(now.hour)}:${pad(now.minute)}',
      'title': title,
    };
    return content.replaceAllMapped(
      RegExp(r'\{\{(date|time|title)\}\}'),
      (m) => values[m[1]]!,
    );
  }
}
