import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class OneNoteSourcePage {
  /// 保存 OneNote 桥提取的源页面信息、分组层级及 XML/笔迹文件，后续转换仍需校验。
  OneNoteSourcePage({
    required this.title,
    required this.section,
    required this.groups,
    required this.xml,
    required this.ink,
  });

  /// 保存和显示使用的完整标题。
  final String title;

  /// section：OneNote 页面所属分区名称，用于导入后的分组与文稿命名。
  final String section;

  /// groups：OneNote 分区组层级名称列表，导入时映射到对应资料库结构。
  final List<String> groups;

  /// xml：OneNote 导出的页面 XML 文件，解析时读取副本，不修改源笔记。
  final File xml;

  /// ink：OneNote 页面导出的原始笔迹文件，交给后续对象转换解析。
  final File ink;
}

class OneNoteReadResult {
  /// 返回提取的源页与警告，警告不能被解释为全部对象均无损转换成功。
  OneNoteReadResult(this.pages, this.warnings);

  /// pages：OneNote 桥提取的源页面描述，尚未等同于已保存的 FastInk 页面。
  final List<OneNoteSourcePage> pages;

  /// warnings：转换中不能完整处理的内容提示，不能静默冒充完全无损导入。
  final List<String> warnings;
}

class OneNoteReader {
  /// 原生解包前检查每个 CAB 成员，包括备用数据流、设备名和
  /// 路径穿越；仅检查文件表，不在此解压内容。
  static Future<void> validatePackage(File source) async {
    final file = await source.open();
    try {
      final header = await file.read(36);
      if (header.length != 36 ||
          ascii.decode(header.sublist(0, 4), allowInvalid: true) != 'MSCF') {
        throw const FormatException(
          'This .onepkg is not a OneNote cabinet package.',
        );
      }
      final data = ByteData.sublistView(header);
      final count = data.getUint16(28, Endian.little);
      if (count == 0 ||
          count > 10000 ||
          data.getUint16(30, Endian.little) & 3 != 0) {
        throw const FormatException(
          'Unsupported or empty multi-volume OneNote package.',
        );
      }
      await file.setPosition(data.getUint32(16, Endian.little));
      final names = <String>{};
      var total = 0;
      for (var i = 0; i < count; i++) {
        final item = await file.read(16);
        if (item.length != 16) {
          throw const FormatException('Truncated OneNote package.');
        }
        total += ByteData.sublistView(item).getUint32(0, Endian.little);
        if (total > 4 * 1024 * 1024 * 1024) {
          throw const FormatException('Expanded OneNote package exceeds 4 GB.');
        }
        final name = <int>[];
        while (true) {
          final byte = await file.readByte();
          if (byte < 0 || name.length > 4096) {
            throw const FormatException('Invalid cabinet filename.');
          }
          if (byte == 0) break;
          name.add(byte);
        }
        final utf8Names =
            ByteData.sublistView(item).getUint16(14, Endian.little) & 0x80 != 0;
        final path =
            (utf8Names ? utf8.decode(name) : systemEncoding.decode(name))
                .replaceAll('\\', '/');
        final parts = path.split('/');
        if (path.contains(':') ||
            parts.any(
              (p) =>
                  p.isEmpty ||
                  p == '.' ||
                  p == '..' ||
                  p.endsWith(' ') ||
                  p.endsWith('.') ||
                  RegExp(
                    r'^(con|nul|aux|prn|com[1-9]|lpt[1-9])(?:\.|$)',
                    caseSensitive: false,
                  ).hasMatch(p),
            ) ||
            !names.add(path.toLowerCase())) {
          throw const FormatException('Unsafe cabinet filename.');
        }
      }
    } finally {
      await file.close();
    }
  }

  /// 判断路径扩展名是否属于支持的本地 OneNote 入口，不保证文件内容一定可解析。
  static bool supports(String path) =>
      RegExp(r'\.(one|onex|onepkg)$', caseSensitive: false).hasMatch(path);

  /// 在隔离目录运行 Windows OneNote 导入桥，收集页面清单与警告并报告进度，不修改原文件。
  Future<OneNoteReadResult> read(
    File source,
    Directory workspace, {
    void Function(String)? onProgress,
  }) async {
    if (!Platform.isWindows) {
      throw UnsupportedError(
        'OneNote import requires Windows desktop OneNote.',
      );
    }
    if (!supports(source.path)) {
      throw ArgumentError('Unsupported OneNote file.');
    }
    if (source.path.toLowerCase().endsWith('.onepkg')) {
      await validatePackage(source);
    }
    final bundled = File(
      '${File(Platform.resolvedExecutable).parent.path}/tools/onenote/import.ps1',
    );
    final script = await bundled.exists()
        ? bundled
        : File('${Directory.current.path}/windows/tools/onenote/import.ps1');
    if (!await script.exists()) {
      throw StateError('OneNote import component is missing.');
    }
    final process = await Process.start(
      '${Platform.environment['SystemRoot'] ?? r'C:\Windows'}/System32/WindowsPowerShell/v1.0/powershell.exe',
      [
        '-NoProfile',
        '-NonInteractive',
        '-STA',
        '-WindowStyle',
        'Hidden',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        script.path,
        '-Source',
        source.absolute.path,
        '-Destination',
        workspace.absolute.path,
      ],
    );
    final errors = StringBuffer();
    final errorRead = process.stderr.transform(utf8.decoder).listen((value) {
      if (errors.length < 8192) errors.write(value);
    });
    final pages = <OneNoteSourcePage>[];
    final warnings = <String>[];
    String? failure;
    // 验证桥输出路径确实位于受控工作目录且文件有效，拒绝清单中的越界引用。
    File checkedFile(String path) {
      final file = File(path).absolute;
      final root =
          '${workspace.absolute.path.replaceAll('/', '\\').toLowerCase()}\\';
      if (!file.path.replaceAll('/', '\\').toLowerCase().startsWith(root)) {
        throw const FormatException('Import output is outside its workspace.');
      }
      return file;
    }

    try {
      await for (final line
          in process.stdout
              .transform(utf8.decoder)
              .transform(const LineSplitter())
              .timeout(const Duration(minutes: 5))) {
        if (line.trim().isEmpty) continue;
        final event = jsonDecode(line) as Map<String, dynamic>;
        switch (event['type']) {
          case 'progress':
            onProgress?.call('OneNote: ${event['message']}');
          case 'warning':
            warnings.add(event['message'] as String);
          case 'error':
            failure = event['message'] as String;
          case 'page':
            pages.add(
              OneNoteSourcePage(
                title: event['title'] as String,
                section: event['section'] as String,
                groups: (event['groups'] as List<dynamic>).cast<String>(),
                xml: checkedFile(event['xml'] as String),
                ink: checkedFile(event['ink'] as String),
              ),
            );
        }
      }
      final code = await process.exitCode;
      if (code != 0 || failure != null) {
        throw StateError(failure ?? errors.toString());
      }
      if (pages.isEmpty) throw StateError('No readable OneNote pages found.');
      return OneNoteReadResult(pages, warnings);
    } catch (_) {
      process.kill(); // Only the private PowerShell reader, never OneNote.
      rethrow;
    } finally {
      await errorRead.cancel();
    }
  }
}
