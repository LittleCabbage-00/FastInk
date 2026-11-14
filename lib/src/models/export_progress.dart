class ExportProgress {
  /// 建立导出阶段文案与可选 0–1 进度，空比例表示该阶段暂时不能可靠估算。
  const ExportProgress(this.message, {this.value});

  /// message：向界面展示的当前进度或反馈文案，不替代进度数字和任务状态。
  final String message;

  /// 总完成比例；某阶段无法报告工作总量时为 null。
  final double? value;
}
