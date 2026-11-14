part of '../../app/fastink_app.dart';

class _DocumentScrollBehavior extends MaterialScrollBehavior {
  /// 创建桌面滚动行为配置，允许支持的指针设备参与列表交互。
  const _DocumentScrollBehavior();

  /// 返回允许拖动滚动的输入设备种类，避免只支持移动端触摸的默认限制。
  @override
  Set<PointerDeviceKind> get dragDevices => const <PointerDeviceKind>{
    PointerDeviceKind.touch,
    PointerDeviceKind.trackpad,
  };
}

extension _FirstOrNull<T> on Iterable<T> {
  /// 安全读取集合首项；集合为空时返回 null 而不是抛出异常。
  T? get firstOrNull => isEmpty ? null : first;
}

class _PaperDialogResult {
  /// 保存模板对话框确认结果，包含生成页面所需的纸张与封面参数。
  const _PaperDialogResult({
    required this.title,
    required this.template,
    required this.allPages,
    this.cover,
  });

  /// 保存和显示使用的完整标题。
  final String title;

  /// template：当前使用的纸张模板值，尺寸、方向、颜色与纹理一起决定生成内容。
  final PaperTemplate template;

  /// allPages：本次操作是否作用于整本文稿，false 时只作用于当前页。
  final bool allPages;

  /// cover：创建笔记时独立选择的封面模板，为空时不额外创建封面。
  final PaperTemplate? cover;
}

class _ExportDialogResult {
  /// 保存用户确认的导出格式与整本/当前页范围，不在构造时启动导出。
  const _ExportDialogResult(this.format, this.allPages);

  /// format：用户选择的输出格式枚举，决定 PDF 或图像编码路径。
  final NoteExportFormat format;

  /// allPages：本次操作是否作用于整本文稿，false 时只作用于当前页。
  final bool allPages;
}
