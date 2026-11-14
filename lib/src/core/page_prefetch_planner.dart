// ---------------------------------------------------------------------------
// PDF 邻页预取规划器。
//
// 核心思路：通过观察用户的翻页节奏，自适应地决定预取多少页。
//
// ## 为什么用 EMA（指数移动平均）？
//
// 用户翻页间隔时快时慢：快速连翻时间隔 ~200ms，细读时可能 5s+。
// 如果只用最近一次间隔来决定预取量，会因为单次异常值导致预取窗口
// 剧烈波动（比如偶尔停顿一下就预取很多页，快速连翻时又不预取）。
//
// EMA = α * 新值 + (1 - α) * 历史均值，α = 0.35
// 效果：新数据对均值的影响被"稀释"，预取窗口平滑过渡。
// - 连续快翻 → EMA 逐渐降低 → 只预取 1 页，节省内存。
// - 开始细读 → EMA 逐渐升高 → 预取 2-N 页，提前加载。
// - 突然停顿 → 不会因为单次长间隔就猛增预取量。
//
// ## 跳页 vs 顺序翻页
//
// 跳页（jump > 1）通常意味着用户在搜索内容，跳到的那页才是重点，
// 邻页可能不需要。因此跳页时最多只预取 1 页，且回看页也省去。
// ---------------------------------------------------------------------------

/// 按最近的翻页间隔规划 PDF 邻页预取。当前页由加载流程单独处理。
class PagePrefetchPlanner {
  /// _previousIndex：预取规划器上次观察到的页索引，用于推断阅读方向。
  int? _previousIndex;

  /// _previousTurn：上次翻页时间，用于估计停留时长。
  DateTime? _previousTurn;

  /// _dwellMs：平滑后的页面停留毫秒数，快速翻页时用于抑制预取。
  double? _dwellMs;

  /// 规划当前页之后需要预取的页面索引列表。
  ///
  /// [direction]：1 = 向后翻（+），-1 = 向前翻（-）。
  /// [maximumAhead]：最大向前预取页数，由外部根据内存策略限制。
  /// [now]：当前时间，用于计算翻页间隔。
  List<int> plan({
    required int index,
    required int pageCount,
    required int direction,
    required int maximumAhead,
    required DateTime now,
  }) {
    if (pageCount <= 0 || maximumAhead <= 0) return const <int>[];
    final int boundedIndex = index.clamp(0, pageCount - 1);

    // ---- 计算跳页距离 ----
    // jump = 0 表示首次翻页或未记录，jump = 1 是顺序翻页，> 1 是跳页。
    final int jump = _previousIndex == null
        ? 0
        : (boundedIndex - _previousIndex!).abs();

    // ---- 更新 EMA ----
    // EMA 公式：newEma = α * 新观测值 + (1 - α) * 旧 EMA
    // α = 0.35 意味着新值占 35% 权重，历史占 65%。
    // 这个值平衡了响应速度和平滑度：太高会让 EMA 跟着单次波动跑，
    // 太低会让 EMA 对用户行为变化反应迟钝。
    // clamp(1, 30000) 防止时钟回拨或极端停顿导致的异常值。
    if (_previousTurn != null && jump > 0) {
      final double elapsed = now
          .difference(_previousTurn!)
          .inMilliseconds
          .clamp(1, 30000)
          .toDouble();
      _dwellMs = _dwellMs == null ? elapsed : 0.35 * elapsed + 0.65 * _dwellMs!;
    }
    _previousIndex = boundedIndex;
    _previousTurn = now;

    // ---- 根据 EMA 决定预取页数 ----
    // 三档策略：
    // - 跳页 / 首次 / 快翻（EMA < 500ms）：只预取 1 页——用户在快速浏览，别浪费带宽。
    // - 中速（500-900ms）：预取 2 页——用户在正常阅读，适度提前加载。
    // - 慢翻（> 900ms）：预取最多 limit 页——用户在细读，可以大方地提前加载。
    final int limit = maximumAhead.clamp(0, 6);
    final int ahead = jump > 1 || _dwellMs == null || _dwellMs! < 500
        ? limit.clamp(0, 1)
        : _dwellMs! < 900
        ? limit.clamp(0, 2)
        : limit;

    // ---- 构建预取列表 ----
    // step 控制预取方向：跟随用户的翻页方向。
    final int step = direction < 0 ? -1 : 1;
    return <int>[
      for (int offset = 1; offset <= ahead; offset++)
        if (boundedIndex + step * offset >= 0 &&
            boundedIndex + step * offset < pageCount)
          boundedIndex + step * offset,
      // 顺序翻页时保留一张回看页；跳页时省去这项预取。
      // 原因：顺序翻页用户经常会回翻一格，预取回看页避免白屏；
      // 跳页时回看页距离较远，用户不太可能精确回跳。
      if (jump == 1 &&
          boundedIndex - step >= 0 &&
          boundedIndex - step < pageCount)
        boundedIndex - step,
    ];
  }
}
