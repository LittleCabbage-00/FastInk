import '../platform/render_power_policy.dart';
import 'dart:math' as math;
import 'package:filepicker_windows/filepicker_windows.dart';
import 'package:flutter/material.dart';
import '../core/app_localizations.dart';
import '../models/paper_template.dart';
import 'paper_template_preview.dart';
import '../storage/template_library.dart';

class PaperTemplateSelection {
  /// 创建不可变的 PaperTemplateSelection 参数对象；各参数保存在对应字段中，不在构造时执行外部读写。
  /// 保存和显示使用的完整标题。
  /// template：当前使用的纸张模板值，尺寸、方向、颜色与纹理一起决定生成内容。
  /// allPages：本次操作是否作用于整本文稿，false 时只作用于当前页。
  /// cover：创建笔记时独立选择的封面模板，为空时不额外创建封面。
  const PaperTemplateSelection({
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

class PaperTemplateDialog extends StatefulWidget {
  /// 创建不可变的 PaperTemplateDialog 参数对象；各参数保存在对应字段中，不在构造时执行外部读写。
  /// initialTemplate：模板窗口打开时的初始纸张配置，取消时不覆盖它。
  /// creating：当前模板窗口是否用于新建文稿，用于显示标题与封面等创建选项。
  /// addingPage：当前模板窗口是否用于添加页面，与整本换纸流程区分。
  /// allowAllPages：本次模板操作是否允许选择作用到全部页面。
  /// library：用户自定义模板库依赖，可为空以禁用导入/收藏相关入口。
  const PaperTemplateDialog({
    super.key,
    this.initialTemplate = const PaperTemplate(),
    this.creating = false,
    this.addingPage = false,
    this.allowAllPages = false,
    this.library,
  });

  /// initialTemplate：模板窗口打开时的初始纸张配置，取消时不覆盖它。
  final PaperTemplate initialTemplate;

  /// creating：当前模板窗口是否用于新建文稿，用于显示标题与封面等创建选项。
  final bool creating;

  /// addingPage：当前模板窗口是否用于添加页面，与整本换纸流程区分。
  final bool addingPage;

  /// allowAllPages：本次模板操作是否允许选择作用到全部页面。
  final bool allowAllPages;

  /// library：用户自定义模板库依赖，可为空以禁用导入/收藏相关入口。
  final TemplateLibrary? library;

  @override
  State<PaperTemplateDialog> createState() => _PaperTemplateDialogState();
}

class _PaperTemplateDialogState extends State<PaperTemplateDialog> {
  /// _template：模板窗口正在编辑的纸张值，确认前不替换文稿页面。
  late PaperTemplate _template = widget.initialTemplate;

  /// _category：当前模板分类过滤，null 表示展示全部分类。
  late PaperCategory? _category = paperCategory(_template.pattern);

  /// _scroll：当前组件持有的滚动控制器，关闭时释放，不与别的活动视图同时绑定。
  final ScrollController _scroll = ScrollController();

  /// _title：新文稿标题的临时输入值，确认创建时再交给仓库命名。
  String _title = tr('无标题笔记', 'Untitled notebook');

  /// _allPages：模板窗口当前是否选中整本应用范围，确认后随结果返回。
  bool _allPages = false;

  /// _coverMode：当前模板选择区域是否在编辑封面而非正文纸张。
  bool _coverMode = false;

  /// _myTemplates：是否正在浏览用户导入/收藏模板，而不是内置模板。
  bool _myTemplates = false;

  /// _importing：是否正在导入模板文件，期间避免重复触发外部转换。
  bool _importing = false;

  /// _cover：创建流程暂选的封面模板，和正文 _template 分开保留。
  PaperTemplate? _cover;

  /// _saved：已载入的用户模板列表，保存或导入后重新同步。
  List<PaperTemplate> _saved = [];

  /// _templateError：当前模板校验失败说明，为空表示没有已知错误。
  String? _templateError;

  /// 返回当前正在选择的正文纸张或封面预览值，切换用途不覆盖另一份暂选配置。
  PaperTemplate get _preview => widget.creating && _coverMode
      ? (_cover ?? const PaperTemplate())
      : _template;

  /// 初始化模板分类和纸张/封面状态，异步载入用户模板，取消窗口不写入文稿。
  @override
  void initState() {
    super.initState();
    _coverMode = !widget.creating && _template.isCover;
    _myTemplates = _template.customName != null;
    _loadTemplates();
  }

  /// 读取用户模板库并同步可选列表，失败保留内置模板入口。
  Future<void> _loadTemplates() async {
    try {
      final saved = await widget.library?.load() ?? <PaperTemplate>[];
      if (mounted) setState(() => _saved = saved);
    } catch (error) {
      if (mounted) setState(() => _templateError = '$error');
    }
  }

  /// 选择一个已保存模板并更新当前纸张或封面暂选项，不立即重写页面。
  void _chooseSaved(PaperTemplate value) => setState(() {
    _myTemplates = true;
    if (widget.creating && _coverMode) {
      _cover = value;
    } else {
      _template = value;
    }
  });

  /// 导入用户选择的图像/PDF 首页为自定义模板，期间阻止重复导入并显示错误。
  Future<void> _importTemplate() async {
    final file =
        (OpenFilePicker()
              ..title = tr('导入图片或 PDF 首页作为模板', 'Import image or first PDF page')
              ..filterSpecification = {
                'PDF / PNG / JPG / WebP': '*.pdf;*.png;*.jpg;*.jpeg;*.webp',
              })
            .getFile();
    if (file == null || widget.library == null) return;
    setState(() {
      _importing = true;
      _templateError = null;
    });
    try {
      final value = await widget.library!.importFile(file, cover: _coverMode);
      if (!mounted) return;
      _chooseSaved(value);
      if (mounted) setState(() => _myTemplates = true);
      await _loadTemplates();
    } catch (error) {
      if (mounted) setState(() => _templateError = '$error');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  /// 将当前模板保存到个人库，完成后刷新已保存列表，原文稿页面不因此改变。
  Future<void> _savePreset() async {
    String name = _preview.label;
    final result = await showDialog<String>(
      context: context,
      animationStyle: appMotionStyle(context),
      builder: (context) => AlertDialog(
        title: Text(tr('收藏模板设置', 'Save template preset')),
        content: TextFormField(
          initialValue: name,
          autofocus: true,
          onChanged: (v) => name = v,
          decoration: InputDecoration(labelText: tr('模板名称', 'Template name')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr('取消', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, name),
            child: Text(tr('保存', 'Save')),
          ),
        ],
      ),
    );
    if (result == null || !mounted || widget.library == null) return;
    setState(() => _importing = true);
    try {
      await widget.library!.save(_preview, result, cover: _coverMode);
      if (mounted) setState(() => _myTemplates = true);
      await _loadTemplates();
    } catch (error) {
      if (mounted) setState(() => _templateError = '$error');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  /// 构建已导入/收藏模板的预览列表及适用操作，和内置分类分别显示。
  Widget _savedTemplates() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        tr(_coverMode ? '我的封面' : '我的纸张', _coverMode ? 'My covers' : 'My paper'),
        style: Theme.of(context).textTheme.titleSmall,
      ),
      const SizedBox(height: 12),
      if (!_saved.any((p) => p.isCover == _coverMode))
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Text(
            tr(
              '导入图片或 PDF 首页，或收藏当前设置，之后可重复使用。',
              'Import an image/PDF page or save a preset to reuse it later.',
            ),
          ),
        ),
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final value in _saved.where((p) => p.isCover == _coverMode))
            SizedBox(
              width: 126,
              height: 168,
              child: Material(
                color: value.toJson().toString() == _preview.toJson().toString()
                    ? Theme.of(context).colorScheme.primaryContainer
                    : Theme.of(context).colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  onTap: _importing ? null : () => _chooseSaved(value),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      children: [
                        Expanded(child: PaperTemplatePreview(template: value)),
                        const SizedBox(height: 8),
                        Text(
                          value.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      const SizedBox(height: 20),
    ],
  );

  /// 释放模板列表的滚动控制器。
  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// 切换当前模板分类并同步滚动位置，null 表示全部分类。
  void _selectCategory(PaperCategory? category) {
    setState(() {
      _category = category;
      _myTemplates = false;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  /// 构建可滚动分类栏，当前分类用明确选中态展示。
  Widget _categories() => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: <Widget>[
        if (widget.library != null)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              key: const ValueKey('paper-category-mine'),
              label: Text(tr('我的', 'My paper')),
              selected: _myTemplates,
              showCheckmark: false,
              onSelected: (_) => setState(() {
                _myTemplates = true;
                if (_scroll.hasClients) _scroll.jumpTo(0);
              }),
            ),
          ),
        for (final category in <PaperCategory?>[null, ...PaperCategory.values])
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              key: ValueKey('paper-category-${category?.name ?? 'all'}'),
              label: Text(
                category == null
                    ? tr('全部', 'All')
                    : paperCategoryLabel(category),
              ),
              selected: !_myTemplates && _category == category,
              showCheckmark: false,
              onSelected: (_) => _selectCategory(category),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              side: BorderSide.none,
            ),
          ),
      ],
    ),
  );

  /// 构建尺寸、方向、纸色和适用间距选项，无可调参数的模板不显示无效滑杆。
  Widget _settings(ColorScheme colors) => Container(
    key: const ValueKey('paper-settings-card'),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (_template.backgroundAsset != null)
          Text(
            tr(
              '导入模板保留原始尺寸、颜色和版式。',
              'Imported templates keep their original size, colors and layout.',
            ),
          ),
        if (_template.backgroundAsset == null) ...<Widget>[
          Text(
            tr('纸张设置', 'Paper settings'),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 16),
          Row(
            children: <Widget>[
              Expanded(
                child: DropdownButtonFormField<PaperSizePreset>(
                  key: const ValueKey('paper-size'),
                  isExpanded: true,
                  initialValue: _template.size,
                  decoration: InputDecoration(
                    labelText: tr('纸张大小', 'Paper size'),
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  items: <DropdownMenuItem<PaperSizePreset>>[
                    for (final size in PaperSizePreset.values)
                      DropdownMenuItem(
                        value: size,
                        child: Text(paperSizeLabel(size)),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(
                        () => _template = _template.copyWith(size: value),
                      );
                    }
                  },
                ),
              ),
              const SizedBox(width: 12),
              SegmentedButton<bool>(
                key: const ValueKey('paper-orientation'),
                showSelectedIcon: false,
                segments: <ButtonSegment<bool>>[
                  ButtonSegment(
                    value: false,
                    icon: const Icon(Icons.stay_current_portrait_rounded),
                    tooltip: tr('竖向', 'Portrait'),
                  ),
                  ButtonSegment(
                    value: true,
                    icon: const Icon(Icons.stay_current_landscape_rounded),
                    tooltip: tr('横向', 'Landscape'),
                  ),
                ],
                selected: <bool>{_template.landscape},
                onSelectionChanged: (values) => setState(
                  () => _template = _template.copyWith(landscape: values.first),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            tr('纸张颜色', 'Paper color'),
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: <Widget>[
              for (final (index, color) in const <Color>[
                Color(0xffffffff),
                Color(0xfffffbed),
                Color(0xfffff3cf),
                Color(0xffeaf2ff),
                Color(0xff202226),
              ].indexed)
                Semantics(
                  selected: _template.color == color,
                  child: Tooltip(
                    message: <String>[
                      tr('白色', 'White'),
                      tr('米白', 'Ivory'),
                      tr('淡黄', 'Yellow'),
                      tr('浅蓝', 'Blue'),
                      tr('深色', 'Dark'),
                    ][index],
                    child: InkWell(
                      key: ValueKey('paper-color-$index'),
                      borderRadius: BorderRadius.circular(24),
                      onTap: () => setState(
                        () => _template = _template.copyWith(color: color),
                      ),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _template.color == color
                                ? colors.primary
                                : colors.outlineVariant,
                            width: _template.color == color ? 2.5 : 1,
                          ),
                        ),
                        child: _template.color == color
                            ? Icon(
                                Icons.check_rounded,
                                size: 20,
                                color: color.computeLuminance() < .35
                                    ? Colors.white
                                    : colors.primary,
                              )
                            : null,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          if (paperHasAdjustableSpacing(_template.pattern)) ...<Widget>[
            const SizedBox(height: 16),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    tr('线距 / 网格间距', 'Line / grid spacing'),
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
                Text(
                  '${(_template.spacing * 100).round()}%',
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(color: colors.primary),
                ),
              ],
            ),
            Slider(
              key: const ValueKey('paper-spacing'),
              value: _template.spacing,
              min: .65,
              max: 1.6,
              divisions: 19,
              label: '${(_template.spacing * 100).round()}%',
              onChanged: (value) => setState(
                () => _template = _template.copyWith(spacing: value),
              ),
            ),
          ],
        ],
        if (widget.allowAllPages) ...<Widget>[
          const SizedBox(height: 12),
          Material(
            type: MaterialType.transparency,
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(tr('应用到整本文稿', 'Apply to all pages')),
              subtitle: Text(
                tr(
                  '确认后替换所有页面的纸张背景',
                  'Replace every page background when you apply',
                ),
              ),
              value: _allPages,
              onChanged: (value) => setState(() => _allPages = value),
            ),
          ),
        ],
      ],
    ),
  );

  /// 按窗口约束排列模板卡片和预览，模板列表与设置/整页预览分开滚动。
  Widget _browser(ColorScheme colors) => LayoutBuilder(
    builder: (context, space) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (widget.creating) ...<Widget>[
          TextFormField(
            initialValue: _title,
            selectAllOnFocus: true,
            onChanged: (value) => _title = value,
            decoration: InputDecoration(
              labelText: tr('笔记名称', 'Notebook name'),
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (widget.library != null && space.maxHeight >= 270) ...[
          Row(
            children: [
              Expanded(
                child: SegmentedButton<bool>(
                  segments: [
                    ButtonSegment(value: false, label: Text(tr('纸张', 'Paper'))),
                    ButtonSegment(value: true, label: Text(tr('封面', 'Covers'))),
                  ],
                  selected: {_coverMode},
                  onSelectionChanged: _importing
                      ? null
                      : (v) => setState(() => _coverMode = v.first),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: tr('导入模板', 'Import template'),
                onPressed: _importing ? null : _importTemplate,
                icon: const Icon(Icons.file_upload_outlined),
              ),
              IconButton(
                tooltip: tr('收藏当前设置', 'Save preset'),
                onPressed: _importing ? null : _savePreset,
                icon: const Icon(Icons.bookmark_add_outlined),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (widget.creating && _coverMode)
            TextButton(
              onPressed: () => setState(() => _cover = null),
              child: Text(
                _cover == null
                    ? tr('不添加封面（已选）', 'No cover (selected)')
                    : tr('不添加封面', 'No cover'),
              ),
            ),
        ],
        if (!_coverMode && space.maxHeight >= 270) _categories(),
        if (_importing) const LinearProgressIndicator(),
        if (_templateError != null)
          Text(_templateError!, style: TextStyle(color: colors.error)),
        const SizedBox(height: 12),
        Expanded(
          child: Scrollbar(
            controller: _scroll,
            child: SingleChildScrollView(
              key: const ValueKey('paper-template-settings'),
              controller: _scroll,
              padding: const EdgeInsets.only(right: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  for (final category in PaperCategory.values)
                    if (!_coverMode &&
                        !_myTemplates &&
                        (_category == null ||
                            _category == category)) ...<Widget>[
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          paperCategoryLabel(category),
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      PaperTemplateGallery(
                        template: _template,
                        patterns: PaperPattern.values
                            .where((p) => paperCategory(p) == category)
                            .toList(),
                        onChanged: (pattern) => setState(
                          () =>
                              _template = _template.copyWith(pattern: pattern),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                  if (widget.library != null && (_myTemplates || _coverMode))
                    _savedTemplates(),
                  if (!_coverMode || !widget.creating) _settings(colors),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );

  /// 组合标题、纸张/封面切换、固定预览、分类和确认操作，确认后才返回完整模板结果。
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final media = MediaQuery.of(context);
    final String heading = widget.creating
        ? tr('新建笔记', 'New notebook')
        : widget.addingPage
        ? tr('添加页面', 'Add page')
        : tr('更改纸张模板', 'Change paper');
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 1040,
        height: math.min(
          880,
          math.max(
            300,
            media.size.height -
                media.viewInsets.bottom -
                media.padding.vertical -
                48,
          ),
        ),
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 18, 12, 14),
              child: Row(
                children: <Widget>[
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: colors.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.auto_stories_outlined,
                      color: colors.primary,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          heading,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          tr('挑一张适合思考的纸', 'A page for your next idea'),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colors.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: tr('关闭', 'Close'),
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final browser = _browser(colors);
                    if (constraints.maxWidth >= 760) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          SizedBox(
                            width: 300,
                            child: PaperTemplatePreviewPanel(
                              template: _preview,
                            ),
                          ),
                          const SizedBox(width: 24),
                          Expanded(child: browser),
                        ],
                      );
                    }
                    // 键盘弹出后仍为名称输入和分类控件保留足够空间；
                    // 完整预览可点击打开。
                    return Column(
                      children: <Widget>[
                        if (constraints.maxHeight >= 400) ...<Widget>[
                          SizedBox(
                            height: math.min(250, constraints.maxHeight * .38),
                            child: PaperTemplatePreviewPanel(
                              template: _preview,
                              compact: true,
                            ),
                          ),
                          const SizedBox(height: 18),
                        ],
                        Expanded(child: browser),
                      ],
                    );
                  },
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      tr(
                        '共 ${15 + _saved.length} 款模板',
                        '${15 + _saved.length} templates',
                      ),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(tr('取消', 'Cancel')),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    key: const ValueKey('paper-template-submit'),
                    onPressed: _importing
                        ? null
                        : () => Navigator.pop(
                            context,
                            PaperTemplateSelection(
                              title: _title.trim().isEmpty
                                  ? tr('无标题笔记', 'Untitled notebook')
                                  : _title.trim(),
                              template: _template,
                              allPages: _allPages,
                              cover: _cover,
                            ),
                          ),
                    child: Text(
                      widget.creating
                          ? tr('创建笔记', 'Create notebook')
                          : widget.addingPage
                          ? tr('添加', 'Add page')
                          : tr('应用', 'Apply'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
