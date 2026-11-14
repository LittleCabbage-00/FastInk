part of 'fastink_app.dart';

/// 只统一界面上的路径分隔符，避免展示内部拼接产生的混合斜杠。
String _displayLocalPath(String path) =>
    Platform.isWindows ? path.replaceAll('/', r'\') : path;

/// _palette：内置基础颜色表，供颜色选择界面提供合法回退项。
const List<Color> _palette = <Color>[
  Color(0xff202124),
  Color(0xff5f6368),
  Color(0xffd93025),
  Color(0xffe91e63),
  Color(0xfff57c00),
  Color(0xffffc107),
  Color(0xff188038),
  Color(0xff00897b),
  Color(0xff1a73e8),
  Color(0xff3949ab),
  Color(0xff9334e6),
  Color(0xffffffff),
];

/// 按当前日期把时间显示为今天或具体日期，供资料库元数据使用，不改变原始时间记录。
String _friendlyDate(DateTime value) {
  final DateTime local = value.toLocal();
  final DateTime now = DateTime.now();
  if (local.year == now.year &&
      local.month == now.month &&
      local.day == now.day) {
    final String time =
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    return tr('今天 $time', 'Today $time');
  }
  return '${local.year}/${local.month}/${local.day}';
}
