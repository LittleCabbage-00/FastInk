import '../platform/render_power_policy.dart';
import 'dart:math' as math;
import 'dart:io';
import 'package:flutter/material.dart';
import '../core/app_localizations.dart';
import '../models/paper_template.dart';

/// 保持纸张宽高比，完整显示整张页面。
class PaperTemplatePreview extends StatelessWidget {
  /// 创建不可变的 PaperTemplatePreview 参数对象；各参数保存在对应字段中，不在构造时执行外部读写。
  /// template：当前使用的纸张模板值，尺寸、方向、颜色与纹理一起决定生成内容。
  const PaperTemplatePreview({super.key, required this.template});

  /// template：当前使用的纸张模板值，尺寸、方向、颜色与纹理一起决定生成内容。
  final PaperTemplate template;

  /// 在可用尺寸内按纸张宽高比绘制预览。
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final double width = math.min(
        constraints.maxWidth,
        constraints.maxHeight * template.aspectRatio,
      );
      return Center(
        child: Container(
          width: width,
          height: width / template.aspectRatio,
          decoration: BoxDecoration(
            color: template.color,
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x24000000),
                blurRadius: 12,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: template.backgroundAsset != null
              ? Image.file(
                  File(template.backgroundAsset!),
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) =>
                      const Center(child: Icon(Icons.broken_image_outlined)),
                )
              : CustomPaint(
                  painter: PaperTemplatePainter(
                    template,
                    mode: PaperRenderMode.preview,
                  ),
                ),
        ),
      );
    },
  );
}

/// 相邻或下方的设置滚动时，预览仍保持可见。
class PaperTemplatePreviewPanel extends StatelessWidget {
  /// 创建不可变的 PaperTemplatePreviewPanel 参数对象；各参数保存在对应字段中，不在构造时执行外部读写。
  /// template：当前使用的纸张模板值，尺寸、方向、颜色与纹理一起决定生成内容。
  /// compact：是否使用紧凑布局或预览细节，数据本身仍保持原尺寸和内容。
  const PaperTemplatePreviewPanel({
    super.key,
    required this.template,
    this.compact = false,
  });

  /// template：当前使用的纸张模板值，尺寸、方向、颜色与纹理一起决定生成内容。
  final PaperTemplate template;

  /// compact：是否使用紧凑布局或预览细节，数据本身仍保持原尺寸和内容。
  final bool compact;

  /// 打开可缩放的整页预览，双指/滚轮仅改变查看比例，取消不改变模板配置。
  Future<void> _enlarge(BuildContext context) => showDialog<void>(
    context: context,
    animationStyle: appMotionStyle(context),
    builder: (context) => Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    template.label,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  key: const ValueKey('paper-preview-close'),
                  tooltip: tr('关闭', 'Close'),
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: InteractiveViewer(
                key: const ValueKey('paper-preview-zoom'),
                minScale: 1,
                maxScale: 5,
                child: PaperTemplatePreview(template: template),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(
              tr('双指或滚轮缩放，拖动查看细节', 'Pinch or scroll to zoom; drag to explore'),
            ),
          ),
        ],
      ),
    ),
  );

  /// 展示当前模板的放大预览与参数。
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('paper-preview-panel'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: .5)),
      ),
      child: compact
          ? Row(
              children: <Widget>[
                Expanded(
                  child: GestureDetector(
                    onTap: () => _enlarge(context),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: PaperTemplatePreview(template: template),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        tr('实时预览', 'Live preview'),
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(color: colors.onSurfaceVariant),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        template.label,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        template.formatLabel,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        key: const ValueKey('paper-preview-enlarge'),
                        onPressed: () => _enlarge(context),
                        icon: const Icon(Icons.zoom_in_rounded, size: 18),
                        label: Text(tr('放大预览', 'Enlarge preview')),
                      ),
                    ],
                  ),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        tr('实时预览', 'Live preview'),
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('paper-preview-enlarge'),
                      tooltip: tr('放大预览', 'Enlarge preview'),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _enlarge(context),
                      icon: const Icon(Icons.zoom_in_rounded, size: 22),
                    ),
                  ],
                ),
                Expanded(
                  child: Semantics(
                    label: '${tr('预览', 'Preview')}: ${template.label}',
                    button: true,
                    child: GestureDetector(
                      onTap: () => _enlarge(context),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
                        child: PaperTemplatePreview(template: template),
                      ),
                    ),
                  ),
                ),
                Text(
                  template.label,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  template.formatLabel,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
    );
  }
}

class PaperTemplateGallery extends StatelessWidget {
  /// 创建不可变的 PaperTemplateGallery 参数对象；各参数保存在对应字段中，不在构造时执行外部读写。
  /// template：当前使用的纸张模板值，尺寸、方向、颜色与纹理一起决定生成内容。
  /// 将控件的新值传给宿主。
  /// patterns：当前分类可选择的纸张纹理列表。
  const PaperTemplateGallery({
    super.key,
    required this.template,
    required this.onChanged,
    this.patterns = PaperPattern.values,
  });

  /// template：当前使用的纸张模板值，尺寸、方向、颜色与纹理一起决定生成内容。
  final PaperTemplate template;

  /// 将控件的新值传给宿主。
  final ValueChanged<PaperPattern> onChanged;

  /// patterns：当前分类可选择的纸张纹理列表。
  final List<PaperPattern> patterns;

  /// 按可用宽度安排模板缩略图列。
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final colors = Theme.of(context).colorScheme;
      final int columns = math.max(2, (constraints.maxWidth / 120).floor());
      final double width =
          (constraints.maxWidth - (columns - 1) * 12) / columns;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: <Widget>[
          for (final pattern in patterns)
            SizedBox(
              width: width,
              child: Semantics(
                selected: template.pattern == pattern,
                child: Material(
                  color: template.pattern == pattern
                      ? colors.primaryContainer
                      : colors.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(
                      color: template.pattern == pattern
                          ? colors.primary
                          : colors.outlineVariant,
                      width: template.pattern == pattern ? 2 : 1,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    key: ValueKey<String>('paper-${pattern.name}'),
                    onTap: () => onChanged(pattern),
                    child: Column(
                      children: <Widget>[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                          child: SizedBox(
                            height: 108,
                            child: Stack(
                              fit: StackFit.expand,
                              children: <Widget>[
                                Center(
                                  child: AspectRatio(
                                    aspectRatio: template.aspectRatio,
                                    child: CustomPaint(
                                      painter: PaperTemplatePainter(
                                        template.copyWith(pattern: pattern),
                                        mode: PaperRenderMode.thumbnail,
                                      ),
                                    ),
                                  ),
                                ),
                                if (template.pattern == pattern)
                                  Align(
                                    alignment: Alignment.topRight,
                                    child: Icon(
                                      Icons.check_circle_rounded,
                                      color: colors.primary,
                                      size: 20,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 8,
                          ),
                          child: Text(
                            paperPatternLabel(pattern),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );
}
