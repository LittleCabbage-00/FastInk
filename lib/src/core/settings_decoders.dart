part of 'settings_repository.dart';

/// 读取并筛选合法笔宽档位；缺失或非法输入回退默认列表。
List<double> _decodeWidthPresets(
  Object? value,
  List<double> fallback,
  double minimum,
  double maximum,
) {
  if (value is! List<Object?>) {
    final List<double> defaults = List<double>.of(fallback)..sort();
    return defaults;
  }
  final List<double> decoded = value
      .whereType<num>()
      .map((num item) => item.toDouble().clamp(minimum, maximum))
      .take(3)
      .toList();
  if (decoded.length != 3) {
    final List<double> defaults = List<double>.of(fallback)..sort();
    return defaults;
  }
  decoded.sort();
  return decoded;
}

/// 校验保存的侧键动作名，未知动作使用 fallback。
String _decodePenButtonAction(Object? value, String fallback) {
  const Set<String> supported = <String>{
    'eraser',
    'defaultEraser',
    'lasso',
    'pen',
    'highlighter',
    'shape',
    'laser',
    'text',
    'none',
  };
  return value is String && supported.contains(value) ? value : fallback;
}

/// 解析工具栏 ARGB 颜色列表，并对非法或缺失值使用默认预设。
List<int> _decodeColorPresets(Object? value) {
  const List<int> fallback = <int>[0xff202124, 0xff2f80ed, 0xffe53935];
  if (value is! List<Object?>) return List<int>.of(fallback);
  final List<int> decoded = value
      .whereType<num>()
      .map((num item) {
        return item.toInt() | 0xff000000;
      })
      .take(3)
      .toList();
  return decoded.length == 3 ? decoded : List<int>.of(fallback);
}
