import 'dart:io';

/// 无需平台插件，使关于页面与包版本保持一致。
void main(List<String> arguments) {
  final root = File.fromUri(Platform.script).parent.parent;
  final pubspec = File('${root.path}/pubspec.yaml').readAsStringSync();
  final match = RegExp(
    r'^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$',
    multiLine: true,
  ).firstMatch(pubspec);
  if (match == null) {
    throw StateError('Expected version: x.y.z+build in pubspec.yaml');
  }
  final source =
      '''// 由 scripts/sync_app_version.dart 根据 pubspec.yaml 生成。
// 修改包版本后，请重新运行版本生成器。
abstract final class AppVersion {
  static const name = '${match[1]}';
  static const buildNumber = '${match[2]}';
  static const display = '\$name (\$buildNumber)';
}
''';
  final output = File('${root.path}/lib/src/core/app_version.dart');
  final current = output.existsSync()
      ? output.readAsStringSync().replaceAll('\r\n', '\n')
      : null;
  if (current != source) {
    if (arguments.contains('--check')) {
      stderr.writeln(
        'About version is stale. Run dart scripts/sync_app_version.dart before building.',
      );
      exitCode = 1;
      return;
    }
    output.writeAsStringSync(source, flush: true);
  }
  stdout.writeln('App version: ${match[1]} (${match[2]})');
}
