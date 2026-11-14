import 'dart:async';
import 'dart:convert';

// 模块职责见项目根目录 ARCHITECTURE.md。本文件装配应用和共享状态。
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:filepicker_windows/filepicker_windows.dart';

import '../engine/ink_canvas.dart';
import '../core/text_box_placement.dart';
import '../widgets/library_note_preview.dart';
import '../widgets/text_object_toolbar.dart';
import '../widgets/app_screen_transition.dart';
import '../widgets/library_document_picker.dart';
import '../platform/render_power_policy.dart';
import '../platform/native_pen_pressure.dart';
import '../core/app_localizations.dart';
import '../core/app_version.dart';
import '../core/canvas_edit_shortcut.dart';
import '../core/crash_guard.dart';
import '../core/document_viewport_layout.dart';
import '../export/export_repository.dart';
import '../storage/library_repository.dart';
import '../core/memory_policy.dart';
import '../core/memory_policy_catalog.dart';
import '../models/models.dart';
import '../storage/note_repository.dart';
import '../core/page_prefetch_planner.dart';
import '../core/page_motion.dart';
import '../core/image_cache_budget.dart';
import '../core/image_file_decode.dart';
import '../widgets/embedded_image_layer.dart';
import '../models/pdf_outline.dart';
import '../widgets/pdf_outline_tree.dart';
import '../widgets/library_document_drag.dart';
import '../widgets/export_progress_panel.dart';
import '../core/page_ink_cache.dart';
import '../core/settings_repository.dart';
import '../controllers/document_controller.dart';
import '../controllers/tool_controller.dart';
import '../controllers/viewport_controller.dart';
import '../core/app_settings_controller.dart';
import '../platform/windows_registry.dart' as winreg;
import '../platform/windows_fullscreen.dart';
import '../platform/windows_capture.dart';
import '../capture/screenshot_document.dart';
import '../capture/screenshot_editor.dart';
import '../features/markdown/markdown_editor.dart';
import '../platform/markdown_editor_service.dart';
import '../platform/markdown_encoding.dart';
import '../platform/markdown_workspace.dart';
import '../widgets/markdown_settings_panel.dart';
import '../widgets/paper_template_dialog.dart';
import '../widgets/page_batch_dialog.dart';
import '../storage/library_backup.dart';
import '../storage/template_library.dart';
part '../core/pen_button_action.dart';
part 'fastink_home.dart';
part 'home_formatters.dart';
part '../features/document/home_fullscreen.dart';
part '../features/document/home_screenshot.dart';
part '../features/settings/home_settings.dart';
part '../features/settings/home_settings_memory.dart';
part '../features/settings/home_settings_workflow.dart';
part '../features/document/home_memory_pressure.dart';
part '../features/library/home_library_core.dart';
part '../features/library/home_onenote_import.dart';
part '../features/document/home_dialogs.dart';
part '../features/document/home_export_dialog.dart';
part '../features/library/home_library_actions.dart';
part '../features/library/home_library_drag.dart';
part '../features/library/home_storage_actions.dart';
part '../features/document/home_input_tools.dart';
part '../features/document/home_canvas_shortcuts.dart';
part '../features/document/home_document_shell.dart';
part '../features/document/home_document_load.dart';
part '../features/document/home_document_input.dart';
part '../features/document/home_touch_page_flow.dart';
part '../features/document/home_navigation_ui.dart';
part '../features/document/home_document_tabs.dart';
part '../features/document/home_toolbar.dart';
part '../features/document/home_toolbar_zoom.dart';
part '../features/document/home_toolbar_preferences.dart';
part '../features/document/home_text_editor.dart';
part '../features/document/home_text_properties.dart';
part '../features/document/home_text_controls.dart';
part '../features/document/home_laser_controls.dart';
part '../features/document/home_pen_controls.dart';
part '../features/document/home_lasso_controls.dart';
part '../features/document/home_selection_editing.dart';
part '../features/document/home_document_search.dart';
part '../features/document/home_pen_presets.dart';
part '../features/library/home_library_ui.dart';
part '../features/library/home_library_content.dart';
part '../features/settings/home_settings_ui.dart';
part '../features/settings/home_settings_cards_primary.dart';
part '../features/settings/home_settings_cards_behavior.dart';
part '../features/settings/home_settings_cards_pen.dart';
part '../features/settings/home_settings_cards_navigation.dart';
part '../features/settings/home_settings_cards_memory.dart';
part '../features/settings/home_settings_cards_import_export.dart';
part '../features/settings/home_settings_cards_laser.dart';
part '../features/settings/home_settings_import_export.dart';
part '../features/settings/home_settings_cards_about.dart';
part '../features/settings/home_settings_cards_workflow.dart';
part '../features/library/home_library_cards.dart';
part '../features/library/home_library_item_cards.dart';
part '../features/document/home_document_view.dart';
part '../features/document/home_document_page.dart';
part '../features/document/home_document_viewport.dart';
part '../features/document/home_virtual_document_viewport.dart';
part '../features/document/home_document_overlays.dart';
part '../features/document/home_page_sidebar.dart';
part '../features/document/home_page_ops.dart';
part '../features/document/home_page_mutations.dart';
part '../features/document/home_components.dart';
part '../features/document/home_interaction_components.dart';
part 'app_shell.dart';

/// 初始化 Flutter、异常兜底与配置，解析普通/外部文件启动参数，再挂载应用；启动期间不预先解码整本文稿。
Future<void> main(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();
  CrashGuard.install();
  // Windows 右键上下文菜单支持：初始化 FFI，提前检测能力。
  if (Platform.isWindows) {
    winreg.initWindowsRegistryFfi();
  }
  // 在创建任何页面前加载设置，首帧直接使用正确的语言、缓存预算和主题。
  final AppSettings settings = await SettingsRepository.initialize();
  final MemoryPolicy memoryPolicy = MemoryPolicyCatalog.resolve(
    settings.deviceMemoryGb,
  );
  ImageCacheBudget.apply(
    entries: math.min(
      settings.imageCacheEntries,
      memoryPolicy.imageCacheEntries,
    ),
    megabytes: math.min(
      settings.imageCacheMegabytes,
      memoryPolicy.imageCacheMegabytes,
    ),
  );
  // 处理命令行参数：--open-external "path" 或直接传入文件路径。
  String? initialPath;
  String? externalFilePath;
  final List<String> args = arguments;
  // 优先检查 --open-external 标志（右键菜单触发）。
  final int flagIndex = args.indexOf('--open-external');
  if (flagIndex != -1 && flagIndex + 1 < args.length) {
    final String candidate = args[flagIndex + 1];
    if (_isSupportedFile(candidate)) {
      externalFilePath = candidate;
    }
    // 不支持的文件类型静默忽略（右键菜单对所有文件可见）。
  } else {
    // 没有标志时，查找第一个图片或 PDF 文件路径。
    initialPath = args.where(_isSupportedFile).firstOrNull;
  }
  final AppLanguage initialLanguage = AppLanguage.values.firstWhere(
    (AppLanguage value) => value.name == settings.language,
    orElse: () => AppLanguage.system,
  );
  AppText.locale = initialLanguage.resolve();
  runApp(
    FastInkApp(
      initialPath: initialPath,
      externalFilePath: externalFilePath,
      settings: settings,
    ),
  );
}

/// 检查参数是否为 FastInk 支持的文件路径。
///
/// 支持的类型：
///   - 图片 (.png/.jpg/.webp)：作为 FastInk 笔记的页面打开。
///   - PDF (.pdf)：复制到 %temp% 后只读预览。
///   - Markdown (.md)：复制到 %temp% 后只读预览，可导入编辑。
///   - FastInk 元数据 (.fastink-notebook.json / .fastink-pdf.json)：
///     打开对应的笔记/PDF 文档。
bool _isSupportedFile(String value) {
  final String lower = value.toLowerCase();
  // FastInk 元数据文件：.fastink-notebook.json / .fastink-pdf.json
  if (lower.endsWith('.fastink-notebook.json') ||
      lower.endsWith('.fastink-pdf.json')) {
    return File(value).existsSync();
  }
  return RegExp(
        r'\.(png|jpe?g|webp|pdf|md)$',
        caseSensitive: false,
      ).hasMatch(lower) &&
      File(value).existsSync();
}

class _FastInkHomeState extends State<FastInkHome>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  /// _copiedInk：应用内选区剪贴板的独立笔画快照，粘贴时再创建目标对象。
  List<InkStroke> _copiedInk = <InkStroke>[];

  /// _copiedInkDocument：选区剪贴板内容所属源文稿，用于迁移嵌入资源路径。
  NoteDocument? _copiedInkDocument;

  /// _pastingInk：是否正在处理跨文稿粘贴，防止重复触发重叠的资源导入。
  bool _pastingInk = false;

  /// _captureBusy：截图交互是否独占输入，期间侧键不应切换底层文稿工具。
  bool _captureBusy = false;

  /// _stablePenMenu：可复用的笔型菜单组件，签名未改变时不因保存提示刷新而重建。
  Widget? _stablePenMenu;

  /// _stablePenMenuSignature：影响笔型菜单的状态签名，真正选项变化才作废稳定组件。
  Object? _stablePenMenuSignature;

  /// _capturePenButtons：截图使用的原始侧键位掩码通知器，按下与松开都需要更新。
  final ValueNotifier<int> _capturePenButtons = ValueNotifier(0);

  /// _inkClipboardSequence：复制选区时观察到的系统剪贴板序列，辨别外部复制是否覆盖应用内内容。
  int? _inkClipboardSequence;

  /// 当前首页状态变更的统一 setState 包装，调用方仍需处理异步 mounted 与任务代次。
  void _updateState(VoidCallback change) => setState(change);

  // ━━━━ 仓库与控制器 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  /// _penChannel：接收 Windows 原生压力和侧键事件的方法通道。
  static const MethodChannel _penChannel = MethodChannel('fastink/pen');

  /// _repository：所属模块的数据仓库依赖；实际读写范围由声明类型和构造根目录决定。
  late NoteRepository _repository;

  /// _exportRepository：导出服务依赖，复用当前资料库读取能力并独立控制导出预算。
  late ExportRepository _exportRepository;

  /// _libraryRepository：资料库索引仓库，只保存文稿/文件夹等轻量记录，不持有整本位图。
  late LibraryRepository _libraryRepository;

  /// _settingsRepository：负责配置持久化的仓库，局部设置更新需经过它的串行写入队列。
  late final SettingsRepository _settingsRepository =
      widget.settingsRepository ?? SettingsRepository();

  /// _prefetchPlanner：根据翻页速度和方向规划邻页预取，快速跳页时减少无效任务。
  final PagePrefetchPlanner _prefetchPlanner = PagePrefetchPlanner();

  /// _dataRoot：运行时采用的资料库根目录；迁移完成后相关仓库必须一起切换。
  late String _dataRoot;

  /// _settings：当前运行时设置副本；与临时工具状态、文稿内容分别维护。
  late final AppSettingsController _settings; // 运行时设置副本（~40 字段）
  /// _toolState：当前工具、颜色、侧键覆盖和文字样式等瞬时状态，不等于打开文稿默认设置。
  late final ToolController _toolState; // 工具运行时状态（15 字段）

  // ━━━━ UI 控制器 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  /// _applyDefaultFitOnNextLayout：下一次有效布局是否应用默认页面适配，完成后复位避免重复改变相机。
  bool _applyDefaultFitOnNextLayout = false;

  /// _pageInput：顶部页码文本控制器；显示页码从 1 开始，内部 pageIndex 从 0 开始。
  final TextEditingController _pageInput = TextEditingController(text: '1');

  /// _searchInput：资料库查询文本控制器，查询变化仅更新列表，不重建整个导航界面。
  final TextEditingController _searchInput = TextEditingController();

  /// _librarySearchFocus：资料库搜索框焦点，Ctrl+F 请求聚焦，宿主卸载时释放。
  final FocusNode _librarySearchFocus = FocusNode(debugLabel: 'Library search');

  /// _inlineTextController：纸面输入面板的全文与输入法状态，提交前不写入持久笔画。
  final TextEditingController _inlineTextController = TextEditingController();

  /// _toolbarScroll：横向工具栏滚动控制器，窄窗口用来访问超出宽度的工具。
  final ScrollController _toolbarScroll = ScrollController();

  /// _thumbnailScroll：页面/书签缩略图列表滚动控制器，用于定位与可见范围加载。
  final ScrollController _thumbnailScroll = ScrollController();

  /// _canvasFocus：画布键盘焦点，供快捷键与文字提交后回到画布使用。
  final FocusNode _canvasFocus = FocusNode(debugLabel: 'FastInk canvas');

  /// _inlineTextFocus：纸面输入面板焦点；编辑文字时保留文本自己的键盘和撤销行为。
  final FocusNode _inlineTextFocus = FocusNode(
    debugLabel: 'FastInk inline text',
  );

  /// _ink：当前实际装载页的可编辑笔迹控制器；保存目标必须用 inkPage 归属而非只看显示页码。
  late final InkController _ink = InkController(onCommitted: _inkCommitted);

  // ━━━━ 视口与缩放 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  /// _viewport：相机矩阵、页面布局和导航定时状态；不保存笔迹内容。
  late final ViewportController _viewport;

  /// _textMotionController：文本定位动画控制器，只改变显示插值，用户接管或卸载时结束/释放。
  AnimationController? _textMotionController;

  /// _textMotionCameraFrom：文本定位前的相机矩阵快照，供平滑定位插值；_textMotionCameraTo：文本定位后的目标相机矩阵，动画结束后成为当前视口。
  Matrix4? _textMotionCameraFrom, _textMotionCameraTo;

  // ━━━━ 触摸与手势 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // 浮动工具条的触摸不参与画布平移，避免移动文字时页面也跟着走。
  /// _overlayPointers：在浮层上按下的指针编号；排除在纸面双击/平移手势识别之外。
  final Set<int> _overlayPointers = {};

  /// _previewViewActivity：最近相机活动的计时，侧栏次要预览在电池模式下等待导航空隙。
  final Stopwatch _previewViewActivity = Stopwatch();

  /// _touchPoints：当前参与手指导航的指针及局部逻辑位置，不参与触笔采样。
  final Map<int, Offset> _touchPoints = <int, Offset>{};

  /// _touchPanVelocity：估算的手指平移速度，用于松手后的惯性相机运动。
  Offset _touchPanVelocity = Offset.zero;

  /// _touchPanLastMove：上一次触摸移动的事件时间，用于按真实间隔估算速度。
  Duration? _touchPanLastMove;

  /// _nativePressure：原生 Windows 压力桥状态，区分设备与时效，防止鼠标覆盖触笔压力。
  final NativePenPressure _nativePressure = NativePenPressure();

  /// _pinchStartDistance：本轮双指手势起始距离，单位逻辑像素。
  double _pinchStartDistance = 1;

  /// _pinchStartScale：本轮双指手势起始相机倍数，捏合始终相对它计算。
  double _pinchStartScale = 1;

  /// _pinchSceneFocal：双指开始时的文稿坐标焦点，缩放围绕该点保持稳定。
  Offset _pinchSceneFocal = Offset.zero;

  /// _canvasViewport：主画布可用尺寸，单位屏幕逻辑像素。
  Size _canvasViewport = Size.zero;

  /// _pageViewportRect：当前页在连续文稿布局中的矩形，用于相机与页内坐标换算。
  Rect _pageViewportRect = Rect.zero;

  // ━━━━ 文本编辑（内联） ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  /// _inlineTextPoint：正在输入文字的归一化页面锚点；为空表示没有纸面输入面板。
  InkPoint? _inlineTextPoint;

  /// _textToolbarMovePoint：通过文本工具条拖动时记录的起始点，松手后清理。
  InkPoint? _textToolbarMovePoint;

  /// _editingTextStroke：正在编辑的已有文字对象；为空时此次输入将创建新对象。
  InkStroke? _editingTextStroke;

  /// _inlineTextSize：当前输入文字的页面逻辑字号，独立于屏幕输入预览的字号上限。
  double _inlineTextSize = 12;

  /// _textObstacles：当前页面已有内容占用矩形，供自适应文本避让，编辑目标自身应排除。
  List<Rect> _textObstacles = [];

  /// _adaptiveTextContent：最近完成自适应测量的全文，用于跳过仅光标变化的重复排版。
  String? _adaptiveTextContent;

  /// _adaptiveTextStyle：最近完成自适应测量的样式签名，字体或宽度变化时触发重算。
  Object? _adaptiveTextStyle;

  /// _autoTextWidth：输入面板是否根据全文自动计算文本宽度；已有框编辑可使用固定宽度。
  bool _autoTextWidth = true;

  /// _inlineTextCanvasSize：文字排版和保存使用的原页面逻辑尺寸，不随屏幕缩放直接变化。
  Size _inlineTextCanvasSize = Size.zero;

  /// _inlineTextEditorWidth：文本保存到页面时使用的布局宽度，单位页面逻辑像素。
  double _inlineTextEditorWidth = 280;

  /// _inlineTextScreenWidth：紧凑输入面板在屏幕上的宽度，单位屏幕逻辑像素。
  double _inlineTextScreenWidth = 224;

  /// _inlineTextAngle：正在编辑的文本旋转角，单位弧度，用于恢复既有几何。
  double _inlineTextAngle = 0;

  // ━━━━ 文档与资料库 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  /// _doc：当前文稿生命周期与保存状态；页面归属、加载标志和重任务锁集中维护。
  late final DocumentController _doc;

  /// _library：当前资料库轻量索引快照，包含文稿与文件夹元数据。
  LibraryState _library = const LibraryState();

  /// _librarySection：当前资料库类别标识：文稿、Markdown、收藏、最近、废纸篓或设置。
  String _librarySection = 'documents';

  /// _settingsCategory：设置当前分类标识，通用、手写与 Markdown 的滚动位置分别保存。
  String _settingsCategory = 'general';

  /// _activeFolderId：资料库当前展开的文件夹编号；null 表示根目录/未展开。
  String? _activeFolderId;

  /// _libraryDraggingDocumentId：正在拖动的资料库文稿编号，用于显示适用的移出目标。
  String? _libraryDraggingDocumentId;

  /// _libraryBusy：资料库是否正在导入、迁移等阻塞操作，用于进度反馈和防止重复提交。
  bool _libraryBusy = false;

  /// _libraryLoaded：首次索引读取是否完成，区分尚未加载与真正没有文稿。
  bool _libraryLoaded = false;

  /// _exportProgress：独立导出进度通知器，计时刷新不重建整个文档界面。
  final ValueNotifier<ExportProgress?> _exportProgress = ValueNotifier(null);

  /// _exportTitle：本次导出进度面板使用的文稿/任务标题。
  String _exportTitle = '';

  /// _pdfOutlineReading：正在读取目录的文稿编号集合，同一文稿不重复启动读取。
  final Set<String> _pdfOutlineReading = {};

  /// _showPageSidebar：是否显示页面/目录/书签侧栏，关闭后排队预览任务不再启动。
  bool _showPageSidebar = false;

  /// _immersiveMode：是否处于全屏书写布局；窗口全屏状态由平台桥另外管理。
  bool _immersiveMode = false;

  /// _windowFullscreen：Windows 全屏控制桥，负责保存与恢复原窗口样式和位置。
  final WindowsFullscreen _windowFullscreen = WindowsFullscreen();

  /// _sidebarTab：当前侧栏页签编号：页面、目录或书签。
  int _sidebarTab = 0;

  /// _contextMenuRegistered：Windows 文件右键入口是否已注册，用于设置界面展示当前状态。
  bool _contextMenuRegistered = false;

  /// _markdownEditorOpen：顶层路由当前是否展示 Markdown 编辑器，不与手写画布同时挂载。
  bool _markdownEditorOpen = false;

  /// _markdownEditorFilePath：当前 Markdown 文件路径；创建新文稿前可为空。
  String? _markdownEditorFilePath;

  /// _markdownInitialHeading：打开 Markdown 后需要定位的标题片段，属于一次导航请求。
  String? _markdownInitialHeading;

  /// _markdownEditorSession：Markdown 编辑器会话编号，换文件时用于建立正确组件身份。
  int _markdownEditorSession = 0;

  /// _markdownOpenTabs：当前会话打开的 Markdown 路径列表，保留切换顺序。
  final List<String> _markdownOpenTabs = [];

  /// _markdownExternalSourcePath：外部 Markdown 原文件位置，与资料库内托管路径区分。
  String? _markdownExternalSourcePath;

  // ━━━━ 缓存与定时器 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  /// 按页面路径缓存实际纸色明暗及是否有模板，供主画布和侧栏共享。
  final _paperAppearanceCache = <String, _PaperAppearance>{};

  /// 只合并同一版本的纸张查询，换纸后可立即读取新底图。
  final _paperAppearanceFlights = <(String, int), Future<_PaperAppearance>>{};

  /// 同一路径的底图替换次数，参与解码缓存键和异步结果校验。
  final _paperImageRevisions = <String, int>{};

  /// _pageAspectRatioCache：按页面路径缓存的真实宽高比，保证首帧几何与最终底图一致。
  final Map<String, double> _pageAspectRatioCache = <String, double>{};

  /// _pageAspectRatioFlights：按页面路径合并的宽高比读取任务，结束后移除。
  final Map<String, Future<double>> _pageAspectRatioFlights =
      <String, Future<double>>{};

  /// _lastMemoryRelief：最近一次瞬态缓存清理时刻，避免短时间内重复清理产生抖动。
  DateTime _lastMemoryRelief = DateTime.fromMillisecondsSinceEpoch(0);

  /// _sidebarThumbnailTimer：侧栏滚动停止后才启动的防抖任务，新滚动会取消旧请求。
  Timer? _sidebarThumbnailTimer;

  /// _sidebarThumbnailUpdateTimer：一批侧栏预览完成后的合并界面刷新任务。
  Timer? _sidebarThumbnailUpdateTimer;

  /// _sidebarThumbnailGeneration：侧栏加载代次，换文稿或滚动范围变化后旧请求作废。
  int _sidebarThumbnailGeneration = 0;
  // 同一可见范围只允许一批预览排队，等待用户操作时不累积重复任务。
  /// _sidebarInkQueued：已排队的侧栏笔迹代次，同一可见范围只保留一批任务。
  final Set<int> _sidebarInkQueued = {};

  /// _sidebarImagesQueued：已排队的侧栏 PDF 图像代次，避免界面重建堆积重复渲染。
  final Set<int> _sidebarImagesQueued = {};

  /// _sidebarThumbnailChain：侧栏页面图像渲染串行队列，与笔迹读取队列分开。
  Future<void> _sidebarThumbnailChain = Future<void>.value();

  /// 侧栏缩略图的笔迹快照。容量由内存档位决定（sidebarInkCachePages）。
  final PageInkCache _pageInkCache = PageInkCache(0);

  /// 笔迹读取的串行队列，和缩略图渲染分开排队但同样串行执行。
  Future<void> _sidebarInkChain = Future<void>.value();

  // ━━━━ 运行时标志 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  /// _lastPenEvent：最近侧键动作的可读诊断文本，只用于反馈，不驱动实际工具状态。
  String _lastPenEvent = tr('尚未检测到笔侧键');

  /// 读取当前共享供电策略，不另建需要用户手动同步的开关。
  RenderPowerPolicy get _renderPolicy => RenderPowerMonitor.instance.value;

  /// _displayDecodeToken：屏幕底图刷新代次，切换电源后过期解码结果不能覆盖新策略。
  int _displayDecodeToken = 0;

  /// 供电变化后释放瞬态缓存并重算屏幕密度，异步更换底图；保留原始笔迹、选择和撤销记录。
  void _powerRenderingChanged() {
    if (!mounted) return;
    _repository.releaseTransientCaches();
    _updateState(() {});
    _syncSelectionViewScale();
    unawaited(_refreshPageDisplayResolution());
  }

  /// 根据用户内存档位读取统一资源预算，图像、预取与导出共用该档位约束。
  MemoryPolicy get _memoryPolicy =>
      MemoryPolicyCatalog.resolve(_settings.deviceMemoryGb);

  /// 读取相机与当前页矩形，更新选择把手屏幕倍率和可见瓦片区域，并标记导航活动供次要任务避让。
  void _syncSelectionViewScale() {
    _previewViewActivity
      ..reset()
      ..start();
    final matrix = _viewport.zoomController.value;
    final double scale = matrix.getMaxScaleOnAxis();
    _ink.selectionViewScale = scale;
    final rect = _pageViewportRect;
    _ink.updateView(
      economical: _renderPolicy.economical,
      maxRasterDensity: _renderPolicy.rasterDensity,
      visibleRect: _canvasViewport.isEmpty || rect.isEmpty
          ? null
          : Rect.fromLTWH(
              -matrix[12] / scale - rect.left,
              -matrix[13] / scale - rect.top,
              _canvasViewport.width / scale,
              _canvasViewport.height / scale,
            ),
      scale: scale,
      pixelRatio: MediaQuery.devicePixelRatioOf(context),
    );
  }

  /// 创建并连接文稿、工具、视口与仓库依赖，注册输入和供电监听，异步载入索引并在首帧后处理启动文件。
  @override
  void initState() {
    super.initState();
    RenderPowerMonitor.instance.addListener(_powerRenderingChanged);
    _inlineTextController.addListener(_adaptInlineText);
    _dataRoot = widget.dataRoot;
    _settings = AppSettingsController(_settingsRepository);
    _settings.syncFromWidget(widget);
    _toolState = ToolController(_settings);
    _toolState.tool = InkTool.values.firstWhere(
      (InkTool value) => value.name == widget.defaultTool,
      orElse: () => InkTool.pen,
    );
    _toolState.lastInkTool = _toolState.tool;
    _toolState.initFromSettings();
    _doc = DocumentController();
    _viewport = ViewportController(this);
    _viewport.zoomReturnController.addListener(() {
      final Animation<Matrix4>? animation = _viewport.zoomReturnAnimation;
      if (animation != null) _viewport.zoomController.value = animation.value;
    });
    _configureRepositories(_dataRoot);
    WidgetsBinding.instance.addObserver(this);
    _ink.addListener(_inkChanged);
    _viewport.zoomController.addListener(_syncSelectionViewScale);
    _penChannel.setMethodCallHandler(_handleNativePenMethod);
    _searchInput.addListener(_librarySearchChanged);
    unawaited(_loadLibrary());
    // 检查右键菜单是否已注册（Windows）。
    if (Platform.isWindows && winreg.ffiReady) {
      _contextMenuRegistered = winreg.isContextMenuRegistered();
    }
    if (widget.initialPath != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _openPathByType(widget.initialPath!, external: false);
      });
    }
    // 右键上下文菜单：--open-external 传入的文件路径。
    if (widget.externalFilePath != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _openPathByType(widget.externalFilePath!, external: true);
      });
    }
  }

  /// 根据文件类型自动路由到正确的打开方式。
  ///
  /// - 图片 / FastInk 元数据 → 手写笔记视图（_openPath / _openExternalFile）
  /// - PDF → 只读预览（_openExternalFile，external=true 时复制到 temp）
  /// - Markdown → Markdown 编辑器（external=true 时走 temp 只读流程）
  void _openPathByType(String path, {required bool external}) {
    final String lower = path.toLowerCase();
    if (lower.endsWith('.md')) {
      // Markdown 文件：external 走 temp 只读，否则直接编辑。
      _openMarkdownEditor(
        filePath: external ? null : path,
        externalSourcePath: external ? path : null,
      );
    } else if (external &&
        (lower.endsWith('.pdf') ||
            lower.endsWith('.png') ||
            lower.endsWith('.jpg') ||
            lower.endsWith('.jpeg') ||
            lower.endsWith('.webp'))) {
      // 外部图片/PDF：复制到 %temp% 后只读打开。
      _openExternalFile(path);
    } else {
      // 图片 / FastInk 元数据 (.fastink-notebook.json / .fastink-pdf.json)：
      // indexFromSelectedPath 会自动找到同目录的页面图片。
      _openPath(path);
    }
  }

  /// 父组件设置变化时同步运行时副本，语言变化同步状态提示；不重新载入当前页笔迹清空历史。
  @override
  void didUpdateWidget(covariant FastInkHome oldWidget) {
    super.didUpdateWidget(oldWidget);
    _settings.syncFromWidget(widget, previous: oldWidget);
    if (oldWidget.language != widget.language) {
      _doc.status = tr('语言已更改', 'Display language changed');
      _lastPenEvent = tr('尚未检测到笔侧键');
    }
  }

  /// 用同一资料库根目录重建内容、索引和导出仓库，应用统一内存预算，防止迁移后各服务读写不同位置。
  void _configureRepositories(String root) {
    _ink.rasterCacheMegabytes = _memoryPolicy.inkRasterCacheMegabytes;
    // 所有内容仓库必须使用同一根目录，避免页面、索引和导出读到不同资料库。
    _repository = NoteRepository(
      dataRoot: root,
      maximumCachedPdfPages: _settings.pdfCachePages,
      pdfImportDpi: _settings.pdfImportDpi,
    );
    _exportRepository = ExportRepository(
      _repository,
      jpgQuality: _settings.jpgExportQuality,
      pdfPagesPerPart: _memoryPolicy.exportPagesPerPart,
      exportPrefetchPages: _memoryPolicy.exportPrefetchPages,
    );
    _libraryRepository = LibraryRepository(root: root);
  }

  /// 窗口进入非活动、暂停或退出状态时提交纸面输入并安排刷盘，避免仅依赖自动保存定时器。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      // Windows 切后台或关闭窗口前提交文本编辑并刷新保存队列。
      _commitInlineText();
      unawaited(_saveNow());
    }
  }

  /// 响应系统内存压力，按统一流程清理可再生成的瞬态缓存，保留可编辑内容。
  @override
  void didHaveMemoryPressure() {
    super.didHaveMemoryPressure();
    _releaseTransientMemory(notify: true);
  }

  /// 发起最后一次笔迹保存，断开原生事件后释放文稿、笔迹和视口资源。
  @override
  void dispose() {
    _textMotionController?.dispose();
    RenderPowerMonitor.instance.removeListener(_powerRenderingChanged);
    _windowFullscreen.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _penChannel.setMethodCallHandler(null);
    _capturePenButtons.dispose();
    _exportProgress.dispose();
    _sidebarThumbnailTimer?.cancel();
    _sidebarThumbnailUpdateTimer?.cancel();
    unawaited(_saveNow());
    _doc.dispose();
    _ink.removeListener(_inkChanged);
    _viewport.zoomController.removeListener(_syncSelectionViewScale);
    _ink.dispose();
    _viewport.dispose();
    _pageInput.dispose();
    _librarySearchFocus.dispose();
    _inlineTextController.dispose();
    _toolbarScroll.dispose();
    _thumbnailScroll.dispose();
    _canvasFocus.dispose();
    _inlineTextFocus.dispose();
    _searchInput
      ..removeListener(_librarySearchChanged)
      ..dispose();
    super.dispose();
  }

  /// 在同一稳定位置包裹导航过渡与独立导出进度，只挂载当前资料库/手写/Markdown 界面。
  @override
  Widget build(BuildContext context) => _withExportProgress(
    AppScreenTransition(
      destination: _markdownEditorOpen
          ? 'markdown'
          : _doc.document == null
          ? 'library'
          : 'document',
      returning: !_markdownEditorOpen && _doc.document == null,
      child: _buildActiveScreen(context),
    ),
  );

  /// 根据顶层路由状态组装一个实际活动界面，绑定保存、切换、外观和键盘回调，避免新旧画布共用控制器。
  Widget _buildActiveScreen(BuildContext context) {
    final NoteDocument? document = _doc.document;
    final bool compact = MediaQuery.sizeOf(context).width < 1400;
    // Markdown 编辑器模式：独立于文档查看器。
    if (_markdownEditorOpen) {
      return MarkdownEditorView(
        key: ValueKey<String>(
          'markdown-$_markdownEditorSession-${_markdownExternalSourcePath ?? _markdownEditorFilePath ?? "new"}',
        ),
        filePath: _markdownEditorFilePath,
        externalSourcePath: _markdownExternalSourcePath,
        dataRoot: _dataRoot,
        darkMode: Theme.of(context).brightness == Brightness.dark,
        onFileSaved: (String path) {
          if (path.toLowerCase().endsWith('.md')) {
            _registerMarkdownInLibrary(path);
            if (!_markdownOpenTabs.any(
              (open) =>
                  MarkdownWorkspace.canonical(open) ==
                  MarkdownWorkspace.canonical(path),
            )) {
              _updateState(() => _markdownOpenTabs.add(path));
            }
          }
        },
        onFileRenamed: (before, after) {
          _renameMarkdownInLibrary(before, after);
          final index = _markdownOpenTabs.indexWhere(
            (open) =>
                MarkdownWorkspace.canonical(open) ==
                MarkdownWorkspace.canonical(before),
          );
          if (index >= 0) {
            _updateState(() => _markdownOpenTabs[index] = after);
          }
        },
        initialHeading: _markdownInitialHeading,
        onCreateMarkdown: () => _openMarkdownEditor(),
        openedPaths: List.of(_markdownOpenTabs),
        onCloseTab: (path, active) {
          _updateState(() => _markdownOpenTabs.remove(path));
          if (active) {
            if (_markdownOpenTabs.isEmpty) {
              _updateState(() {
                _markdownEditorOpen = false;
                _markdownEditorFilePath = null;
                _markdownExternalSourcePath = null;
              });
              _loadLibrary();
            } else {
              _openMarkdownEditor(filePath: _markdownOpenTabs.last);
            }
          }
        },
        preferences: _settings.markdown,
        workspacePaths: [
          for (final doc in _library.documents)
            if (!doc.trashed && doc.scope == LibraryScope.markdown)
              doc.sourcePath,
        ],
        onOpenMarkdown: (path) {
          final uri = Uri.tryParse(path);
          _openMarkdownEditor(
            filePath: uri?.scheme == 'file'
                ? File.fromUri(uri!.replace(fragment: '')).path
                : path,
            initialHeading: uri?.scheme == 'file' ? uri!.fragment : null,
          );
        },
        onPreferencesChanged: _setMarkdownPreferences,
        onExit: () {
          _updateState(() {
            _markdownEditorOpen = false;
            _markdownEditorFilePath = null;
            _markdownExternalSourcePath = null;
          });
          _loadLibrary(); // 刷新资料库，显示新建/导入的 Markdown 文件。
        },
        onThemeToggle: () {
          final Brightness current = Theme.of(context).brightness;
          widget.onThemeModeChanged(
            current == Brightness.dark ? ThemeMode.light : ThemeMode.dark,
          );
        },
      );
    }
    // 是否存在当前文稿是首页与编辑器之间唯一的顶层路由状态。
    final Widget screen = document == null
        ? KeyedSubtree(
            key: const ValueKey<String>('library'),
            child: _libraryScaffold(),
          )
        : Scaffold(
            // 文稿标签共用画布焦点和侧栏控制器，因此切换文稿时复用
            // 同一编辑器子树；若对旧编辑器执行退场动画，
            // 控制器会同时绑定到两个视图。
            key: const ValueKey<String>('document-editor'),
            appBar: AppBar(
              automaticallyImplyLeading: false,
              toolbarHeight: _immersiveMode ? 64 : 112,
              titleSpacing: _immersiveMode ? 4 : 12,
              title: _immersiveMode
                  ? _immersiveToolbar()
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        SizedBox(
                          height: 46,
                          child: _navigationRow(document, compact: compact),
                        ),
                        const SizedBox(height: 4),
                        SizedBox(height: 56, child: _inkToolbar()),
                      ],
                    ),
            ),
            body: _documentView(document),
          );
    return PopScope(
      canPop: document == null,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && document != null) {
          if (_immersiveMode) {
            _setImmersive(false);
          } else {
            unawaited(_goToLibrary());
          }
        }
      },
      child: TooltipVisibility(
        visible: _settings.tooltipsEnabled,
        child: Focus(
          key: screen.key,
          autofocus: document == null,
          onKeyEvent: _handleFullscreenKey,
          child: screen,
        ),
      ),
    );
  }
}
