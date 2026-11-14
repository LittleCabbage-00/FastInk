part of 'markdown_editor.dart';

extension _MarkdownActions on _MarkdownEditorViewState {
  /// 把当前选区约束到有效全文范围，没有有效选区时使用末尾光标，避免替换时索引越界。
  TextSelection get _selection {
    final selection = _text.selection;
    return selection.isValid
        ? TextSelection(
            baseOffset: selection.start.clamp(0, _text.text.length),
            extentOffset: selection.end.clamp(0, _text.text.length),
          )
        : TextSelection.collapsed(offset: _text.text.length);
  }

  /// 只替换指定源文范围并设置新光标，尊重只读状态，修改后恢复编辑焦点。
  void _replaceRange(int start, int end, String replacement, {int? caret}) {
    if (_readOnly) return;
    _text.value = TextEditingValue(
      text: _text.text.replaceRange(start, end, replacement),
      selection: TextSelection.collapsed(
        offset: caret ?? start + replacement.length,
      ),
    );
    _focusEditing();
  }

  /// 在当前选区两侧包裹 before/after，保留选中文字并把光标放在指定格式内。
  void _wrap(String before, String after) {
    final selection = _selection;
    final selected = selection.textInside(_text.text);
    _replaceRange(
      selection.start,
      selection.end,
      '$before$selected$after',
      caret: selection.start + before.length + selected.length,
    );
  }

  /// 按需要补充分隔换行后插入块级前后缀，避免把块结构粘到上一行末尾。
  void _block(String before, String after) {
    final selection = _selection;
    final needsNewline =
        selection.start > 0 && _text.text[selection.start - 1] != '\n';
    _wrap('${needsNewline ? '\n' : ''}$before', after);
  }

  /// 给选中逻辑行增加前缀，标题模式先去掉旧标题标记，避免反复叠加标题等级。
  void _prefix(String prefix, {bool heading = false}) {
    final selection = _selection;
    final text = _text.text;
    final start = selection.start == 0
        ? 0
        : text.lastIndexOf('\n', selection.start - 1) + 1;
    var end = selection.end;
    if (end > start && text[end - 1] == '\n') end--;
    final next = text.indexOf('\n', end);
    end = next < 0 ? text.length : next;
    final replacement = text
        .substring(start, end)
        .split('\n')
        .map(
          (line) =>
              '$prefix${heading ? line.replaceFirst(RegExp(r'^ {0,3}#{1,6}\s+'), '') : line}',
        )
        .join('\n');
    _replaceRange(start, end, replacement);
  }

  /// 选择图像并收集到当前文稿资源目录，再在原选区插入相对引用；失败向状态栏反馈。
  Future<void> _insertImage() async {
    if (_readOnly) return;
    final selection = _selection;
    final file =
        (OpenFilePicker()
              ..title = tr('插入图片文件')
              ..filterSpecification = {
                'Images': '*.png;*.jpg;*.jpeg;*.webp;*.gif',
              })
            .getFile();
    if (file == null) return;
    try {
      final path = await _service.insertImage(file);
      if (!mounted) return;
      if (path == null) throw StateError(tr('请先导入到资料库再插入图片'));
      _replaceRange(selection.start, selection.end, '![](<$path>)');
    } catch (error) {
      _change(() => _status = '${tr('插入失败')}: $error');
    }
  }

  /// 根据托管/外部来源保存到正确目标，返回成功与否；进行中或只读时不重复提交。
  Future<bool> _save() async {
    if (_readOnly || _file == null || _saving) return false;
    _change(() => _saving = true);
    final ok = _editingExternal
        ? await _service.saveToPath(_externalPath!)
        : await _service.save();
    _change(() {
      _saving = false;
      _status = ok ? tr('已保存') : tr('保存失败，请检查路径和磁盘空间');
    });
    if (ok && !_editingExternal) widget.onFileSaved?.call(_service.state!.path);
    return ok;
  }

  /// 先通过可离开检查，确认保存/取消语义后才通知宿主切回资料库。
  Future<void> _exit() async {
    if (await _canLeave() && mounted) widget.onExit();
  }

  /// 检查正在保存/导出与脏状态，外部原文修改按用户决定写回或取消，返回是否允许离开。
  Future<bool> _canLeave() async {
    if (_saving || _exporting) return false;
    if (_file == null || _readOnly) {
      return true;
    }
    if (_editingExternal && _file!.isDirty) {
      final decision = await showDialog<String>(
        context: context,
        animationStyle: appMotionStyle(context),
        builder: (ctx) => AlertDialog(
          title: Text(tr('保存更改？')),
          content: Text(tr('是否将更改保存到原始 Markdown 文件？')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'cancel'),
              child: Text(tr('取消')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'discard'),
              child: Text(tr('不保存')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, 'save'),
              child: Text(tr('保存')),
            ),
          ],
        ),
      );
      if (decision == null || decision == 'cancel') return false;
      if (decision == 'save' && !await _save()) return false;
    } else if (!_editingExternal && !await _save()) {
      return false;
    }
    return mounted;
  }

  /// 确认标题或路径变化后通过服务重命名，并通知宿主迁移资料库与标签身份。
  Future<void> _rename() async {
    if (_file == null) return;
    final controller = TextEditingController(
      text: _file!.fileName.replaceFirst(
        RegExp(r'\.md$', caseSensitive: false),
        '',
      ),
    );
    final name = await showDialog<String>(
      context: context,
      animationStyle: appMotionStyle(context),
      builder: (ctx) => AlertDialog(
        title: Text(tr('重命名')),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 80,
          decoration: const InputDecoration(suffixText: '.md'),
          onSubmitted: (value) => Navigator.pop(ctx, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr('取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: Text(tr('确定')),
          ),
        ],
      ),
    );
    // 对话框反向动画期间，文字输入框还会保留一帧。
    await Future<void>.delayed(const Duration(milliseconds: 250));
    controller.dispose();
    if (!mounted || name == null || name.trim().isEmpty) return;
    final oldPath = _file!.path;
    final path = await _service.rename(name.trim());
    _change(() {
      _file = _service.state;
      _status = path == null ? tr('重命名失败：名称无效或文件已存在') : tr('已重命名');
    });
    if (path != null) {
      widget.onFileRenamed?.call(oldPath, path);
      widget.onFileSaved?.call(path);
    }
  }

  /// 明确展示外部来源、只读/编辑原文件等行为，避免用户把临时副本保存误当修改原文件。
  Widget _externalBanner() => MaterialBanner(
    content: Text(tr('外部文件 · 只读预览；可编辑原文件或导入资料库')),
    leading: const Icon(Icons.lock_outline, size: 20),
    actions: [
      TextButton(
        onPressed: () {
          _service.autoSaveEnabled = false;
          _change(() {
            _editingExternal = true;
            _mode = _MarkdownMode.split;
            _status = tr('编辑原文件 · Ctrl+S 保存');
          });
        },
        child: Text(tr('编辑原文件')),
      ),
      TextButton(
        onPressed: () async {
          final path = await _service.importToLibrary(widget.dataRoot);
          if (!mounted) return;
          _change(() {
            if (path != null) {
              _file = _service.state;
              _text.text = _file!.content;
              _lastText = _preview = _file!.content;
              _externalPath = null;
              _editingExternal = false;
              _mode = _MarkdownMode.split;
            }
            _status = path != null ? tr('已导入到资料库') : tr('导入失败');
          });
          if (path != null) widget.onFileSaved?.call(path);
        },
        child: Text(tr('导入到资料库')),
      ),
    ],
  );

  /// 打开查找/替换并优先采用当前单行选中文字，随后请求查找框焦点。
  void _openFind() {
    final selected = _selection.textInside(_text.text);
    if (selected.isNotEmpty && !selected.contains('\n')) {
      _find.text = selected;
      _findRegex = false;
      _lastFindStart = null;
    }
    _change(() => _showFind = true);
    _findFocus.requestFocus();
  }

  /// 按大小写、整词与正则选项创建匹配器，非法正则返回 null 并提供错误反馈。
  RegExp? get _findPattern {
    if (_find.text.isEmpty) return null;
    final source = _findRegex ? _find.text : RegExp.escape(_find.text);
    final pattern = _findWholeWords
        ? '(?<![\\p{L}\\p{N}_])(?:$source)(?![\\p{L}\\p{N}_])'
        : source;
    try {
      return RegExp(
        pattern,
        caseSensitive: _matchCase,
        multiLine: true,
        unicode: true,
      );
    } on FormatException {
      return null;
    }
  }

  /// 返回当前有效查询在全文中的匹配列表，查询无效或为空时不虚构结果。
  List<Match> get _matches =>
      _findPattern?.allMatches(_text.text).toList() ?? [];

  /// 普通模式原样使用替换文字，正则模式解析受支持捕获组引用。
  String _replacementFor(Match match) => !_findRegex
      ? _replace.text
      : _replace.text.replaceAllMapped(RegExp(r'\$\$|\$(\d+)'), (token) {
          if (token.group(0) == r'$$') return r'$';
          final group = int.parse(token.group(1)!);
          return group <= match.groupCount
              ? match.group(group) ?? ''
              : token.group(0)!;
        });

  /// 按当前定位循环选择下一处或上一处匹配，backwards 决定方向并滚动揭示目标。
  void _findNext({bool backwards = false}) {
    final matches = _matches;
    if (matches.isEmpty) return;
    final selection = _selection;
    final begin = selection.isCollapsed && _lastFindStart == selection.end
        ? selection.end + 1
        : selection.end;
    final match = backwards
        ? matches.lastWhere(
            (m) => m.end <= selection.start,
            orElse: () => matches.last,
          )
        : matches.firstWhere(
            (m) => m.start >= begin,
            orElse: () => matches.first,
          );
    if (_mode == _MarkdownMode.read) _change(() => _mode = _MarkdownMode.edit);
    _lastFindStart = match.start;
    _jumpToOffset(match.start);
    _text.selection = TextSelection(
      baseOffset: match.start,
      extentOffset: match.end,
    );
  }

  /// 只替换当前匹配并更新光标与后续定位，不全篇重写其他内容。
  void _replaceOne() {
    if (_readOnly) return;
    final selection = _selection;
    final exact = _matches.where(
      (m) => m.start == selection.start && m.end == selection.end,
    );
    if (exact.isEmpty) {
      _findNext();
      return;
    }
    _replaceRange(selection.start, selection.end, _replacementFor(exact.first));
    _findNext();
  }

  /// 基于原文匹配位置一次性构造全部替换，捕获组按各匹配独立展开并保留可撤销编辑。
  void _replaceAll() {
    if (_readOnly || _find.text.isEmpty) return;
    final matches = _matches;
    if (matches.isEmpty) return;
    final text = _text.text.replaceAllMapped(_findPattern!, _replacementFor);
    _replaceRange(0, _text.text.length, text);
    _change(() => _status = tr('已替换 ${matches.length} 处'));
  }

  /// 构建查询、替换、匹配选项、导航和错误提示，当前开关使用选中态表达。
  Widget _findBar() => Material(
    color: Theme.of(context).colorScheme.surfaceContainer,
    child: Padding(
      padding: const EdgeInsets.all(8),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 190,
            child: TextField(
              key: const ValueKey('markdown-find'),
              focusNode: _findFocus,
              controller: _find,
              decoration: InputDecoration(
                isDense: true,
                hintText: tr('查找文本'),
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => _change(() {
                _lastFindStart = null;
              }),
              onSubmitted: (_) => _findNext(),
            ),
          ),
          Text('${_matches.length} ${tr('处')}'),
          IconButton(
            tooltip: tr('区分大小写'),
            isSelected: _matchCase,
            onPressed: () => _change(() => _matchCase = !_matchCase),
            icon: const Icon(Icons.text_fields),
          ),
          IconButton(
            tooltip: tr('正则表达式'),
            isSelected: _findRegex,
            onPressed: () => _change(() => _findRegex = !_findRegex),
            icon: const Icon(Icons.data_array),
          ),
          IconButton(
            tooltip: tr('完整词语'),
            isSelected: _findWholeWords,
            onPressed: () => _change(() => _findWholeWords = !_findWholeWords),
            icon: const Icon(Icons.text_format),
          ),
          if (_find.text.isNotEmpty && _findPattern == null)
            Text(
              tr('正则表达式无效'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          IconButton(
            tooltip: tr('上一处'),
            onPressed: () => _findNext(backwards: true),
            icon: const Icon(Icons.keyboard_arrow_up),
          ),
          IconButton(
            tooltip: tr('下一处'),
            onPressed: _findNext,
            icon: const Icon(Icons.keyboard_arrow_down),
          ),
          if (!_readOnly) ...[
            SizedBox(
              width: 160,
              child: TextField(
                key: const ValueKey('markdown-replace'),
                controller: _replace,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: tr('替换为'),
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            TextButton(onPressed: _replaceOne, child: Text(tr('替换'))),
            TextButton(onPressed: _replaceAll, child: Text(tr('全部替换'))),
          ],
          IconButton(
            tooltip: tr('关闭查找'),
            onPressed: () => _change(() => _showFind = false),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    ),
  );

  /// 按稳定动作标识分派 Markdown 工具、视图、属性和导出，翻译标签不参与行为判断。
  Future<void> _menuAction(String action) async {
    switch (action) {
      case 'quick-open':
        await _quickOpen();
      case 'tasks':
        await _tasksDialog();
      case 'save-template':
        await _saveTemplate();
      case 'manage-templates':
        await _manageTemplates();
      case 'duplicate-line':
        _editLines(MarkdownLineAction.duplicate);
      case 'move-line-up':
        _editLines(MarkdownLineAction.moveUp);
      case 'move-line-down':
        _editLines(MarkdownLineAction.moveDown);
      case 'delete-line':
        _editLines(MarkdownLineAction.delete);
      case 'toggle-task':
        _editLines(MarkdownLineAction.toggleTask);
      case 'insert-date':
        _insertTemplateContent('{{date}} {{time}}');
      case 'encoding':
        await _reloadEncoding();
      case 'workspace':
        await _workspaceSearch();
      case 'links':
        await _linksDialog();
      case 'properties':
        await _propertiesDialog();
      case 'history':
        await _historyDialog();
      case 'slides':
        await _slides();
      case 'preferences':
        await _preferencesDialog();
      case 'commands':
        await _commandPalette();
      case 'templates':
        await _insertTemplate();
      case 'table':
        await _editTable();
      case 'paste-image':
        await _pasteImage();
      case 'copy-html':
        await Clipboard.setData(
          ClipboardData(
            text: _htmlDocument(await _htmlPreparedContent(_text.text)),
          ),
        );
        _change(() => _status = tr('已复制 HTML'));
      case 'heading':
        await _quickHeading();
      case 'line':
        await _goToLine();
      case 'fullscreen':
        _toggleFullscreen();
      case 'focus':
        _setPreferences(_prefs.copyWith(focusMode: !_prefs.focusMode));
      case 'typewriter':
        _setPreferences(_prefs.copyWith(typewriter: !_prefs.typewriter));
      case 'theme':
        widget.onThemeToggle();
      case 'sync':
        _setPreferences(_prefs.copyWith(syncScroll: !_syncScroll));
      case 'smaller':
        _setPreferences(
          _prefs.copyWith(fontSize: (_fontSize - 1).clamp(11, 26)),
        );
      case 'larger':
        _setPreferences(
          _prefs.copyWith(fontSize: (_fontSize + 1).clamp(11, 26)),
        );
      default:
        await _export(action);
    }
  }

  /// 按格式收集目标并输出正文与资源，维护导出状态/进度，取消或失败不把临时结果当成功。
  Future<void> _export(String format) async {
    if (_file == null || _exporting) return;
    final target = widget.pickExportDestination != null
        ? await widget.pickExportDestination!(format)
        : (SaveFilePicker()
                ..title = tr('导出 Markdown 文档')
                ..fileName =
                    '${_file!.fileName.replaceFirst(RegExp(r'\.md$', caseSensitive: false), '')}.$format'
                ..defaultExtension = format
                ..filterSpecification = {format.toUpperCase(): '*.$format'})
              .getFile();
    if (target == null || !mounted) return;
    _change(() {
      _exporting = true;
      _status = '${tr('正在导出')} ${format.toUpperCase()}…';
    });
    OverlayEntry? entry;
    final progress = ValueNotifier<String>(tr('正在准备导出…'));
    bool dialogOpen = false;
    // 始终先写入同目录临时文件，避免未完成或失败的导出
    // 覆盖用户指定的目标文件。
    final temporary = File(
      '${target.path}.fastink-${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    try {
      if (format == 'docx') {
        await temporary.writeAsBytes(
          await MarkdownDocumentExport.docx(
            _text.text,
            sourcePath: _externalPath ?? _file!.path,
            renderDiagrams: _prefs.diagramEnabled,
          ),
          flush: true,
        );
      } else if (format == 'txt') {
        await temporary.writeAsString(
          MarkdownDocumentExport.plainText(_text.text),
          flush: true,
        );
      } else if (format == 'md' || format == 'html') {
        final content = await MarkdownEditorService.copyLocalImages(
          content: format == 'html'
              ? await _htmlPreparedContent(_text.text)
              : _text.text,
          sourcePath: _externalPath ?? _file!.path,
          targetPath: target.path,
        );
        await temporary.writeAsString(
          format == 'html' ? _htmlDocument(content) : content,
          flush: true,
        );
      } else {
        if (!mounted) return;
        final boundaryKey = GlobalKey();
        entry = OverlayEntry(
          builder: (_) => Positioned(
            left: 0,
            top: 0,
            width: 794,
            child: IgnorePointer(
              child: Material(
                color: _prefs.exportDark && widget.darkMode
                    ? const Color(0xff101217)
                    : Colors.white,
                child: MarkdownExportBoundary(
                  key: boundaryKey,
                  child: ColoredBox(
                    color: _prefs.exportDark && widget.darkMode
                        ? const Color(0xff101217)
                        : Colors.white,
                    child: _markdownBody(
                      _text.text,
                      dark: _prefs.exportDark && widget.darkMode,
                      exporting: true,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        Overlay.of(context).insert(entry);
        // 进度对话框位于导出画布上方，用户可持续看到进度。
        unawaited(
          showDialog<void>(
            context: context,
            animationStyle: appMotionStyle(context),
            barrierDismissible: false,
            builder: (_) => PopScope(
              canPop: false,
              child: AlertDialog(
                title: Text(tr('正在导出')),
                content: ValueListenableBuilder<String>(
                  valueListenable: progress,
                  builder: (_, value, _) => Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const LinearProgressIndicator(),
                      const SizedBox(height: 16),
                      Text(value),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        dialogOpen = true;
        await _precacheImages(_text.text);
        await WidgetsBinding.instance.endOfFrame;
        final boundary =
            boundaryKey.currentContext!.findRenderObject()!
                as MarkdownExportRenderBoundary;
        await MarkdownRenderExport.write(
          boundary: boundary,
          target: temporary,
          format: format,
          pixelRatio: _prefs.exportScale,
          jpgQuality: _prefs.jpgQuality,
          onProgress: (done, total) => progress.value = '$done / $total',
        );
      }
      await temporary.rename(target.path);
      _change(() => _status = '${tr('已导出')}: ${target.path}');
    } catch (error) {
      _change(() => _status = '${tr('导出失败')}: $error');
    } finally {
      entry?.remove();
      entry?.dispose();
      if (dialogOpen && mounted) Navigator.of(context).pop();
      // 等对话框退出动画完成，再释放进度通知器。
      Future<void>.delayed(const Duration(milliseconds: 300), progress.dispose);
      if (await temporary.exists()) await temporary.delete();
      _change(() => _exporting = false);
    }
  }
}
