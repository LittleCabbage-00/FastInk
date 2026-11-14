part of '../../app/fastink_app.dart';

extension _FastInkTextProperties on _FastInkHomeState {
  /// 打开自定义默认字号输入，验证有限正数与范围后保存，取消保持当前配置。
  Future<void> _customTextSize() async {
    if (_ink.selectedTextStroke != null) {
      await _showTextProperties(_pageViewportRect.size);
      return;
    }
    final input = TextEditingController(
      text: _settings.defaultTextSize.toString(),
    );
    String? error;
    final value = await showDialog<double>(
      context: context,
      animationStyle: appMotionStyle(context),
      builder: (ctx) => StatefulBuilder(
        builder: (_, change) => AlertDialog(
          title: Text(tr('自定义字号', 'Custom font size')),
          content: TextField(
            key: const ValueKey('custom-text-size'),
            controller: input,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              helperText: '1 – 512 px',
              errorText: error,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(tr('取消')),
            ),
            FilledButton(
              onPressed: () {
                final n = double.tryParse(input.text);
                if (n != null && n.isFinite && n >= 1 && n <= 512) {
                  Navigator.pop(ctx, n);
                } else {
                  change(
                    () => error = tr(
                      '请输入 1 到 512 的字号',
                      'Enter a font size from 1 to 512',
                    ),
                  );
                }
              },
              child: Text(tr('应用', 'Apply')),
            ),
          ],
        ),
      ),
    );
    if (value != null && mounted) {
      _updateState(() {
        _settings.defaultTextSize = value;
        _inlineTextSize = value;
      });
      await _settings.saveNum('defaultTextSize', value);
    }
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 300), input.dispose),
    );
  }

  /// 展示长文本全文与字体、字号、宽度等属性，异步计算适应页面，确认后整体更新为一次可撤销编辑。
  Future<void> _showTextProperties(Size canvasSize) async {
    if (_doc.readOnly || _doc.inkInputBlocked) return;
    if (_inlineTextPoint != null) _commitInlineText(canvasSize: canvasSize);
    final original = _ink.selectedTextStroke;
    if (canvasSize.isEmpty ||
        original == null ||
        original.points.length < 4 ||
        _doc.readOnly ||
        _doc.inkInputBlocked) {
      return;
    }
    final horizontal = Offset(
      (original.points[1].x - original.points[0].x) * canvasSize.width,
      (original.points[1].y - original.points[0].y) * canvasSize.height,
    );
    final baseWidth =
        (original.textBoxWidth ?? horizontal.distance / canvasSize.width) *
        canvasSize.width;
    final scale = (horizontal.distance / math.max(1, baseWidth)).clamp(.01, 20);
    final content = TextEditingController(text: original.text);
    final sizeInput = TextEditingController(
      text: (original.textSize * canvasSize.height * scale).toStringAsFixed(1),
    );
    final widthInput = TextEditingController(
      text: horizontal.distance
          .clamp(40, canvasSize.width)
          .floorToDouble()
          .toStringAsFixed(0),
    );
    String family = original.textFontFamily;
    bool bold = original.textWeight >= 600,
        italic = original.textItalic,
        fit = false;
    bool fitting = false, fitFailed = false;
    int fitGeneration = 0;
    TextBoxFit? fitted;
    String? error;
    // 输入内容或样式变化后作废旧适配结果和错误提示，避免将过期布局应用到新全文。
    void resetFit() {
      fitGeneration++;
      fit = false;
      fitted = null;
      fitting = false;
      fitFailed = false;
      error = null;
    }

    final result = await showDialog<bool>(
      context: context,
      // 关闭属性窗后立即让出画布，让用户看完整的文本定位过渡。
      animationStyle:
          appMotionStyle(context) ??
          const AnimationStyle(reverseDuration: Duration.zero),
      builder: (dialogContext) => StatefulBuilder(
        builder: (ctx, change) {
          final fonts = <String>{
            family,
            'Microsoft YaHei UI',
            'Segoe UI Variable',
            'Arial',
            'Calibri',
            'Times New Roman',
            'Consolas',
          };
          return Dialog(
            child: SizedBox(
              width: 640,
              height: MediaQuery.sizeOf(ctx).height * .85,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            tr('编辑文本框', 'Edit text box'),
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: tr('关闭'),
                          onPressed: () => Navigator.pop(dialogContext, false),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.sizeOf(ctx).height * .35,
                      ),
                      child: SingleChildScrollView(
                        child: Wrap(
                          spacing: 12,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            SizedBox(
                              width: 200,
                              child: DropdownButtonFormField<String>(
                                initialValue: family,
                                isExpanded: true,
                                decoration: InputDecoration(
                                  labelText: tr('字体', 'Font'),
                                ),
                                items: [
                                  for (final font in fonts)
                                    DropdownMenuItem(
                                      value: font,
                                      child: Text(
                                        font,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                ],
                                onChanged: (v) {
                                  if (v != null) {
                                    change(() {
                                      family = v;
                                      resetFit();
                                    });
                                  }
                                },
                              ),
                            ),
                            SizedBox(
                              width: 110,
                              child: TextField(
                                key: const ValueKey('text-properties-size'),
                                controller: sizeInput,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                decoration: InputDecoration(
                                  labelText: tr('字号', 'Font size'),
                                  helperText: '1 – 512 px',
                                ),
                                onChanged: (_) => change(resetFit),
                              ),
                            ),
                            SizedBox(
                              width: 110,
                              child: TextField(
                                key: const ValueKey('text-properties-width'),
                                controller: widthInput,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                decoration: InputDecoration(
                                  labelText: tr('文本框宽度', 'Box width'),
                                  suffixText: 'px',
                                  helperText:
                                      '40 – ${canvasSize.width.floor()}',
                                ),
                                onChanged: (_) => change(resetFit),
                              ),
                            ),
                            FilterChip(
                              label: Text(tr('粗体', 'Bold')),
                              selected: bold,
                              onSelected: (v) => change(() {
                                bold = v;
                                resetFit();
                              }),
                            ),
                            FilterChip(
                              label: Text(tr('斜体', 'Italic')),
                              selected: italic,
                              onSelected: (v) => change(() {
                                italic = v;
                                resetFit();
                              }),
                            ),
                            OutlinedButton.icon(
                              key: const ValueKey('text-properties-fit'),
                              icon: const Icon(Icons.fit_screen),
                              label: Text(tr('适合页面', 'Fit to page')),
                              onPressed: fitting
                                  ? null
                                  : () async {
                                      final generation = ++fitGeneration;
                                      change(() {
                                        fitting = true;
                                        fit = false;
                                        fitFailed = false;
                                        error = null;
                                      });
                                      final placement = await fitTextBoxToPage(
                                        text: content.text,
                                        style: TextStyle(
                                          fontFamily: family,
                                          fontFamilyFallback: const [
                                            'Microsoft YaHei UI',
                                          ],
                                          fontSize:
                                              double.tryParse(sizeInput.text) ??
                                              _settings.defaultTextSize,
                                          fontWeight: bold
                                              ? FontWeight.w700
                                              : FontWeight.w400,
                                          fontStyle: italic
                                              ? FontStyle.italic
                                              : FontStyle.normal,
                                        ),
                                        textAlign: original.textAlign,
                                        preferred: Rect.fromLTWH(
                                          original.points.first.x *
                                              canvasSize.width,
                                          original.points.first.y *
                                              canvasSize.height,
                                          horizontal.distance,
                                          1,
                                        ),
                                        pageSize: canvasSize,
                                        occupied: _ink.contentBounds(
                                          canvasSize,
                                          excluding: original,
                                        ),
                                        isCurrent: () =>
                                            mounted &&
                                            ctx.mounted &&
                                            generation == fitGeneration,
                                      );
                                      if (!ctx.mounted ||
                                          !mounted ||
                                          generation != fitGeneration) {
                                        return;
                                      }
                                      change(() {
                                        fitting = false;
                                        fitted = placement;
                                        fit = placement != null;
                                        fitFailed = placement == null;
                                        if (placement == null) {
                                          error = tr(
                                            '页面空白不足，无法避开现有内容放下全文。请先移动部分内容或添加页面。',
                                            'Not enough blank space for all the text. Move existing content or add a page.',
                                          );
                                        } else {
                                          sizeInput.text = placement.fontSize
                                              .toStringAsFixed(2);
                                          widthInput.text = placement
                                              .bounds
                                              .width
                                              .toStringAsFixed(1);
                                        }
                                      });
                                    },
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: TextField(
                        key: const ValueKey('text-properties-content'),
                        controller: content,
                        maxLines: null,
                        expands: true,
                        textAlignVertical: TextAlignVertical.top,
                        style: TextStyle(fontSize: 16, fontFamily: family),
                        decoration: InputDecoration(
                          border: const OutlineInputBorder(),
                          hintText: tr('输入文字'),
                          helperText: tr(
                            '此处按易读字号编辑，应用后使用上方的实际字号。',
                            'Editing uses a readable size; the chosen size applies to the page.',
                          ),
                        ),
                        onChanged: (_) => change(resetFit),
                      ),
                    ),
                    if (fitting || fit)
                      Text(
                        fitting
                            ? tr('正在查找空白区域…', 'Finding blank space…')
                            : tr(
                                '已找到空白区域，点击“应用”后移动文本框。',
                                'Blank space found. Apply to move the text box.',
                              ),
                        key: const ValueKey('text-properties-fit-status'),
                      ),
                    if (fit && fitted!.hardToRead)
                      Text(
                        tr(
                          '适配后字号为 ${fitted!.fontSize.toStringAsFixed(2)} px，可能难以阅读。仍可应用，也可腾出更多空白或放到新页面。',
                          'The fitted font size is ${fitted!.fontSize.toStringAsFixed(2)} px and may be hard to read. You can apply it, make more room, or use a new page.',
                        ),
                        key: const ValueKey('text-properties-fit-warning'),
                        style: TextStyle(
                          color: Theme.of(ctx).colorScheme.error,
                        ),
                      ),
                    if (error != null)
                      Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(ctx).colorScheme.error,
                        ),
                      ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialogContext, false),
                          child: Text(tr('取消')),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          key: const ValueKey('text-properties-apply'),
                          onPressed: fitting || fitFailed
                              ? null
                              : () {
                                  final font = double.tryParse(sizeInput.text),
                                      width = double.tryParse(widthInput.text);
                                  if (font == null ||
                                      !font.isFinite ||
                                      font < 1 ||
                                      font > 512 ||
                                      width == null ||
                                      !width.isFinite ||
                                      width < 40 ||
                                      width > canvasSize.width) {
                                    change(
                                      () => error = tr(
                                        '请输入有效字号和页面范围内的宽度。',
                                        'Enter a valid font size and a width within the page.',
                                      ),
                                    );
                                    return;
                                  }
                                  Navigator.pop(dialogContext, true);
                                },
                          child: Text(tr('应用', 'Apply')),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
    if (result == true &&
        mounted &&
        !_doc.inkInputBlocked &&
        !_doc.readOnly &&
        _ink.strokes.contains(original)) {
      _ink.updateText(
        original,
        content.text,
        canvasSize,
        fontSize: double.parse(sizeInput.text),
        boxWidth: double.parse(widthInput.text),
        textFontFamily: family,
        textWeight: bold ? 700 : 400,
        textItalic: italic,
        anchor: fit
            ? InkPoint(
                fitted!.bounds.left / canvasSize.width,
                fitted!.bounds.top / canvasSize.height,
                .5,
              )
            : null,
        rotation: fit ? 0 : null,
        resetScale: fit,
      );
      if (fit) _animateFittedText(original.points, fitted!.bounds);
    }
    fitGeneration++;
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 300), () {
        content.dispose();
        sizeInput.dispose();
        widthInput.dispose();
      }),
    );
  }

  /// 只计算目标相机位置，文本与相机使用同一条时间线，避免先跳页再移动文字。
  Matrix4 _fittedTextCamera(Rect bounds) {
    final matrix = Matrix4.copy(_viewport.zoomController.value);
    if (_canvasViewport.isEmpty || _pageViewportRect.isEmpty) return matrix;
    final screen = MatrixUtils.transformRect(
      matrix,
      bounds.shift(_pageViewportRect.topLeft),
    );
    final visible = (Offset.zero & _canvasViewport).deflate(24);
    // 计算把目标区间移入允许可见范围所需的平移量，空间不足时采用边界约束。
    double shift(double start, double end, double low, double high) {
      if (end - start > high - low || start < low) return low - start;
      if (end > high) return high - end;
      return 0;
    }

    matrix[12] += shift(screen.left, screen.right, visible.left, visible.right);
    matrix[13] += shift(screen.top, screen.bottom, visible.top, visible.bottom);
    return _viewport.documentViewportLayout?.constrainCamera(
          matrix,
          maximumScale: _settings.maximumZoom,
        ) ??
        matrix;
  }

  /// 自动定位保留短暂的功能性过渡；电池供电缩短时长，手动操作可立即接管。
  void _animateFittedText(List<InkPoint> from, Rect bounds) {
    final target = _ink.selectedTextStroke;
    if (target == null) return;
    if (_textMotionController == null) {
      final timeline = AnimationController(vsync: this);
      timeline.addListener(_textMotionFrame);
      timeline.addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted) {
          _ink.finishTextRelocation();
          _textMotionCameraFrom = null;
          _textMotionCameraTo = null;
        }
      });
      _textMotionController = timeline;
    }
    _textMotionController!.stop();
    _viewport.zoomReturnController.stop();
    _textMotionCameraFrom = Matrix4.copy(_viewport.zoomController.value);
    _textMotionCameraTo = _fittedTextCamera(bounds);
    _ink.startTextRelocation(target, from);
    _textMotionController!
      ..duration = Duration(milliseconds: _renderPolicy.economical ? 140 : 220)
      ..forward(from: 0);
  }

  /// 将定位动画同一进度应用到文本四角与相机，结束时恢复正常显示，不生成逐帧编辑历史。
  void _textMotionFrame() {
    final timeline = _textMotionController!;
    if (!mounted || !_ink.isTextRelocating) {
      timeline.stop();
      _textMotionCameraFrom = null;
      _textMotionCameraTo = null;
      return;
    }
    final progress = Curves.easeInOutCubic.transform(timeline.value);
    _ink.updateTextRelocation(progress);
    final from = _textMotionCameraFrom, to = _textMotionCameraTo;
    if (from != null && to != null) {
      _viewport.zoomController.value = Matrix4Tween(
        begin: from,
        end: to,
      ).transform(progress);
    }
  }
}
