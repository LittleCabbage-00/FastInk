part of '../../app/fastink_app.dart';

extension _FastInkToolbarZoom on _FastInkHomeState {
  /// 局部订阅相机矩阵展示百分比及缩放按钮，避免仅倍率变化就刷新整套导航。
  Widget _zoomIndicator() => ValueListenableBuilder<Matrix4>(
    valueListenable: _viewport.zoomController,
    builder: (BuildContext context, Matrix4 matrix, Widget? child) {
      final double scale = matrix.getMaxScaleOnAxis();
      final int percent = (scale * 100).round();
      final double defaultScale = _defaultPageFitScale();
      final bool atDefaultScale = (scale - defaultScale).abs() < 0.025;
      final String scaleLabel = atDefaultScale
          ? _settings.defaultPageFit == 'width'
                ? tr('适宽', 'Fit width')
                : tr('整页', 'Fit page')
          : '$percent%';
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          IconButton(
            tooltip: tr('缩小（Ctrl + -）', 'Zoom out (Ctrl + -)'),
            visualDensity: VisualDensity.compact,
            onPressed: scale > 1.01 ? () => _stepZoom(-0.25) : null,
            icon: const Icon(Icons.remove_rounded, size: 19),
          ),
          Tooltip(
            message: tr(
              '恢复默认显示比例（Ctrl+0）；滚轮上下平移，Shift+滚轮左右平移',
              'Restore the default fit (Ctrl+0); wheel pans vertically, Shift+wheel pans horizontally',
            ),
            child: SizedBox(
              width: math.max(
                74,
                MediaQuery.textScalerOf(context).scale(60) + 14,
              ),
              child: TextButton(
                onPressed: _applyDefaultPageFit,
                style: TextButton.styleFrom(
                  minimumSize: const Size(64, 38),
                  padding: const EdgeInsets.symmetric(horizontal: 7),
                ),
                child: Text(
                  scaleLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: tr('放大（Ctrl + +）', 'Zoom in (Ctrl + +)'),
            visualDensity: VisualDensity.compact,
            onPressed: scale < _settings.maximumZoom - 0.01
                ? () => _stepZoom(0.25)
                : null,
            icon: const Icon(Icons.add_rounded, size: 19),
          ),
        ],
      );
    },
  );

  /// 按当前页和可用视口计算默认适配倍数，遵守最大缩放限制。
  double _defaultPageFitScale() {
    if (_settings.defaultPageFit == 'page' ||
        _canvasViewport.isEmpty ||
        _pageViewportRect.isEmpty) {
      return 1;
    }
    return ((_canvasViewport.width - 24) / _pageViewportRect.width).clamp(
      1.0,
      _settings.maximumZoom,
    );
  }
}
