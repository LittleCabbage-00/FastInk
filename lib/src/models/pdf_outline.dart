class PdfOutlineEntry {
  /// 通过标题、目标页和嵌套深度描述一个 PDF 目录项。
  /// 保存和显示使用的完整标题。
  /// originalPage：页面的稳定原始编号，用于定位笔迹文件，不能用当前页序代替。
  /// children：当前目录节点的直接子项，保留 PDF 目录层级。
  const PdfOutlineEntry({
    required this.title,
    this.originalPage,
    this.children = const [],
  });

  /// 保存和显示使用的完整标题。
  final String title;

  /// 原始 PDF 页码从 1 开始，与编辑后的页面顺序相互独立。
  final int? originalPage;

  /// children：当前目录节点的直接子项，保留 PDF 目录层级。
  final List<PdfOutlineEntry> children;

  /// 递归统计当前节点及全部子节点数量，用于目录项计数。
  int get count => 1 + children.fold<int>(0, (sum, child) => sum + child.count);

  /// 将目录标题、目标页和子项递归编码，保留原层级。
  Map<String, Object?> toJson() => {
    'title': title,
    'originalPage': originalPage,
    'children': children.map((entry) => entry.toJson()).toList(),
  };

  /// 从持久索引恢复目录树，页面映射仍由当前文稿清单在跳转时解析。
  factory PdfOutlineEntry.fromJson(Map<String, Object?> json) =>
      PdfOutlineEntry(
        title: json['title'] as String,
        originalPage: (json['originalPage'] as num?)?.toInt(),
        children: (json['children'] as List<Object?>? ?? [])
            .map(
              (entry) =>
                  PdfOutlineEntry.fromJson(entry as Map<String, Object?>),
            )
            .toList(),
      );
}
