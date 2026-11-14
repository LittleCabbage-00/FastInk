import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// 记录未处理异常，并把局部组件错误限制在错误组件内。
///
/// 这不能挽救操作系统级的内存耗尽，但能防止普通异步异常或单个组件
/// 构建失败直接结束整个进程，同时为后续定位保留本地日志。
class CrashGuard {
  /// 阻止实例化，全局异常安装与记录统一走静态入口。
  CrashGuard._();

  /// _installed：错误钩子是否已安装，避免重复挂接全局异常处理器。
  static bool _installed = false;

  /// 安装 Flutter 构建异常与平台异步异常兜底，保留原错误输出并尝试写入本地日志。
  static void install() {
    if (_installed) return;
    _installed = true;

    final FlutterExceptionHandler? previousFlutterHandler =
        FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      previousFlutterHandler?.call(details);
      unawaited(_record(details.exception, details.stack));
    };

    final ui.ErrorCallback? previousPlatformHandler =
        ui.PlatformDispatcher.instance.onError;
    ui.PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      unawaited(_record(error, stack));
      previousPlatformHandler?.call(error, stack);
      // Dart 层异常已记录并由当前界面处理，不让它继续终止进程。
      return true;
    };

    ErrorWidget.builder = (FlutterErrorDetails details) {
      unawaited(_record(details.exception, details.stack));
      final bool chinese = ui.PlatformDispatcher.instance.locale.languageCode
          .toLowerCase()
          .startsWith('zh');
      return Directionality(
        textDirection: TextDirection.ltr,
        child: ColoredBox(
          color: const Color(0xff202226),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                chinese
                    ? '界面加载失败。请关闭当前页面后重试。'
                    : 'Could not load this view. Close it and try again.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xfff1f1f4)),
              ),
            ),
          ),
        ),
      );
    };
  }

  /// 将错误与调用栈追加到诊断日志；记录失败不能再次打断当前界面。
  static Future<void> _record(Object error, StackTrace? stack) async {
    try {
      final String profile =
          Platform.environment['USERPROFILE'] ?? Directory.systemTemp.path;
      final Directory directory = Directory('$profile/.fastink/logs');
      await directory.create(recursive: true);
      final File log = File('${directory.path}/errors.log');
      if (await log.exists() && await log.length() > 1024 * 1024) {
        final File previous = File('${directory.path}/errors.previous.log');
        if (await previous.exists()) await previous.delete();
        await log.rename(previous.path);
      }
      await log.writeAsString(
        '[${DateTime.now().toIso8601String()}] $error\n'
        '${stack ?? StackTrace.current}\n\n',
        mode: FileMode.append,
        flush: true,
      );
    } catch (_) {
      // 写日志失败不能再次触发全局异常处理。
    }
  }
}
