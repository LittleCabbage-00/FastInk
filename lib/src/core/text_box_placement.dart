import 'dart:math' as math;
import 'package:flutter/painting.dart';

/// 优先寻找附近空白区域，页面已满时选择遮挡最少的位置。
Rect placeTextBox(Rect preferred, Rect area, List<Rect> occupied) {
  if (area.isEmpty) return preferred;
  // 候选宽度先限制在可用区域内，单位页面逻辑像素。
  final width = math.min(preferred.width, area.width);
  // 候选高度与区域统一尺度，避免仅改变锚点仍越出页面。
  final height = math.min(preferred.height, area.height);
  // 按候选左上角生成保持原宽高的文本矩形，使用页面逻辑坐标。
  Rect at(double x, double y) => Rect.fromLTWH(
    x.clamp(area.left, area.right - width),
    y.clamp(area.top, area.bottom - height),
    width,
    height,
  );
  final initial = at(preferred.left, preferred.top);
  // 只保留与当前可放置区域相交的占用框，减少后续无效相交检测。
  final obstacles = occupied.where((r) => r.overlaps(area)).toList();
  // 判断候选矩形是否避开所有已有内容边界。
  bool clear(Rect candidate) => !obstacles.any(candidate.overlaps);
  if (clear(initial)) return initial;
  // 横向候选取原位置、边缘和障碍边界，不逐像素搜索。
  final xs = <double>{initial.left, area.left, area.right - width};
  // 纵向候选与横向组成有限笛卡尔积，控制避让搜索量。
  final ys = <double>{initial.top, area.top, area.bottom - height};
  for (final r in obstacles) {
    xs.addAll([r.right + 2, r.left - width - 2]);
    ys.addAll([r.bottom + 2, r.top - height - 2]);
  }
  // 按到原位置的距离排列候选坐标，优先找到移动较小的空白区域。
  List<double> nearest(Set<double> values, double start) =>
      values.toList()
        ..sort((a, b) => (a - start).abs().compareTo((b - start).abs()));
  final candidates =
      [
        for (final x in nearest(xs, initial.left).take(12))
          for (final y in nearest(ys, initial.top).take(16)) at(x, y),
      ]..sort(
        (a, b) => (a.topLeft - initial.topLeft).distanceSquared.compareTo(
          (b.topLeft - initial.topLeft).distanceSquared,
        ),
      );
  var best = initial;
  // 最小重叠面积的回退指标；普通放置与必须全文避让的适配流程语义不同。
  double bestOverlap = double.infinity;
  for (final candidate in candidates) {
    double overlap = 0;
    for (final obstacle in obstacles) {
      final intersection = candidate.intersect(obstacle);
      if (!intersection.isEmpty) {
        overlap += intersection.width * intersection.height;
      }
    }
    if (overlap == 0) return candidate;
    if (overlap < bestOverlap) {
      bestOverlap = overlap;
      best = candidate;
    }
  }
  return best;
}

/// 按真实字体与最大宽度测量文本，返回自适应尺寸；结果只用于布局，不截断源文。
Size measureAdaptiveText(String text, TextStyle style, double maximumWidth) {
  final painter = TextPainter(
    text: TextSpan(text: text.isEmpty ? ' ' : text, style: style),
    textDirection: TextDirection.ltr,
    textWidthBasis: TextWidthBasis.longestLine,
  )..layout(maxWidth: math.max(40, maximumWidth));
  final size = Size(
    (painter.width + 4).clamp(40, math.max(40, maximumWidth)),
    painter.height,
  );
  painter.dispose();
  return size;
}

/// 适合页面后的实际排版结果；框高来自完整文字排版，不裁切或省略正文。
class TextBoxFit {
  /// 保存全文可容纳的页面边界和字号，返回给属性窗口统一应用。
  const TextBoxFit(this.bounds, this.fontSize);

  /// bounds：文本适配后完整容纳全文的页面逻辑矩形，不能只容纳可见片段。
  final Rect bounds;

  /// fontSize：文字排版字号，单位所在布局的逻辑像素；持久笔迹的归一化字号另用 textSize。
  final double fontSize;

  /// 常规页面比例下低于 8 px 已明显偏小；只提示，不阻止用户应用。
  bool get hardToRead => fontSize < 8;
}

/// 用保守占用网格寻找连续空白矩形。与字迹相交的单元格整格禁用，
/// 不会把笔画包围框内部误认为空白；网格最多 96 × 96，与笔迹数量解耦。
/// 直方图单调栈在线性扫描中提取候选，避免逐笔拆分矩形造成组合爆炸。
List<Rect> _emptyTextRegions(Rect area, List<Rect> obstacles) {
  // 占用网格边长自适应，最长方向约 96 格，避免大页面生成百万级网格。
  final cell = math.max(8.0, math.max(area.width, area.height) / 96);
  final columns = math.max(1, (area.width / cell).ceil());
  final rows = math.max(1, (area.height / cell).ceil());
  // 实际单元宽高按整行列均分，索引换算与矩形还原必须使用同一 dx/dy。
  final dx = area.width / columns, dy = area.height / rows;
  // 保守标记每格是否被已有内容占用，不能把擦过边缘的格子误当空白。
  final blocked = List<bool>.filled(columns * rows, false);
  for (final obstacle in obstacles) {
    final clipped = obstacle.intersect(area);
    if (clipped.isEmpty) continue;
    final left = ((clipped.left - area.left) / dx).floor().clamp(0, columns);
    final right = ((clipped.right - area.left) / dx).ceil().clamp(0, columns);
    final top = ((clipped.top - area.top) / dy).floor().clamp(0, rows);
    final bottom = ((clipped.bottom - area.top) / dy).ceil().clamp(0, rows);
    for (var y = top; y < bottom; y++) {
      for (var x = left; x < right; x++) {
        blocked[y * columns + x] = true;
      }
    }
  }
  // 直方图记录各列连续空白高度，用单调栈查找大空白矩形。
  final heights = List<int>.filled(columns, 0);
  final candidates = <Rect>[];
  for (var y = 0; y < rows; y++) {
    // 栈元素保存候选起列和高度，弹栈时一次求出最大连续矩形。
    final stack = <(int, int)>[];
    for (var x = 0; x <= columns; x++) {
      final height = x == columns
          ? 0
          : (heights[x] = blocked[y * columns + x] ? 0 : heights[x] + 1);
      var start = x;
      while (stack.isNotEmpty && stack.last.$2 > height) {
        final entry = stack.removeLast();
        start = entry.$1;
        final rect = Rect.fromLTRB(
          area.left + start * dx,
          area.top + (y + 1 - entry.$2) * dy,
          area.left + x * dx,
          area.top + (y + 1) * dy,
        ).deflate(.5);
        if (rect.width >= 40 && rect.height >= 1) candidates.add(rect);
      }
      if (height > 0 && (stack.isEmpty || stack.last.$2 < height)) {
        stack.add((start, height));
      }
    }
  }
  candidates.sort((a, b) => (b.width * b.height).compareTo(a.width * a.height));
  final regions = <Rect>[];
  for (final rect in candidates) {
    if (regions.any(
      (r) =>
          r.left <= rect.left &&
          r.top <= rect.top &&
          r.right >= rect.right &&
          r.bottom >= rect.bottom,
    )) {
      continue;
    }
    regions.add(rect);
    // 限制完整文字排版的次数；最终仍逐项校验与原始占用框不相交。
    if (regions.length == 24) break;
  }
  return regions;
}

/// 先找空白再排版：优先保留当前字号，放不下时缩小并重排框宽。
/// 无法容纳全文时返回 null，调用方必须提示，不能退回覆盖字迹的位置。
/// 多段长文排版期间定期让出界面线程，过期的弹窗请求可及时取消。
Future<TextBoxFit?> fitTextBoxToPage({
  required String text,
  required TextStyle style,
  required TextAlign textAlign,
  required Rect preferred,
  required Size pageSize,
  required List<Rect> occupied,
  bool Function()? isCurrent,
}) async {
  if (pageSize.isEmpty || text.trim().isEmpty) return null;
  // 左右页边距随页面宽度变化，保持文本不贴纸边。
  final horizontalMargin = math.max(12.0, pageSize.width * .04);
  // 上下边距与横向独立计算，避免高窄页面留出不合理巨大空隙。
  final verticalMargin = math.max(8.0, pageSize.height * .04);
  final area = Rect.fromLTRB(
    horizontalMargin,
    verticalMargin,
    pageSize.width - horizontalMargin,
    pageSize.height - verticalMargin,
  );
  if (area.width < 40 || area.height < 1) return null;
  final obstacles = occupied
      .where((r) => !r.isEmpty && r.overlaps(area))
      .map((r) => r.inflate(2))
      .toList();
  // 空白候选先由几何筛选，再用全文 TextPainter 验证，不按字数估算高度。
  final regions = _emptyTextRegions(area, obstacles);
  final requested = style.fontSize ?? 12;
  // 字号最大值是原请求上限；适配只缩小，不把用户文字擅自放大。
  final maximum = requested.isFinite ? requested.clamp(1.0, 512.0) : 12.0;
  // 计算分片计时器，长搜索需让出事件循环以保持界面响应。
  final watch = Stopwatch()..start();
  TextBoxFit? best;
  // 按候选宽度与字号进行全文排版，返回所需高度以验证是否完整容纳。
  double heightAt(double width, double font) {
    final painter = TextPainter(
      text: TextSpan(
        text: text.trim(),
        style: style.copyWith(fontSize: font),
      ),
      textAlign: textAlign,
      textDirection: TextDirection.ltr,
      textWidthBasis: TextWidthBasis.parent,
    )..layout(maxWidth: width);
    final height = painter.height;
    painter.dispose();
    return height;
  }

  for (final region in regions) {
    if (isCurrent != null && !isCurrent()) return null;
    if (watch.elapsedMilliseconds >= 8) {
      await Future<void>.delayed(Duration.zero);
      watch.reset();
      if (isCurrent != null && !isCurrent()) return null;
    }
    // 向下取整与输入框显示精度一致，避免“应用”时四舍五入后再次溢出。
    final width = (region.width * 10).floor() / 10;
    if (heightAt(width, best?.fontSize ?? 1) > region.height) continue;
    // 二分搜索当前候选能容纳全文的最大字号，已知更好结果作为下界。
    double low = best?.fontSize ?? 1, high = maximum;
    if (heightAt(width, maximum) <= region.height) {
      low = maximum;
    } else {
      for (var i = 0; i < 14; i++) {
        if (watch.elapsedMilliseconds >= 8) {
          await Future<void>.delayed(Duration.zero);
          watch.reset();
          if (isCurrent != null && !isCurrent()) return null;
        }
        final middle = (low + high) / 2;
        if (heightAt(width, middle) <= region.height) {
          low = middle;
        } else {
          high = middle;
        }
      }
    }
    // 字号向下取整到百分位，避免显示四舍五入后重新溢出空白区域。
    final font = (low * 100).floor() / 100;
    final height = heightAt(width, font);
    final rect = Rect.fromLTWH(
      preferred.left.clamp(region.left, region.right - width),
      preferred.top.clamp(region.top, region.bottom - height),
      width,
      height,
    );
    if (obstacles.any(rect.overlaps)) continue;
    // 字号相同时用距原锚点的平方距离排序，尽量少移动文字。
    final distance = (rect.topLeft - preferred.topLeft).distanceSquared;
    if (best == null ||
        font > best.fontSize ||
        (font == best.fontSize &&
            distance <
                (best.bounds.topLeft - preferred.topLeft).distanceSquared)) {
      best = TextBoxFit(rect, font);
    }
  }
  return best;
}
