import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import '../core/app_localizations.dart';

enum PaperPattern {
  blank,
  ruled,
  grid,
  dotted,
  cornell,
  isometric,
  music,
  handwriting,
  vocabulary,
  daily,
  weekly,
  monthly,
  todo,
  meeting,
  storyboard,
}

enum PaperSizePreset { a4, letter, a5, square, a3, b5, tablet }

enum PaperCategory { basic, study, planning, creative }

/// 将纹理类型映射到基础、学习、计划或工作分类，分类仅用于选择界面组织。
PaperCategory paperCategory(PaperPattern pattern) => switch (pattern) {
  PaperPattern.blank ||
  PaperPattern.ruled ||
  PaperPattern.grid ||
  PaperPattern.dotted ||
  PaperPattern.isometric => PaperCategory.basic,
  PaperPattern.cornell ||
  PaperPattern.handwriting ||
  PaperPattern.vocabulary => PaperCategory.study,
  PaperPattern.daily ||
  PaperPattern.weekly ||
  PaperPattern.monthly ||
  PaperPattern.todo => PaperCategory.planning,
  PaperPattern.music ||
  PaperPattern.meeting ||
  PaperPattern.storyboard => PaperCategory.creative,
};

/// 返回纸张分类的当前语言名称。
String paperCategoryLabel(PaperCategory category) => switch (category) {
  PaperCategory.basic => tr('基础纸张', 'Basic paper'),
  PaperCategory.study => tr('学习笔记', 'Study'),
  PaperCategory.planning => tr('计划安排', 'Planning'),
  PaperCategory.creative => tr('工作创作', 'Work & creative'),
};

/// 返回纸张尺寸预设的当前语言显示名，自定义实际尺寸另存。
String paperSizeLabel(PaperSizePreset size) => switch (size) {
  PaperSizePreset.a4 => 'A4',
  PaperSizePreset.a3 => 'A3',
  PaperSizePreset.a5 => 'A5',
  PaperSizePreset.b5 => 'B5',
  PaperSizePreset.letter => 'Letter',
  PaperSizePreset.square => tr('正方形', 'Square'),
  PaperSizePreset.tablet => tr('平板 16:10', 'Tablet 16:10'),
};

/// 判断该版式是否支持间距调整，不支持时隐藏无效滑杆。
bool paperHasAdjustableSpacing(PaperPattern pattern) => switch (pattern) {
  PaperPattern.blank ||
  PaperPattern.weekly ||
  PaperPattern.monthly ||
  PaperPattern.storyboard => false,
  _ => true,
};

class PaperTemplate {
  /// 定义纸张尺寸、方向、底色及纹理。
  /// pattern：纸张纹理或版式类型，决定生成器绘制的布局。
  /// size：纸张尺寸预设，与像素解码预算和当前窗口尺寸无关。
  /// landscape：是否将纸张尺寸按横向使用。
  /// 绘制颜色。
  /// spacing：模板的纹理间距倍率，仅影响支持间距调整的版式。
  /// backgroundAsset：自定义纸张/封面的底图资源路径，标准自绘模板可为空。
  /// customName：用户保存的模板名称，未命名的内置模板可为空。
  /// customWidth：自定义底图原始宽度，单位像素；非自定义图可为空。
  /// customHeight：自定义底图原始高度，单位像素；非自定义图可为空。
  /// isCover：该模板是否用作封面，区别正文纸张的默认布局。
  const PaperTemplate({
    this.pattern = PaperPattern.blank,
    this.size = PaperSizePreset.a4,
    this.landscape = false,
    this.color = const ui.Color(0xffffffff),
    this.spacing = 1,
    this.backgroundAsset,
    this.customName,
    this.customWidth,
    this.customHeight,
    this.isCover = false,
  });

  /// pattern：纸张纹理或版式类型，决定生成器绘制的布局。
  final PaperPattern pattern;

  /// size：纸张尺寸预设，与像素解码预算和当前窗口尺寸无关。
  final PaperSizePreset size;

  /// landscape：是否将纸张尺寸按横向使用。
  final bool landscape;

  /// 绘制颜色。
  final ui.Color color;

  /// spacing：模板的纹理间距倍率，仅影响支持间距调整的版式。
  final double spacing;

  /// backgroundAsset：自定义纸张/封面的底图资源路径，标准自绘模板可为空。
  final String? backgroundAsset;

  /// customName：用户保存的模板名称，未命名的内置模板可为空。
  final String? customName;

  /// customWidth：自定义底图原始宽度，单位像素；非自定义图可为空。
  final int? customWidth;

  /// customHeight：自定义底图原始高度，单位像素；非自定义图可为空。
  final int? customHeight;

  /// isCover：该模板是否用作封面，区别正文纸张的默认布局。
  final bool isCover;

  /// 按指定布局位置绘制模板文字标签，不进入可编辑笔迹集合。
  String get label => customName ?? paperPatternLabel(pattern);

  /// 生成纸张或自定义底图的尺寸说明，供选择器显示，不作为文件身份。
  String get formatLabel => backgroundAsset != null
      ? '${pixelSize.width.round()} × ${pixelSize.height.round()} px'
      : '${paperSizeLabel(size)} · ${landscape ? tr('横向', 'Landscape') : tr('竖向', 'Portrait')}';

  /// 按尺寸预设、自定义图像和横竖方向计算实际生成像素尺寸。
  ui.Size get pixelSize {
    if (backgroundAsset != null &&
        (customWidth ?? 0) > 0 &&
        (customHeight ?? 0) > 0) {
      return ui.Size(customWidth!.toDouble(), customHeight!.toDouble());
    }
    final (double w, double h) = switch (size) {
      PaperSizePreset.a4 => (1240, 1754),
      PaperSizePreset.letter => (1275, 1650),
      PaperSizePreset.a5 => (874, 1240),
      PaperSizePreset.square => (1400, 1400),
      PaperSizePreset.a3 => (1754, 2480),
      PaperSizePreset.b5 => (1075, 1518),
      PaperSizePreset.tablet => (1200, 1920),
    };
    return landscape ? ui.Size(h, w) : ui.Size(w, h);
  }

  /// 返回最终纸张宽高比，侧栏与页面布局据此保持比例。
  double get aspectRatio => pixelSize.width / pixelSize.height;

  /// 生成纸张配置的新值，只替换显式参数，保留其他纹理/底图设置。
  PaperTemplate copyWith({
    PaperPattern? pattern,
    PaperSizePreset? size,
    bool? landscape,
    ui.Color? color,
    double? spacing,
    String? backgroundAsset,
    String? customName,
    int? customWidth,
    int? customHeight,
    bool? isCover,
  }) => PaperTemplate(
    pattern: pattern ?? this.pattern,
    size: size ?? this.size,
    landscape: landscape ?? this.landscape,
    color: color ?? this.color,
    spacing: spacing ?? this.spacing,
    backgroundAsset:
        backgroundAsset ?? (pattern == null ? this.backgroundAsset : null),
    customName: customName ?? (pattern == null ? this.customName : null),
    customWidth: customWidth ?? (pattern == null ? this.customWidth : null),
    customHeight: customHeight ?? (pattern == null ? this.customHeight : null),
    isCover: isCover ?? this.isCover,
  );

  /// 保存可重建纸张的纹理、尺寸、方向、颜色和自定义资源信息。
  Map<String, Object?> toJson() => <String, Object?>{
    'version': 1,
    'pattern': pattern.name,
    'size': size.name,
    'landscape': landscape,
    'color': color.toARGB32(),
    'spacing': spacing,
    if (backgroundAsset != null) 'backgroundAsset': backgroundAsset,
    if (customName != null) 'customName': customName,
    if (customWidth != null) 'customWidth': customWidth,
    if (customHeight != null) 'customHeight': customHeight,
    if (isCover) 'isCover': true,
  };

  /// 按兼容默认值恢复纸张配置，未知枚举或缺失自定义尺寸不使整个文稿无法载入。
  factory PaperTemplate.fromJson(Map<String, Object?> json) {
    final double gap = (json['spacing'] as num?)?.toDouble() ?? 1;
    return PaperTemplate(
      pattern:
          PaperPattern.values
              .where((v) => v.name == json['pattern'])
              .firstOrNull ??
          PaperPattern.blank,
      size:
          PaperSizePreset.values
              .where((v) => v.name == json['size'])
              .firstOrNull ??
          PaperSizePreset.a4,
      landscape: json['landscape'] == true,
      color: ui.Color((json['color'] as num?)?.toInt() ?? 0xffffffff),
      spacing: gap.isFinite ? gap.clamp(0.65, 1.6) : 1,
      backgroundAsset: json['backgroundAsset'] as String?,
      customName: json['customName'] as String?,
      customWidth: (json['customWidth'] as num?)?.toInt(),
      customHeight: (json['customHeight'] as num?)?.toInt(),
      isCover: json['isCover'] == true,
    );
  }
}

/// 返回各内置纹理的当前语言名称，稳定枚举值不依赖文案。
String paperPatternLabel(PaperPattern pattern) => switch (pattern) {
  PaperPattern.blank => tr('空白', 'Blank'),
  PaperPattern.ruled => tr('横线', 'Ruled'),
  PaperPattern.grid => tr('方格', 'Grid'),
  PaperPattern.dotted => tr('点阵', 'Dots'),
  PaperPattern.cornell => tr('康奈尔笔记', 'Cornell'),
  PaperPattern.isometric => tr('等距网格', 'Isometric'),
  PaperPattern.music => tr('五线谱', 'Music staff'),
  PaperPattern.handwriting => tr('田字格', 'Handwriting'),
  PaperPattern.vocabulary => tr('词汇笔记', 'Vocabulary'),
  PaperPattern.daily => tr('每日计划', 'Daily planner'),
  PaperPattern.weekly => tr('每周计划', 'Weekly planner'),
  PaperPattern.monthly => tr('月度计划', 'Monthly planner'),
  PaperPattern.todo => tr('待办清单', 'Checklist'),
  PaperPattern.meeting => tr('会议记录', 'Meeting notes'),
  PaperPattern.storyboard => tr('分镜草图', 'Storyboard'),
};

enum PaperRenderMode { page, preview, thumbnail }

class PaperTemplatePainter extends CustomPainter {
  /// 接收待绘制模板及正式页或预览绘制模式。
  /// template：当前使用的纸张模板值，尺寸、方向、颜色与纹理一起决定生成内容。
  /// mode：模板渲染用途，区分正式页面与缩略预览的细节补偿。
  const PaperTemplatePainter(this.template, {this.mode = PaperRenderMode.page});

  /// template：当前使用的纸张模板值，尺寸、方向、颜色与纹理一起决定生成内容。
  final PaperTemplate template;

  /// mode：模板渲染用途，区分正式页面与缩略预览的细节补偿。
  final PaperRenderMode mode;

  /// 按指定渲染模式绘制纸张；缩略模式可补偿细线可见性，正式页面保留真实纹理。
  @override
  void paint(ui.Canvas canvas, ui.Size size) =>
      paintPaperTemplate(canvas, size, template, mode: mode);

  /// 绘制模式或模板配置变化时重新生成纸张纹理。
  @override
  bool shouldRepaint(PaperTemplatePainter oldDelegate) =>
      oldDelegate.mode != mode ||
      oldDelegate.template.toJson().toString() != template.toJson().toString();
}

/// 使用共享几何规则；小预览增强亚像素细线的可见性，正式页面
/// 仍保留原始浅色书写辅助线。重复图案的缩略图显示放大局部，
/// 避免把每一条细线都挤进小卡片。
void paintPaperTemplate(
  ui.Canvas canvas,
  ui.Size size,
  PaperTemplate template, {
  PaperRenderMode mode = PaperRenderMode.page,
}) {
  if (size.isEmpty) return;
  final bool preview = mode != PaperRenderMode.page;
  final bool detail =
      mode == PaperRenderMode.thumbnail &&
      switch (template.pattern) {
        PaperPattern.ruled ||
        PaperPattern.grid ||
        PaperPattern.dotted ||
        PaperPattern.isometric ||
        PaperPattern.music ||
        PaperPattern.handwriting => true,
        _ => false,
      };
  final double viewportWidth = detail ? 420 : 1000;
  final double viewportHeight = viewportWidth / template.aspectRatio;
  final double h = 1000 / template.aspectRatio;
  final bool dark = template.color.computeLuminance() < 0.35;
  final ui.Color ink = dark
      ? const ui.Color(0xffb6c5d8)
      : const ui.Color(0xff526579);
  final ui.Paint pen = ui.Paint()
    ..color = ink.withValues(alpha: preview ? 0.65 : 0.4)
    ..strokeWidth = preview
        ? math.max(1.2, 0.75 * viewportWidth / size.width)
        : 1.2;
  final double gap =
      46 * (template.spacing.isFinite ? template.spacing.clamp(0.65, 1.6) : 1);
  canvas.save();
  canvas.scale(size.width / viewportWidth, size.height / viewportHeight);
  canvas.clipRect(ui.Rect.fromLTWH(0, 0, viewportWidth, viewportHeight));
  canvas.drawColor(template.color, ui.BlendMode.src);
  // 在当前页面逻辑坐标绘制单条辅助线，复用当前模板画笔。
  void line(double x, double y, double x2, double y2) =>
      canvas.drawLine(ui.Offset(x, y), ui.Offset(x2, y2), pen);
  // 绘制指定位置和尺寸的模板框线，单位均为本次画布坐标。
  void box(double x, double y, double w, double height) {
    canvas.drawRect(
      ui.Rect.fromLTWH(x, y, w, height),
      ui.Paint()
        ..color = pen.color
        ..strokeWidth = pen.strokeWidth
        ..style = ui.PaintingStyle.stroke,
    );
  }

  // 按指定布局位置绘制模板文字标签，不进入可编辑笔迹集合。
  void label(
    String text,
    double x,
    double y, {
    double width = 880,
    double font = 20,
  }) {
    final ui.ParagraphBuilder builder =
        ui.ParagraphBuilder(
            ui.ParagraphStyle(fontSize: font, fontFamily: 'sans-serif'),
          )
          ..pushStyle(ui.TextStyle(color: ink, fontSize: font))
          ..addText(text);
    final ui.Paragraph paragraph = builder.build()
      ..layout(ui.ParagraphConstraints(width: width));
    canvas.drawParagraph(paragraph, ui.Offset(x, y));
    paragraph.dispose();
  }

  // 在指定矩形内按当前间距生成横线等辅助规则，裁到给定范围。
  void rules(double left, double top, double right, double bottom) {
    for (double y = top; y < bottom; y += gap) {
      line(left, y, right, y);
    }
  }

  // 绘制当前版式标题区域，标题仅属于纸张底图。
  void header(String title) {
    label(title, 60, 38, font: 28);
    line(60, 94, 940, 94);
  }

  switch (template.pattern) {
    case PaperPattern.blank:
      break;
    case PaperPattern.ruled:
      rules(0, gap * 1.7, 1000, h);
      line(120, 0, 120, h);
    case PaperPattern.grid:
      for (double x = gap; x < 1000; x += gap) {
        line(x, 0, x, h);
      }
      rules(0, gap, 1000, h);
    case PaperPattern.dotted:
      for (double x = gap; x < 1000; x += gap) {
        for (double y = gap; y < h; y += gap) {
          canvas.drawCircle(
            ui.Offset(x, y),
            preview ? math.max(1.6, 0.9 * viewportWidth / size.width) : 1.6,
            pen,
          );
        }
      }
    case PaperPattern.cornell:
      header(paperPatternLabel(template.pattern));
      label(tr('关键词 / 问题', 'Cues / questions'), 60, 112, width: 230);
      label(tr('笔记', 'Notes'), 320, 112);
      line(300, 104, 300, h * .78);
      rules(320, 160, 940, h * .78);
      line(60, h * .8, 940, h * .8);
      label(tr('总结', 'Summary'), 60, h * .8 + 16);
      rules(60, h * .8 + 64, 940, h - 40);
    case PaperPattern.isometric:
      final double rise = gap * math.sqrt(3);
      for (double y = -1800; y < h + 1800; y += rise) {
        line(0, y, 1000, y + 1000 * math.sqrt(3));
        line(0, y, 1000, y - 1000 * math.sqrt(3));
      }
      for (double y = 0; y < h; y += rise / 2) {
        line(0, y, 1000, y);
      }
    case PaperPattern.music:
      for (double y = 80; y + gap * .9 < h - 40; y += gap * 2.8) {
        for (int i = 0; i < 5; i++) {
          line(60, y + i * gap * .22, 940, y + i * gap * .22);
        }
      }
    case PaperPattern.handwriting:
      final double cell = gap * 1.6;
      for (double x = 60; x + cell <= 940; x += cell) {
        for (double y = 60; y + cell <= h - 40; y += cell) {
          box(x, y, cell, cell);
          final ui.Color previous = pen.color;
          pen.color = previous.withValues(alpha: preview ? .4 : .18);
          line(x + cell / 2, y, x + cell / 2, y + cell);
          line(x, y + cell / 2, x + cell, y + cell / 2);
          pen.color = previous;
        }
      }
    case PaperPattern.vocabulary:
      header(paperPatternLabel(template.pattern));
      label(tr('词汇', 'Word'), 60, 112, width: 220);
      label(tr('释义 / 例句', 'Meaning / example'), 340, 112);
      line(300, 104, 300, h - 40);
      rules(60, 160, 940, h - 40);
    case PaperPattern.daily:
      header(paperPatternLabel(template.pattern));
      label(tr('日期：', 'Date:'), 600, 42, width: 320);
      label(tr('时间安排', 'Schedule'), 60, 112);
      label(tr('今日重点 / 笔记', 'Priorities / notes'), 540, 112);
      line(500, 104, 500, h - 40);
      final double row = (h - 200) / 16;
      for (int i = 0; i < 16; i++) {
        label(
          '${(6 + i).toString().padLeft(2, '0')}:00',
          60,
          160 + i * row,
          width: 90,
          font: 16,
        );
        line(150, 180 + i * row, 470, 180 + i * row);
      }
      rules(540, 180, 940, h - 40);
    case PaperPattern.weekly:
      header(paperPatternLabel(template.pattern));
      final double row = (h - 170) / 4;
      for (int i = 0; i < 8; i++) {
        final double x = 60 + (i % 2) * 440, y = 130 + (i ~/ 2) * row;
        box(x, y, 440, row);
        label(
          i < 7
              ? <String>[
                  tr('周一', 'Monday'),
                  tr('周二', 'Tuesday'),
                  tr('周三', 'Wednesday'),
                  tr('周四', 'Thursday'),
                  tr('周五', 'Friday'),
                  tr('周六', 'Saturday'),
                  tr('周日', 'Sunday'),
                ][i]
              : tr('笔记', 'Notes'),
          x + 16,
          y + 14,
          width: 400,
        );
      }
    case PaperPattern.monthly:
      header(paperPatternLabel(template.pattern));
      label(tr('年 / 月：', 'Year / month:'), 600, 42, width: 330);
      final double cellW = 880 / 7, cellH = (h - 220) / 6;
      for (int col = 0; col < 7; col++) {
        label(
          <String>['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'][col],
          68 + col * cellW,
          126,
          width: cellW - 10,
          font: 16,
        );
        for (int row = 0; row < 6; row++) {
          box(60 + col * cellW, 170 + row * cellH, cellW, cellH);
        }
      }
    case PaperPattern.todo:
      header(paperPatternLabel(template.pattern));
      for (double y = 150; y < h - 60; y += gap * 1.35) {
        box(60, y, 22, 22);
        line(105, y + 24, 940, y + 24);
      }
    case PaperPattern.meeting:
      header(paperPatternLabel(template.pattern));
      label(tr('主题 / 日期：', 'Topic / date:'), 60, 115);
      label(tr('参会人员：', 'Participants:'), 60, 164);
      line(60, 210, 940, 210);
      label(tr('讨论记录', 'Discussion'), 60, 226);
      rules(60, 278, 940, h * .7);
      line(60, h * .72, 940, h * .72);
      label(
        tr('行动项 / 负责人 / 截止时间', 'Actions / owner / deadline'),
        60,
        h * .72 + 18,
      );
      rules(60, h * .72 + 70, 940, h - 40);
    case PaperPattern.storyboard:
      header(paperPatternLabel(template.pattern));
      final double row = (h - 180) / 3;
      for (int i = 0; i < 6; i++) {
        final double x = 60 + (i % 2) * 450, y = 130 + (i ~/ 2) * row;
        box(x, y, 420, row * .65);
        label('${i + 1}', x + 10, y + 8, width: 50, font: 16);
        line(x, y + row * .8, x + 420, y + row * .8);
      }
  }
  canvas.restore();
}
