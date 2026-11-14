import 'dart:ui';

import '../core/app_settings_controller.dart';
import '../engine/ink_canvas.dart';

/// 当前工具的运行时状态（颜色、粗细、文本格式等）。
///
/// 工具切换逻辑在 `_selectTool()` 中（home_document_input.dart），
/// 切换前保存当前工具参数，切换后从 [AppSettingsController] 恢复目标工具默认值。
class ToolController {
  /// 绑定运行时设置副本，工具临时状态由本控制器维护；持久默认值仍由设置层保存。
  ToolController(this._settings);

  /// _settings：当前运行时设置副本；与临时工具状态、文稿内容分别维护。
  final AppSettingsController _settings;

  // ── 当前活跃状态 ────────────────────────────────────────────────────────

  /// tool：当前画布输入工具；与临时侧键工具共同决定本次手势的行为。
  InkTool tool = InkTool.pen;

  /// shapeType：形状工具当前几何类型，影响拖动时生成的点列。
  ShapeType shapeType = ShapeType.line;

  /// lastInkTool：最近使用的普通书写工具，临时切到橡皮或套索后可恢复。
  InkTool lastInkTool = InkTool.pen;

  /// 绘制颜色。
  Color color = const Color(0xff202124);

  /// width：当前工具基准线宽，单位页面逻辑像素；普通笔与荧光笔各自记忆。
  double width = 3;

  /// highlighterColor：当前荧光笔颜色，与普通笔和文字颜色分开维护。
  Color highlighterColor = const Color(0xffffc107);

  /// textColor：最终文字对象的颜色，不与输入面板主题文字色混用。
  Color textColor = const Color(0xff202124);

  /// textFontFamily：文字对象使用的字体族名称，保存后继续用于编辑与导出。
  String textFontFamily = 'Segoe UI Variable';

  /// textBold：文字加粗开关，提交时转换为具体字重。
  bool textBold = false;

  /// textItalic：文字斜体标志，属于可持久化文本样式。
  bool textItalic = false;

  /// textUnderline：文字下划线标志，属于可持久化文本样式。
  bool textUnderline = false;

  /// textAlign：段落水平对齐方式，文字排版和保存共用。
  TextAlign textAlign = TextAlign.left;

  /// textToolPinned：提交文字后是否保留文字工具，未固定时返回选择工具。
  bool textToolPinned = false;

  /// paperDark：当前纸张明暗判定，用于默认中性墨色对比，不代表界面主题。
  bool paperDark = false;

  /// heldPenButton：当前按住的物理侧键编号；0 表示没有临时工具覆盖。
  int heldPenButton = 0;

  /// partialEraserFromButton：当前局部橡皮模式是否由侧键临时触发，松开时不改默认橡皮。
  bool partialEraserFromButton = false;

  // ── 初始化 ──────────────────────────────────────────────────────────────

  /// 从设置初始化默认值。在 [initState] 中调用。
  void initFromSettings() {
    color = Color(_settings.penColor);
    width = _settings.penWidth;
    textColor = Color(_settings.penColor);
  }
}
