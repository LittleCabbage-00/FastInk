import 'package:flutter/foundation.dart';

import 'memory_policy_catalog.dart';
import 'settings_repository.dart';

/// [FastInkHome] 构造参数里与设置有关的那一部分。
///
/// [AppSettingsController.syncFromWidget] 要按名字把这些值读进来。早先它
/// 收的是 `dynamic`，写错名字完全不报编译错误，直到 initState 运行时才抛
/// NoSuchMethodError——首页整个构建失败，用户只看得到错误占位页，而
/// `flutter analyze` 是绿的。改成显式接口之后，改名漏改一律在编译期暴露。
///
/// 这里是"Widget 提供给设置的输入"，不含 dataRoot、initialPath、语言和
/// 主题回调等运行时依赖——那些由 State 自己处理。
abstract interface class AppSettingsSource {
  /// markdown：Markdown 独立配置，供工作台与设置面板共享，不改变手写设置。
  MarkdownPreferences get markdown;

  /// configStorageLocation：配置存储位置标识，区分用户目录、程序目录与资料库目录。
  String get configStorageLocation;

  /// pressureEnabled：是否将触笔压力用于笔宽；鼠标输入不能污染该开关。
  bool get pressureEnabled;

  /// pressureSensitivity：输入时的压感响应倍率；形成有效压力点，修改偏好不追溯改写旧笔迹。
  double get pressureSensitivity;

  /// pressureCurve：压力映射曲线名称，用于笔迹宽度计算。
  String get pressureCurve;

  /// stylusOnly：是否只接受触笔书写；鼠标选择等非书写操作仍按输入规则处理。
  bool get stylusOnly;

  /// showPerformance：是否显示诊断性能信息，不改变实际渲染精度。
  bool get showPerformance;

  /// doubleTapZoomEnabled：是否启用纸面双击缩放手势，浮层按钮会排除在识别范围外。
  bool get doubleTapZoomEnabled;

  /// edgeBounceEnabled：页面边界回弹配置，读取方决定是否用于当前交互。
  bool get edgeBounceEnabled;

  /// keepZoomOnPageChange：切页时是否保留缩放比例。
  bool get keepZoomOnPageChange;

  /// maximumZoom：视图最大缩放倍数，1 表示基准比例。
  double get maximumZoom;

  /// wheelZoomSensitivity：Ctrl+滚轮的缩放灵敏度倍率。
  double get wheelZoomSensitivity;

  /// pdfCachePages：PDF 页面缓存的数量预算，单位为页。
  int get pdfCachePages;

  /// pdfPrefetchPages：PDF 邻页预取数量上限，经济策略可进一步限制。
  int get pdfPrefetchPages;

  /// pdfImportDpi 用于 PDF 页面栅格化，单位为 DPI。
  int get pdfImportDpi;

  /// jpgExportQuality：JPG 编码质量百分比，与屏幕预览清晰度分开。
  int get jpgExportQuality;

  /// deviceMemoryGb：选择的设备内存档位，单位 GB，用于解析资源预算。
  int get deviceMemoryGb;

  /// imageCacheEntries：Flutter 图像缓存条目数量预算。
  int get imageCacheEntries;

  /// imageCacheMegabytes：Flutter 图像缓存容量预算，单位 MB。
  int get imageCacheMegabytes;

  /// pagePreviewWidth：页面低分辨率预览宽度预算，单位像素。
  int get pagePreviewWidth;

  /// pageAnimationsEnabled：是否允许页面导航动画，系统减少动画或经济策略还可抑制。
  bool get pageAnimationsEnabled;

  /// touchInertiaStrength：触摸平移惯性的强度参数，不降低笔采样频率。
  double get touchInertiaStrength;

  /// tooltipsEnabled：是否展示工具提示，仅影响界面说明。
  bool get tooltipsEnabled;

  /// compactToolbar：是否使用紧凑工具栏布局。
  bool get compactToolbar;

  /// openSidebarByDefault：打开手写文稿时是否默认展示页面侧栏。
  bool get openSidebarByDefault;

  /// defaultReadOnly：新打开文稿的默认只读状态，不改写文稿文件权限。
  bool get defaultReadOnly;

  /// confirmClearInk：清空笔迹前是否要求确认。
  bool get confirmClearInk;

  /// showLibraryStatusBar：是否展示资料库状态栏。
  bool get showLibraryStatusBar;

  /// defaultSidebarTab：初始侧栏页签编号：页面、目录、书签由界面约定解释。
  int get defaultSidebarTab;

  /// sidebarWidth：页面侧栏的逻辑像素宽度，窄窗口会进一步约束。
  double get sidebarWidth;

  /// defaultTool：新打开文稿的默认工具名称，独立于临时侧键工具。
  String get defaultTool;

  /// defaultPageFit：初始页面适配方式名称，例如适应宽度。
  String get defaultPageFit;

  /// defaultPenStyle：打开文稿时采用的默认笔型名称。
  String get defaultPenStyle;

  /// autoSaveEnabled：手写笔迹自动保存开关；关闭不取消切页/退出刷盘。
  bool get autoSaveEnabled;

  /// autoSaveDelayMs：修改后自动保存的等待时间，单位毫秒，连续输入会重新计时。
  int get autoSaveDelayMs;

  /// selectionPriority：命中已有选区时是否优先移动，避免直接开始新选区。
  bool get selectionPriority;

  /// selectionHitRadius：选择命中的容差，使用方按屏幕比例换算。
  double get selectionHitRadius;

  /// lassoShape：自由套索或矩形套索的名称。
  String get lassoShape;

  /// defaultEraserMode：默认橡皮模式；侧键临时模式不覆盖此配置。
  String get defaultEraserMode;

  /// defaultEraserSize：默认橡皮范围，单位逻辑像素。
  double get defaultEraserSize;

  /// defaultTextSize：新文本的字号，单位页面布局逻辑像素，默认 12。
  double get defaultTextSize;

  /// showPageNumber：是否绘制页面角标，不控制顶部页码输入框。
  bool get showPageNumber;

  /// defaultPenColor：初始普通笔颜色，使用 32 位 ARGB 保存。
  int get defaultPenColor;

  /// defaultPenWidth：初始普通笔的基准页面逻辑像素宽度。
  double get defaultPenWidth;

  /// defaultHighlighterWidth：初始荧光笔基准页面宽度。
  double get defaultHighlighterWidth;

  /// penWidthPresets：普通笔工具栏的快速宽度档位列表。
  List<double> get penWidthPresets;

  /// highlighterWidthPresets：荧光笔工具栏的快速宽度档位列表。
  List<double> get highlighterWidthPresets;

  /// penButtonOneAction：逻辑一键的动作名称，物理侧键经过交换设置后映射到这里。
  String get penButtonOneAction;

  /// penButtonTwoAction：逻辑二键的动作名称，与逻辑一键分别保存。
  String get penButtonTwoAction;

  /// penButtonMomentary：侧键是否只在按住期间临时切换工具。
  bool get penButtonMomentary;

  /// swapPenButtons：是否交换两个物理侧键对应的逻辑动作。
  bool get swapPenButtons;

  /// penColorPresets：工具栏快速颜色列表，元素为 32 位 ARGB。
  List<int> get penColorPresets;

  /// laserMode：激光点或尾迹模式名称，激光不写入持久笔迹。
  String get laserMode;

  /// laserColor：激光显示颜色，使用 32 位 ARGB 保存。
  int get laserColor;

  /// laserWidth：激光显示宽度，单位逻辑像素。
  double get laserWidth;

  /// laserFadeMs：激光尾迹保留时长，单位毫秒。
  int get laserFadeMs;
}

/// 运行时设置状态的可变副本。
///
/// Widget 构造参数在 [syncFromWidget] 时写入；设置 UI 通过 setter 方法
/// 修改并自动持久化到 [SettingsRepository]。State 类只需持有这一个对象，
/// 不再需要 40 多个独立的 `late` 字段。
class AppSettingsController {
  /// 绑定配置仓库，持有界面运行时设置副本；持久化由保存方法排队完成。
  AppSettingsController(this._repository);

  /// _repository：所属模块的数据仓库依赖；实际读写范围由声明类型和构造根目录决定。
  final SettingsRepository _repository;

  // ── 运行时副本 ──────────────────────────────────────────────────────────

  /// markdown：Markdown 独立配置，供工作台与设置面板共享，不改变手写设置。
  MarkdownPreferences markdown = const MarkdownPreferences();

  /// configStorageLocation：配置存储位置标识，区分用户目录、程序目录与资料库目录。
  String configStorageLocation = 'user';

  /// pressureEnabled：是否将触笔压力用于笔宽；鼠标输入不能污染该开关。
  bool pressureEnabled = true;

  /// pressureSensitivity：输入时的压感响应倍率；形成有效压力点，修改偏好不追溯改写旧笔迹。
  double pressureSensitivity = 1.0;

  /// stylusOnly：是否只接受触笔书写；鼠标选择等非书写操作仍按输入规则处理。
  bool stylusOnly = false;

  /// showPerformance：是否显示诊断性能信息，不改变实际渲染精度。
  bool showPerformance = true;

  /// doubleTapZoomEnabled：是否启用纸面双击缩放手势，浮层按钮会排除在识别范围外。
  bool doubleTapZoomEnabled = true;

  /// edgeBounceEnabled：页面边界回弹配置，读取方决定是否用于当前交互。
  bool edgeBounceEnabled = true;

  /// keepZoomOnPageChange：切页时是否保留缩放比例。
  bool keepZoomOnPageChange = true;

  /// maximumZoom：视图最大缩放倍数，1 表示基准比例。
  double maximumZoom = 5;

  /// wheelZoomSensitivity：Ctrl+滚轮的缩放灵敏度倍率。
  double wheelZoomSensitivity = 1;

  /// pdfCachePages：PDF 页面缓存的数量预算，单位为页。
  int pdfCachePages = 160;

  /// pdfPrefetchPages：PDF 邻页预取数量上限，经济策略可进一步限制。
  int pdfPrefetchPages = 2;

  /// pdfImportDpi 用于 PDF 页面栅格化，单位为 DPI。
  int pdfImportDpi = 132;

  /// jpgExportQuality：JPG 编码质量百分比，与屏幕预览清晰度分开。
  int jpgExportQuality = 94;

  /// deviceMemoryGb：选择的设备内存档位，单位 GB，用于解析资源预算。
  int deviceMemoryGb = MemoryPolicyCatalog.defaultDeviceMemoryGb;

  /// imageCacheEntries：Flutter 图像缓存条目数量预算。
  int imageCacheEntries = 48;

  /// imageCacheMegabytes：Flutter 图像缓存容量预算，单位 MB。
  int imageCacheMegabytes = 64;

  /// pagePreviewWidth：页面低分辨率预览宽度预算，单位像素。
  int pagePreviewWidth = 800;

  /// pageAnimationsEnabled：是否允许页面导航动画，系统减少动画或经济策略还可抑制。
  bool pageAnimationsEnabled = true;

  /// touchInertiaStrength：触摸平移惯性的强度参数，不降低笔采样频率。
  double touchInertiaStrength = 1;

  /// tooltipsEnabled：是否展示工具提示，仅影响界面说明。
  bool tooltipsEnabled = true;

  /// compactToolbar：是否使用紧凑工具栏布局。
  bool compactToolbar = false;

  /// openSidebarByDefault：打开手写文稿时是否默认展示页面侧栏。
  bool openSidebarByDefault = true;

  /// defaultReadOnly：新打开文稿的默认只读状态，不改写文稿文件权限。
  bool defaultReadOnly = false;

  /// confirmClearInk：清空笔迹前是否要求确认。
  bool confirmClearInk = true;

  /// showLibraryStatusBar：是否展示资料库状态栏。
  bool showLibraryStatusBar = true;

  /// defaultSidebarTab：初始侧栏页签编号：页面、目录、书签由界面约定解释。
  int defaultSidebarTab = 0;

  /// sidebarWidth：页面侧栏的逻辑像素宽度，窄窗口会进一步约束。
  double sidebarWidth = 260;

  /// defaultPageFit：初始页面适配方式名称，例如适应宽度。
  String defaultPageFit = 'width';

  /// autoSaveEnabled：手写笔迹自动保存开关；关闭不取消切页/退出刷盘。
  bool autoSaveEnabled = true;

  /// autoSaveDelayMs：修改后自动保存的等待时间，单位毫秒，连续输入会重新计时。
  int autoSaveDelayMs = 300;

  /// selectionPriority：命中已有选区时是否优先移动，避免直接开始新选区。
  bool selectionPriority = true;

  /// selectionHitRadius：选择命中的容差，使用方按屏幕比例换算。
  double selectionHitRadius = 64;

  /// showPageNumber：是否绘制页面角标，不控制顶部页码输入框。
  bool showPageNumber = true;

  // ── 工具默认值（运行时可变，切工具时恢复） ──────────────────────────────

  /// defaultTool：新打开文稿的默认工具名称，独立于临时侧键工具。
  String defaultTool = 'pen';

  /// penStyle：钢笔、圆珠笔、画笔等笔型名称，决定宽度响应与绘制方式。
  String penStyle = 'fountain';

  /// pressureCurve：压力映射曲线名称，用于笔迹宽度计算。
  String pressureCurve = 'linear';

  /// lassoShape：自由套索或矩形套索的名称。
  String lassoShape = 'freehand';

  /// eraserMode：整笔擦除或局部擦除的名称。
  String eraserMode = 'stroke';

  /// eraserSize：橡皮范围的逻辑像素半径，显示与命中使用同一参数。
  double eraserSize = 30;

  /// defaultTextSize：新文本的字号，单位页面布局逻辑像素，默认 12。
  double defaultTextSize = 12;

  /// penColor：普通笔颜色，使用 32 位 ARGB 保存。
  int penColor = 0xff202124;

  /// penWidth：普通笔笔宽，单位基准页面逻辑像素；保存笔迹时另做归一化。
  double penWidth = 3;

  /// highlighterWidth：荧光笔基准宽度，独立于普通笔宽度。
  double highlighterWidth = 18;

  /// penWidthPresets：普通笔工具栏的快速宽度档位列表。
  List<double> penWidthPresets = const <double>[1, 3, 8];

  /// highlighterWidthPresets：荧光笔工具栏的快速宽度档位列表。
  List<double> highlighterWidthPresets = const <double>[8, 18, 26];

  /// penButtonOneAction：逻辑一键的动作名称，物理侧键经过交换设置后映射到这里。
  String penButtonOneAction = 'eraser';

  /// penButtonTwoAction：逻辑二键的动作名称，与逻辑一键分别保存。
  String penButtonTwoAction = 'lasso';

  /// penButtonMomentary：侧键是否只在按住期间临时切换工具。
  bool penButtonMomentary = true;

  /// swapPenButtons：是否交换两个物理侧键对应的逻辑动作。
  bool swapPenButtons = false;

  /// penColorPresets：工具栏快速颜色列表，元素为 32 位 ARGB。
  List<int> penColorPresets = const <int>[0xff202124, 0xff2f80ed, 0xffe53935];

  /// laserMode：激光点或尾迹模式名称，激光不写入持久笔迹。
  String laserMode = 'trail';

  /// laserColor：激光显示颜色，使用 32 位 ARGB 保存。
  int laserColor = 0xffff3b30;

  /// laserWidth：激光显示宽度，单位逻辑像素。
  double laserWidth = 7;

  /// laserFadeMs：激光尾迹保留时长，单位毫秒。
  int laserFadeMs = 800;

  // ── Widget → 运行时同步 ─────────────────────────────────────────────────

  /// 初始化时同步全部值；重建时只接受宿主真正修改过的输入。
  /// 外观、语言等重建不能用启动值覆盖用户在当前会话修改的偏好。
  void syncFromWidget(AppSettingsSource widget, {AppSettingsSource? previous}) {
    if (previous == null || previous.markdown != widget.markdown) {
      markdown = widget.markdown;
    }
    if (previous == null ||
        previous.configStorageLocation != widget.configStorageLocation) {
      configStorageLocation = widget.configStorageLocation;
    }
    if (previous == null ||
        previous.pressureEnabled != widget.pressureEnabled) {
      pressureEnabled = widget.pressureEnabled;
    }
    if (previous == null ||
        previous.pressureSensitivity != widget.pressureSensitivity) {
      pressureSensitivity = widget.pressureSensitivity;
    }
    if (previous == null || previous.stylusOnly != widget.stylusOnly) {
      stylusOnly = widget.stylusOnly;
    }
    if (previous == null ||
        previous.showPerformance != widget.showPerformance) {
      showPerformance = widget.showPerformance;
    }
    if (previous == null ||
        previous.doubleTapZoomEnabled != widget.doubleTapZoomEnabled) {
      doubleTapZoomEnabled = widget.doubleTapZoomEnabled;
    }
    if (previous == null ||
        previous.edgeBounceEnabled != widget.edgeBounceEnabled) {
      edgeBounceEnabled = widget.edgeBounceEnabled;
    }
    if (previous == null ||
        previous.keepZoomOnPageChange != widget.keepZoomOnPageChange) {
      keepZoomOnPageChange = widget.keepZoomOnPageChange;
    }
    if (previous == null || previous.maximumZoom != widget.maximumZoom) {
      maximumZoom = widget.maximumZoom;
    }
    if (previous == null ||
        previous.wheelZoomSensitivity != widget.wheelZoomSensitivity) {
      wheelZoomSensitivity = widget.wheelZoomSensitivity;
    }
    if (previous == null || previous.pdfCachePages != widget.pdfCachePages) {
      pdfCachePages = widget.pdfCachePages;
    }
    if (previous == null ||
        previous.pdfPrefetchPages != widget.pdfPrefetchPages) {
      pdfPrefetchPages = widget.pdfPrefetchPages;
    }
    if (previous == null || previous.pdfImportDpi != widget.pdfImportDpi) {
      pdfImportDpi = widget.pdfImportDpi;
    }
    if (previous == null ||
        previous.jpgExportQuality != widget.jpgExportQuality) {
      jpgExportQuality = widget.jpgExportQuality;
    }
    if (previous == null || previous.deviceMemoryGb != widget.deviceMemoryGb) {
      deviceMemoryGb = widget.deviceMemoryGb;
    }
    if (previous == null ||
        previous.imageCacheEntries != widget.imageCacheEntries) {
      imageCacheEntries = widget.imageCacheEntries;
    }
    if (previous == null ||
        previous.imageCacheMegabytes != widget.imageCacheMegabytes) {
      imageCacheMegabytes = widget.imageCacheMegabytes;
    }
    if (previous == null ||
        previous.pagePreviewWidth != widget.pagePreviewWidth) {
      pagePreviewWidth = widget.pagePreviewWidth;
    }
    if (previous == null ||
        previous.pageAnimationsEnabled != widget.pageAnimationsEnabled) {
      pageAnimationsEnabled = widget.pageAnimationsEnabled;
    }
    if (previous == null ||
        previous.touchInertiaStrength != widget.touchInertiaStrength) {
      touchInertiaStrength = widget.touchInertiaStrength;
    }
    if (previous == null ||
        previous.tooltipsEnabled != widget.tooltipsEnabled) {
      tooltipsEnabled = widget.tooltipsEnabled;
    }
    if (previous == null || previous.compactToolbar != widget.compactToolbar) {
      compactToolbar = widget.compactToolbar;
    }
    if (previous == null ||
        previous.openSidebarByDefault != widget.openSidebarByDefault) {
      openSidebarByDefault = widget.openSidebarByDefault;
    }
    if (previous == null ||
        previous.defaultReadOnly != widget.defaultReadOnly) {
      defaultReadOnly = widget.defaultReadOnly;
    }
    if (previous == null ||
        previous.confirmClearInk != widget.confirmClearInk) {
      confirmClearInk = widget.confirmClearInk;
    }
    if (previous == null ||
        previous.showLibraryStatusBar != widget.showLibraryStatusBar) {
      showLibraryStatusBar = widget.showLibraryStatusBar;
    }
    if (previous == null ||
        previous.defaultSidebarTab != widget.defaultSidebarTab) {
      defaultSidebarTab = widget.defaultSidebarTab;
    }
    if (previous == null || previous.sidebarWidth != widget.sidebarWidth) {
      sidebarWidth = widget.sidebarWidth;
    }
    if (previous == null || previous.defaultPageFit != widget.defaultPageFit) {
      defaultPageFit = widget.defaultPageFit;
    }
    if (previous == null ||
        previous.autoSaveEnabled != widget.autoSaveEnabled) {
      autoSaveEnabled = widget.autoSaveEnabled;
    }
    if (previous == null ||
        previous.autoSaveDelayMs != widget.autoSaveDelayMs) {
      autoSaveDelayMs = widget.autoSaveDelayMs;
    }
    if (previous == null ||
        previous.selectionPriority != widget.selectionPriority) {
      selectionPriority = widget.selectionPriority;
    }
    if (previous == null ||
        previous.selectionHitRadius != widget.selectionHitRadius) {
      selectionHitRadius = widget.selectionHitRadius;
    }
    if (previous == null || previous.showPageNumber != widget.showPageNumber) {
      showPageNumber = widget.showPageNumber;
    }
    if (previous == null || previous.defaultTool != widget.defaultTool) {
      defaultTool = widget.defaultTool;
    }
    if (previous == null ||
        previous.defaultPenStyle != widget.defaultPenStyle) {
      penStyle = widget.defaultPenStyle;
    }
    if (previous == null || previous.pressureCurve != widget.pressureCurve) {
      pressureCurve = widget.pressureCurve;
    }
    if (previous == null || previous.lassoShape != widget.lassoShape) {
      lassoShape = widget.lassoShape;
    }
    if (previous == null ||
        previous.defaultEraserMode != widget.defaultEraserMode) {
      eraserMode = widget.defaultEraserMode;
    }
    if (previous == null ||
        previous.defaultEraserSize != widget.defaultEraserSize) {
      eraserSize = widget.defaultEraserSize;
    }
    if (previous == null ||
        previous.defaultTextSize != widget.defaultTextSize) {
      defaultTextSize = widget.defaultTextSize;
    }
    if (previous == null ||
        previous.defaultPenColor != widget.defaultPenColor) {
      penColor = widget.defaultPenColor;
    }
    if (previous == null ||
        previous.defaultPenWidth != widget.defaultPenWidth) {
      penWidth = widget.defaultPenWidth;
    }
    if (previous == null ||
        previous.defaultHighlighterWidth != widget.defaultHighlighterWidth) {
      highlighterWidth = widget.defaultHighlighterWidth;
    }
    if (previous == null ||
        !listEquals(previous.penWidthPresets, widget.penWidthPresets)) {
      penWidthPresets = List<double>.of(widget.penWidthPresets);
    }
    if (previous == null ||
        !listEquals(
          previous.highlighterWidthPresets,
          widget.highlighterWidthPresets,
        )) {
      highlighterWidthPresets = List<double>.of(widget.highlighterWidthPresets);
    }
    if (previous == null ||
        previous.penButtonOneAction != widget.penButtonOneAction) {
      penButtonOneAction = widget.penButtonOneAction;
    }
    if (previous == null ||
        previous.penButtonTwoAction != widget.penButtonTwoAction) {
      penButtonTwoAction = widget.penButtonTwoAction;
    }
    if (previous == null ||
        previous.penButtonMomentary != widget.penButtonMomentary) {
      penButtonMomentary = widget.penButtonMomentary;
    }
    if (previous == null || previous.swapPenButtons != widget.swapPenButtons) {
      swapPenButtons = widget.swapPenButtons;
    }
    if (previous == null ||
        !listEquals(previous.penColorPresets, widget.penColorPresets)) {
      penColorPresets = List<int>.of(widget.penColorPresets);
    }
    if (previous == null || previous.laserMode != widget.laserMode) {
      laserMode = widget.laserMode;
    }
    if (previous == null || previous.laserColor != widget.laserColor) {
      laserColor = widget.laserColor;
    }
    if (previous == null || previous.laserWidth != widget.laserWidth) {
      laserWidth = widget.laserWidth;
    }
    if (previous == null || previous.laserFadeMs != widget.laserFadeMs) {
      laserFadeMs = widget.laserFadeMs;
    }
  }

  // ── 持久化 ──────────────────────────────────────────────────────────────

  /// 更新并持久化单个布尔设置。
  Future<void> saveBool(String key, bool value) async {
    await _repository.update((current) => _applyBool(current, key, value));
  }

  /// 更新并持久化单个数值设置。
  Future<void> saveNum(String key, num value) async {
    await _repository.update((current) => _applyNum(current, key, value));
  }

  /// 更新并持久化单个字符串设置。
  Future<void> saveString(String key, String value) async {
    await _repository.update((current) => _applyString(current, key, value));
  }

  /// 批量更新并持久化多个设置。
  Future<void> saveAll(Map<String, Object?> values) async {
    await _repository.update((current) {
      AppSettings s = current;
      for (final MapEntry<String, Object?> entry in values.entries) {
        final Object? v = entry.value;
        if (v is bool) {
          s = _applyBool(s, entry.key, v);
        } else if (v is num) {
          s = _applyNum(s, entry.key, v);
        } else if (v is String) {
          s = _applyString(s, entry.key, v);
        }
      }
      return s;
    });
  }

  // ── copyWith 路由 ───────────────────────────────────────────────────────

  /// 按布尔设置键复制并更新设置快照；未识别的键不改变其他设置。
  static AppSettings _applyBool(AppSettings s, String key, bool v) {
    switch (key) {
      case 'pressureEnabled':
        return s.copyWith(pressureEnabled: v);
      case 'stylusOnly':
        return s.copyWith(stylusOnly: v);
      case 'showPerformance':
        return s.copyWith(showPerformance: v);
      case 'doubleTapZoomEnabled':
        return s.copyWith(doubleTapZoomEnabled: v);
      case 'edgeBounceEnabled':
        return s.copyWith(edgeBounceEnabled: v);
      case 'keepZoomOnPageChange':
        return s.copyWith(keepZoomOnPageChange: v);
      case 'pageAnimationsEnabled':
        return s.copyWith(pageAnimationsEnabled: v);
      case 'tooltipsEnabled':
        return s.copyWith(tooltipsEnabled: v);
      case 'compactToolbar':
        return s.copyWith(compactToolbar: v);
      case 'openSidebarByDefault':
        return s.copyWith(openSidebarByDefault: v);
      case 'defaultReadOnly':
        return s.copyWith(defaultReadOnly: v);
      case 'confirmClearInk':
        return s.copyWith(confirmClearInk: v);
      case 'showLibraryStatusBar':
        return s.copyWith(showLibraryStatusBar: v);
      case 'autoSaveEnabled':
        return s.copyWith(autoSaveEnabled: v);
      case 'selectionPriority':
        return s.copyWith(selectionPriority: v);
      case 'showPageNumber':
        return s.copyWith(showPageNumber: v);
      case 'penButtonMomentary':
        return s.copyWith(penButtonMomentary: v);
      case 'swapPenButtons':
        return s.copyWith(swapPenButtons: v);
      default:
        return s;
    }
  }

  /// 按数值设置键更新对应配置并保留其余字段；整数字段在分支内进行类型转换。
  static AppSettings _applyNum(AppSettings s, String key, num v) {
    switch (key) {
      case 'pressureSensitivity':
        return s.copyWith(pressureSensitivity: v.toDouble());
      case 'maximumZoom':
        return s.copyWith(maximumZoom: v.toDouble());
      case 'wheelZoomSensitivity':
        return s.copyWith(wheelZoomSensitivity: v.toDouble());
      case 'pdfCachePages':
        return s.copyWith(pdfCachePages: v.toInt());
      case 'pdfPrefetchPages':
        return s.copyWith(pdfPrefetchPages: v.toInt());
      case 'pdfImportDpi':
        return s.copyWith(pdfImportDpi: v.toInt());
      case 'jpgExportQuality':
        return s.copyWith(jpgExportQuality: v.toInt());
      case 'deviceMemoryGb':
        return s.copyWith(deviceMemoryGb: v.toInt());
      case 'imageCacheEntries':
        return s.copyWith(imageCacheEntries: v.toInt());
      case 'imageCacheMegabytes':
        return s.copyWith(imageCacheMegabytes: v.toInt());
      case 'pagePreviewWidth':
        return s.copyWith(pagePreviewWidth: v.toInt());
      case 'touchInertiaStrength':
        return s.copyWith(touchInertiaStrength: v.toDouble());
      case 'defaultSidebarTab':
        return s.copyWith(defaultSidebarTab: v.toInt());
      case 'sidebarWidth':
        return s.copyWith(sidebarWidth: v.toDouble());
      case 'autoSaveDelayMs':
        return s.copyWith(autoSaveDelayMs: v.toInt());
      case 'selectionHitRadius':
        return s.copyWith(selectionHitRadius: v.toDouble());
      case 'eraserSize':
        return s.copyWith(eraserSize: v.toDouble());
      case 'defaultTextSize':
        return s.copyWith(defaultTextSize: v.toDouble());
      case 'penColor':
        return s.copyWith(penColor: v.toInt());
      case 'penWidth':
        return s.copyWith(penWidth: v.toDouble());
      case 'highlighterWidth':
        return s.copyWith(highlighterWidth: v.toDouble());
      case 'laserColor':
        return s.copyWith(laserColor: v.toInt());
      case 'laserWidth':
        return s.copyWith(laserWidth: v.toDouble());
      case 'laserFadeMs':
        return s.copyWith(laserFadeMs: v.toInt());
      default:
        return s;
    }
  }

  /// 按字符串设置键更新枚举名称或路径等配置，不直接改写文稿内容。
  static AppSettings _applyString(AppSettings s, String key, String v) {
    switch (key) {
      case 'configStorageLocation':
        return s.copyWith(configStorageLocation: v);
      case 'pressureCurve':
        return s.copyWith(pressureCurve: v);
      case 'defaultPageFit':
        return s.copyWith(defaultPageFit: v);
      case 'defaultTool':
        return s.copyWith(defaultTool: v);
      case 'penStyle':
        return s.copyWith(penStyle: v);
      case 'lassoShape':
        return s.copyWith(lassoShape: v);
      case 'eraserMode':
        return s.copyWith(eraserMode: v);
      case 'penButtonOneAction':
        return s.copyWith(penButtonOneAction: v);
      case 'penButtonTwoAction':
        return s.copyWith(penButtonTwoAction: v);
      case 'laserMode':
        return s.copyWith(laserMode: v);
      default:
        return s;
    }
  }
}
