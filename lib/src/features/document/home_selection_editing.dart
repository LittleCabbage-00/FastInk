part of '../../app/fastink_app.dart';

extension _FastInkSelectionEditing on _FastInkHomeState {
  /// 保存独立选区快照及源文稿信息；cut 为 true 时再删除源选择，复制本身不改变原内容。
  void _copyInkSelection({bool cut = false}) {
    if (!_ink.hasSelection || _doc.inkInputBlocked) return;
    if (cut && _doc.readOnly) return;
    _copiedInk = _ink.copySelection();
    _copiedInkDocument = _doc.document;
    if (Platform.isWindows &&
        !Platform.environment.containsKey('FLUTTER_TEST')) {
      _inkClipboardSequence = WindowsCapture().clipboardSequence;
    }
    if (cut) _ink.deleteSelection();
    _updateState(
      () => _doc.status = tr(
        '已复制选区，可切换页面或文稿后粘贴',
        'Selection copied; paste into any page or document',
      ),
    );
  }

  /// 粘贴独立笔画对象，跨文稿时收集嵌入图片并重写资源引用；期间检查目标归属与修改锁。
  Future<void> _pasteInkSelection() async {
    final NoteDocument? target = _doc.document;
    final NoteDocument? source = _copiedInkDocument;
    if (target == null ||
        source == null ||
        _copiedInk.isEmpty ||
        _doc.readOnly ||
        _doc.inkInputBlocked ||
        _pastingInk) {
      return;
    }
    final int token = _doc.pageToken;
    final List<InkStroke> payload = _copiedInk.map((s) => s.copy()).toList();
    _pastingInk = true;
    try {
      final Map<String, String> assets = <String, String>{};
      final List<InkStroke> prepared = <InkStroke>[];
      for (final InkStroke stroke in payload) {
        final String? asset = stroke.imageAsset;
        if (asset != null && source.id != target.id) {
          assets[asset] ??= await _repository.importEmbeddedImage(
            target,
            File(_repository.resolveEmbeddedImagePath(source, asset)),
          );
          prepared.add(stroke.copy(imageAsset: assets[asset]));
        } else {
          prepared.add(stroke);
        }
      }
      if (!mounted ||
          token != _doc.pageToken ||
          _doc.document?.id != target.id ||
          _doc.readOnly ||
          _doc.inkInputBlocked) {
        return;
      }
      _selectTool(InkTool.lasso);
      _ink.pasteStrokes(prepared);
      _updateState(
        () => _doc.status = tr(
          '选区已粘贴，可直接移动或缩放',
          'Selection pasted; drag or resize it',
        ),
      );
    } catch (error) {
      if (mounted) {
        _updateState(
          () => _doc.status = tr('粘贴失败：$error', 'Paste failed: $error'),
        );
      }
    } finally {
      _pastingInk = false;
    }
  }

  /// 让用户选择新颜色，并把选区整体改色作为一次可撤销编辑。
  Future<void> _recolorInkSelection() async {
    if (_doc.readOnly || _doc.inkInputBlocked) return;
    final int token = _doc.pageToken;
    final Set<InkStroke> selection = Set<InkStroke>.of(_ink.selectedStrokes);
    final Color? color = await showDialog<Color>(
      context: context,
      animationStyle: appMotionStyle(context),
      builder: (context) => AlertDialog(
        title: Text(tr('选区颜色', 'Selection color')),
        content: SizedBox(
          width: 280,
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: <Widget>[
              for (final int value in _settings.penColorPresets)
                IconButton(
                  tooltip: '#${value.toRadixString(16)}',
                  onPressed: () => Navigator.pop(context, Color(value)),
                  icon: Icon(Icons.circle, color: Color(value), size: 32),
                ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr('取消')),
          ),
        ],
      ),
    );
    if (color == null ||
        !mounted ||
        token != _doc.pageToken ||
        _doc.readOnly ||
        _doc.inkInputBlocked ||
        !selection.containsAll(_ink.selectedStrokes) ||
        selection.length != _ink.selectedStrokes.length) {
      return;
    }
    _ink.recolorSelection(color.toARGB32());
  }
}
