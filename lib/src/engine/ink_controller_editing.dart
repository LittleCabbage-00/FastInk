part of 'ink_canvas.dart';

extension InkControllerEditing on InkController {
  /// 保留页面中的叠放顺序，剪贴板坐标与实时笔迹分离。
  List<InkStroke> copySelection() => strokes
      .where(selectedStrokes.contains)
      .map((stroke) => stroke.copy())
      .toList();

  /// 复制输入笔画为独立对象并加入当前页，更新选择与历史；不与剪贴板源对象共享可变点列。
  void pasteStrokes(Iterable<InkStroke> source) {
    final List<InkStroke> copies = source
        .map((stroke) => stroke.copy())
        .toList();
    if (copies.isEmpty) return;
    final _InkHistorySnapshot before = _captureHistory();
    double right = double.negativeInfinity;
    double bottom = double.negativeInfinity;
    for (final InkStroke stroke in copies) {
      for (final InkPoint point in stroke.points) {
        right = math.max(right, point.x);
        bottom = math.max(bottom, point.y);
      }
    }
    // 对整组选区施加相同平移，避免边缘对象变形。
    final double dx = math.min(0.025, math.max(0, 1 - right));
    final double dy = math.min(0.025, math.max(0, 1 - bottom));
    final List<InkStroke> pasted = copies
        .map(
          (stroke) => stroke.copy(
            points: stroke.points
                .map((p) => InkPoint(p.x + dx, p.y + dy, p.pressure))
                .toList(),
          ),
        )
        .toList();
    strokes.addAll(pasted);
    selectedStrokes
      ..clear()
      ..addAll(pasted);
    lassoPoints.clear();
    _commitHistoryChange(before);
    _committedChanged(appendOnly: true);
    _selectionChanged();
    onCommitted();
  }

  /// 将选中对象移到前层或后层；toFront 决定方向，保留同组对象相对顺序并生成一次历史。
  void reorderSelection({required bool toFront}) {
    if (!hasSelection) return;
    final List<InkStroke> selected = strokes
        .where(selectedStrokes.contains)
        .toList();
    final List<InkStroke> remaining = strokes
        .where((s) => !selectedStrokes.contains(s))
        .toList();
    final List<InkStroke> ordered = toFront
        ? <InkStroke>[...remaining, ...selected]
        : <InkStroke>[...selected, ...remaining];
    if (List<int>.generate(
      strokes.length,
      (i) => i,
    ).every((i) => identical(strokes[i], ordered[i]))) {
      return;
    }
    final _InkHistorySnapshot before = _captureHistory();
    strokes
      ..clear()
      ..addAll(ordered);
    _commitHistoryChange(before);
    _committedChanged(appendOnly: true);
    onCommitted();
  }

  /// 用 ARGB 颜色更新选中笔画，保持位置和全文等其他属性，整体提交一次历史。
  void recolorSelection(int color) {
    final List<InkStroke> targets = strokes
        .where(
          (stroke) =>
              selectedStrokes.contains(stroke) &&
              stroke.kind != StrokeKind.image &&
              stroke.color != color,
        )
        .toList();
    if (targets.isEmpty) return;
    final _InkHistorySnapshot before = _captureHistory();
    final targetSet = targets.toSet();
    for (var index = 0; index < strokes.length; index++) {
      final stroke = strokes[index];
      if (!targetSet.contains(stroke)) continue;
      final InkStroke replacement = stroke.copy(color: color);
      strokes[index] = replacement;
      selectedStrokes
        ..remove(stroke)
        ..add(replacement);
    }
    _commitHistoryChange(before);
    _committedChanged(appendOnly: true);
    _selectionChanged();
    onCommitted();
  }
}
