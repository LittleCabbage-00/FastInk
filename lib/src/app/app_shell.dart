part of 'fastink_app.dart';

class FastInkApp extends StatefulWidget {
  /// 接收启动路径、不可变设置和可选测试仓库，建立 Windows 应用根组件；文件打开在首页挂载后执行。
  const FastInkApp({
    super.key,
    this.initialPath,
    this.externalFilePath,
    required this.settings,
    this.settingsRepository,
  });

  /// 直接传入的文件路径（图片或 PDF）。
  final String? initialPath;

  /// 从右键上下文菜单 --open-external 传入的文件路径。
  /// 会先复制到 %temp% 再以只读模式打开。
  final String? externalFilePath;

  /// settings：应用启动时的不可变配置快照，运行中通过控制器副本更新并持久化。
  final AppSettings settings;

  /// settingsRepository：宿主提供的设置仓库，可在测试中指向独立临时配置目录。
  final SettingsRepository? settingsRepository;

  /// 持有应用主题、语言、供电监测和工具提示状态。
  @override
  State<FastInkApp> createState() => _FastInkAppState();
}

class _FastInkAppState extends State<FastInkApp> with WidgetsBindingObserver {
  /// _settings：当前运行时设置副本；与临时工具状态、文稿内容分别维护。
  late final SettingsRepository _settings =
      widget.settingsRepository ?? SettingsRepository();

  /// _themeMode：根组件当前外观选择，变化后重建 Theme，不改变文稿纸色。
  late ThemeMode _themeMode = widget.settings.themeMode;

  /// _tooltipsEnabled：根组件的工具提示显示通知，避免无关设置更新牵连整个应用。
  late final ValueNotifier<bool> _tooltipsEnabled = ValueNotifier(
    widget.settings.tooltipsEnabled,
  );

  /// _language：根组件当前语言选择，可为跟随系统；实际 Locale 在显示前解析。
  late AppLanguage _language = AppLanguage.values.firstWhere(
    (AppLanguage value) => value.name == widget.settings.language,
    orElse: () => AppLanguage.system,
  );

  /// 按当前语言选择解析实际 Locale，跟随系统时使用平台语言。
  Locale get _locale => _language.resolve();

  /// 注册生命周期与供电监听，启动共享电源监测；对应订阅在 dispose 中解除。
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    RenderPowerMonitor.instance.start();
    RenderPowerMonitor.instance.addListener(_renderPolicyChanged);
  }

  /// 供电策略发生变化时刷新依赖主题/显示策略的根配置，不修改文稿内容。
  void _renderPolicyChanged() {
    if (mounted) setState(() {});
  }

  /// 停止供电监测，解除界面生命周期监听并释放工具提示开关。
  @override
  void dispose() {
    RenderPowerMonitor.instance.removeListener(_renderPolicyChanged);
    RenderPowerMonitor.instance.stop();
    _tooltipsEnabled.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// 系统语言变化时仅在跟随系统模式下重新解析当前显示语言。
  @override
  void didChangeLocales(List<Locale>? locales) {
    if (_language != AppLanguage.system || !mounted) return;
    setState(() => AppText.locale = _locale);
  }

  /// 更新根主题并保存外观选择，文稿纸色与所选墨色不随界面主题改写。
  Future<void> _setThemeMode(ThemeMode mode) async {
    setState(() => _themeMode = mode);
    await _settings.saveThemeMode(mode);
  }

  /// 更新语言、全局翻译状态和持久设置，让已挂载界面同步显示文案。
  Future<void> _setLanguage(AppLanguage language) async {
    setState(() {
      _language = language;
      AppText.locale = _locale;
    });
    await _settings.saveLanguage(language);
  }

  /// 建立指定亮度的 Material 主题，统一字体、颜色和桌面控件密度。
  ThemeData _theme(Brightness brightness) {
    final ColorScheme colors = ColorScheme.fromSeed(
      seedColor: const Color(0xff5965df),
      brightness: brightness,
    );
    final bool dark = brightness == Brightness.dark;
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: Platform.isWindows ? 'Segoe UI Variable' : null,
      fontFamilyFallback: Platform.isWindows
          ? const <String>['Microsoft YaHei UI', 'Segoe UI']
          : null,
      colorScheme: colors,
      scaffoldBackgroundColor: dark
          ? const Color(0xff101217)
          : const Color(0xfff7f7fa),
      appBarTheme: AppBarTheme(
        backgroundColor: dark
            ? const Color(0xff171a20)
            : const Color(0xfffbfbfd),
        foregroundColor: dark
            ? const Color(0xfff4f4f6)
            : const Color(0xff24252a),
        surfaceTintColor: Colors.transparent,
      ),
      tooltipTheme: const TooltipThemeData(
        waitDuration: Duration(milliseconds: 300),
      ),
      dividerColor: dark ? Colors.white12 : Colors.black12,
      popupMenuTheme: PopupMenuThemeData(
        color: dark ? const Color(0xff24272e) : Colors.white,
        surfaceTintColor: Colors.transparent,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: dark ? const Color(0xff24272e) : Colors.white,
        surfaceTintColor: Colors.transparent,
      ),
    );
  }

  /// 组装 MaterialApp、本地化、主题和首页配置，将持久选项传给运行时控制器。
  @override
  Widget build(BuildContext context) {
    AppText.locale = _locale;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'FastInk',
      builder: (context, child) => ValueListenableBuilder<bool>(
        valueListenable: _tooltipsEnabled,
        child: child,
        builder: (context, enabled, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations:
                MediaQuery.disableAnimationsOf(context) ||
                RenderPowerMonitor.instance.value.economical,
          ),
          child: TooltipVisibility(visible: enabled, child: child!),
        ),
      ),
      locale: _locale,
      supportedLocales: const <Locale>[Locale('zh'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      themeMode: _themeMode,
      themeAnimationDuration: RenderPowerMonitor.instance.value.economical
          ? Duration.zero
          : const Duration(milliseconds: 140),
      themeAnimationCurve: Curves.easeOutCubic,
      scrollBehavior: const _DocumentScrollBehavior(),
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      home: FastInkHome(
        settingsRepository: _settings,
        onTooltipsChanged: (value) => _tooltipsEnabled.value = value,
        initialPath: widget.initialPath,
        externalFilePath: widget.externalFilePath,
        dataRoot: widget.settings.dataRoot,
        pressureEnabled: widget.settings.pressureEnabled,
        pressureSensitivity: widget.settings.pressureSensitivity,
        pressureCurve: widget.settings.pressureCurve,
        stylusOnly: widget.settings.stylusOnly,
        showPerformance: widget.settings.showPerformance,
        doubleTapZoomEnabled: widget.settings.doubleTapZoomEnabled,
        edgeBounceEnabled: widget.settings.edgeBounceEnabled,
        keepZoomOnPageChange: widget.settings.keepZoomOnPageChange,
        maximumZoom: widget.settings.maximumZoom,
        wheelZoomSensitivity: widget.settings.wheelZoomSensitivity,
        pdfCachePages: widget.settings.pdfCachePages,
        pdfPrefetchPages: widget.settings.pdfPrefetchPages,
        pdfImportDpi: widget.settings.pdfImportDpi,
        jpgExportQuality: widget.settings.jpgExportQuality,
        deviceMemoryGb: widget.settings.deviceMemoryGb,
        imageCacheEntries: widget.settings.imageCacheEntries,
        imageCacheMegabytes: widget.settings.imageCacheMegabytes,
        pagePreviewWidth: widget.settings.pagePreviewWidth,
        pageAnimationsEnabled: widget.settings.pageAnimationsEnabled,
        touchInertiaStrength: widget.settings.touchInertiaStrength,
        tooltipsEnabled: widget.settings.tooltipsEnabled,
        compactToolbar: widget.settings.compactToolbar,
        openSidebarByDefault: widget.settings.openSidebarByDefault,
        defaultReadOnly: widget.settings.defaultReadOnly,
        confirmClearInk: widget.settings.confirmClearInk,
        showLibraryStatusBar: widget.settings.showLibraryStatusBar,
        defaultSidebarTab: widget.settings.defaultSidebarTab,
        sidebarWidth: widget.settings.sidebarWidth,
        defaultTool: widget.settings.defaultTool,
        defaultPageFit: widget.settings.defaultPageFit,
        defaultPenStyle: widget.settings.penStyle,
        autoSaveEnabled: widget.settings.autoSaveEnabled,
        autoSaveDelayMs: widget.settings.autoSaveDelayMs,
        selectionPriority: widget.settings.selectionPriority,
        selectionHitRadius: widget.settings.selectionHitRadius,
        lassoShape: widget.settings.lassoShape,
        defaultEraserMode: widget.settings.eraserMode,
        defaultEraserSize: widget.settings.eraserSize,
        defaultTextSize: widget.settings.defaultTextSize,
        showPageNumber: widget.settings.showPageNumber,
        defaultPenColor: widget.settings.penColor,
        defaultPenWidth: widget.settings.penWidth,
        defaultHighlighterWidth: widget.settings.highlighterWidth,
        penWidthPresets: widget.settings.penWidthPresets,
        highlighterWidthPresets: widget.settings.highlighterWidthPresets,
        penButtonOneAction: widget.settings.penButtonOneAction,
        penButtonTwoAction: widget.settings.penButtonTwoAction,
        penButtonMomentary: widget.settings.penButtonMomentary,
        swapPenButtons: widget.settings.swapPenButtons,
        markdown: widget.settings.markdown,
        penColorPresets: widget.settings.penColorPresets,
        laserMode: widget.settings.laserMode,
        laserColor: widget.settings.laserColor,
        laserWidth: widget.settings.laserWidth,
        laserFadeMs: widget.settings.laserFadeMs,
        configStorageLocation: widget.settings.configStorageLocation,
        themeMode: _themeMode,
        onThemeModeChanged: _setThemeMode,
        language: _language,
        onLanguageChanged: _setLanguage,
      ),
    );
  }
}
