import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/material.dart';
import '../models/models.dart';
import '../platform/note_cover_cache.dart';

/// 资料库卡片只展示缓存位图；未完成的预览任务不占用滚动动画的界面线程。
class LibraryNotePreview extends StatefulWidget {
  /// 创建不可变的 LibraryNotePreview 参数对象；各参数保存在对应字段中，不在构造时执行外部读写。
  /// root：所属仓库或缓存的本地根目录，所有相对资源定位以此为基准。
  /// documentId：封面所属文稿编号，用于缓存和首页面笔迹定位。
  /// coverPath：资料库卡片展示首页/封面的底图路径，不改变正文页序。
  const LibraryNotePreview({
    super.key,
    required this.root,
    required this.documentId,
    required this.coverPath,
  });

  /// root：所属仓库或缓存的本地根目录，所有相对资源定位以此为基准；documentId：封面所属文稿编号，用于缓存和首页面笔迹定位；coverPath：资料库卡片展示首页/封面的底图路径，不改变正文页序。
  final String root, documentId, coverPath;

  @override
  State<LibraryNotePreview> createState() => _LibraryNotePreviewState();
}

class _LibraryNotePreviewState extends State<LibraryNotePreview> {
  /// _preview：已生成或命中的封面缓存文件；为空时先显示低分辨率底图。
  File? _preview;

  /// _failed：当前预览/服务是否失败，用于显示失败标志或禁止继续提交。
  bool _failed = false;

  /// 先使用最近已知封面以快速显示，再异步校验指纹与生成必要更新。
  @override
  void initState() {
    super.initState();
    _preview = NoteCoverCache.peek(widget.root, widget.documentId);
    _load();
  }

  /// 通过串行封面服务读取缓存，冷渲染等待滚动结束，卸载后取消尚未开始的工作；失败显示可识别提示。
  Future<void> _load() async {
    try {
      final file = await NoteCoverCache.load(
        widget.root,
        widget.documentId,
        widget.coverPath,
        active: () => mounted,
        beforeRender: () async {
          // 滚动期间先使用已有封面，冷封面的生成等待手势结束。
          while (mounted &&
              (Scrollable.maybeOf(
                    context,
                  )?.position.isScrollingNotifier.value ??
                  false)) {
            await Future<void>.delayed(const Duration(milliseconds: 120));
          }
          if (mounted) await WidgetsBinding.instance.endOfFrame;
        },
      );
      if (mounted && file != null) setState(() => _preview = file);
    } catch (error, stack) {
      assert(() {
        debugPrint('封面缓存生成失败：$error\n$stack');
        return true;
      }());
      if (mounted) setState(() => _failed = true);
    }
  }

  /// 显示低分辨率封面或底图，顶部对齐裁切填满卡片，裁切不改原文稿文件。
  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: Stack(
      fit: StackFit.expand,
      children: [
        Image(
          image: _preview == null
              ? ResizeImage(
                  FileImage(File(widget.coverPath)),
                  width: 240,
                  height: 320,
                  policy: ResizeImagePolicy.fit,
                )
              : FileImage(_preview!),
          key: ValueKey(_preview?.path ?? widget.coverPath),
          // 封面铺满卡片，从顶部裁切以保留标题；不改动原始页面。
          fit: BoxFit.cover,
          alignment: Alignment.topCenter,
          gaplessPlayback: true,
          filterQuality: FilterQuality.low,
          errorBuilder: (_, _, _) =>
              const Center(child: Icon(Icons.description_outlined, size: 58)),
        ),
        if (_preview == null)
          Positioned(
            left: 8,
            bottom: 8,
            child: Icon(
              _failed
                  ? Icons.warning_amber_rounded
                  : Icons.hourglass_empty_rounded,
              size: 12,
            ),
          ),
      ],
    ),
  );
}

/// 在独立线程根据清单定位真正首页笔迹，尝试有效主/前一版本并兼容旧宽度，返回完整可预览内容。
Future<PageInk> readLibraryCoverInk(String root, String id) =>
    Isolate.run(() async {
      if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(id)) {
        throw ArgumentError('Invalid document ID');
      }
      final directory = '$root/documents/$id';
      int originalPage = 1;
      final manifest = File('$directory/manifest.json');
      if (await manifest.exists()) {
        final data = jsonDecode(await manifest.readAsString()) as Map;
        final pages = data['pages'] as List?;
        if (pages != null && pages.isNotEmpty) {
          originalPage = ((pages.first as Map)['originalPage'] as num).toInt();
        }
      }
      final path =
          '$directory/pages/${originalPage.toString().padLeft(6, '0')}.json';
      for (final candidate in [File(path), File('$path.previous')]) {
        if (!await candidate.exists()) continue;
        try {
          return PageInk.fromJson(
            jsonDecode(await candidate.readAsString()) as Map<String, Object?>,
          ).withNormalizedWidths(legacyInkWidthFallbackReference);
        } on FormatException {
          continue;
        }
      }
      return const PageInk(strokes: []);
    });
