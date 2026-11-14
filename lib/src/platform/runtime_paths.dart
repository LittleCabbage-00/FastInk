import 'dart:io';

/// 解析并校验随包 Markdown 工具文件位置，缺失时抛出明确错误而不是静默依赖系统 PATH。
Future<File> markdownTool(String name) async {
  final candidates = [
    File(
      '${File(Platform.resolvedExecutable).parent.path}/tools/markdown/$name',
    ),
    File('${Directory.current.path}/windows/tools/markdown/$name'),
  ];
  for (final candidate in candidates) {
    if (await candidate.exists()) return candidate;
  }
  throw StateError('Markdown 组件缺失：$name');
}
