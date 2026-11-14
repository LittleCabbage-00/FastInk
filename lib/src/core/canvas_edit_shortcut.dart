import 'package:flutter/services.dart';

/// 文稿和截图共用的编辑按键。内容和历史始终由当前编辑器处理。
enum CanvasEditShortcut {
  undo,
  redo,
  copy,
  cut,
  paste,
  duplicate,
  delete,
  escape,
  save,
}

/// 只识别首次按下。Alt 和系统键组合留给系统或当前输入框。
CanvasEditShortcut? canvasEditShortcut(KeyEvent event) {
  final keyboard = HardwareKeyboard.instance;
  if (event is! KeyDownEvent ||
      keyboard.isAltPressed ||
      keyboard.isMetaPressed) {
    return null;
  }
  final key = event.logicalKey;
  if (keyboard.isControlPressed) {
    if (key == LogicalKeyboardKey.keyZ) {
      return keyboard.isShiftPressed
          ? CanvasEditShortcut.redo
          : CanvasEditShortcut.undo;
    }
    return switch (key) {
      LogicalKeyboardKey.keyY => CanvasEditShortcut.redo,
      LogicalKeyboardKey.keyC => CanvasEditShortcut.copy,
      LogicalKeyboardKey.keyX => CanvasEditShortcut.cut,
      LogicalKeyboardKey.keyV => CanvasEditShortcut.paste,
      LogicalKeyboardKey.keyD => CanvasEditShortcut.duplicate,
      LogicalKeyboardKey.keyS => CanvasEditShortcut.save,
      _ => null,
    };
  }
  return switch (key) {
    LogicalKeyboardKey.delete ||
    LogicalKeyboardKey.backspace => CanvasEditShortcut.delete,
    LogicalKeyboardKey.escape => CanvasEditShortcut.escape,
    _ => null,
  };
}
