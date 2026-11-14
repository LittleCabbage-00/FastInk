// 连续文稿的几何布局引擎。
//
// 本文件是整个滚动系统的基础层——它只做几何计算，不持有任何 Flutter 组件。
//
// ## 核心算法
//
// **前缀和布局**：所有页面垂直排列，每页的 Rect 在 build 时一次性算好
// 并存入 pages 列表。由于页面按 top 严格递增排列，滚动时可以用二分查找
// O(log n) 定位可见范围，而不是遍历全部页面。
//
// **等面积缩放**：不同宽高比的页面保持相同"纸面面积"，宽度按 √(ratio / refRatio)
// 缩放。选择平方根是因为面积 = width × height = width × (width / ratio)，
// 要让 width² / ratio 为常数，就得 width ∝ √ratio。这样横向 A4 比纵向 A4 宽约 √2
// 倍，而不是简单地保持同宽导致高度被压扁。
//
// **弹性越界**：elasticCamera 允许用户把内容拉出边界，但使用指数衰减函数
// 让越界阻力逐渐增大——近处跟手，远处"顶死"——模拟 iOS 橡皮筋效果。

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// 连续文稿的几何索引。
///
/// 页面位置只存在于文稿坐标系中；[camera] 负责把文稿坐标换算为屏幕坐标。
/// 前缀位置在布局建立时一次算好，滚动过程中可用二分查找定位可见页面，
/// 不需要创建数千个页面组件。
class DocumentViewportLayout {
  /// 保存已算好的视口、页面矩形与整体边界；通过 build 工厂统一建立几何约束。
  DocumentViewportLayout._({
    required this.viewport,
    required this.pages,
    required this.documentBounds,
    required this.signature,
  });

  /// 根据视口尺寸和逐页宽高比建立连续文稿布局；页面矩形使用同一文稿坐标系，不按当前页重置基准。
  factory DocumentViewportLayout.build({
    required Size viewport,
    required List<double> aspectRatios,
    required double referenceAspectRatio,
    double pageGap = 10,
    double horizontalPadding = 32,
    double verticalPadding = 10,
  }) {
    final double safeRatio = _validRatio(referenceAspectRatio);
    final double availableWidth = math.max(
      120,
      viewport.width - horizontalPadding * 2,
    );
    final double availableHeight = math.max(
      120,
      viewport.height - verticalPadding * 2,
    );
    // 所有页面按相同纸面面积建立物理尺度。横向 A4 因此会比纵向 A4
    // 宽约 √2，而不是错误地保持同宽、仅把高度压扁。
    final List<double> ratios = aspectRatios
        .map((double value) => _validRatio(value, fallback: safeRatio))
        .toList(growable: false);

    // ---------- 等面积布局的关键推导 ----------
    // 目标：让所有页面保持相同的"纸面面积"，与宽高比无关。
    //
    // 设 basePageWidth 为基准宽度（refRatio 对应的宽度），则：
    //   某页宽度 = basePageWidth * √(ratio / refRatio)
    //   某页高度 = 宽度 / ratio
    //
    // 验证：面积 = width² / ratio
    //        = basePageWidth² * (ratio / refRatio) / ratio
    //        = basePageWidth² / refRatio    ← 与 ratio 无关，常数！
    //
    // maximumWidthFactor 记录所有页面中宽度相对于 basePageWidth 的最大倍率，
    // 用于保证最宽的页面也不超出 availableWidth。
    final double maximumWidthFactor = ratios.fold<double>(
      1,
      (double current, double ratio) =>
          math.max(current, math.sqrt(ratio / safeRatio)),
    );
    // maximumHeightPerBaseWidth 记录所有页面中 (高度 / basePageWidth) 的最大值，
    // 用于保证最高的页面也不超出 availableHeight。
    final double maximumHeightPerBaseWidth = ratios.fold<double>(
      1 / safeRatio,
      (double current, double ratio) =>
          math.max(current, 1 / math.sqrt(ratio * safeRatio)),
    );
    // 100% 时整张纸保持在视口内；适宽只改变相机，不重排页面。
    // 取三个约束的最小值：最大宽度 1100px、视口宽度约束、视口高度约束。
    final double basePageWidth = math.min(
      1100,
      math.min(
        availableWidth / maximumWidthFactor,
        availableHeight / maximumHeightPerBaseWidth,
      ),
    );
    // 逐页计算 Rect：宽度随宽高比变化，水平居中，垂直从上到下依次堆叠。
    final List<Rect> pages = <Rect>[];
    double top = verticalPadding;
    double documentLeft = viewport.width / 2;
    double documentRight = viewport.width / 2;
    int hash = Object.hash(
      viewport.width.round(),
      viewport.height.round(),
      aspectRatios.length,
      (safeRatio * 10000).round(),
    );
    for (final double ratio in ratios) {
      // √(ratio / refRatio) 确保面积恒定：详见上方推导。
      final double width = basePageWidth * math.sqrt(ratio / safeRatio);
      final double height = width / ratio;
      final double left = (viewport.width - width) / 2;
      pages.add(Rect.fromLTWH(left, top, width, height));
      documentLeft = math.min(documentLeft, left);
      documentRight = math.max(documentRight, left + width);
      top += height + pageGap;
      hash = Object.hash(hash, (ratio * 10000).round());
    }
    final double bottom = pages.isEmpty
        ? verticalPadding
        : pages.last.bottom + verticalPadding;
    return DocumentViewportLayout._(
      viewport: viewport,
      pages: pages,
      documentBounds: Rect.fromLTRB(documentLeft, 0, documentRight, bottom),
      signature: hash,
    );
  }

  /// viewport：当前可见区域尺寸，单位逻辑像素。
  final Size viewport;

  /// pages：按当前页序保存的页面描述集合，实际位图与笔迹另行按需读取。
  final List<Rect> pages;

  /// documentBounds：整本文稿的布局坐标边界，用于相机约束。
  final Rect documentBounds;

  /// signature：布局内容签名，用于识别需要重建的几何变化。
  final int signature;

  /// 返回文稿布局的统一基准宽度，单位逻辑像素。
  double get pageWidth => documentBounds.width;

  /// 将指定页面的文稿矩形通过 camera 映射到屏幕坐标，供可见性和浮层定位使用。
  Rect screenPageRect(int index, Matrix4 camera) {
    final Rect page = pages[index];
    final double scale = camera.getMaxScaleOnAxis();
    return Rect.fromLTWH(
      page.left * scale + camera[12],
      page.top * scale + camera[13],
      page.width * scale,
      page.height * scale,
    );
  }

  /// 返回需要创建的首尾页（尾页为闭区间）。
  ///
  /// [cacheScreens] 控制缓冲区大小：在实际可见区域上下各扩展若干屏的高度，
  /// 让即将进入视口的页面提前创建，减少滚动时的白闪。
  (int, int) visibleRange(Matrix4 camera, {double cacheScreens = 0.75}) {
    if (pages.isEmpty) return (0, -1);
    final double scale = camera.getMaxScaleOnAxis();
    // margin: 在视口上下各扩展 cacheScreens 屏作为缓冲。
    final double margin = viewport.height * cacheScreens;
    // 将屏幕坐标变换为世界（文稿）坐标：
    // 屏幕 y = 世界 y * scale + camera[13]，因此 世界 y = (屏幕 y - camera[13]) / scale
    final double worldTop = (-camera[13] - margin) / scale;
    final double worldBottom = (viewport.height - camera[13] + margin) / scale;
    // 二分查找：找到第一个 bottom >= worldTop 的页面（即底部进入缓冲区的第一页）
    // 和最后一个 top <= worldBottom 的页面（即顶部进入缓冲区的最后一页）。
    final int first = _firstPageWhoseBottomReaches(worldTop);
    final int last = _lastPageWhoseTopPrecedes(worldBottom);
    return (first.clamp(0, pages.length - 1), last.clamp(0, pages.length - 1));
  }

  /// 计算视口中心点落在哪一页上。
  ///
  /// 先用二分找到最后一个 top <= 中心点的页面（candidate）。
  /// 如果中心点落在该页内部，直接返回；
  /// 如果落在两页之间的空白间隙中，比较距哪页更近就返回哪页。
  int pageAtViewportCenter(Matrix4 camera) {
    if (pages.isEmpty) return 0;
    final double scale = camera.getMaxScaleOnAxis();
    // 屏幕中心 → 世界坐标
    final double worldY = (viewport.height / 2 - camera[13]) / scale;
    final int candidate = _lastPageWhoseTopPrecedes(
      worldY,
    ).clamp(0, pages.length - 1);
    // candidate 的 bottom >= worldY 说明中心点在该页内部；或者已是最后一页。
    if (worldY <= pages[candidate].bottom || candidate == pages.length - 1) {
      return candidate;
    }
    // 中心点落在 candidate 和 candidate+1 之间的间隙中，选更近的。
    final double previousDistance = worldY - pages[candidate].bottom;
    final double nextDistance = pages[candidate + 1].top - worldY;
    return nextDistance < previousDistance ? candidate + 1 : candidate;
  }

  /// 计算目标页在视口中的相机矩阵；可保留当前比例，最终位置仍受文稿边界约束。
  Matrix4 cameraForPage(
    Matrix4 current,
    int index, {
    double topInset = 10,
    double maximumScale = 5,
  }) {
    final Matrix4 target = Matrix4.copy(current);
    // 必须先把倍率夹到合法区间，再用夹过之后的倍率算位移。否则倍率在
    // constrainCamera 里被改小，而位移还是按原倍率算的，落点会偏出
    // pages[index].top * (原倍率 − 实际倍率)，翻页直接跳到别的页上。
    final double scale = target.getMaxScaleOnAxis().clamp(1.0, maximumScale);
    target[0] = scale;
    target[5] = scale;
    target[13] = topInset - pages[index].top * scale;
    return constrainCamera(target, maximumScale: maximumScale);
  }

  /// 硬约束相机：将缩放和位移限制在合法范围内。
  ///
  /// 水平方向：如果文档比视口窄则居中，否则不允许露出文档边界之外。
  /// 垂直方向：同理，但不允许露出文档顶部以上或底部以下的空白。
  /// 缩放：限制在 [minimumScale, maximumScale] 之间。
  Matrix4 constrainCamera(
    Matrix4 value, {
    double minimumScale = 1,
    double maximumScale = 5,
  }) {
    final Matrix4 result = Matrix4.copy(value);
    final double scale = result.getMaxScaleOnAxis().clamp(
      minimumScale,
      maximumScale,
    );
    result[0] = scale;
    result[5] = scale;
    result[12] = _constrainHorizontal(result[12], scale);
    result[13] = _constrainVertical(result[13], scale);
    return result;
  }

  /// 弹性相机：允许越界但使用指数衰减增加阻力。
  ///
  /// 工作原理：
  /// 1. 先调用 [constrainCamera] 得到合法位置 `legal`。
  /// 2. 计算原始值与合法值的差值 `overflow`——即越界量。
  /// 3. 使用 `pullLimit * (1 - e^(-|overflow| / pullLimit))` 将越界量压缩：
  ///    - 当 |overflow| 很小时，指数函数近似线性，用户感觉跟手。
  ///    - 当 |overflow| 增大，函数趋近 pullLimit，阻力越来越大。
  ///    - 永远不会超过 pullLimit，防止内容被拉出太远。
  /// 4. 只对垂直方向做弹性处理；水平方向永远硬约束。
  Matrix4 elasticCamera(
    Matrix4 value, {
    double minimumScale = 1,
    double maximumScale = 5,
    double? maximumPull,
  }) {
    final Matrix4 legal = constrainCamera(
      value,
      minimumScale: minimumScale,
      maximumScale: maximumScale,
    );
    final double overflow = value[13] - legal[13];
    if (overflow.abs() < 0.01) return legal;
    final Matrix4 result = Matrix4.copy(legal);
    // 仅文稿顶部和底部存在橡皮筋；横向永远硬约束。
    // 拉伸上限随视口变化，避免固定 46px 在大屏上很快“顶死”。指数曲线的
    // 斜率连续，越界初段跟手，随后才逐渐增加阻力。
    final double pullLimit =
        maximumPull ?? (viewport.height * 0.14).clamp(72.0, 120.0);
    final double resisted =
        pullLimit * (1 - math.exp(-overflow.abs() / pullLimit));
    result[13] = legal[13] + overflow.sign * resisted;
    return result;
  }

  /// 水平约束：文档窄于视口时居中，否则限制在左右边界内。
  double _constrainHorizontal(double translation, double scale) {
    final double width = documentBounds.width * scale;
    if (width <= viewport.width) {
      return (viewport.width - width) / 2 - documentBounds.left * scale;
    }
    final double minimum = viewport.width - documentBounds.right * scale;
    final double maximum = -documentBounds.left * scale;
    return translation.clamp(minimum, maximum);
  }

  /// 垂直约束：文档矮于视口时居中，否则限制在上下边界内。
  double _constrainVertical(double translation, double scale) {
    final double height = documentBounds.height * scale;
    if (height <= viewport.height) {
      return (viewport.height - height) / 2 - documentBounds.top * scale;
    }
    final double minimum = viewport.height - documentBounds.bottom * scale;
    final double maximum = -documentBounds.top * scale;
    return translation.clamp(minimum, maximum);
  }

  /// 二分查找：返回第一个 bottom >= y 的页面索引。
  ///
  /// 本质是在已排序的 bottom 数组上做 lower_bound。
  /// 循环不变量：答案在 [low, high) 区间内。
  /// 每次比较 middle 页的 bottom 与目标 y：
  /// - 若 bottom < y，说明 middle 页完全在 y 上方，答案在右半。
  /// - 否则，middle 页可能是答案，收缩 high。
  /// 最终 low == high 就是答案。
  int _firstPageWhoseBottomReaches(double y) {
    int low = 0;
    int high = pages.length;
    while (low < high) {
      final int middle = (low + high) >> 1;
      if (pages[middle].bottom < y) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low;
  }

  /// 二分查找：返回最后一个 top <= y 的页面索引。
  ///
  /// 本质是在已排序的 top 数组上做 upper_bound 再减一。
  /// 循环不变量：答案在 [low, high) 内。
  /// 每次比较 middle 页的 top 与目标 y：
  /// - 若 top <= y，middle 页的顶部在 y 上方（或恰好在 y），可能是答案，搜索右半。
  /// - 否则 middle 页完全在 y 下方，收缩 high。
  /// 最终 low - 1 就是答案（若 low == 0 则返回 -1 表示没有找到）。
  int _lastPageWhoseTopPrecedes(double y) {
    int low = 0;
    int high = pages.length;
    while (low < high) {
      final int middle = (low + high) >> 1;
      if (pages[middle].top <= y) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low - 1;
  }

  /// 验证宽高比：拒绝 NaN、Infinity、极端值，防止布局计算出错。
  /// fallback 默认 0.707 ≈ 1/√2，即 A4 纵向比例。
  static double _validRatio(double value, {double fallback = 0.707}) =>
      value.isFinite && value > 0.1 && value < 10 ? value : fallback;
}
