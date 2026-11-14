import 'markdown_preferences.dart';
export 'markdown_preferences.dart';
import 'package:flutter/material.dart';

import 'memory_policy_catalog.dart';

class AppSettings {
  /// 创建不可变的应用设置快照；默认参数提供首次启动基线，手写与 Markdown 配置分别保存。
  const AppSettings({
    this.markdown = const MarkdownPreferences(),
    this.themeMode = ThemeMode.system,
    this.language = 'system',
    required this.dataRoot,
    this.pressureEnabled = true,
    this.pressureSensitivity = 1.0,
    this.pressureCurve = 'linear',
    this.stylusOnly = false,
    this.showPerformance = true,
    this.doubleTapZoomEnabled = true,
    this.edgeBounceEnabled = true,
    this.keepZoomOnPageChange = true,
    this.maximumZoom = 5,
    this.wheelZoomSensitivity = 1,
    this.pdfCachePages = 160,
    this.pdfPrefetchPages = 2,
    this.pdfImportDpi = 132,
    this.jpgExportQuality = 94,
    this.deviceMemoryGb = MemoryPolicyCatalog.defaultDeviceMemoryGb,
    this.imageCacheEntries = 48,
    this.imageCacheMegabytes = 64,
    this.pagePreviewWidth = 800,
    this.pageAnimationsEnabled = true,
    this.touchInertiaStrength = 1,
    this.tooltipsEnabled = true,
    this.compactToolbar = false,
    this.openSidebarByDefault = true,
    this.defaultReadOnly = false,
    this.confirmClearInk = true,
    this.showLibraryStatusBar = true,
    this.defaultSidebarTab = 0,
    this.sidebarWidth = 260,
    this.defaultTool = 'pen',
    this.defaultPageFit = 'width',
    this.penStyle = 'fountain',
    this.autoSaveEnabled = true,
    this.autoSaveDelayMs = 300,
    this.selectionPriority = true,
    this.selectionHitRadius = 64,
    this.lassoShape = 'freehand',
    this.eraserMode = 'stroke',
    this.eraserSize = 30,
    this.defaultTextSize = 12,
    this.showPageNumber = true,
    this.penColor = 0xff202124,
    this.penWidth = 3,
    this.highlighterWidth = 18,
    this.penWidthPresets = const <double>[1, 3, 8],
    this.highlighterWidthPresets = const <double>[8, 18, 26],
    this.penButtonOneAction = 'eraser',
    this.penButtonTwoAction = 'lasso',
    this.penButtonMomentary = true,
    this.swapPenButtons = false,
    this.penColorPresets = const <int>[0xff202124, 0xff2f80ed, 0xffe53935],
    this.laserMode = 'trail',
    this.laserColor = 0xffff3b30,
    this.laserWidth = 7,
    this.laserFadeMs = 800,
    this.configStorageLocation = 'user',
  });

  /// markdown：Markdown 独立配置，供工作台与设置面板共享，不改变手写设置。
  final MarkdownPreferences markdown;

  /// themeMode：界面外观模式：跟随系统、浅色或深色，不等同于纸张颜色。
  final ThemeMode themeMode;

  /// language：用户选择的界面语言标识，系统语言模式在显示时解析。
  final String language;

  /// dataRoot：当前资料库根目录，文稿、笔迹和本地资源都相对该目录定位。
  final String dataRoot;

  /// pressureEnabled：是否将触笔压力用于笔宽；鼠标输入不能污染该开关。
  final bool pressureEnabled;

  /// pressureSensitivity：输入时的压感响应倍率；形成有效压力点，修改偏好不追溯改写旧笔迹。
  final double pressureSensitivity;

  /// pressureCurve：压力映射曲线名称，用于笔迹宽度计算。
  final String pressureCurve;

  /// stylusOnly：是否只接受触笔书写；鼠标选择等非书写操作仍按输入规则处理。
  final bool stylusOnly;

  /// showPerformance：是否显示诊断性能信息，不改变实际渲染精度。
  final bool showPerformance;

  /// doubleTapZoomEnabled：是否启用纸面双击缩放手势，浮层按钮会排除在识别范围外。
  final bool doubleTapZoomEnabled;

  /// edgeBounceEnabled：页面边界回弹配置，读取方决定是否用于当前交互。
  final bool edgeBounceEnabled;

  /// keepZoomOnPageChange：切页时是否保留缩放比例。
  final bool keepZoomOnPageChange;

  /// maximumZoom：视图最大缩放倍数，1 表示基准比例。
  final double maximumZoom;

  /// wheelZoomSensitivity：Ctrl+滚轮的缩放灵敏度倍率。
  final double wheelZoomSensitivity;

  /// pdfCachePages：PDF 页面缓存的数量预算，单位为页。
  final int pdfCachePages;

  /// pdfPrefetchPages：PDF 邻页预取数量上限，经济策略可进一步限制。
  final int pdfPrefetchPages;

  /// pdfImportDpi 用于 PDF 页面栅格化，单位为 DPI。
  final int pdfImportDpi;

  /// jpgExportQuality：JPG 编码质量百分比，与屏幕预览清晰度分开。
  final int jpgExportQuality;

  /// deviceMemoryGb：选择的设备内存档位，单位 GB，用于解析资源预算。
  final int deviceMemoryGb;

  /// imageCacheEntries：Flutter 图像缓存条目数量预算。
  final int imageCacheEntries;

  /// imageCacheMegabytes：Flutter 图像缓存容量预算，单位 MB。
  final int imageCacheMegabytes;

  /// pagePreviewWidth：页面低分辨率预览宽度预算，单位像素。
  final int pagePreviewWidth;

  /// pageAnimationsEnabled：是否允许页面导航动画，系统减少动画或经济策略还可抑制。
  final bool pageAnimationsEnabled;

  /// touchInertiaStrength：触摸平移惯性的强度参数，不降低笔采样频率。
  final double touchInertiaStrength;

  /// tooltipsEnabled：是否展示工具提示，仅影响界面说明。
  final bool tooltipsEnabled;

  /// compactToolbar：是否使用紧凑工具栏布局。
  final bool compactToolbar;

  /// openSidebarByDefault：打开手写文稿时是否默认展示页面侧栏。
  final bool openSidebarByDefault;

  /// defaultReadOnly：新打开文稿的默认只读状态，不改写文稿文件权限。
  final bool defaultReadOnly;

  /// confirmClearInk：清空笔迹前是否要求确认。
  final bool confirmClearInk;

  /// showLibraryStatusBar：是否展示资料库状态栏。
  final bool showLibraryStatusBar;

  /// defaultSidebarTab：初始侧栏页签编号：页面、目录、书签由界面约定解释。
  final int defaultSidebarTab;

  /// sidebarWidth：页面侧栏的逻辑像素宽度，窄窗口会进一步约束。
  final double sidebarWidth;

  /// defaultTool：新打开文稿的默认工具名称，独立于临时侧键工具。
  final String defaultTool;

  /// defaultPageFit：初始页面适配方式名称，例如适应宽度。
  final String defaultPageFit;

  /// penStyle：钢笔、圆珠笔、画笔等笔型名称，决定宽度响应与绘制方式。
  final String penStyle;

  /// autoSaveEnabled：手写笔迹自动保存开关；关闭不取消切页/退出刷盘。
  final bool autoSaveEnabled;

  /// autoSaveDelayMs：修改后自动保存的等待时间，单位毫秒，连续输入会重新计时。
  final int autoSaveDelayMs;

  /// selectionPriority：命中已有选区时是否优先移动，避免直接开始新选区。
  final bool selectionPriority;

  /// selectionHitRadius：选择命中的容差，使用方按屏幕比例换算。
  final double selectionHitRadius;

  /// lassoShape：自由套索或矩形套索的名称。
  final String lassoShape;

  /// eraserMode：整笔擦除或局部擦除的名称。
  final String eraserMode;

  /// eraserSize：橡皮范围的逻辑像素半径，显示与命中使用同一参数。
  final double eraserSize;

  /// defaultTextSize：新文本的字号，单位页面布局逻辑像素，默认 12。
  final double defaultTextSize;

  /// showPageNumber：是否绘制页面角标，不控制顶部页码输入框。
  final bool showPageNumber;

  /// penColor：普通笔颜色，使用 32 位 ARGB 保存。
  final int penColor;

  /// penWidth：普通笔笔宽，单位基准页面逻辑像素；保存笔迹时另做归一化。
  final double penWidth;

  /// highlighterWidth：荧光笔基准宽度，独立于普通笔宽度。
  final double highlighterWidth;

  /// penWidthPresets：普通笔工具栏的快速宽度档位列表。
  final List<double> penWidthPresets;

  /// highlighterWidthPresets：荧光笔工具栏的快速宽度档位列表。
  final List<double> highlighterWidthPresets;

  /// penButtonOneAction：逻辑一键的动作名称，物理侧键经过交换设置后映射到这里。
  final String penButtonOneAction;

  /// penButtonTwoAction：逻辑二键的动作名称，与逻辑一键分别保存。
  final String penButtonTwoAction;

  /// penButtonMomentary：侧键是否只在按住期间临时切换工具。
  final bool penButtonMomentary;

  /// swapPenButtons：是否交换两个物理侧键对应的逻辑动作。
  final bool swapPenButtons;

  /// penColorPresets：工具栏快速颜色列表，元素为 32 位 ARGB。
  final List<int> penColorPresets;

  /// laserMode：激光点或尾迹模式名称，激光不写入持久笔迹。
  final String laserMode;

  /// laserColor：激光显示颜色，使用 32 位 ARGB 保存。
  final int laserColor;

  /// laserWidth：激光显示宽度，单位逻辑像素。
  final double laserWidth;

  /// laserFadeMs：激光尾迹保留时长，单位毫秒。
  final int laserFadeMs;

  /// configStorageLocation：配置存储位置标识，区分用户目录、程序目录与资料库目录。
  final String configStorageLocation;

  /// 基于当前快照生成新设置；仅覆盖非空参数，未传入的选项保持原值，不修改原快照。
  AppSettings copyWith({
    MarkdownPreferences? markdown,
    ThemeMode? themeMode,
    String? language,
    String? dataRoot,
    bool? pressureEnabled,
    double? pressureSensitivity,
    String? pressureCurve,
    bool? stylusOnly,
    bool? showPerformance,
    bool? doubleTapZoomEnabled,
    bool? edgeBounceEnabled,
    bool? keepZoomOnPageChange,
    double? maximumZoom,
    double? wheelZoomSensitivity,
    int? pdfCachePages,
    int? pdfPrefetchPages,
    int? pdfImportDpi,
    int? jpgExportQuality,
    int? deviceMemoryGb,
    int? imageCacheEntries,
    int? imageCacheMegabytes,
    int? pagePreviewWidth,
    bool? pageAnimationsEnabled,
    double? touchInertiaStrength,
    bool? tooltipsEnabled,
    bool? compactToolbar,
    bool? openSidebarByDefault,
    bool? defaultReadOnly,
    bool? confirmClearInk,
    bool? showLibraryStatusBar,
    int? defaultSidebarTab,
    double? sidebarWidth,
    String? defaultTool,
    String? defaultPageFit,
    String? penStyle,
    bool? autoSaveEnabled,
    int? autoSaveDelayMs,
    bool? selectionPriority,
    double? selectionHitRadius,
    String? lassoShape,
    String? eraserMode,
    double? eraserSize,
    double? defaultTextSize,
    bool? showPageNumber,
    int? penColor,
    double? penWidth,
    double? highlighterWidth,
    List<double>? penWidthPresets,
    List<double>? highlighterWidthPresets,
    String? penButtonOneAction,
    String? penButtonTwoAction,
    bool? penButtonMomentary,
    bool? swapPenButtons,
    List<int>? penColorPresets,
    String? laserMode,
    int? laserColor,
    double? laserWidth,
    int? laserFadeMs,
    String? configStorageLocation,
  }) => AppSettings(
    markdown: markdown ?? this.markdown,
    themeMode: themeMode ?? this.themeMode,
    language: language ?? this.language,
    dataRoot: dataRoot ?? this.dataRoot,
    pressureEnabled: pressureEnabled ?? this.pressureEnabled,
    pressureSensitivity: pressureSensitivity ?? this.pressureSensitivity,
    pressureCurve: pressureCurve ?? this.pressureCurve,
    stylusOnly: stylusOnly ?? this.stylusOnly,
    showPerformance: showPerformance ?? this.showPerformance,
    doubleTapZoomEnabled: doubleTapZoomEnabled ?? this.doubleTapZoomEnabled,
    edgeBounceEnabled: edgeBounceEnabled ?? this.edgeBounceEnabled,
    keepZoomOnPageChange: keepZoomOnPageChange ?? this.keepZoomOnPageChange,
    maximumZoom: maximumZoom ?? this.maximumZoom,
    wheelZoomSensitivity: wheelZoomSensitivity ?? this.wheelZoomSensitivity,
    pdfCachePages: pdfCachePages ?? this.pdfCachePages,
    pdfPrefetchPages: pdfPrefetchPages ?? this.pdfPrefetchPages,
    pdfImportDpi: pdfImportDpi ?? this.pdfImportDpi,
    jpgExportQuality: jpgExportQuality ?? this.jpgExportQuality,
    deviceMemoryGb: deviceMemoryGb ?? this.deviceMemoryGb,
    imageCacheEntries: imageCacheEntries ?? this.imageCacheEntries,
    imageCacheMegabytes: imageCacheMegabytes ?? this.imageCacheMegabytes,
    pagePreviewWidth: pagePreviewWidth ?? this.pagePreviewWidth,
    pageAnimationsEnabled: pageAnimationsEnabled ?? this.pageAnimationsEnabled,
    touchInertiaStrength: touchInertiaStrength ?? this.touchInertiaStrength,
    tooltipsEnabled: tooltipsEnabled ?? this.tooltipsEnabled,
    compactToolbar: compactToolbar ?? this.compactToolbar,
    openSidebarByDefault: openSidebarByDefault ?? this.openSidebarByDefault,
    defaultReadOnly: defaultReadOnly ?? this.defaultReadOnly,
    confirmClearInk: confirmClearInk ?? this.confirmClearInk,
    showLibraryStatusBar: showLibraryStatusBar ?? this.showLibraryStatusBar,
    defaultSidebarTab: defaultSidebarTab ?? this.defaultSidebarTab,
    sidebarWidth: sidebarWidth ?? this.sidebarWidth,
    defaultTool: defaultTool ?? this.defaultTool,
    defaultPageFit: defaultPageFit ?? this.defaultPageFit,
    penStyle: penStyle ?? this.penStyle,
    autoSaveEnabled: autoSaveEnabled ?? this.autoSaveEnabled,
    autoSaveDelayMs: autoSaveDelayMs ?? this.autoSaveDelayMs,
    selectionPriority: selectionPriority ?? this.selectionPriority,
    selectionHitRadius: selectionHitRadius ?? this.selectionHitRadius,
    lassoShape: lassoShape ?? this.lassoShape,
    eraserMode: eraserMode ?? this.eraserMode,
    eraserSize: eraserSize ?? this.eraserSize,
    defaultTextSize: defaultTextSize ?? this.defaultTextSize,
    showPageNumber: showPageNumber ?? this.showPageNumber,
    penColor: penColor ?? this.penColor,
    penWidth: penWidth ?? this.penWidth,
    highlighterWidth: highlighterWidth ?? this.highlighterWidth,
    penWidthPresets: penWidthPresets ?? this.penWidthPresets,
    highlighterWidthPresets:
        highlighterWidthPresets ?? this.highlighterWidthPresets,
    penButtonOneAction: penButtonOneAction ?? this.penButtonOneAction,
    penButtonTwoAction: penButtonTwoAction ?? this.penButtonTwoAction,
    penButtonMomentary: penButtonMomentary ?? this.penButtonMomentary,
    swapPenButtons: swapPenButtons ?? this.swapPenButtons,
    penColorPresets: penColorPresets ?? this.penColorPresets,
    laserMode: laserMode ?? this.laserMode,
    laserColor: laserColor ?? this.laserColor,
    laserWidth: laserWidth ?? this.laserWidth,
    laserFadeMs: laserFadeMs ?? this.laserFadeMs,
    configStorageLocation: configStorageLocation ?? this.configStorageLocation,
  );
}
