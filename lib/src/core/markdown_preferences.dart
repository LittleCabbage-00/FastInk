/// 持久化的 Markdown 偏好，由资料库和编辑器设置共用。
class MarkdownPreferences {
  /// 创建独立的 Markdown 设置快照，默认值不会继承手写工具配置。
  const MarkdownPreferences({
    this.showWordCount = true,
    this.hideCompletedTasks = false,
    this.historyEnabled = true,
    this.historyLimit = 50,
    this.diagramEnabled = true,
    this.defaultMode = 'split',
    this.openOutline = false,
    this.lineNumbers = true,
    this.syntaxHighlight = true,
    this.autoPair = true,
    this.continueLists = true,
    this.tabSize = 2,
    this.editorFont = 'Consolas',
    this.fontSize = 15,
    this.lineHeight = 1.6,
    this.previewFontSize = 15,
    this.previewWidth = 900,
    this.syncScroll = true,
    this.previewDelayMs = 250,
    this.mathEnabled = true,
    this.remoteImages = true,
    this.autoSave = true,
    this.autoSaveDelayMs = 1000,
    this.typewriter = false,
    this.focusMode = false,
    this.exportFormat = 'pdf',
    this.exportScale = 1.5,
    this.jpgQuality = 94,
    this.exportDark = false,
  });

  /// showWordCount：是否显示 Markdown 全文及选区统计。
  final bool showWordCount;

  /// hideCompletedTasks：待办总览是否隐藏已完成条目。
  final bool hideCompletedTasks;

  /// historyEnabled：是否为 Markdown 保存本地修订历史。
  final bool historyEnabled;

  /// historyLimit：每篇 Markdown 保留的修订数量上限。
  final int historyLimit;

  /// diagramEnabled：是否渲染受支持的 Markdown 图表围栏。
  final bool diagramEnabled;

  /// defaultMode：Markdown 默认编辑/分栏/阅读模式标识。
  final String defaultMode;

  /// openOutline：是否在打开 Markdown 时显示目录面板。
  final bool openOutline;

  /// lineNumbers：是否显示 Markdown 源码行号。
  final bool lineNumbers;

  /// syntaxHighlight：是否启用源码和代码块语法高亮。
  final bool syntaxHighlight;

  /// autoPair：是否自动配对括号、引号与反引号。
  final bool autoPair;

  /// continueLists：回车时是否延续列表、待办与引用前缀。
  final bool continueLists;

  /// tabSize：Tab 缩进对应的空格数量。
  final int tabSize;

  /// editorFont：Markdown 源码字体名称。
  final String editorFont;

  /// fontSize：文字排版字号，单位所在布局的逻辑像素；持久笔迹的归一化字号另用 textSize。
  final double fontSize;

  /// lineHeight：文本行高倍率，与字号相乘得到行高。
  final double lineHeight;

  /// previewFontSize：Markdown 阅读预览字号，单位逻辑像素。
  final double previewFontSize;

  /// previewWidth：Markdown 阅读区域宽度上限，单位逻辑像素。
  final double previewWidth;

  /// syncScroll：是否启用编辑与预览的滚动联动。
  final bool syncScroll;

  /// previewDelayMs：源码变化到重新渲染预览的防抖间隔，单位毫秒。
  final int previewDelayMs;

  /// mathEnabled：是否渲染 Markdown 数学公式。
  final bool mathEnabled;

  /// remoteImages：是否允许加载 Markdown 中的远程图片。
  final bool remoteImages;

  /// autoSave：Markdown 自动保存开关，独立于手写自动保存。
  final bool autoSave;

  /// autoSaveDelayMs：修改后自动保存的等待时间，单位毫秒，连续输入会重新计时。
  final int autoSaveDelayMs;

  /// typewriter：是否启用打字机式跟随光标滚动。
  final bool typewriter;

  /// focusMode：是否隐藏 Markdown 编辑的次要界面元素。
  final bool focusMode;

  /// exportFormat：Markdown 导出的格式名称。
  final String exportFormat;

  /// exportScale：Markdown 栅格导出的缩放倍率，不改变源文。
  final double exportScale;

  /// jpgQuality：Markdown JPG 导出质量百分比。
  final int jpgQuality;

  /// exportDark：Markdown 导出是否使用深色配色。
  final bool exportDark;

  /// 复制 Markdown 配置，只替换显式传入的选项，其余选项保持原值。
  MarkdownPreferences copyWith({
    bool? showWordCount,
    bool? hideCompletedTasks,
    bool? historyEnabled,
    int? historyLimit,
    bool? diagramEnabled,
    String? defaultMode,
    bool? openOutline,
    bool? lineNumbers,
    bool? syntaxHighlight,
    bool? autoPair,
    bool? continueLists,
    int? tabSize,
    String? editorFont,
    double? fontSize,
    double? lineHeight,
    double? previewFontSize,
    double? previewWidth,
    bool? syncScroll,
    int? previewDelayMs,
    bool? mathEnabled,
    bool? remoteImages,
    bool? autoSave,
    int? autoSaveDelayMs,
    bool? typewriter,
    bool? focusMode,
    String? exportFormat,
    double? exportScale,
    int? jpgQuality,
    bool? exportDark,
  }) => MarkdownPreferences(
    showWordCount: showWordCount ?? this.showWordCount,
    hideCompletedTasks: hideCompletedTasks ?? this.hideCompletedTasks,
    historyEnabled: historyEnabled ?? this.historyEnabled,
    historyLimit: historyLimit ?? this.historyLimit,
    diagramEnabled: diagramEnabled ?? this.diagramEnabled,
    defaultMode: defaultMode ?? this.defaultMode,
    openOutline: openOutline ?? this.openOutline,
    lineNumbers: lineNumbers ?? this.lineNumbers,
    syntaxHighlight: syntaxHighlight ?? this.syntaxHighlight,
    autoPair: autoPair ?? this.autoPair,
    continueLists: continueLists ?? this.continueLists,
    tabSize: tabSize ?? this.tabSize,
    editorFont: editorFont ?? this.editorFont,
    fontSize: fontSize ?? this.fontSize,
    lineHeight: lineHeight ?? this.lineHeight,
    previewFontSize: previewFontSize ?? this.previewFontSize,
    previewWidth: previewWidth ?? this.previewWidth,
    syncScroll: syncScroll ?? this.syncScroll,
    previewDelayMs: previewDelayMs ?? this.previewDelayMs,
    mathEnabled: mathEnabled ?? this.mathEnabled,
    remoteImages: remoteImages ?? this.remoteImages,
    autoSave: autoSave ?? this.autoSave,
    autoSaveDelayMs: autoSaveDelayMs ?? this.autoSaveDelayMs,
    typewriter: typewriter ?? this.typewriter,
    focusMode: focusMode ?? this.focusMode,
    exportFormat: exportFormat ?? this.exportFormat,
    exportScale: exportScale ?? this.exportScale,
    jpgQuality: jpgQuality ?? this.jpgQuality,
    exportDark: exportDark ?? this.exportDark,
  );

  /// 将 Markdown 选项编码成可持久化键值；不包含正文或编辑器瞬时状态。
  Map<String, Object?> toJson() => {
    'showWordCount': showWordCount,
    'hideCompletedTasks': hideCompletedTasks,
    'historyEnabled': historyEnabled,
    'historyLimit': historyLimit,
    'diagramEnabled': diagramEnabled,
    'defaultMode': defaultMode,
    'openOutline': openOutline,
    'lineNumbers': lineNumbers,
    'syntaxHighlight': syntaxHighlight,
    'autoPair': autoPair,
    'continueLists': continueLists,
    'tabSize': tabSize,
    'editorFont': editorFont,
    'fontSize': fontSize,
    'lineHeight': lineHeight,
    'previewFontSize': previewFontSize,
    'previewWidth': previewWidth,
    'syncScroll': syncScroll,
    'previewDelayMs': previewDelayMs,
    'mathEnabled': mathEnabled,
    'remoteImages': remoteImages,
    'autoSave': autoSave,
    'autoSaveDelayMs': autoSaveDelayMs,
    'typewriter': typewriter,
    'focusMode': focusMode,
    'exportFormat': exportFormat,
    'exportScale': exportScale,
    'jpgQuality': jpgQuality,
    'exportDark': exportDark,
  };

  /// 读取持久化 Markdown 配置；非对象、字段类型错误、越界数值与未知枚举按各项默认规则回退。
  factory MarkdownPreferences.fromJson(Object? value) {
    final json = value is Map ? value : const <String, Object?>{};
    // 读取指定布尔选项；类型不匹配时使用 fallback，避免一个坏字段重置整份配置。
    bool flag(String key, bool fallback) =>
        json[key] is bool ? json[key] as bool : fallback;
    // 读取数值并限制到 minimum/maximum；非法或非有限值回退 fallback。
    double number(String key, double fallback, double minimum, double maximum) {
      final raw = json[key];
      return raw is num && raw.isFinite
          ? raw.toDouble().clamp(minimum, maximum)
          : fallback;
    }

    // 读取限定集合中的字符串选项；未知名称使用 fallback。
    String choice(String key, List<String> options, String fallback) =>
        options.contains(json[key]) ? json[key] as String : fallback;
    return MarkdownPreferences(
      showWordCount: flag('showWordCount', true),
      hideCompletedTasks: flag('hideCompletedTasks', false),
      historyEnabled: flag('historyEnabled', true),
      historyLimit: number('historyLimit', 50, 10, 200).round(),
      diagramEnabled: flag('diagramEnabled', true),
      defaultMode: choice('defaultMode', const [
        'live',
        'edit',
        'split',
        'read',
      ], 'split'),
      openOutline: flag('openOutline', false),
      lineNumbers: flag('lineNumbers', true),
      syntaxHighlight: flag('syntaxHighlight', true),
      autoPair: flag('autoPair', true),
      continueLists: flag('continueLists', true),
      tabSize:
          json['tabSize'] is int && const [2, 4, 8].contains(json['tabSize'])
          ? json['tabSize'] as int
          : 2,
      editorFont: choice('editorFont', const [
        'Consolas',
        'Microsoft YaHei UI',
        'Segoe UI',
      ], 'Consolas'),
      fontSize: number('fontSize', 15, 11, 26),
      lineHeight: number('lineHeight', 1.6, 1.2, 2.2),
      previewFontSize: number('previewFontSize', 15, 12, 26),
      previewWidth: number('previewWidth', 900, 600, 1200),
      syncScroll: flag('syncScroll', true),
      previewDelayMs: number('previewDelayMs', 250, 100, 1000).round(),
      mathEnabled: flag('mathEnabled', true),
      remoteImages: flag('remoteImages', true),
      autoSave: flag('autoSave', true),
      autoSaveDelayMs: number('autoSaveDelayMs', 1000, 300, 5000).round(),
      typewriter: flag('typewriter', false),
      focusMode: flag('focusMode', false),
      exportFormat: choice('exportFormat', const [
        'pdf',
        'png',
        'jpg',
        'md',
        'html',
        'docx',
        'txt',
      ], 'pdf'),
      exportScale: number('exportScale', 1.5, 1, 2),
      jpgQuality: number('jpgQuality', 94, 70, 100).round(),
      exportDark: flag('exportDark', false),
    );
  }

  /// 按持久化内容比较两份 Markdown 配置，便于界面判断是否需要同步。
  @override
  bool operator ==(Object other) =>
      other is MarkdownPreferences &&
      showWordCount == other.showWordCount &&
      hideCompletedTasks == other.hideCompletedTasks &&
      historyEnabled == other.historyEnabled &&
      historyLimit == other.historyLimit &&
      diagramEnabled == other.diagramEnabled &&
      defaultMode == other.defaultMode &&
      openOutline == other.openOutline &&
      lineNumbers == other.lineNumbers &&
      syntaxHighlight == other.syntaxHighlight &&
      autoPair == other.autoPair &&
      continueLists == other.continueLists &&
      tabSize == other.tabSize &&
      editorFont == other.editorFont &&
      fontSize == other.fontSize &&
      lineHeight == other.lineHeight &&
      previewFontSize == other.previewFontSize &&
      previewWidth == other.previewWidth &&
      syncScroll == other.syncScroll &&
      previewDelayMs == other.previewDelayMs &&
      mathEnabled == other.mathEnabled &&
      remoteImages == other.remoteImages &&
      autoSave == other.autoSave &&
      autoSaveDelayMs == other.autoSaveDelayMs &&
      typewriter == other.typewriter &&
      focusMode == other.focusMode &&
      exportFormat == other.exportFormat &&
      exportScale == other.exportScale &&
      jpgQuality == other.jpgQuality &&
      exportDark == other.exportDark;

  /// 根据同一组持久化字段计算哈希，保持与相等比较一致。
  @override
  int get hashCode => Object.hashAll(toJson().values);
}
