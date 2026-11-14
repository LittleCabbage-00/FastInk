import 'dart:async';
import 'package:flutter/material.dart';
import '../models/export_progress.dart';
import '../core/app_localizations.dart';

class ExportProgressPanel extends StatefulWidget {
  /// 创建不可变的 ExportProgressPanel 参数对象；各参数保存在对应字段中，不在构造时执行外部读写。
  /// 保存和显示使用的完整标题。
  /// progress：当前导出任务的进度值对象，含阶段、计数、消息与时间信息。
  const ExportProgressPanel({
    super.key,
    required this.title,
    required this.progress,
  });

  /// 保存和显示使用的完整标题。
  final String title;

  /// progress：当前导出任务的进度值对象，含阶段、计数、消息与时间信息。
  final ExportProgress progress;

  @override
  State<ExportProgressPanel> createState() => _ExportProgressPanelState();
}

class _ExportProgressPanelState extends State<ExportProgressPanel> {
  /// _clock：进度面板的单调耗时计时器，刷新时间不触发整页重建。
  final _clock = Stopwatch()..start();

  /// _timer：尚未执行的延迟任务，更新或释放所属对象时需取消。
  Timer? _timer;

  /// _collapsed：进度面板是否收起详情，任务本身不会因折叠而停止。
  bool _collapsed = false;

  /// 启动本面板的低频耗时刷新任务，进度计时不重建宿主编辑器，卸载时取消。
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  /// 关闭进度面板时停止计时和定时刷新。
  @override
  void dispose() {
    _timer?.cancel();
    _clock.stop();
    super.dispose();
  }

  /// 根据进度和耗时显示阶段、完成比例与可折叠详情，未知比例使用不确定状态而非虚报百分比。
  @override
  Widget build(BuildContext context) {
    final value = widget.progress.value;
    final seconds = _clock.elapsed.inSeconds;
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(18),
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: Padding(
        padding: EdgeInsets.all(_collapsed ? 12 : 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    tr('正在导出', 'Exporting'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (_collapsed)
                  Text(
                    value == null
                        ? '…'
                        : '${(value * 100).floor().clamp(0, 100)}%',
                    key: const ValueKey('export-progress-percent'),
                  ),
                IconButton(
                  key: const ValueKey('collapse-export-progress'),
                  tooltip: _collapsed
                      ? tr('展开导出详情', 'Show export details')
                      : tr('收起导出详情', 'Minimize export details'),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() => _collapsed = !_collapsed),
                  icon: Icon(
                    _collapsed
                        ? Icons.expand_more_rounded
                        : Icons.expand_less_rounded,
                  ),
                ),
              ],
            ),
            if (!_collapsed) ...[
              const SizedBox(height: 4),
              Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
            const SizedBox(height: 14),
            LinearProgressIndicator(
              key: const ValueKey('export-progress-bar'),
              value: value?.clamp(0, 1),
            ),
            if (!_collapsed) ...[
              const SizedBox(height: 10),
              Text(
                widget.progress.message,
                key: const ValueKey('export-progress-message'),
                maxLines: 3,
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    value == null
                        ? tr('处理中…', 'Working…')
                        : '${(value * 100).floor().clamp(0, 100)}%',
                    key: const ValueKey('export-progress-percent'),
                  ),
                  Text(
                    tr(
                      '已用时 ${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}',
                      'Elapsed ${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}',
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
