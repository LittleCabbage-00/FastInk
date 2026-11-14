import '../../platform/render_power_policy.dart';
import 'dart:async';
import 'dart:io';

import 'package:filepicker_windows/filepicker_windows.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:markdown/markdown.dart' as md;

import '../../core/app_localizations.dart';
import '../../core/markdown_preferences.dart';
import '../../core/markdown_writing_tools.dart';
import '../../platform/markdown_templates.dart';
import '../../widgets/markdown_item_picker.dart';
import '../../core/markdown_table_data.dart';
import '../../platform/markdown_workspace.dart';
import '../../platform/markdown_history.dart';
import '../../platform/markdown_diagrams.dart';
import '../../platform/markdown_encoding.dart';
import '../../platform/markdown_document_export.dart';
import '../../widgets/markdown_settings_panel.dart';
import '../../widgets/markdown_source_editor.dart';
import '../../widgets/markdown_live_editor.dart';
import '../../platform/windows_capture.dart';
import '../../platform/windows_fullscreen.dart';
import '../../widgets/markdown_code_highlighter.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as html_dom;
import 'dart:convert';
import '../../platform/markdown_editor_service.dart';
import '../../platform/markdown_render_export.dart';

part 'markdown_editor_actions.dart';
part 'markdown_editor_preview.dart';
part 'markdown_editor_workbench.dart';
part 'markdown_editor_workspace.dart';
part 'markdown_editor_blocks.dart';
part 'markdown_editor_productivity.dart';

enum _MarkdownMode { live, edit, split, read }

class MarkdownEditorView extends StatefulWidget {
  /// 接收源文路径、编辑设置和资料库操作回调。
  /// filePath：当前要编辑的 Markdown 本地路径，新建前可为空。
  /// externalSourcePath：外部 Markdown 原始路径，与资料库托管副本的保存契约分开。
  /// dataRoot：当前资料库根目录，文稿、笔迹和本地资源都相对该目录定位。
  /// darkMode：宿主传入的 Markdown 界面深浅状态，不改源文或代码围栏内容。
  /// onExit：用户确认离开后的宿主回调；是否需要保存由编辑器退出流程先检查。
  /// onThemeToggle：请求宿主切换界面主题的回调。
  /// onFileSaved：Markdown 托管文件保存完成后的路径回调，宿主据此登记资料库。
  /// pickExportDestination：可注入的 Markdown 输出位置选择器，返回 null 表示用户取消。
  /// onFileRenamed：Markdown 重命名完成通知，提供旧、新路径以同步标签与资料库身份。
  /// preferences：当前 Markdown 配置快照，设置变化后由组件更新流程同步。
  /// onPreferencesChanged：Markdown 配置改变后的通知，宿主负责与设置页同步并保存。
  /// readClipboardImage：可注入的系统图片读取入口，测试可替代原生剪贴板访问。
  /// workspacePaths：当前 Markdown 工作区有效源文件路径集合，搜索时排除废纸篓记录。
  /// onOpenMarkdown：请求宿主切换到指定 Markdown 路径的回调。
  /// openedPaths：当前 Markdown 会话已打开文件路径列表，供标签与快速切换使用。
  /// onCloseTab：关闭 Markdown 标签回调，参数为路径及该标签是否活动。
  /// initialHeading：打开文件后希望定位的标题片段，属于导航请求而非正文。
  /// onCreateMarkdown：请求宿主创建新 Markdown 文稿的回调。
  const MarkdownEditorView({
    super.key,
    this.filePath,
    this.externalSourcePath,
    required this.dataRoot,
    required this.darkMode,
    required this.onExit,
    required this.onThemeToggle,
    this.onFileSaved,
    this.pickExportDestination,
    this.onFileRenamed,
    this.preferences = const MarkdownPreferences(),
    this.onPreferencesChanged,
    this.readClipboardImage,
    this.workspacePaths = const [],
    this.onOpenMarkdown,
    this.openedPaths = const [],
    this.onCloseTab,
    this.initialHeading,
    this.onCreateMarkdown,
  });

  /// openedPaths：当前 Markdown 会话已打开文件路径列表，供标签与快速切换使用。
  final List<String> openedPaths;

  /// onCloseTab：关闭 Markdown 标签回调，参数为路径及该标签是否活动。
  final void Function(String path, bool active)? onCloseTab;

  /// initialHeading：打开文件后希望定位的标题片段，属于导航请求而非正文。
  final String? initialHeading;

  /// onCreateMarkdown：请求宿主创建新 Markdown 文稿的回调。
  final VoidCallback? onCreateMarkdown;

  /// workspacePaths：当前 Markdown 工作区有效源文件路径集合，搜索时排除废纸篓记录。
  final List<String> workspacePaths;

  /// onOpenMarkdown：请求宿主切换到指定 Markdown 路径的回调。
  final ValueChanged<String>? onOpenMarkdown;

  /// preferences：当前 Markdown 配置快照，设置变化后由组件更新流程同步。
  final MarkdownPreferences preferences;

  /// onPreferencesChanged：Markdown 配置改变后的通知，宿主负责与设置页同步并保存。
  final ValueChanged<MarkdownPreferences>? onPreferencesChanged;

  /// readClipboardImage：可注入的系统图片读取入口，测试可替代原生剪贴板访问。
  final Future<Uint8List?> Function()? readClipboardImage;

  /// filePath：当前要编辑的 Markdown 本地路径，新建前可为空。
  final String? filePath;

  /// externalSourcePath：外部 Markdown 原始路径，与资料库托管副本的保存契约分开。
  final String? externalSourcePath;

  /// dataRoot：当前资料库根目录，文稿、笔迹和本地资源都相对该目录定位。
  final String dataRoot;

  /// darkMode：宿主传入的 Markdown 界面深浅状态，不改源文或代码围栏内容。
  final bool darkMode;

  /// onExit：用户确认离开后的宿主回调；是否需要保存由编辑器退出流程先检查。
  final VoidCallback onExit;

  /// onThemeToggle：请求宿主切换界面主题的回调。
  final VoidCallback onThemeToggle;

  /// onFileSaved：Markdown 托管文件保存完成后的路径回调，宿主据此登记资料库。
  final ValueChanged<String>? onFileSaved;

  /// pickExportDestination：可注入的 Markdown 输出位置选择器，返回 null 表示用户取消。
  final Future<File?> Function(String format)? pickExportDestination;

  /// onFileRenamed：Markdown 重命名完成通知，提供旧、新路径以同步标签与资料库身份。
  final void Function(String oldPath, String newPath)? onFileRenamed;

  /// 管理 Markdown 文稿、输入焦点、预览和历史。
  @override
  State<MarkdownEditorView> createState() => _MarkdownEditorViewState();
}

class _MarkdownEditorViewState extends State<MarkdownEditorView> {
  /// _service：Markdown 文件读取、保存和资源操作服务，与界面状态分开。
  final _service = MarkdownEditorService();

  /// _text：Markdown 全文文本控制器，实时块编辑按范围回写到这里。
  final _text = MarkdownTextController();

  /// _editorScroll：Markdown 源码滚动控制器，和预览滚动分别持有。
  final _editorScroll = ScrollController();

  /// _previewScroll：Markdown 阅读预览滚动控制器，双向同步需防递归。
  final _previewScroll = ScrollController();

  /// _editorFocus：Markdown 全文编辑焦点，工具操作后可恢复到这里。
  final _editorFocus = FocusNode();

  /// _findFocus：查找输入焦点，打开查找时选中查询文本。
  final _findFocus = FocusNode();

  /// _undo：Markdown 源文撤销控制器，跨工具操作也复用同一历史起点。
  final _undo = UndoHistoryController();

  /// _find：查找查询的文本控制器，正则与普通文本按开关解释。
  final _find = TextEditingController();

  /// _replace：替换输入控制器；正则模式下可包含受支持的捕获组引用。
  final _replace = TextEditingController();

  /// _previewTimer：源码变化到重建阅读预览之间的防抖任务，输入期间合并重复请求。
  Timer? _previewTimer;

  /// _file：当前服务返回的文件状态，包含源路径、正文与脏标记。
  MarkdownFileState? _file;

  /// _externalPath：外部 Markdown 原文件路径，保留它以便退出时决定是否写回。
  String? _externalPath;

  /// _preview：最近已提交到阅读预览的 Markdown 源文快照，与正在输入的全文可短暂不同。
  String _preview = '';

  /// _lastText：最近参与同步/排版的源文快照，用于忽略仅光标变化的通知。
  String _lastText = '';

  /// _status：Markdown 当前操作的可读状态提示，不替代保存与导出布尔状态。
  String _status = '';

  /// _countedContent：已完成字数统计的全文签名，内容不变时复用统计，移动光标不重扫全文。
  String? _countedContent;

  /// _counts：缓存的 Markdown 行数与字词计数，更新依据为实际源文变化。
  (int, int) _counts = (1, 0);

  /// 内容变化时才重新统计全文行数和字词数，光标/选区变化复用全文统计，选区统计另行计算。
  (int, int) get _writingCounts {
    if (_countedContent != _text.text) {
      _countedContent = _text.text;
      _counts = (
        '\n'.allMatches(_text.text).length + 1,
        markdownWordCount(_text.text),
      );
    }
    return _counts;
  }

  /// _editingExternal：是否正在编辑外部原文件，影响保存目的地与退出确认。
  bool _editingExternal = false;

  /// _showToc：Markdown 当前是否显示目录区域，和默认打开方式分开。
  bool _showToc = false;

  /// _showFind：Markdown 查找/替换栏是否打开。
  bool _showFind = false;

  /// _matchCase：查找是否区分大小写。
  bool _matchCase = false;

  /// _findRegex：查找是否把查询按正则解释，非法表达式需显示错误而不是抛出到整页；_findWholeWords：查找是否要求完整词边界匹配。
  bool _findRegex = false, _findWholeWords = false;

  /// _lastFindStart：最近定位到的匹配起始偏移，用于下一处/上一处循环。
  int? _lastFindStart;

  /// _prefs：编辑器当前采用的 Markdown 设置快照，外部设置变化时重新同步。
  late MarkdownPreferences _prefs;

  /// 读取当前 Markdown 源码/预览滚动联动开关。
  bool get _syncScroll => _prefs.syncScroll;

  /// 读取 Markdown 源码逻辑字号，不与纸面文字大小混用。
  double get _fontSize => _prefs.fontSize;

  /// _window：Markdown 全屏平台桥，与手写画布的窗口恢复流程分开持有。
  final _window = WindowsFullscreen();

  /// _liveKey：实时块编辑器状态定位键，供工具操作把选区或焦点交还当前块。
  final _liveKey = GlobalKey<MarkdownLiveEditorState>();

  /// 判断当前模式是否隐藏全文源码，实时块编辑与只读阅读的输入入口不同。
  bool get _sourceHidden =>
      _mode == _MarkdownMode.read || _mode == _MarkdownMode.live;

  /// 把焦点交还当前可编辑区域，实时模式先定位活动块，源码模式聚焦全文输入。
  void _focusEditing() {
    if (_mode == _MarkdownMode.live) {
      _liveKey.currentState?.focusSelection();
    } else {
      _editorFocus.requestFocus();
    }
  }

  /// _syncing：当前是否在同步相关输入/滚动状态，防止双向监听递归回写。
  bool _syncing = false;

  /// _exporting：Markdown 是否正在输出文件，期间防止重复导出或不完整退出。
  bool _exporting = false;

  /// _saving：Markdown 是否正在执行保存，用于按钮禁用与退出等待。
  bool _saving = false;

  /// _splitRatio：源码/预览分栏宽度比例，0–1 范围内解释。
  double _splitRatio = .5;

  /// _mode：Markdown 当前实时、源码、分栏或阅读模式，独立于保存文件格式。
  _MarkdownMode _mode = _MarkdownMode.split;

  /// _headingKeys：标题源偏移到预览组件键的映射，用于目录定位。
  final Map<int, GlobalKey> _headingKeys = {};

  /// _readerBodyCache：内容和渲染配置未改变时复用的阅读组件树，减少无关状态引发的重新解析。
  Widget? _readerBodyCache;

  /// _readerBodyKey：阅读组件缓存签名，包含源文、主题、偏好和资源基址。
  (String, bool, MarkdownPreferences, String)? _readerBodyKey;

  /// 判断外部预览是否仍未进入编辑原文件模式，决定工具是否可改写正文。
  bool get _readOnly => _externalPath != null && !_editingExternal;

  /// 组件仍挂载时执行状态更新，异步完成回调不得对已卸载状态 setState。
  void _change(VoidCallback action) {
    if (mounted) setState(action);
  }

  /// 建立源文、查找和滚动监听，应用偏好并异步初始化文件；卸载时解除监听与定时器。
  @override
  void initState() {
    super.initState();
    _service.history = MarkdownHistory(
      '${widget.dataRoot}${Platform.pathSeparator}.markdown-history',
    );
    _prefs = widget.preferences;
    _configurePreferences();
    _showToc = _prefs.openOutline;
    _mode = _MarkdownMode.values.byName(_prefs.defaultMode);
    _externalPath = widget.externalSourcePath;
    if (_externalPath != null) _mode = _MarkdownMode.read;
    _service.onAutoSaved = (ok) {
      if (!mounted) return;
      setState(() => _status = ok ? tr('已自动保存') : tr('自动保存失败，请重试保存'));
      if (ok) widget.onFileSaved?.call(_service.state!.path);
    };
    _initFile();
  }

  /// 按托管、外部或新建来源初始化文件状态与源文，载入完成后更新预览和初始标题定位。
  Future<void> _initFile() async {
    try {
      final state = _externalPath != null
          ? await _service.openExternalAsTemp(_externalPath!)
          : widget.filePath != null
          ? await _service.openFile(widget.filePath!)
          : _service.createNew(widget.dataRoot);
      if (!mounted) return;
      // 初始化有效光标，使撤销历史在工具栏修改前记录初始内容，
      // 即使源文稿的输入框从未获得焦点也能撤销。
      _text.value = TextEditingValue(
        text: state.content,
        selection: const TextSelection.collapsed(offset: 0),
      );
      _lastText = _preview = state.content;
      _text.addListener(_onTextChanged);
      setState(() {
        _file = state;
        _status =
            '${_readOnly ? tr('只读预览') : tr('已打开')} · ${_service.detectedEncoding}';
      });
      if (widget.initialHeading?.isNotEmpty == true) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final heading = _file!.tocItems
              .where(
                (item) =>
                    item.title.toLowerCase() ==
                    widget.initialHeading!.toLowerCase(),
              )
              .firstOrNull;
          if (heading != null) _jumpToOffset(heading.offset);
        });
      }
    } catch (error) {
      if (mounted) setState(() => _status = '${tr('打开失败')}: $error');
    }
  }

  /// 同步全文修改到文件服务、缓存统计与防抖预览，避免仅光标变化触发保存和重新解析。
  void _onTextChanged() {
    if (_readOnly || _text.text == _lastText) return;
    _lastText = _text.text;
    _service.updateContent(_lastText);
    setState(() => _status = tr('未保存'));
    _previewTimer?.cancel();
    _previewTimer = Timer(Duration(milliseconds: _prefs.previewDelayMs), () {
      if (mounted) setState(() => _preview = _text.text);
    });
  }

  /// 把当前偏好应用到文件自动保存、编辑显示及渲染相关状态，不重新生成正文。
  void _configurePreferences() {
    _service.historyEnabled = _prefs.historyEnabled;
    _service.historyLimit = _prefs.historyLimit;
    _service.autoSaveEnabled = _prefs.autoSave && !_editingExternal;
    _service.autoSaveDelayMs = _prefs.autoSaveDelayMs;
    _text.highlighting = _prefs.syntaxHighlight;
    _text.focusMode = _prefs.focusMode;
  }

  /// 更新 Markdown 偏好并同步所依赖的界面/服务；persist 为 true 时通知宿主保存。
  void _setPreferences(MarkdownPreferences next, {bool persist = true}) {
    final previous = _prefs;
    _change(() {
      _prefs = next;
      if (previous.defaultMode != next.defaultMode && !_readOnly) {
        _mode = _MarkdownMode.values.byName(next.defaultMode);
      }
      if (previous.openOutline != next.openOutline) _showToc = next.openOutline;
      _configurePreferences();
      _readerBodyKey = null;
    });
    if (_file?.isDirty == true && _service.autoSaveEnabled) {
      _service.updateContent(_text.text);
    }
    if (persist) widget.onPreferencesChanged?.call(next);
  }

  /// 同步宿主变化后的主题、文件请求与偏好，避免旧窗口配置继续驱动当前文件。
  @override
  void didUpdateWidget(covariant MarkdownEditorView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.preferences != widget.preferences &&
        widget.preferences != _prefs) {
      _setPreferences(widget.preferences, persist: false);
    }
  }

  /// 停止预览刷新并退出全屏，释放输入、查找、撤销与自动保存状态。
  @override
  void dispose() {
    _previewTimer?.cancel();
    if (_window.enabled) _window.setEnabled(false);
    _text.removeListener(_onTextChanged);
    _text.dispose();
    _find.dispose();
    _replace.dispose();
    _editorScroll.dispose();
    _previewScroll.dispose();
    _editorFocus.dispose();
    _findFocus.dispose();
    _undo.dispose();
    _service.dispose();
    super.dispose();
  }

  /// 组装 Markdown 顶部导航、编辑/预览、目录、查找和状态区，并安装对应快捷键与退出检查。
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _exit();
      },
      child: Scaffold(
        backgroundColor: colors.surface,
        body: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.keyP, control: true):
                _quickOpen,
            const SingleActivator(
              LogicalKeyboardKey.keyD,
              control: true,
              shift: true,
            ): () =>
                _editLines(MarkdownLineAction.duplicate),
            const SingleActivator(
              LogicalKeyboardKey.keyK,
              control: true,
              shift: true,
            ): () =>
                _editLines(MarkdownLineAction.delete),
            const SingleActivator(LogicalKeyboardKey.arrowUp, alt: true): () =>
                _editLines(MarkdownLineAction.moveUp),
            const SingleActivator(
              LogicalKeyboardKey.arrowDown,
              alt: true,
            ): () =>
                _editLines(MarkdownLineAction.moveDown),
            const SingleActivator(
              LogicalKeyboardKey.enter,
              control: true,
            ): () =>
                _editLines(MarkdownLineAction.toggleTask),
            const SingleActivator(LogicalKeyboardKey.f3): _findNext,
            const SingleActivator(LogicalKeyboardKey.f3, shift: true): () =>
                _findNext(backwards: true),
            const SingleActivator(LogicalKeyboardKey.keyS, control: true):
                _save,
            const SingleActivator(LogicalKeyboardKey.keyF, control: true):
                _openFind,
            const SingleActivator(LogicalKeyboardKey.keyH, control: true):
                _openFind,
            const SingleActivator(LogicalKeyboardKey.keyB, control: true): () =>
                _wrap('**', '**'),
            const SingleActivator(LogicalKeyboardKey.keyI, control: true): () =>
                _wrap('*', '*'),
            const SingleActivator(LogicalKeyboardKey.escape): () {
              if (_showFind) {
                setState(() => _showFind = false);
              } else if (_window.enabled) {
                _toggleFullscreen();
              } else if (_prefs.focusMode) {
                _setPreferences(_prefs.copyWith(focusMode: false));
              }
            },
            const SingleActivator(
              LogicalKeyboardKey.keyP,
              control: true,
              shift: true,
            ): _commandPalette,
            const SingleActivator(
              LogicalKeyboardKey.keyO,
              control: true,
              shift: true,
            ): _quickHeading,
            const SingleActivator(LogicalKeyboardKey.keyL, control: true):
                _goToLine,
            const SingleActivator(
              LogicalKeyboardKey.keyV,
              control: true,
              alt: true,
            ): _pasteImage,
            const SingleActivator(LogicalKeyboardKey.f11): _toggleFullscreen,
            const SingleActivator(
              LogicalKeyboardKey.keyJ,
              control: true,
              shift: true,
            ): () =>
                _setPreferences(_prefs.copyWith(focusMode: !_prefs.focusMode)),
            const SingleActivator(
              LogicalKeyboardKey.keyG,
              control: true,
              shift: true,
            ): () => _setPreferences(
              _prefs.copyWith(typewriter: !_prefs.typewriter),
            ),
          },
          child: Focus(
            autofocus: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _toolbar(colors),
                if (_exporting) const LinearProgressIndicator(minHeight: 2),
                if (widget.openedPaths.length > 1) _documentTabs(),
                if (_readOnly) _externalBanner(),
                if (!_readOnly &&
                    !_prefs.focusMode &&
                    _mode != _MarkdownMode.read)
                  _formatBar(),
                if (_showFind) _findBar(),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final narrow = constraints.maxWidth < 900;
                      final split =
                          _mode == _MarkdownMode.split &&
                          constraints.maxWidth >= 700;
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_showToc && !narrow)
                            SizedBox(width: 210, child: _toc()),
                          Expanded(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Flexible(
                                  fit: _sourceHidden
                                      ? FlexFit.loose
                                      : FlexFit.tight,
                                  flex: _sourceHidden
                                      ? 0
                                      : split
                                      ? (_splitRatio * 100).round()
                                      : 1,
                                  child: SizedBox(
                                    width: _sourceHidden ? 0 : null,
                                    child: Offstage(
                                      offstage: _sourceHidden,
                                      child: ExcludeFocus(
                                        excluding: _sourceHidden,
                                        child: OverflowBox(
                                          minWidth: _sourceHidden ? 600 : 0,
                                          maxWidth: _sourceHidden ? 600 : null,
                                          alignment: Alignment.topLeft,
                                          child: _editor(),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                if (split)
                                  MouseRegion(
                                    cursor: SystemMouseCursors.resizeColumn,
                                    child: GestureDetector(
                                      onHorizontalDragUpdate: (details) =>
                                          setState(
                                            () => _splitRatio =
                                                (_splitRatio +
                                                        details.delta.dx /
                                                            constraints
                                                                .maxWidth)
                                                    .clamp(.25, .75),
                                          ),
                                      child: Container(
                                        width: 5,
                                        color: colors.outlineVariant,
                                      ),
                                    ),
                                  ),
                                if (_mode == _MarkdownMode.live)
                                  Expanded(
                                    child: MarkdownLiveEditor(
                                      key: _liveKey,
                                      controller: _text,
                                      preferences: _prefs,
                                      undo: _undo,
                                      renderBlock: (content, offset) =>
                                          _markdownBody(
                                            content,
                                            dark: widget.darkMode,
                                            liveOffset: offset,
                                          ),
                                      onEditTable: _editTable,
                                      onProperties: _propertiesDialog,
                                      onPasteImage: _pasteImage,
                                    ),
                                  ),
                                if (_mode == _MarkdownMode.read || split)
                                  Expanded(
                                    flex: split
                                        ? ((1 - _splitRatio) * 100).round()
                                        : 1,
                                    child: _reader(),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                if (!_prefs.focusMode) _statusBar(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 构建文件保存、标签、模式、目录和更多操作的顶部区域，外部预览使用明确的来源提示。
  Widget _toolbar(ColorScheme colors) => Material(
    color: colors.surfaceContainerLow,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Row(
        children: [
          IconButton(
            tooltip: tr('返回'),
            onPressed: _exporting ? null : _exit,
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          Expanded(
            child: InkWell(
              onTap: _readOnly || _editingExternal ? null : _rename,
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      _file?.fileName ?? 'Markdown',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (_file?.isDirty == true)
                    Padding(
                      padding: const EdgeInsets.all(6),
                      child: Icon(Icons.circle, size: 7, color: colors.primary),
                    ),
                ],
              ),
            ),
          ),
          IconButton(
            tooltip: tr('查找 / 替换'),
            onPressed: _openFind,
            icon: const Icon(Icons.manage_search_rounded),
          ),
          IconButton(
            tooltip: tr('目录'),
            isSelected: _showToc,
            onPressed: _toggleToc,
            icon: const Icon(Icons.toc_rounded),
          ),
          IconButton(
            tooltip: tr('本文待办总览'),
            onPressed: _tasksDialog,
            icon: const Icon(Icons.checklist),
          ),
          PopupMenuButton<_MarkdownMode>(
            popUpAnimationStyle: appMotionStyle(context),
            tooltip: tr('编辑 / 分栏 / 阅读'),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(switch (_mode) {
                    _MarkdownMode.live => Icons.auto_awesome_motion_outlined,
                    _MarkdownMode.edit => Icons.edit_note_rounded,
                    _MarkdownMode.split => Icons.vertical_split_rounded,
                    _MarkdownMode.read => Icons.chrome_reader_mode_outlined,
                  }),
                  if (MediaQuery.sizeOf(context).width >= 900) ...[
                    const SizedBox(width: 6),
                    Text(
                      tr(switch (_mode) {
                        _MarkdownMode.live => '实时编辑',
                        _MarkdownMode.edit => '编辑',
                        _MarkdownMode.split => '分栏',
                        _MarkdownMode.read => '阅读',
                      }),
                    ),
                  ],
                ],
              ),
            ),
            onSelected: (mode) {
              _change(() {
                _mode = mode;
                _preview = _text.text;
              });
              _setPreferences(_prefs.copyWith(defaultMode: mode.name));
            },
            itemBuilder: (_) => [
              for (final mode in _MarkdownMode.values)
                CheckedPopupMenuItem(
                  value: mode,
                  enabled: mode != _MarkdownMode.live || !_readOnly,
                  checked: mode == _mode,
                  child: Text(switch (mode) {
                    _MarkdownMode.live => tr('实时编辑（点击段落修改）'),
                    _MarkdownMode.edit => tr('仅编辑'),
                    _MarkdownMode.split => tr('编辑与预览（窄窗口仅编辑）'),
                    _MarkdownMode.read => tr('仅阅读'),
                  }),
                ),
            ],
          ),
          IconButton(
            tooltip: tr('保存'),
            onPressed: _readOnly || _saving || _exporting ? null : _save,
            icon: const Icon(Icons.save_outlined),
          ),
          PopupMenuButton<String>(
            popUpAnimationStyle: appMotionStyle(context),
            tooltip: tr('导出'),
            icon: const Icon(Icons.ios_share_rounded),
            enabled: !_exporting,
            onSelected: _menuAction,
            itemBuilder: (_) => [
              _menuItem(
                _prefs.exportFormat,
                Icons.file_upload_outlined,
                '快捷导出（${_prefs.exportFormat.toUpperCase()}）',
              ),
              const PopupMenuDivider(),
              _menuItem('docx', Icons.description, '导出 Word（DOCX）'),
              _menuItem('txt', Icons.text_snippet_outlined, '导出纯文本'),
              _menuItem('html', Icons.html, '导出 HTML'),
              _menuItem('md', Icons.description_outlined, '导出 Markdown 源文件'),
              _menuItem('pdf', Icons.picture_as_pdf_outlined, '导出 PDF'),
              _menuItem('png', Icons.image_outlined, '导出 PNG 长图'),
              _menuItem('jpg', Icons.photo_outlined, '导出 JPG 长图'),
            ],
          ),
          PopupMenuButton<String>(
            popUpAnimationStyle: appMotionStyle(context),
            tooltip: tr('更多操作'),
            onSelected: _menuAction,
            itemBuilder: (_) => [
              _menuItem('quick-open', Icons.folder_open, '快速打开文稿'),
              _menuItem('tasks', Icons.checklist, '本文待办总览'),
              _menuItem('workspace', Icons.search, '全文搜索与标签'),
              _menuItem('links', Icons.hub_outlined, '双链与反向链接'),
              _menuItem('properties', Icons.data_object, '文稿属性'),
              _menuItem('history', Icons.history, '本地版本历史'),
              _menuItem('slides', Icons.slideshow, '幻灯片演示'),
              _menuItem('commands', Icons.terminal, '命令面板'),
              _menuItem('preferences', Icons.tune, 'Markdown 设置'),
              _menuItem('templates', Icons.article_outlined, '从模板插入'),
              _menuItem(
                'save-template',
                Icons.bookmark_add_outlined,
                '保存为自定义模板',
              ),
              _menuItem(
                'manage-templates',
                Icons.folder_copy_outlined,
                '管理自定义模板',
              ),
              _menuItem('fullscreen', Icons.fullscreen, '全屏'),
              CheckedPopupMenuItem(
                value: 'focus',
                checked: _prefs.focusMode,
                child: Text(tr('专注写作')),
              ),
              CheckedPopupMenuItem(
                value: 'typewriter',
                checked: _prefs.typewriter,
                child: Text(tr('打字机模式')),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  /// 以稳定动作标识、图标和翻译标签生成一致菜单项。
  PopupMenuItem<String> _menuItem(String value, IconData icon, String label) =>
      PopupMenuItem(
        value: value,
        child: Row(
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: 12),
            Flexible(child: Text(tr(label))),
          ],
        ),
      );

  /// 构建源文格式、撤销重做和行操作工具条，动作以当前源文选区为目标。
  Widget _formatBar() => Material(
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          ValueListenableBuilder<UndoHistoryValue>(
            valueListenable: _undo,
            builder: (_, value, _) => Row(
              children: [
                IconButton(
                  tooltip: tr('撤销'),
                  onPressed: value.canUndo ? _undo.undo : null,
                  icon: const Icon(Icons.undo_rounded, size: 20),
                ),
                IconButton(
                  tooltip: tr('重做'),
                  onPressed: value.canRedo ? _undo.redo : null,
                  icon: const Icon(Icons.redo_rounded, size: 20),
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            popUpAnimationStyle: appMotionStyle(context),
            tooltip: tr('行操作', 'Line actions'),
            icon: const Icon(Icons.format_line_spacing, size: 20),
            onSelected: _menuAction,
            itemBuilder: (_) => [
              _menuItem('duplicate-line', Icons.copy, '复制当前行 / 选中行'),
              _menuItem('move-line-up', Icons.arrow_upward, '上移当前行 / 选中行'),
              _menuItem('move-line-down', Icons.arrow_downward, '下移当前行 / 选中行'),
              _menuItem('delete-line', Icons.delete_outline, '删除当前行 / 选中行'),
              _menuItem('toggle-task', Icons.check_box_outlined, '完成 / 取消当前待办'),
            ],
          ),
          _button(Icons.format_bold, '粗体', () => _wrap('**', '**')),
          _button(Icons.format_italic, '斜体', () => _wrap('*', '*')),
          _button(Icons.strikethrough_s, '删除线', () => _wrap('~~', '~~')),
          PopupMenuButton<int>(
            popUpAnimationStyle: appMotionStyle(context),
            tooltip: tr('标题级别'),
            icon: const Icon(Icons.title, size: 20),
            onSelected: (level) => _prefix('${'#' * level} ', heading: true),
            itemBuilder: (_) => [
              for (int i = 1; i <= 6; i++)
                PopupMenuItem(value: i, child: Text('H$i')),
            ],
          ),
          _button(Icons.format_list_bulleted, '无序列表', () => _prefix('- ')),
          _button(Icons.format_list_numbered, '有序列表', () => _prefix('1. ')),
          _button(Icons.checklist_rounded, '待办列表', () => _prefix('- [ ] ')),
          _button(Icons.format_quote, '引用', () => _prefix('> ')),
          _button(Icons.code, '行内代码', () => _wrap('`', '`')),
          _button(Icons.code_off, '代码块', () => _block('```\n', '\n```')),
          _button(Icons.functions, '公式', () => _block('\$\$\n', '\n\$\$')),
          _button(Icons.link, '链接', () => _wrap('[', '](https://)')),
          _button(Icons.image_outlined, '插入图片文件', _insertImage),
          _button(Icons.table_chart_outlined, '插入表格', _editTable),
          _button(Icons.horizontal_rule, '分隔线', () => _block('\n---\n', '')),
        ],
      ),
    ),
  );

  /// 创建带可读提示的格式按钮并绑定指定 action，避免只显示难辨认图标。
  Widget _button(IconData icon, String label, VoidCallback action) =>
      IconButton(
        tooltip: tr(label),
        onPressed: action,
        icon: Icon(icon, size: 20),
        visualDensity: VisualDensity.compact,
      );

  /// 建立全文编辑区及滚动通知，源文焦点、撤销控制器和偏好由当前会话持有。
  Widget _editor() => NotificationListener<ScrollUpdateNotification>(
    onNotification: (_) {
      _sync(_editorScroll, _previewScroll);
      return false;
    },
    child: MarkdownSourceEditor(
      controller: _text,
      scroll: _editorScroll,
      focus: _editorFocus,
      undo: _undo,
      preferences: _prefs,
      onPasteImage: _pasteImage,
      readOnly: _readOnly || _file == null,
    ),
  );

  /// 按可滚动范围映射源码与预览位置，使用同步标志阻止两个控制器循环触发。
  void _sync(ScrollController source, ScrollController target) {
    if (!_syncScroll ||
        _syncing ||
        !source.hasClients ||
        !target.hasClients ||
        source.position.maxScrollExtent <= 0) {
      return;
    }
    _syncing = true;
    try {
      final ratio = (source.offset / source.position.maxScrollExtent).clamp(
        0.0,
        1.0,
      );
      target.jumpTo(ratio * target.position.maxScrollExtent);
    } finally {
      _syncing = false;
    }
  }

  /// 局部订阅文字/选区值显示保存状态、统计与光标信息，不因每次光标移动重新解析全文。
  Widget _statusBar() => ValueListenableBuilder<TextEditingValue>(
    valueListenable: _text,
    builder: (_, value, _) => Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _status,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
            ),
            const SizedBox(width: 12),
            if (_prefs.showWordCount)
              Flexible(
                child: Text(
                  '${_writingCounts.$1} ${tr('行')} · ${_writingCounts.$2} ${tr('字 / 词', 'words')}'
                  '${value.selection.isValid && !value.selection.isCollapsed ? ' · ${tr('选中', 'Selected')} ${markdownWordCount(value.selection.textInside(value.text))}' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
