import 'dart:math' as math;
import 'dart:ui';

enum StrokeKind { pen, highlighter, image }

enum PenStyle { fountain, ball, brush, pencil }

class NotePage {
  /// 记录底图路径、尺寸及稳定页编号。
  /// index：该页面在当前文稿序列中的零基位置，重排后可以变化。
  /// originalPage：页面的稳定原始编号，用于定位笔迹文件，不能用当前页序代替。
  /// path：对象对应的本地文件路径；具体是否已存在由读取/创建入口校验。
  /// name：用户可读名称；用于显示或文件名解析，不应替代稳定编号。
  const NotePage({
    required this.index,
    required this.originalPage,
    required this.path,
    required this.name,
  });

  /// index：该页面在当前文稿序列中的零基位置，重排后可以变化。
  final int index;

  /// originalPage：页面的稳定原始编号，用于定位笔迹文件，不能用当前页序代替。
  final int originalPage;

  /// 本页位图路径。按需 PDF 页由 [NoteRepository.ensurePageImage] 生成。
  final String path;

  /// name：用户可读名称；用于显示或文件名解析，不应替代稳定编号。
  final String name;
}

class NoteDocument {
  /// 记录文稿身份、页面顺序、底图来源和目录。
  /// id：对象的稳定身份编号，用于索引、关联和缓存键，不是显示标题。
  /// 保存和显示使用的完整标题。
  /// directory：该对象对应的本地目录；只表示路径，不保证目录已经创建。
  /// pages：按当前页序保存的页面描述集合，实际位图与笔迹另行按需读取。
  /// initialIndex：打开文稿时定位的零基页面索引。
  const NoteDocument({
    required this.id,
    required this.title,
    required this.directory,
    required this.pages,
    required this.initialIndex,
  });

  /// id：对象的稳定身份编号，用于索引、关联和缓存键，不是显示标题。
  final String id;

  /// 保存和显示使用的完整标题。
  final String title;

  /// directory：该对象对应的本地目录；只表示路径，不保证目录已经创建。
  final String directory;

  /// pages：按当前页序保存的页面描述集合，实际位图与笔迹另行按需读取。
  final List<NotePage> pages;

  /// initialIndex：打开文稿时定位的零基页面索引。
  final int initialIndex;
}

class InkPoint {
  /// 建立归一化页面位置与已映射的有效压力采样，视图缩放不能直接写回这些坐标。
  const InkPoint(this.x, this.y, this.pressure);

  /// 页面归一化坐标，与窗口尺寸和导出分辨率无关。
  final double x;

  /// y：点在页面高度上的归一化坐标，与屏幕像素和视图缩放无关。
  final double y;

  /// pressure：该点保存的有效压力，实时输入已应用当时的曲线与灵敏度；后续显示/导出不应再次应用用户曲线。
  final double pressure;

  /// 把笔迹对象编码为稳定 JSON 字段，完整点列、文字和样式必须保留以便继续编辑。
  Map<String, Object?> toJson() => <String, Object?>{
    'x': x,
    'y': y,
    'p': pressure,
  };

  /// 从 JSON 恢复点位置与压力，兼容旧记录的缺省值。
  factory InkPoint.fromJson(Map<String, Object?> json) => InkPoint(
    (json['x'] as num).toDouble(),
    (json['y'] as num).toDouble(),
    (json['p'] as num?)?.toDouble() ?? 0.5,
  );
}

class InkStroke {
  /// 建立普通笔画、形状、文字或图片对象；类型专用参数仅在相应 kind 下解释，点列须由调用方明确所有权。
  InkStroke({
    required this.color,
    required this.width,
    required this.points,
    this.kind = StrokeKind.pen,
    this.penStyle = PenStyle.fountain,
    this.text,
    this.textSize = 0.035,
    this.textBoxWidth,
    this.textWeight = 400,
    this.textItalic = false,
    this.textUnderline = false,
    this.textAlign = TextAlign.left,
    this.textFontFamily = 'Segoe UI Variable',
    this.imageAsset,
  });

  /// 绘制颜色。
  final int color;

  /// 笔迹粗细，按**页面几何平均边长**归一化：像素粗细 = `width × √(宽×高)`。
  ///
  /// 和 [points] 一样与窗口尺寸、导出分辨率无关，所以屏幕、侧栏缩略图和
  /// 导出用的是同一个数，粗细自然一致（v2 及以前存的是当时的布局像素，
  /// 导出按图片像素画，结果比屏幕细一个页面尺度——见 [PageInk.version]）。
  ///
  /// 基准取几何平均而不是页宽，是为了让 90° 旋转天然保持粗细：旋转时
  /// 宽高互换、几何平均不变，[copy] 原样搬字段即可。若按页宽归一，每次
  /// 旋转都得记得折算粗细，漏一次就是静默的粗细错误。
  final double width;

  /// points：笔画的归一化页面点列；文字和图片用角点表达可变换几何。
  final List<InkPoint> points;

  /// kind：笔画内容种类，决定普通线段、文字、形状和图片各自的绘制/编辑路径。
  final StrokeKind kind;

  /// penStyle：钢笔、圆珠笔、画笔等笔型枚举；JSON 保存其名称，内存中不是字符串。
  final PenStyle penStyle;

  /// text：对象保存的完整文字内容；非文字对象可为空，不用截断显示文本替代源文。
  final String? text;

  /// textSize：文字保存的归一化字号，绘制时相对页面高度还原为逻辑字号。
  final double textSize;

  /// 按页宽归一化的排版宽度。[points] 记录变换后的文本框轮廓。
  final double? textBoxWidth;

  /// textWeight：文字字重数值，常规与粗体分别按实际字重恢复。
  final int textWeight;

  /// textItalic：文字斜体标志，属于可持久化文本样式。
  final bool textItalic;

  /// textUnderline：文字下划线标志，属于可持久化文本样式。
  final bool textUnderline;

  /// textAlign：段落水平对齐方式，文字排版和保存共用。
  final TextAlign textAlign;

  /// textFontFamily：文字对象使用的字体族名称，保存后继续用于编辑与导出。
  final String textFontFamily;

  /// 文稿资源目录中的相对路径。图片的四个角由 [points] 保存，因此移动、
  /// 缩放和旋转可以复用文字与选区的变换逻辑。
  final String? imageAsset;

  /// 把笔迹对象编码为稳定 JSON 字段，完整点列、文字和样式必须保留以便继续编辑。
  Map<String, Object?> toJson() => <String, Object?>{
    'color': color,
    'width': width,
    'kind': kind.name,
    'penStyle': penStyle.name,
    if (text != null) 'text': text,
    if (text != null) 'textSize': textSize,
    if (text != null && textBoxWidth != null) 'textBoxWidth': textBoxWidth,
    if (text != null) 'textWeight': textWeight,
    if (text != null) 'textItalic': textItalic,
    if (text != null) 'textUnderline': textUnderline,
    if (text != null) 'textAlign': textAlign.name,
    if (text != null) 'textFontFamily': textFontFamily,
    if (imageAsset != null) 'imageAsset': imageAsset,
    'points': points.map((point) => point.toJson()).toList(growable: false),
  };

  /// 根据持久字段恢复笔画类型、原点列和文字/图片样式，旧宽度后续由版本兼容流程归一化。
  factory InkStroke.fromJson(Map<String, Object?> json) => InkStroke(
    color: (json['color'] as num).toInt(),
    width: (json['width'] as num).toDouble(),
    kind: StrokeKind.values.firstWhere(
      (StrokeKind value) => value.name == json['kind'],
      orElse: () => StrokeKind.pen,
    ),
    penStyle: PenStyle.values.firstWhere(
      (PenStyle value) => value.name == json['penStyle'],
      orElse: () => PenStyle.fountain,
    ),
    text: json['text'] as String?,
    textSize: (json['textSize'] as num?)?.toDouble() ?? 0.035,
    textBoxWidth: (json['textBoxWidth'] as num?)?.toDouble(),
    textWeight: (json['textWeight'] as num?)?.toInt() ?? 400,
    textItalic: json['textItalic'] as bool? ?? false,
    textUnderline: json['textUnderline'] as bool? ?? false,
    textAlign: TextAlign.values.firstWhere(
      (TextAlign value) => value.name == json['textAlign'],
      orElse: () => TextAlign.left,
    ),
    textFontFamily: json['textFontFamily'] as String? ?? 'Segoe UI Variable',
    imageAsset: json['imageAsset'] as String?,
    points: (json['points'] as List<Object?>)
        .map((point) => InkPoint.fromJson(point! as Map<String, Object?>))
        .toList(),
  );

  /// 复制笔画及其点列，允许显式覆盖属性，粘贴和历史不能共享后续会原位变换的点列表。
  InkStroke copy({
    List<InkPoint>? points,
    double? width,
    int? color,
    String? imageAsset,
  }) => InkStroke(
    color: color ?? this.color,
    width: width ?? this.width,
    kind: kind,
    penStyle: penStyle,
    text: text,
    textSize: textSize,
    textBoxWidth: textBoxWidth,
    textWeight: textWeight,
    textItalic: textItalic,
    textUnderline: textUnderline,
    textAlign: textAlign,
    textFontFamily: textFontFamily,
    imageAsset: imageAsset ?? this.imageAsset,
    points: points ?? List<InkPoint>.of(this.points),
  );
}

/// [InkStroke.width] 的像素换算：归一化粗细 × 绘制目标的几何平均边长。
///
/// 绘制目标可以是主画布布局、侧栏缩略图或导出图片，[size] 各自不同，
/// 但同一份笔迹在任何尺度下占页面的比例都一样。
double inkPixelWidth(double normalizedWidth, Size size) =>
    normalizedWidth * math.sqrt(size.width * size.height);

/// 布局尚未建立时的旧笔迹换算基准（几何平均边长）。
///
/// 只影响打开文稿后第一帧的竞态窗口；文件一旦重新保存就带上版本号，
/// 不再走换算。
const double legacyInkWidthFallbackReference = 1100;

class PageInk {
  /// 绑定笔画列表与用于还原坐标的页面逻辑尺寸。
  /// strokes：当前对象持有的笔画集合，元素坐标和宽度遵循 InkStroke 数据约定。
  /// updatedAt：最近内容修改时间，可为空以兼容旧格式。
  /// version：持久数据格式版本，用于兼容解码与必要迁移。
  const PageInk({
    required this.strokes,
    this.updatedAt,
    this.version = currentVersion,
  });

  /// 笔迹格式版本。
  ///
  /// - v2 及以前：`width` 是绘制时的**页面布局像素**。屏幕按布局画、导出
  ///   按图片像素画，两边差一个页面尺度，导出结果比屏幕上细（Surface Pro
  ///   上约 1.8 倍）。
  /// - v3（当前）：`width` 按页面几何平均边长归一化（见 [InkStroke.width]），
  ///   屏幕、缩略图、导出共用同一换算。
  static const int currentVersion = 3;

  /// strokes：当前对象持有的笔画集合，元素坐标和宽度遵循 InkStroke 数据约定。
  final List<InkStroke> strokes;

  /// updatedAt：最近内容修改时间，可为空以兼容旧格式。
  final DateTime? updatedAt;

  /// version：持久数据格式版本，用于兼容解码与必要迁移。
  final int version;

  /// 存盘一律写成当前版本：内存里的笔迹在 [NoteRepository.loadPageInk]
  /// 读过时就已换算成归一化粗细。
  Map<String, Object?> toJson() => <String, Object?>{
    'version': currentVersion,
    'updatedAt': (updatedAt ?? DateTime.now()).toUtc().toIso8601String(),
    'strokes': strokes.map((stroke) => stroke.toJson()).toList(growable: false),
  };

  /// 解码整页笔迹及版本信息，保留全文对象，宽度兼容转换由页面装载路径处理。
  factory PageInk.fromJson(Map<String, Object?> json) => PageInk(
    version: (json['version'] as num?)?.toInt() ?? 1,
    updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? ''),
    strokes: ((json['strokes'] as List<Object?>?) ?? const <Object?>[])
        .map((stroke) => InkStroke.fromJson(stroke! as Map<String, Object?>))
        .toList(),
  );

  /// 把 v2 及以前的像素粗细换算成归一化粗细。
  ///
  /// [legacyWidthReference] 是这些笔迹绘制时页面尺寸的几何平均边长——
  /// 只有绘制者当时的"页面在屏幕上多大"能还原出粗细，而这个数没有被记下来。
  /// 正常路径传当前该页的布局尺寸：画和看通常在同一台设备的同一个窗口里，
  /// 换算后屏幕上粗细不变。换算结果下一次保存即固化，此后各设备一致。
  PageInk withNormalizedWidths(double legacyWidthReference) {
    if (version >= currentVersion) return this;
    if (!legacyWidthReference.isFinite || legacyWidthReference <= 0) {
      return this;
    }
    return PageInk(
      updatedAt: updatedAt,
      strokes: strokes
          .map(
            (stroke) => stroke.copy(width: stroke.width / legacyWidthReference),
          )
          .toList(),
    );
  }
}

/// 把持久 32 位 ARGB 整数转换为 Flutter Color，不改变颜色通道语义。
Color colorFromArgb(int value) => Color(value);
