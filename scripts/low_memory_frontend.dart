// 使用 Flutter 支持的前端启动入口限制编译器内存，不修改 SDK。
import 'dart:io';

/// 启动 SDK 自带前端 AOT 快照并透传 Flutter 参数；仅约束编译器堆，不修改 SDK 文件。
Future<void> main(List<String> arguments) async {
  // 当前 Dart SDK 可执行目录，前端与 runtime 必须来自同一 SDK。
  final bin = File(Platform.resolvedExecutable).parent.path;
  // 编译器老年代堆上限，单位 MB；环境变量非法或超范围时失败，不静默放大预算。
  final heap =
      int.tryParse(Platform.environment['FASTINK_COMPILER_HEAP_MB'] ?? '') ??
      1024;
  // 启动前端快照的 AOT 运行器路径。
  final runtime = '$bin/dartaotruntime.exe';
  // 与当前 SDK 配套的前端快照，缺失时不启动不兼容替代程序。
  final snapshot = '$bin/snapshots/frontend_server_aot.dart.snapshot';
  if (!File(runtime).existsSync() ||
      !File(snapshot).existsSync() ||
      heap < 512 ||
      heap > 4096) {
    stderr.writeln(
      'Low-memory frontend: incompatible Dart SDK or invalid heap budget.',
    );
    exitCode = 1;
    return;
  }
  // 本脚本创建的唯一编译子进程，标准输入输出继承给 Flutter 协议调用方。
  final process = await Process.start(runtime, [
    '--old_gen_heap_size=$heap',
    snapshot,
    ...arguments,
  ], mode: ProcessStartMode.inheritStdio);
  exitCode = await process.exitCode;
}
