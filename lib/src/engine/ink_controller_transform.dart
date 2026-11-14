part of 'ink_canvas.dart';

extension InkControllerTransform on InkController {
  /// 把最新手势点应用到选择对象，始终以手势起点快照计算，避免连续缩放旋转产生累积误差。
  void updateSelectionTransform(InkPoint point, Size size) {
    final InkPoint? start = _transformStart;
    final Rect? bounds = _transformBounds;
    final SelectionTransform? transform = _selectionTransform;
    if (start == null || bounds == null || transform == null) return;

    if (transform == SelectionTransform.move) {
      final double minDx = -bounds.left;
      final double maxDx = 1 - bounds.right;
      final double minDy = -bounds.top;
      final double maxDy = 1 - bounds.bottom;
      // 超大导入对象或文本框也必须可移动；至少保留一侧边缘可达，
      // 避免构造上下界倒置的 clamp 区间。
      final double dx = (point.x - start.x).clamp(
        math.min(minDx, maxDx),
        math.max(minDx, maxDx),
      );
      final double dy = (point.y - start.y).clamp(
        math.min(minDy, maxDy),
        math.max(minDy, maxDy),
      );
      for (final MapEntry<InkStroke, List<InkPoint>> entry
          in _transformOrigin.entries) {
        entry.key.points
          ..clear()
          ..addAll(
            entry.value.map(
              (InkPoint original) =>
                  InkPoint(original.x + dx, original.y + dy, original.pressure),
            ),
          );
      }
    } else if (transform == SelectionTransform.scale) {
      final double width = math.max(0.0001, bounds.width);
      final double height = math.max(0.0001, bounds.height);
      // 横纵共用缩放系数；笔宽使用屏幕单位，不随选区缩放。
      final double factor = math
          .max((point.x - bounds.left) / width, (point.y - bounds.top) / height)
          .clamp(
            0.01,
            math.max(
              0.01,
              math.min((1 - bounds.left) / width, (1 - bounds.top) / height),
            ),
          );
      for (final MapEntry<InkStroke, List<InkPoint>> entry
          in _transformOrigin.entries) {
        entry.key.points
          ..clear()
          ..addAll(
            entry.value.map(
              (InkPoint original) => InkPoint(
                bounds.left + (original.x - bounds.left) * factor,
                bounds.top + (original.y - bounds.top) * factor,
                original.pressure,
              ),
            ),
          );
      }
    } else {
      // 在纸张像素坐标中旋转；归一化坐标会受纸张纵横比影响。
      final Offset center = bounds.center;
      final double angle =
          math.atan2(
            point.y * size.height - center.dy * size.height,
            point.x * size.width - center.dx * size.width,
          ) -
          _transformStartAngle;
      final double cosine = math.cos(angle);
      final double sine = math.sin(angle);
      final Map<InkStroke, List<InkPoint>> transformed =
          <InkStroke, List<InkPoint>>{};
      double left = double.infinity;
      double top = double.infinity;
      double right = double.negativeInfinity;
      double bottom = double.negativeInfinity;
      for (final MapEntry<InkStroke, List<InkPoint>> entry
          in _transformOrigin.entries) {
        final List<InkPoint> points = entry.value.map((InkPoint original) {
          final double dx = (original.x - center.dx) * size.width;
          final double dy = (original.y - center.dy) * size.height;
          final InkPoint result = InkPoint(
            center.dx + (dx * cosine - dy * sine) / size.width,
            center.dy + (dx * sine + dy * cosine) / size.height,
            original.pressure,
          );
          left = math.min(left, result.x);
          top = math.min(top, result.y);
          right = math.max(right, result.x);
          bottom = math.max(bottom, result.y);
          return result;
        }).toList();
        transformed[entry.key] = points;
      }
      // 将选区限制在纸面内，保留原旋转角度。
      final double correctionX = left < 0
          ? -left
          : right > 1
          ? 1 - right
          : 0;
      final double correctionY = top < 0
          ? -top
          : bottom > 1
          ? 1 - bottom
          : 0;
      for (final MapEntry<InkStroke, List<InkPoint>> entry
          in transformed.entries) {
        entry.key.points
          ..clear()
          ..addAll(
            entry.value.map(
              (InkPoint point) => InkPoint(
                point.x + correctionX,
                point.y + correctionY,
                point.pressure,
              ),
            ),
          );
      }
    }
    _selectionChangedDuringDrag = true;
    for (final stroke in selectedStrokes) {
      _eraserBounds.remove(stroke);
    }
    _committedRenderCache.invalidate(selectedStrokes);
    _committedRevision.value++;
    _selectionChanged(notifyToolbar: false);
  }

  /// 结束选区变换；有有效改动时提交一次历史，清理手势原点状态。
  void finishSelectionTransform() {
    if (_selectionTransform == null) return;
    _selectionTransform = null;
    _transformStart = null;
    _transformBounds = null;
    _transformOrigin.clear();
    _selectionChanged();
    if (_selectionChangedDuringDrag) {
      _historyTransactionChanged = true;
      finishHistoryTransaction();
      onCommitted();
    } else {
      finishHistoryTransaction(commit: false);
    }
    _selectionChangedDuringDrag = false;
  }

  /// 按当前类型过滤开关选择本页所有可选对象。
  void selectAll() {
    selectedStrokes
      ..clear()
      ..addAll(strokes.where(canSelectStroke));
    lassoPoints.clear();
    _selectionChanged();
  }

  /// 围绕联合选区中心旋转选中对象，angle 使用弧度，作为一次可撤销编辑。
  void rotateSelection(double angle) {
    final Rect? bounds = selectionBounds;
    if (bounds == null) return;
    final _InkHistorySnapshot before = _captureHistory(selectedStrokes);
    final Offset center = bounds.center;
    final double cosine = math.cos(angle);
    final double sine = math.sin(angle);
    for (final InkStroke stroke in selectedStrokes) {
      final List<InkPoint> original = List<InkPoint>.of(stroke.points);
      stroke.points
        ..clear()
        ..addAll(
          original.map((InkPoint point) {
            final double dx = point.x - center.dx;
            final double dy = point.y - center.dy;
            return InkPoint(
              center.dx + dx * cosine - dy * sine,
              center.dy + dx * sine + dy * cosine,
              point.pressure,
            );
          }),
        );
    }
    _committedRenderCache.invalidate(selectedStrokes);
    _committedRevision.value++;
    _commitHistoryChange(before);
    for (final stroke in selectedStrokes) {
      _eraserBounds.remove(stroke);
    }
    _selectionChanged();
    onCommitted();
  }

  /// 移除全部选中对象，清空选择并提交一次历史。
  void deleteSelection() {
    if (selectedStrokes.isEmpty) return;
    final _InkHistorySnapshot before = _captureHistory();
    strokes.removeWhere(selectedStrokes.contains);
    selectedStrokes.clear();
    _commitHistoryChange(before);
    _committedChanged(appendOnly: true);
    _selectionChanged();
    onCommitted();
  }

  /// 仅取消选择与临时变换，不删除笔画或生成内容历史。
  void clearSelection() {
    if (selectedStrokes.isEmpty && lassoPoints.isEmpty) return;
    selectedStrokes.clear();
    lassoPoints.clear();
    _selectionChanged();
  }

  /// 恢复最近历史的修改前快照，并将条目移入重做栈。
  void undo() {
    if (_undoHistory.isEmpty) return;
    finishHistoryTransaction(commit: false);
    final _InkHistoryEntry entry = _undoHistory.removeLast();
    _redoHistory.add(entry);
    _restoreHistory(entry.before);
  }

  /// 恢复最近撤销条目的修改后快照，并移回撤销栈。
  void redo() {
    if (_redoHistory.isEmpty) return;
    finishHistoryTransaction(commit: false);
    final _InkHistoryEntry entry = _redoHistory.removeLast();
    _undoHistory.add(entry);
    _restoreHistory(entry.after);
  }

  /// 清空当前页笔画并生成可撤销提交；与换页用 replace 的语义不同。
  void clear() {
    if (strokes.isEmpty) return;
    final _InkHistorySnapshot before = _captureHistory();
    strokes.clear();
    selectedStrokes.clear();
    _commitHistoryChange(before);
    _committedChanged();
    _selectionChanged();
    onCommitted();
  }

  /// 返回适合保存/复制的独立笔画快照，不能把后续可变点列继续共享给写入队列。
  List<InkStroke> snapshot() =>
      strokes.map((InkStroke stroke) => stroke.copy()).toList(growable: false);
}
