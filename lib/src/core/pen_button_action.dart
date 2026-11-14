part of '../app/fastink_app.dart';

enum PenButtonAction {
  eraser,
  defaultEraser,
  lasso,
  pen,
  highlighter,
  shape,
  laser,
  text,
  none,
}

/// 把保存的动作名解析为侧键枚举，未知值回退到传入默认动作。
PenButtonAction _decodePenButtonAction(
  String value,
  PenButtonAction fallback,
) => PenButtonAction.values.firstWhere(
  (PenButtonAction action) => action.name == value,
  orElse: () => fallback,
);

extension on PenButtonAction {
  /// 返回侧键动作的当前语言显示名称。
  String get label => switch (this) {
    PenButtonAction.eraser => tr('局部橡皮擦', 'Partial eraser'),
    PenButtonAction.defaultEraser => tr('橡皮擦（跟随设置）', 'Eraser (use settings)'),
    PenButtonAction.lasso => tr('框选'),
    PenButtonAction.pen => tr('钢笔'),
    PenButtonAction.highlighter => tr('荧光笔'),
    PenButtonAction.shape => tr('形状'),
    PenButtonAction.laser => tr('激光笔'),
    PenButtonAction.text => tr('文本'),
    PenButtonAction.none => tr('无操作', 'No action'),
  };

  /// 返回动作在设置与提示中使用的图标。
  IconData get icon => switch (this) {
    PenButtonAction.eraser => Icons.auto_fix_normal_rounded,
    PenButtonAction.defaultEraser => Icons.auto_fix_normal_outlined,
    PenButtonAction.lasso => Icons.gesture_rounded,
    PenButtonAction.pen => Icons.edit_rounded,
    PenButtonAction.highlighter => Icons.border_color_rounded,
    PenButtonAction.shape => Icons.category_outlined,
    PenButtonAction.laser => Icons.flashlight_on_outlined,
    PenButtonAction.text => Icons.text_fields_rounded,
    PenButtonAction.none => Icons.block_rounded,
  };

  /// 返回动作对应的临时画布工具；非工具型动作返回 null，由调用方单独执行。
  InkTool? get tool => switch (this) {
    PenButtonAction.eraser => InkTool.eraser,
    PenButtonAction.defaultEraser => InkTool.eraser,
    PenButtonAction.lasso => InkTool.lasso,
    PenButtonAction.pen => InkTool.pen,
    PenButtonAction.highlighter => InkTool.highlighter,
    PenButtonAction.shape => InkTool.shape,
    PenButtonAction.laser => InkTool.laser,
    PenButtonAction.text => InkTool.text,
    PenButtonAction.none => null,
  };
}
