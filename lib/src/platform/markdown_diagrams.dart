import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as raster;
import 'runtime_paths.dart';

class MarkdownDiagramSuperseded implements Exception {
  /// 返回图表任务取消的可读描述，区别于真正渲染失败。
  @override
  String toString() => '图表内容已更新';
}

class MarkdownDiagrams {
  /// _queue：串行任务链，前一次失败通过调用方捕获后不阻塞后续任务。
  static Future<void> _queue = Future<void>.value();

  /// _pending：已经排队但尚未完成的任务，按键合并，避免重复创建同一结果。
  static final Map<String, Future<File>> _pending = {};

  /// _completed：已经完成的图表渲染文件缓存，命中后不再启动浏览器渲染。
  static final Map<String, File> _completed = {};

  /// _wanted：图表槽位当前需要的内容签名，排队旧内容在启动前可据此作废。
  static final Map<String, String> _wanted = {};

  /// _forced：图表槽位强制刷新版本，允许显式重试时绕过旧结果。
  static final Map<String, int> _forced = {};

  /// 释放槽位对指定源码和主题的渲染需求，旧排队任务启动前会检查是否仍需要。
  static void release(String slot, String code, bool dark) {
    if (_wanted[slot] == _key(code, dark)) _wanted.remove(slot);
  }

  /// 由源码和主题生成渲染身份，只有相同内容和配色才能复用结果。
  static String _key(String code, bool dark) =>
      sha256.convert(utf8.encode('mermaid-12.2.0\n$dark\n$code')).toString();

  /// 查询已有图表图像文件，未完成或已失效时返回 null。
  static File? cached(String code, bool dark) => _completed[_key(code, dark)];

  /// 扫描真正的 Mermaid 围栏并返回源文范围与内容，忽略其他代码围栏中的示例。
  static List<(int, int, String)> blocks(String content) {
    final result = <(int, int, String)>[];
    final lines = content.split('\n');
    int offset = 0, start = -1, body = 0, length = 0;
    String fence = '';
    bool collecting = false;
    for (final line in lines) {
      if (start < 0) {
        final match = RegExp(r'^ {0,3}(`{3,}|~{3,})(.*)$').firstMatch(line);
        if (match != null) {
          start = offset;
          body = offset + line.length + 1;
          fence = match.group(1)![0];
          length = match.group(1)!.length;
          collecting = match.group(2)!.trim() == 'mermaid';
        }
      } else if (RegExp(
        '^ {0,3}${RegExp.escape(fence)}{$length,}[ \\t]*\$',
      ).hasMatch(line)) {
        if (collecting) {
          result.add((
            start,
            offset + line.length,
            content.substring(body, offset).trimRight(),
          ));
        }
        start = -1;
      }
      offset += line.length + 1;
    }
    return result;
  }

  /// 登记图表槽位需求并按内容签名复用/排队任务，避免相同图表重复启动浏览器。
  static Future<File> render(String code, {required bool dark, String? slot}) {
    final key = _key(code, dark);
    if (slot != null) {
      _wanted[slot] = key;
    } else {
      _forced[key] = (_forced[key] ?? 0) + 1;
    }
    final pending = _pending.putIfAbsent(key, () {
      final result = _queue.then((_) {
        if ((_forced[key] ?? 0) == 0 && !_wanted.containsValue(key)) {
          throw MarkdownDiagramSuperseded();
        }
        return _render(code, dark, key);
      });
      _queue = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
      result.then<void>(
        (file) {
          _completed[key] = file;
          while (_completed.length > 128) {
            _completed.remove(_completed.keys.first);
          }
          while (_pending.length > 128) {
            _pending.remove(_pending.keys.first);
          }
        },
        onError: (Object _, StackTrace _) {
          _pending.remove(key);
        },
      );
      return result;
    });
    if (slot != null) return pending;
    return pending
        .onError((Object error, StackTrace stack) {
          if (error is MarkdownDiagramSuperseded) {
            return render(code, dark: dark);
          }
          Error.throwWithStackTrace(error, stack);
        })
        .whenComplete(() {
          final remaining = (_forced[key] ?? 1) - 1;
          if (remaining <= 0) {
            _forced.remove(key);
          } else {
            _forced[key] = remaining;
          }
        });
  }

  /// 调用随包离线图表工具生成文件，受资源作业限制；启动前检查请求是否过期，失败保留诊断信息。
  static Future<File> _render(String code, bool dark, String key) async {
    if (code.length > 100000) throw const FormatException('Mermaid 图表过长');
    final root = await Directory(
      '${Directory.systemTemp.path}${Platform.pathSeparator}FastInk-diagrams',
    ).create(recursive: true);
    final cached = File('${root.path}${Platform.pathSeparator}$key.png');
    if (await cached.exists()) return cached;
    final tool = await markdownTool('render_diagram.ps1');
    final library = File(
      '${tool.parent.path}${Platform.pathSeparator}mermaid.min.js',
    );
    if (!await library.exists()) throw StateError('Mermaid 渲染组件缺失');
    final work = await root.createTemp('render-');
    try {
      final html = File('${work.path}${Platform.pathSeparator}diagram.html');
      final output = File('${work.path}${Platform.pathSeparator}diagram.png');
      final input = jsonEncode(code).replaceAll('<', r'\u003c');
      await html.writeAsString(
        '''<!doctype html><html><head><meta charset="utf-8"><meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src file: 'unsafe-inline'; style-src 'unsafe-inline'; img-src data:; font-src file: data:"><style>html,body{margin:0;padding:0;background:${dark ? '#101217' : '#ffffff'}}#diagram{padding:16px;box-sizing:border-box;width:1200px}svg{max-width:1168px!important;height:auto;font-family:"Microsoft YaHei","Segoe UI",sans-serif}</style><script src="${library.uri}"></script></head><body><div id="diagram"></div><script type="application/json" id="input">$input</script><script>
(async()=>{try {
mermaid.initialize({startOnLoad:false,securityLevel:'strict',theme:'${dark ? 'dark' : 'default'}',flowchart:{htmlLabels:false},maxTextSize:100000});
const result=await mermaid.render('fastinkDiagram',JSON.parse(document.getElementById('input').textContent));
document.getElementById('diagram').innerHTML=result.svg;
await document.fonts.ready;
const svg=document.querySelector('#diagram svg'); const box=svg.getBoundingClientRect();
if(box.height>3968) throw new Error('图表过高，请拆分成多个图表');
document.documentElement.dataset.result=JSON.stringify({width:Math.ceil(Math.min(1200,box.width+32)),height:Math.ceil(box.height+32)});
}catch(error){document.documentElement.dataset.result=JSON.stringify({error:String(error)});}})();
</script></body></html>''',
        flush: true,
      );
      final request = File('${work.path}${Platform.pathSeparator}request.json');
      await request.writeAsString(
        jsonEncode({'html': html.path, 'output': output.path}),
      );
      final process = await Process.start('powershell.exe', [
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        tool.path,
        '-Request',
        request.path,
      ]);
      final stdout = process.stdout.transform(utf8.decoder).join();
      final stderr = process.stderr
          .transform(const Utf8Decoder(allowMalformed: true))
          .join();
      final exit = await process.exitCode;
      final text = await stdout, error = await stderr;
      if (exit != 0) {
        throw StateError(error.trim().isEmpty ? text : error.trim());
      }
      final result = jsonDecode(text.trim()) as Map;
      final width = (result['width'] as num).toInt().clamp(1, 1200);
      final height = (result['height'] as num).toInt().clamp(1, 4000);
      final sourcePath = output.path, targetPath = cached.path;
      await Isolate.run(() async {
        final decoded = raster.decodePng(await File(sourcePath).readAsBytes());
        if (decoded == null) {
          throw const FormatException('Invalid diagram image');
        }
        final image = raster.copyCrop(
          decoded,
          x: 0,
          y: 0,
          width: width,
          height: height,
        );
        await File(
          targetPath,
        ).writeAsBytes(raster.encodePng(image), flush: true);
      });
      return cached;
    } finally {
      // 渲染器返回前，已关闭其进程作业并清理子进程。
      for (int attempt = 0; attempt < 4; attempt++) {
        try {
          await work.delete(recursive: true);
          break;
        } catch (_) {
          if (attempt < 3) {
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
        }
      }
    }
  }
}
