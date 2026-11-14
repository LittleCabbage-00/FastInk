import 'dart:async';
import 'dart:io';

/// 测试截图和性能记录统一写入可清理的构建目录，源代码目录不再积累临时文件。
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  await Directory('build/diagnostics').create(recursive: true);
  await testMain();
}
