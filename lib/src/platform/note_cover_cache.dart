import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:crypto/crypto.dart';
import '../engine/ink_canvas.dart';
import '../models/models.dart';

/// 封面只生成一次低分辨率位图。滚动、悬停和打开文件夹时复用位图，
/// 不再把整页笔迹和长文本交给每一张资料库卡片重复排版。
class NoteCoverCache {
  /// _queue：串行任务链，前一次失败通过调用方捕获后不阻塞后续任务。
  static Future<void> _queue = Future<void>.value();

  /// _recent：最近使用的封面文件映射，只缓存低分辨率展示结果，不持有整页原始图像。
  static final Map<String, File> _recent = {};

  /// renderCount：诊断用的封面实际生成次数，缓存命中不应增加。
  static int renderCount = 0;

  /// 同步查询最近已知封面文件，仅用于立即显示，不在此入口校验或重新生成。
  static File? peek(String root, String id) => _recent['$root/$id'];

  /// 全局串行限制冷封面生成；调用方离开页面后跳过尚未开始的重活。
  static Future<File?> load(
    String root,
    String id,
    String background, {
    bool Function()? active,
    Future<void> Function()? beforeRender,
  }) {
    File? result;
    // 封面请求全局串行，前一任务失败不会阻塞后续卡片。
    final task = _queue.catchError((Object _) {}).then((_) async {
      if (active != null && !active()) return;
      // 指纹读取和笔迹 JSON 解析在后台完成，主线程只处理必要的低分辨率合成。
      final prepared = await _prepareInBackground(root, id, background);
      if (prepared.ink == null) {
        result = File(prepared.path);
      } else {
        await beforeRender?.call();
        if (active != null && !active()) return;
        await _renderCover(prepared, background);
        renderCount++;
        result = File(prepared.path);
        await _finishInBackground(prepared);
      }
      if (result != null) {
        _recent.remove('$root/$id');
        _recent['$root/$id'] = result!;
        while (_recent.length > 48) {
          _recent.remove(_recent.keys.first);
        }
      }
    });
    _queue = task.catchError((Object _) {});
    return task.then((_) => result);
  }
}

// 隔离线程入口单独声明，避免闭包连带捕获界面回调及不可发送的组件状态。
/// 在独立线程检查首页、笔迹和资源指纹，返回已有缓存或需要渲染的数据，避免 UI 线程解析大 JSON。
Future<_PreparedCover> _prepareInBackground(
  String root,
  String id,
  String background,
) => Isolate.run(() => _prepareCover(root, id, background));

/// 在后台写入已生成封面的元数据，当前界面不用等待重复排版。
Future<void> _finishInBackground(_PreparedCover cover) =>
    Isolate.run(() => _finishCover(cover));

class _PreparedCover {
  /// 保存生成封面所需的首页信息与已读取的笔迹。
  /// path：对象对应的本地文件路径；具体是否已存在由读取/创建入口校验。
  /// metadataPath：预览指纹元数据文件路径，用于判断封面是否需要重新生成。
  /// metadata：封面原图、笔迹和资源的指纹信息，不是文稿正文。
  /// ink：等待合成封面的页面笔迹；缓存有效时可为空，表示直接使用已有图像。
  /// directory：该对象对应的本地目录；只表示路径，不保证目录已经创建。
  const _PreparedCover(
    this.path,
    this.metadataPath,
    this.metadata,
    this.ink,
    this.directory,
  );

  /// path：对象对应的本地文件路径；具体是否已存在由读取/创建入口校验；metadataPath：预览指纹元数据文件路径，用于判断封面是否需要重新生成；directory：该对象对应的本地目录；只表示路径，不保证目录已经创建。
  final String path, metadataPath, directory;

  /// metadata：封面原图、笔迹和资源的指纹信息，不是文稿正文。
  final Map<String, Object?> metadata;

  /// ink：等待合成封面的页面笔迹；缓存有效时可为空，表示直接使用已有图像。
  final PageInk? ink;
}

/// 读取路径的文件类型、修改时刻与长度形成轻量指纹，不加载文件全部内容。
Future<String> _fileStamp(String path) async {
  final stat = await File(path).stat();
  return '${stat.type}:${stat.modified.microsecondsSinceEpoch}:${stat.size}';
}

/// 文件指纹包含首页顺序、笔迹、底图和嵌入图片。只读校验不修改原文稿。
Future<_PreparedCover> _prepareCover(
  String root,
  String id,
  String background,
) async {
  if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(id)) {
    throw ArgumentError('Invalid document ID');
  }
  final directory = '$root/documents/$id';
  final cache = '$root/.preview-cache';
  final metadataPath = '$cache/$id.json';
  final manifest = '$directory/manifest.json';
  // 首页清单变化也要作废封面，不能只看第一页文件名。
  final manifestStamp = await _fileStamp(manifest);
  Map<String, Object?> old = {};
  try {
    old =
        jsonDecode(await File(metadataPath).readAsString())
            as Map<String, Object?>;
  } catch (_) {}
  int page = (old['page'] as num?)?.toInt() ?? 1;
  if (old['manifestStamp'] != manifestStamp && await File(manifest).exists()) {
    final data = jsonDecode(await File(manifest).readAsString()) as Map;
    final pages = data['pages'] as List?;
    if (pages != null && pages.isNotEmpty) {
      page = ((pages.first as Map)['originalPage'] as num).toInt();
    }
  }
  // 笔迹文件按稳定 originalPage 定位，不能假定当前首页永远是 000001。
  final inkPath = '$directory/pages/${page.toString().padLeft(6, '0')}.json';
  // 指纹同时包含原图和有效笔迹版本，新增/修改文字也会更新封面。
  final base =
      'cover-v2:$manifestStamp:${await _fileStamp(inkPath)}:${await _fileStamp('$inkPath.previous')}:${await _fileStamp(background)}';
  // 旧资源列表用于快速复查图片修改，避免缓存命中时重新解析整页。
  final oldAssets = ((old['assets'] as List?) ?? []).cast<String>();
  // 合并嵌入资源的路径与文件指纹，任意图片变化都能使旧封面失效。
  Future<String> assetStamp(List<String> assets) async => (await Future.wait(
    assets.map((p) async => '$p:${await _fileStamp(p)}'),
  )).join('|');
  if (old['base'] == base && old['assetStamp'] == await assetStamp(oldAssets)) {
    final filename = old['filename'];
    if (filename is String &&
        RegExp(r'^[a-zA-Z0-9_-]+\.png$').hasMatch(filename)) {
      final path = '$cache/$filename';
      if (await File(path).exists()) {
        return _PreparedCover(path, metadataPath, old, null, directory);
      }
    }
  }
  PageInk ink = const PageInk(strokes: []);
  for (final file in [File(inkPath), File('$inkPath.previous')]) {
    if (!await file.exists()) continue;
    try {
      ink = PageInk.fromJson(
        jsonDecode(await file.readAsString()) as Map<String, Object?>,
      ).withNormalizedWidths(legacyInkWidthFallbackReference);
      break;
    } on FormatException {
      continue;
    }
  }
  final assets = ink.strokes
      .where((s) => s.imageAsset != null)
      .map(
        (s) => File(s.imageAsset!).isAbsolute
            ? s.imageAsset!
            : '$directory/${s.imageAsset}',
      )
      .toSet()
      .toList();
  // 嵌入资源指纹加入最终签名，源图变化不能继续显示旧封面。
  final stamps = await assetStamp(assets);
  // 内容签名用于稳定缓存文件身份，不以用户标题作为唯一缓存键。
  final digest = sha256
      .convert(utf8.encode('$base|$stamps'))
      .toString()
      .substring(0, 20);
  final filename = '$id-$digest.png';
  final metadata = <String, Object?>{
    'page': page,
    'manifestStamp': manifestStamp,
    'base': base,
    'assets': assets,
    'assetStamp': stamps,
    'filename': filename,
  };
  return _PreparedCover(
    '$cache/$filename',
    metadataPath,
    metadata,
    PageInk(strokes: ink.strokes.map(simplifyCoverStroke).toList()),
    directory,
  );
}

/// 仅精简封面副本：误差控制在 512 像素缩略图的约 0.65 像素内。
/// 原始坐标、压感和正文文件始终不变，导出与继续编辑仍读取原始数据。
InkStroke simplifyCoverStroke(InkStroke stroke) {
  if (stroke.text != null ||
      stroke.kind == StrokeKind.image ||
      stroke.points.length < 4) {
    return stroke;
  }
  // 简化容差按约 512 像素封面尺度确定，只减少预览几何，不改原始笔迹。
  const epsilon = .65 / 512;
  final points = stroke.points;
  // 始终保留首末点，避免缩略图简化丢掉笔画的可见端点。
  final keep = <int>{0, points.length - 1};
  // 用显式栈分段求最大偏差，避免密集笔迹深递归占用调用栈。
  final stack = <(int, int)>[(0, points.length - 1)];
  while (stack.isNotEmpty) {
    final (start, end) = stack.removeLast();
    final a = points[start], b = points[end];
    // 线段方向与长度平方用于投影，零长度段要单独处理以免除零。
    final dx = b.x - a.x, dy = b.y - a.y, length = dx * dx + dy * dy;
    double largest = epsilon * epsilon;
    int split = -1;
    for (int i = start + 1; i < end; i++) {
      final p = points[i];
      final t = length == 0
          ? 0.0
          : (((p.x - a.x) * dx + (p.y - a.y) * dy) / length).clamp(0.0, 1.0);
      // 点到投影点的差值用于几何偏差，比较平方距离避免反复开平方。
      final x = p.x - a.x - t * dx, y = p.y - a.y - t * dy;
      final distance = x * x + y * y;
      if (distance > largest) {
        largest = distance;
        split = i;
      }
    }
    if (split >= 0) {
      keep.add(split);
      stack.addAll([(start, split), (split, end)]);
    }
  }
  // 恢复源点顺序后只生成预览副本，原 strokes 和压力样本不被替换。
  final indices = keep.toList()..sort();
  return stroke.copy(points: [for (final i in indices) points[i]]);
}

/// 原生解码器直接缩小图像，避免先解压整张扫描页再缩放。
Future<ui.Image> _decodeCoverImage(String path) async {
  // 通过原生解码描述器直接缩图，避免先展开超大原图再缩成封面。
  final buffer = await ui.ImmutableBuffer.fromFilePath(path);
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  try {
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    // 最长边限制在封面预算内，宽高使用同一比例，不把纸面拉伸。
    final scale = math.min(
      1.0,
      512 / math.max(descriptor.width, descriptor.height),
    );
    codec = await descriptor.instantiateCodec(
      targetWidth: math.max(1, (descriptor.width * scale).round()),
      targetHeight: math.max(1, (descriptor.height * scale).round()),
    );
    return (await codec.getNextFrame()).image;
  } finally {
    codec?.dispose();
    descriptor?.dispose();
    buffer.dispose();
  }
}

/// 将低分辨率底图、嵌入图片、文字和简化后的笔迹合成为封面缓存，临时图像在完成后释放。
Future<void> _renderCover(_PreparedCover cover, String background) async {
  // 这里只载入封面所需小图，正式导出仍从原图和原笔迹重建。
  final page = await _decodeCoverImage(background);
  final recorder = ui.PictureRecorder();
  final size = ui.Size(page.width.toDouble(), page.height.toDouble());
  final canvas = ui.Canvas(recorder)
    ..clipRect(ui.Offset.zero & size)
    ..drawImage(page, ui.Offset.zero, ui.Paint());
  final ink = cover.ink!;
  try {
    for (final stroke in ink.strokes) {
      if (stroke.kind != StrokeKind.image ||
          stroke.imageAsset == null ||
          stroke.points.length < 4) {
        continue;
      }
      final asset = stroke.imageAsset!;
      ui.Image? image;
      try {
        image = await _decodeCoverImage(
          File(asset).isAbsolute ? asset : '${cover.directory}/$asset',
        );
        final p = stroke.points;
        final x = (p[1].x - p[0].x) * size.width,
            y = (p[1].y - p[0].y) * size.height;
        final width = math.sqrt(x * x + y * y);
        final vx = (p[3].x - p[0].x) * size.width,
            vy = (p[3].y - p[0].y) * size.height;
        canvas
          ..save()
          ..translate(p[0].x * size.width, p[0].y * size.height)
          ..rotate(math.atan2(y, x));
        canvas.drawImageRect(
          image,
          ui.Rect.fromLTWH(
            0,
            0,
            image.width.toDouble(),
            image.height.toDouble(),
          ),
          ui.Rect.fromLTWH(0, 0, width, math.sqrt(vx * vx + vy * vy)),
          ui.Paint()..filterQuality = ui.FilterQuality.low,
        );
        canvas.restore();
      } catch (_) {
        /* 单张附件损坏不阻止其余封面内容显示。 */
      } finally {
        image?.dispose();
      }
    }
    paintInkThumbnail(canvas, size, ink.strokes);
    // 结束记录后才可以转换图像；Picture 与 Image 的释放分别管理。
    final picture = recorder.endRecording();
    ui.Image? image;
    try {
      image = await picture.toImage(page.width, page.height);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File(cover.path).parent.create(recursive: true);
      // 先完成临时 PNG 写入再替换缓存文件，避免卡片读取半份图像。
      final temporary = File('${cover.path}.tmp');
      await temporary.writeAsBytes(bytes!.buffer.asUint8List(), flush: true);
      await temporary.rename(cover.path);
    } finally {
      image?.dispose();
      picture.dispose();
    }
  } finally {
    page.dispose();
  }
}

/// 原子替换索引；清理同一缓存目录里的旧位图，不触碰任何文稿文件。
Future<void> _finishCover(_PreparedCover cover) async {
  final temporary = File('${cover.metadataPath}.tmp');
  await temporary.writeAsString(jsonEncode(cover.metadata), flush: true);
  await temporary.rename(cover.metadataPath);
  final files = await File(cover.path).parent
      .list()
      .where((f) => f is File && f.path.endsWith('.png'))
      .cast<File>()
      .toList();
  if (files.length <= 64) return;
  final dated = await Future.wait(
    files.map((f) async => (f, (await f.stat()).modified)),
  );
  dated.sort((a, b) => a.$2.compareTo(b.$2));
  for (final entry in dated.take(dated.length - 64)) {
    if (entry.$1.path != cover.path) {
      try {
        await entry.$1.delete();
      } catch (_) {}
    }
  }
}
