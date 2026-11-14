part of 'fastink_app.dart';

class FastInkHome extends StatefulWidget implements AppSettingsSource {
  /// 接收根组件传入的初始设置、存储位置与宿主回调；运行时状态交给首页控制器，构造参数不是可变文稿内容。
  const FastInkHome({
    super.key,
    this.settingsRepository,
    this.onTooltipsChanged,
    this.initialPath,
    this.externalFilePath,
    required this.themeMode,
    required this.onThemeModeChanged,
    required this.language,
    required this.onLanguageChanged,
    required this.dataRoot,
    required this.pressureEnabled,
    required this.pressureSensitivity,
    required this.pressureCurve,
    required this.stylusOnly,
    required this.showPerformance,
    required this.doubleTapZoomEnabled,
    required this.edgeBounceEnabled,
    required this.keepZoomOnPageChange,
    required this.maximumZoom,
    required this.wheelZoomSensitivity,
    required this.pdfCachePages,
    required this.pdfPrefetchPages,
    required this.pdfImportDpi,
    required this.jpgExportQuality,
    required this.deviceMemoryGb,
    required this.imageCacheEntries,
    required this.imageCacheMegabytes,
    required this.pagePreviewWidth,
    required this.pageAnimationsEnabled,
    required this.touchInertiaStrength,
    required this.tooltipsEnabled,
    required this.compactToolbar,
    required this.openSidebarByDefault,
    required this.defaultReadOnly,
    required this.confirmClearInk,
    required this.showLibraryStatusBar,
    required this.defaultSidebarTab,
    required this.sidebarWidth,
    required this.defaultTool,
    required this.defaultPageFit,
    required this.defaultPenStyle,
    required this.autoSaveEnabled,
    required this.autoSaveDelayMs,
    required this.selectionPriority,
    required this.selectionHitRadius,
    required this.lassoShape,
    required this.defaultEraserMode,
    required this.defaultEraserSize,
    required this.defaultTextSize,
    required this.showPageNumber,
    required this.defaultPenColor,
    required this.defaultPenWidth,
    required this.defaultHighlighterWidth,
    required this.penWidthPresets,
    required this.highlighterWidthPresets,
    required this.penButtonOneAction,
    required this.penButtonTwoAction,
    required this.penButtonMomentary,
    required this.swapPenButtons,
    this.markdown = const MarkdownPreferences(),
    required this.penColorPresets,
    required this.laserMode,
    required this.laserColor,
    required this.laserWidth,
    required this.laserFadeMs,
    required this.configStorageLocation,
  });

  /// initialPath：启动后要打开的内部文件路径，为空时先展示资料库。
  final String? initialPath;

  /// settingsRepository：宿主提供的设置仓库，可在测试中指向独立临时配置目录。
  final SettingsRepository? settingsRepository;

  /// onTooltipsChanged：工具提示开关变化通知根组件的回调，使已有控件同步显示策略。
  final ValueChanged<bool>? onTooltipsChanged;

  /// 从右键上下文菜单传入的外部文件路径，以只读模式打开。
  final String? externalFilePath;

  /// themeMode：界面外观模式：跟随系统、浅色或深色，不等同于纸张颜色。
  final ThemeMode themeMode;

  /// onThemeModeChanged：用户选择外观模式后的回调，根组件统一更新主题并保存。
  final ValueChanged<ThemeMode> onThemeModeChanged;

  /// language：用户选择的界面语言标识，系统语言模式在显示时解析。
  final AppLanguage language;

  /// onLanguageChanged：用户选择语言后的回调，根组件统一解析 Locale 并持久化。
  final ValueChanged<AppLanguage> onLanguageChanged;

  /// dataRoot：当前资料库根目录，文稿、笔迹和本地资源都相对该目录定位。
  final String dataRoot;

  /// pressureEnabled：是否将触笔压力用于笔宽；鼠标输入不能污染该开关。
  @override
  final bool pressureEnabled;

  /// pressureSensitivity：输入时的压感响应倍率；形成有效压力点，修改偏好不追溯改写旧笔迹。
  @override
  final double pressureSensitivity;

  /// pressureCurve：压力映射曲线名称，用于笔迹宽度计算。
  @override
  final String pressureCurve;

  /// stylusOnly：是否只接受触笔书写；鼠标选择等非书写操作仍按输入规则处理。
  @override
  final bool stylusOnly;

  /// showPerformance：是否显示诊断性能信息，不改变实际渲染精度。
  @override
  final bool showPerformance;

  /// doubleTapZoomEnabled：是否启用纸面双击缩放手势，浮层按钮会排除在识别范围外。
  @override
  final bool doubleTapZoomEnabled;

  /// edgeBounceEnabled：页面边界回弹配置，读取方决定是否用于当前交互。
  @override
  final bool edgeBounceEnabled;

  /// keepZoomOnPageChange：切页时是否保留缩放比例。
  @override
  final bool keepZoomOnPageChange;

  /// maximumZoom：视图最大缩放倍数，1 表示基准比例。
  @override
  final double maximumZoom;

  /// wheelZoomSensitivity：Ctrl+滚轮的缩放灵敏度倍率。
  @override
  final double wheelZoomSensitivity;

  /// pdfCachePages：PDF 页面缓存的数量预算，单位为页。
  @override
  final int pdfCachePages;

  /// pdfPrefetchPages：PDF 邻页预取数量上限，经济策略可进一步限制。
  @override
  final int pdfPrefetchPages;

  /// pdfImportDpi 用于 PDF 页面栅格化，单位为 DPI。
  @override
  final int pdfImportDpi;

  /// jpgExportQuality：JPG 编码质量百分比，与屏幕预览清晰度分开。
  @override
  final int jpgExportQuality;

  /// deviceMemoryGb：选择的设备内存档位，单位 GB，用于解析资源预算。
  @override
  final int deviceMemoryGb;

  /// imageCacheEntries：Flutter 图像缓存条目数量预算。
  @override
  final int imageCacheEntries;

  /// imageCacheMegabytes：Flutter 图像缓存容量预算，单位 MB。
  @override
  final int imageCacheMegabytes;

  /// pagePreviewWidth：页面低分辨率预览宽度预算，单位像素。
  @override
  final int pagePreviewWidth;

  /// pageAnimationsEnabled：是否允许页面导航动画，系统减少动画或经济策略还可抑制。
  @override
  final bool pageAnimationsEnabled;

  /// touchInertiaStrength：触摸平移惯性的强度参数，不降低笔采样频率。
  @override
  final double touchInertiaStrength;

  /// tooltipsEnabled：是否展示工具提示，仅影响界面说明。
  @override
  final bool tooltipsEnabled;

  /// compactToolbar：是否使用紧凑工具栏布局。
  @override
  final bool compactToolbar;

  /// openSidebarByDefault：打开手写文稿时是否默认展示页面侧栏。
  @override
  final bool openSidebarByDefault;

  /// defaultReadOnly：新打开文稿的默认只读状态，不改写文稿文件权限。
  @override
  final bool defaultReadOnly;

  /// confirmClearInk：清空笔迹前是否要求确认。
  @override
  final bool confirmClearInk;

  /// showLibraryStatusBar：是否展示资料库状态栏。
  @override
  final bool showLibraryStatusBar;

  /// defaultSidebarTab：初始侧栏页签编号：页面、目录、书签由界面约定解释。
  @override
  final int defaultSidebarTab;

  /// sidebarWidth：页面侧栏的逻辑像素宽度，窄窗口会进一步约束。
  @override
  final double sidebarWidth;

  /// defaultTool：新打开文稿的默认工具名称，独立于临时侧键工具。
  @override
  final String defaultTool;

  /// defaultPageFit：初始页面适配方式名称，例如适应宽度。
  @override
  final String defaultPageFit;

  /// defaultPenStyle：打开文稿时采用的默认笔型名称。
  @override
  final String defaultPenStyle;

  /// autoSaveEnabled：手写笔迹自动保存开关；关闭不取消切页/退出刷盘。
  @override
  final bool autoSaveEnabled;

  /// autoSaveDelayMs：修改后自动保存的等待时间，单位毫秒，连续输入会重新计时。
  @override
  final int autoSaveDelayMs;

  /// selectionPriority：命中已有选区时是否优先移动，避免直接开始新选区。
  @override
  final bool selectionPriority;

  /// selectionHitRadius：选择命中的容差，使用方按屏幕比例换算。
  @override
  final double selectionHitRadius;

  /// lassoShape：自由套索或矩形套索的名称。
  @override
  final String lassoShape;

  /// defaultEraserMode：默认橡皮模式；侧键临时模式不覆盖此配置。
  @override
  final String defaultEraserMode;

  /// defaultEraserSize：默认橡皮范围，单位逻辑像素。
  @override
  final double defaultEraserSize;

  /// defaultTextSize：新文本的字号，单位页面布局逻辑像素，默认 12。
  @override
  final double defaultTextSize;

  /// showPageNumber：是否绘制页面角标，不控制顶部页码输入框。
  @override
  final bool showPageNumber;

  /// defaultPenColor：初始普通笔颜色，使用 32 位 ARGB 保存。
  @override
  final int defaultPenColor;

  /// defaultPenWidth：初始普通笔的基准页面逻辑像素宽度。
  @override
  final double defaultPenWidth;

  /// defaultHighlighterWidth：初始荧光笔基准页面宽度。
  @override
  final double defaultHighlighterWidth;

  /// penWidthPresets：普通笔工具栏的快速宽度档位列表。
  @override
  final List<double> penWidthPresets;

  /// highlighterWidthPresets：荧光笔工具栏的快速宽度档位列表。
  @override
  final List<double> highlighterWidthPresets;

  /// penButtonOneAction：逻辑一键的动作名称，物理侧键经过交换设置后映射到这里。
  @override
  final String penButtonOneAction;

  /// penButtonTwoAction：逻辑二键的动作名称，与逻辑一键分别保存。
  @override
  final String penButtonTwoAction;

  /// penButtonMomentary：侧键是否只在按住期间临时切换工具。
  @override
  final bool penButtonMomentary;

  /// swapPenButtons：是否交换两个物理侧键对应的逻辑动作。
  @override
  final bool swapPenButtons;

  /// markdown：Markdown 独立配置，供工作台与设置面板共享，不改变手写设置。
  @override
  final MarkdownPreferences markdown;

  /// penColorPresets：工具栏快速颜色列表，元素为 32 位 ARGB。
  @override
  final List<int> penColorPresets;

  /// laserMode：激光点或尾迹模式名称，激光不写入持久笔迹。
  @override
  final String laserMode;

  /// laserColor：激光显示颜色，使用 32 位 ARGB 保存。
  @override
  final int laserColor;

  /// laserWidth：激光显示宽度，单位逻辑像素。
  @override
  final double laserWidth;

  /// laserFadeMs：激光尾迹保留时长，单位毫秒。
  @override
  final int laserFadeMs;

  /// configStorageLocation：配置存储位置标识，区分用户目录、程序目录与资料库目录。
  @override
  final String configStorageLocation;

  /// 维护资料库、打开的文稿和画布交互状态。
  @override
  State<FastInkHome> createState() => _FastInkHomeState();
}
