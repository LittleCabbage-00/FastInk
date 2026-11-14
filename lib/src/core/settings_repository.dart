import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import 'app_localizations.dart';
import 'app_settings.dart';
import '../storage/library_repository.dart';
import 'memory_policy_catalog.dart';
import 'runtime_environment.dart';

export 'app_settings.dart';

part 'storage_migration.dart';
part 'settings_decoders.dart';

/// 负责读取、迁移和保存应用设置。
///
/// 配置目录和文稿目录相互独立：程序目录只保存一个很小的位置指针，
/// `settings.json` 始终写入用户当前选择的位置。
class SettingsRepository {
  /// 创建配置仓库，可显式指定根目录；未指定时使用当前激活的配置位置。
  SettingsRepository({String? configRoot}) : _explicitConfigRoot = configRoot;

  /// _explicitConfigRoot：构造时显式指定的配置根目录，为空时使用活动配置位置。
  final String? _explicitConfigRoot;

  /// _activeConfigRoot：本进程当前启用的配置根目录，未激活时回退默认目录。
  static String? _activeConfigRoot;

  /// _writeQueues：按配置文件路径串行排列的写入队列，防止并发更新覆盖。
  static final Map<String, Future<void>> _writeQueues =
      <String, Future<void>>{};

  /// 返回本仓库实际读写配置的根目录。
  String get configRoot =>
      _explicitConfigRoot ?? _activeConfigRoot ?? defaultConfigRoot;

  /// 返回进程当前配置根目录，未激活时回退默认位置。
  static String get activeConfigRoot => _activeConfigRoot ?? defaultConfigRoot;

  /// 返回应用程序目录，委托统一运行环境解析以避免与工作目录混淆。
  static String get applicationDirectory =>
      RuntimeEnvironment.applicationDirectory;

  /// 根据便携模式确定程序旁配置目录，仅用于配置，不扫描文稿。
  static String get programConfigRoot => RuntimeEnvironment.isPortable
      ? RuntimeEnvironment.portableConfigDirectory
      : applicationDirectory;

  /// 解析当前 Windows 用户的配置目录，供默认安装模式使用。
  static String get userConfigRoot {
    final String profile =
        Platform.environment['USERPROFILE'] ??
        Platform.environment['LOCALAPPDATA'] ??
        Directory.systemTemp.path;
    return '$profile/.fastink';
  }

  /// 构造指定资料库内的隐藏配置目录路径。
  static String documentConfigRoot(String dataRoot) => '$dataRoot/.fastink';

  /// 把 user/program/document 等位置标识解析成实际配置目录。
  static String rootForLocation(String location, String dataRoot) =>
      switch (location) {
        'document' => documentConfigRoot(dataRoot),
        'user' => userConfigRoot,
        _ => programConfigRoot,
      };

  /// 返回记录活动配置位置的指针文件，启动时先读它再加载具体设置。
  static File get _locationPointer =>
      File('$applicationDirectory/.fastink-config-root');

  /// 启动时解析位置指针并载入设置，建立后续仓库使用的活动配置根目录。
  static Future<AppSettings> initialize() async {
    try {
      // 程序旁只存配置位置指针，完整设置写入用户选定的目录。
      if (await _locationPointer.exists()) {
        final String selected = (await _locationPointer.readAsString()).trim();
        if (selected.isNotEmpty &&
            await File('$selected/settings.json').exists()) {
          _activeConfigRoot = selected;
          return SettingsRepository().load();
        }
      }
    } catch (_) {
      // 位置指针损坏时使用默认配置位置。
    }

    // 没有可用指针时先读取旧位置，再把完整配置迁移到选定位置。
    // 这样升级旧版本不会悄悄丢失用户已经调整过的选项。
    final AppSettings previous = await SettingsRepository(
      configRoot: defaultConfigRoot,
    ).load();
    final String target = rootForLocation(
      previous.configStorageLocation,
      previous.dataRoot,
    );
    final AppSettings migrated = previous.copyWith(
      configStorageLocation: previous.configStorageLocation,
    );
    await SettingsRepository(configRoot: target).save(migrated);
    await _writeLocationPointer(target);
    _activeConfigRoot = target;
    return migrated;
  }

  /// 切换活动配置位置，必要时迁移配置并更新指针；返回实际启用的根目录。
  static Future<String> activateStorage({
    required AppSettings settings,
    required String location,
    required String dataRoot,
  }) async {
    // 先把完整设置写到目标目录，写成功后才切换指针。
    // 若复制过程中断，下次启动仍能读到原配置。
    final String target = rootForLocation(location, dataRoot);
    final AppSettings updated = settings.copyWith(
      dataRoot: dataRoot,
      configStorageLocation: location,
    );
    await SettingsRepository(configRoot: target).save(updated);
    await _writeLocationPointer(target);
    _activeConfigRoot = target;
    return target;
  }

  /// 将新配置位置写入位置指针，供下次启动继续使用。
  static Future<void> _writeLocationPointer(String target) async {
    await _locationPointer.parent.create(recursive: true);
    final File temporary = File('${_locationPointer.path}.tmp');
    await temporary.writeAsString(target, flush: true);
    if (await _locationPointer.exists()) await _locationPointer.delete();
    await temporary.rename(_locationPointer.path);
  }

  /// 按便携标记与用户环境选择默认配置目录。
  static String get defaultConfigRoot {
    // Portable 模式默认把设置留在程序旁；安装版仍兼容现有的 D 盘配置。
    if (RuntimeEnvironment.isPortable) {
      return RuntimeEnvironment.portableConfigDirectory;
    }
    if (Directory(r'D:\ComputerProgram\path').existsSync()) {
      return r'D:\ComputerProgram\path\FastInk\config';
    }
    final String local =
        Platform.environment['LOCALAPPDATA'] ?? Directory.systemTemp.path;
    return '$local/FastInk/config';
  }

  /// 返回当前配置根目录中的 settings.json 文件。
  File get _file => File('$configRoot/settings.json');

  /// 载入设置并逐字段解码，缺失、损坏或类型不符的选项采用相应默认值。
  Future<AppSettings> load() async {
    try {
      File source = _file;
      final File legacy = File(
        '${LibraryRepository.defaultRoot}/settings.json',
      );
      // 兼容早期版本把 settings.json 放在资料库根目录的布局。
      if (!await source.exists() &&
          configRoot == defaultConfigRoot &&
          await legacy.exists()) {
        source = legacy;
      }
      if (!await source.exists()) {
        return _newSettings();
      }
      final Map<String, Object?> json =
          jsonDecode(await source.readAsString())! as Map<String, Object?>;
      final double storedPenWidth =
          ((json['penWidth'] as num?)?.toDouble() ?? 3).clamp(1, 24);
      return AppSettings(
        markdown: MarkdownPreferences.fromJson(json['markdown']),
        themeMode: ThemeMode.values.firstWhere(
          (ThemeMode mode) => mode.name == json['themeMode'],
          orElse: () => ThemeMode.system,
        ),
        language:
            const <String>{'system', 'zh', 'en'}.contains(json['language'])
            ? json['language']! as String
            : 'system',
        dataRoot: (json['dataRoot'] as String?)?.trim().isNotEmpty == true
            ? json['dataRoot']! as String
            : LibraryRepository.defaultRoot,
        pressureEnabled: json['pressureEnabled'] as bool? ?? true,
        pressureSensitivity:
            ((json['pressureSensitivity'] as num?)?.toDouble() ?? 1.0).clamp(
              0.5,
              2.0,
            ),
        pressureCurve:
            const <String>{
              'linear',
              'gentle',
              'firm',
            }.contains(json['pressureCurve'])
            ? json['pressureCurve']! as String
            : 'linear',
        stylusOnly: json['stylusOnly'] as bool? ?? false,
        showPerformance: json['showPerformance'] as bool? ?? true,
        doubleTapZoomEnabled: json['doubleTapZoomEnabled'] as bool? ?? true,
        edgeBounceEnabled: json['edgeBounceEnabled'] as bool? ?? true,
        keepZoomOnPageChange: json['keepZoomOnPageChange'] as bool? ?? true,
        maximumZoom: ((json['maximumZoom'] as num?)?.toDouble() ?? 5).clamp(
          2,
          8,
        ),
        wheelZoomSensitivity:
            ((json['wheelZoomSensitivity'] as num?)?.toDouble() ?? 1).clamp(
              0.5,
              2,
            ),
        pdfCachePages: ((json['pdfCachePages'] as num?)?.toInt() ?? 160).clamp(
          40,
          320,
        ),
        pdfPrefetchPages: ((json['pdfPrefetchPages'] as num?)?.toInt() ?? 2)
            .clamp(0, 6),
        pdfImportDpi: ((json['pdfImportDpi'] as num?)?.toInt() ?? 132).clamp(
          96,
          180,
        ),
        jpgExportQuality: ((json['jpgExportQuality'] as num?)?.toInt() ?? 94)
            .clamp(70, 100),
        deviceMemoryGb: MemoryPolicyCatalog.normalize(
          (json['deviceMemoryGb'] as num?)?.toInt(),
        ),
        imageCacheEntries: ((json['imageCacheEntries'] as num?)?.toInt() ?? 48)
            .clamp(8, 96),
        imageCacheMegabytes:
            ((json['imageCacheMegabytes'] as num?)?.toInt() ?? 64).clamp(
              32,
              160,
            ),
        pagePreviewWidth: ((json['pagePreviewWidth'] as num?)?.toInt() ?? 800)
            .clamp(400, 1000),
        pageAnimationsEnabled: json['pageAnimationsEnabled'] as bool? ?? true,
        touchInertiaStrength:
            ((json['touchInertiaStrength'] as num?)?.toDouble() ?? 1).clamp(
              0,
              2,
            ),
        tooltipsEnabled: json['tooltipsEnabled'] as bool? ?? true,
        compactToolbar: json['compactToolbar'] as bool? ?? false,
        openSidebarByDefault: json['openSidebarByDefault'] as bool? ?? true,
        defaultReadOnly: json['defaultReadOnly'] as bool? ?? false,
        confirmClearInk: json['confirmClearInk'] as bool? ?? true,
        showLibraryStatusBar: json['showLibraryStatusBar'] as bool? ?? true,
        defaultSidebarTab: ((json['defaultSidebarTab'] as num?)?.toInt() ?? 0)
            .clamp(0, 2),
        sidebarWidth: ((json['sidebarWidth'] as num?)?.toDouble() ?? 260).clamp(
          200,
          360,
        ),
        defaultTool:
            const <String>{
              'pen',
              'highlighter',
              'eraser',
              'lasso',
              'shape',
              'laser',
              'text',
            }.contains(json['defaultTool'])
            ? json['defaultTool']! as String
            : 'pen',
        defaultPageFit:
            const <String>{'page', 'width'}.contains(json['defaultPageFit'])
            ? json['defaultPageFit']! as String
            : 'width',
        penStyle: json['penStyle'] as String? ?? 'fountain',
        autoSaveEnabled: json['autoSaveEnabled'] as bool? ?? true,
        autoSaveDelayMs: ((json['autoSaveDelayMs'] as num?)?.toInt() ?? 300)
            .clamp(100, 2000),
        selectionPriority: json['selectionPriority'] as bool? ?? true,
        selectionHitRadius:
            ((json['selectionHitRadius'] as num?)?.toDouble() ?? 64).clamp(
              32,
              96,
            ),
        lassoShape:
            const <String>{'freehand', 'rectangle'}.contains(json['lassoShape'])
            ? json['lassoShape']! as String
            : 'freehand',
        eraserMode: json['eraserMode'] as String? ?? 'stroke',
        eraserSize: ((json['eraserSize'] as num?)?.toDouble() ?? 30).clamp(
          6,
          60,
        ),
        defaultTextSize:
            (json['adaptiveTextVersion'] == 1
                    ? ((json['defaultTextSize'] as num?)?.toDouble() ?? 12)
                    : 12.0)
                .clamp(1, 512),
        showPageNumber: json['showPageNumber'] as bool? ?? true,
        penColor: (json['penColor'] as num?)?.toInt() ?? 0xff202124,
        penWidth: storedPenWidth,
        highlighterWidth: ((json['highlighterWidth'] as num?)?.toDouble() ?? 18)
            .clamp(4, 48),
        penWidthPresets: _decodeWidthPresets(
          json['penWidthPresets'],
          <double>[1, storedPenWidth, 8],
          0.5,
          24,
        ),
        highlighterWidthPresets: _decodeWidthPresets(
          json['highlighterWidthPresets'],
          const <double>[8, 18, 26],
          4,
          48,
        ),
        penButtonOneAction: _decodePenButtonAction(
          json['penButtonOneAction'],
          'eraser',
        ),
        penButtonTwoAction: _decodePenButtonAction(
          json['penButtonTwoAction'],
          'lasso',
        ),
        penButtonMomentary: json['penButtonMomentary'] as bool? ?? true,
        swapPenButtons: json['swapPenButtons'] as bool? ?? false,
        penColorPresets: _decodeColorPresets(json['penColorPresets']),
        laserMode: const <String>{'dot', 'trail'}.contains(json['laserMode'])
            ? json['laserMode']! as String
            : 'trail',
        laserColor: (json['laserColor'] as num?)?.toInt() ?? 0xffff3b30,
        laserWidth: ((json['laserWidth'] as num?)?.toDouble() ?? 7).clamp(
          3,
          18,
        ),
        laserFadeMs: ((json['laserFadeMs'] as num?)?.toInt() ?? 800).clamp(
          300,
          1600,
        ),
        configStorageLocation:
            const <String>{
              'document',
              'program',
              'user',
            }.contains(json['configStorageLocation'])
            ? json['configStorageLocation']! as String
            : 'program',
      );
    } catch (_) {
      return _newSettings();
    }
  }

  /// 按当前运行环境构造首次启动设置，避免把开发工作目录写进用户数据位置。
  static AppSettings _newSettings() => AppSettings(
    dataRoot: LibraryRepository.defaultRoot,
    configStorageLocation: RuntimeEnvironment.isPortable ? 'program' : 'user',
  );

  /// 加载已保存的主题模式，供启动外观初始化使用。
  Future<ThemeMode> loadThemeMode() async => (await load()).themeMode;

  /// 按配置文件路径串行执行写入任务，前次失败不阻塞之后重试。
  Future<void> _enqueueWrite(Future<void> Function() write) {
    // 同一配置目录的写入必须串行执行。update 会在轮到自己时重新读取，
    // 避免用户快速修改两个选项时，后一次用旧副本覆盖前一次结果。
    final String root = configRoot;
    final Future<void> previous = _writeQueues[root] ?? Future<void>.value();
    final Future<void> next = previous
        .catchError((Object _) {})
        .then((_) => write());
    _writeQueues[root] = next;
    return next.whenComplete(() {
      if (identical(_writeQueues[root], next)) _writeQueues.remove(root);
    });
  }

  /// 排队保存完整设置快照；等待返回的 Future 才表示本次写入任务结束。
  Future<void> save(AppSettings settings) =>
      _enqueueWrite(() => _writeJson(_encode(settings)));

  /// 在串行队列中读取当前设置、应用 change 并保存，避免并发局部更新互相覆盖。
  Future<void> update(AppSettings Function(AppSettings) change) =>
      _enqueueWrite(() async {
        // 读取动作也放在队列内，保证 current 包含前一项刚写入的内容。
        final AppSettings current = await load();
        await _writeJson(_encode(change(current)));
      });

  /// 将完整设置快照编码为 JSON 字段，Markdown 保持独立嵌套配置。
  Map<String, Object?> _encode(AppSettings settings) => <String, Object?>{
    'version': 10,
    'markdown': settings.markdown.toJson(),
    'themeMode': settings.themeMode.name,
    'language': settings.language,
    'dataRoot': settings.dataRoot,
    'pressureEnabled': settings.pressureEnabled,
    'pressureSensitivity': settings.pressureSensitivity,
    'pressureCurve': settings.pressureCurve,
    'stylusOnly': settings.stylusOnly,
    'showPerformance': settings.showPerformance,
    'doubleTapZoomEnabled': settings.doubleTapZoomEnabled,
    'edgeBounceEnabled': settings.edgeBounceEnabled,
    'keepZoomOnPageChange': settings.keepZoomOnPageChange,
    'maximumZoom': settings.maximumZoom,
    'wheelZoomSensitivity': settings.wheelZoomSensitivity,
    'pdfCachePages': settings.pdfCachePages,
    'pdfPrefetchPages': settings.pdfPrefetchPages,
    'pdfImportDpi': settings.pdfImportDpi,
    'jpgExportQuality': settings.jpgExportQuality,
    'deviceMemoryGb': settings.deviceMemoryGb,
    'imageCacheEntries': settings.imageCacheEntries,
    'imageCacheMegabytes': settings.imageCacheMegabytes,
    'pagePreviewWidth': settings.pagePreviewWidth,
    'pageAnimationsEnabled': settings.pageAnimationsEnabled,
    'touchInertiaStrength': settings.touchInertiaStrength,
    'tooltipsEnabled': settings.tooltipsEnabled,
    'compactToolbar': settings.compactToolbar,
    'openSidebarByDefault': settings.openSidebarByDefault,
    'defaultReadOnly': settings.defaultReadOnly,
    'confirmClearInk': settings.confirmClearInk,
    'showLibraryStatusBar': settings.showLibraryStatusBar,
    'defaultSidebarTab': settings.defaultSidebarTab,
    'sidebarWidth': settings.sidebarWidth,
    'defaultTool': settings.defaultTool,
    'defaultPageFit': settings.defaultPageFit,
    'penStyle': settings.penStyle,
    'autoSaveEnabled': settings.autoSaveEnabled,
    'autoSaveDelayMs': settings.autoSaveDelayMs,
    'selectionPriority': settings.selectionPriority,
    'selectionHitRadius': settings.selectionHitRadius,
    'lassoShape': settings.lassoShape,
    'eraserMode': settings.eraserMode,
    'eraserSize': settings.eraserSize,
    'adaptiveTextVersion': 1,
    'defaultTextSize': settings.defaultTextSize,
    'showPageNumber': settings.showPageNumber,
    'penColor': settings.penColor,
    'penWidth': settings.penWidth,
    'highlighterWidth': settings.highlighterWidth,
    'penWidthPresets': settings.penWidthPresets,
    'highlighterWidthPresets': settings.highlighterWidthPresets,
    'penButtonOneAction': settings.penButtonOneAction,
    'penButtonTwoAction': settings.penButtonTwoAction,
    'penButtonMomentary': settings.penButtonMomentary,
    'swapPenButtons': settings.swapPenButtons,
    'penColorPresets': settings.penColorPresets,
    'laserMode': settings.laserMode,
    'laserColor': settings.laserColor,
    'laserWidth': settings.laserWidth,
    'laserFadeMs': settings.laserFadeMs,
    'configStorageLocation': settings.configStorageLocation,
  };

  /// 只更新外观模式并保留其余配置，写入仍经过统一队列。
  Future<void> saveThemeMode(ThemeMode mode) =>
      update((current) => current.copyWith(themeMode: mode));

  /// 只更新界面语言并保留其余配置。
  Future<void> saveLanguage(AppLanguage language) =>
      update((current) => current.copyWith(language: language.name));

  /// 只更新资料库根目录配置，不在此方法中迁移实际文稿。
  Future<void> saveDataRoot(String path) =>
      update((current) => current.copyWith(dataRoot: path));

  /// 创建目录并写入配置 JSON，使用临时文件替换流程减少中断时损坏风险。
  Future<void> _writeJson(Map<String, Object?> json) async {
    // 先写临时文件，再替换 settings.json；中断时保留上次完整配置。
    await _file.parent.create(recursive: true);
    final File temporary = File('${_file.path}.tmp');
    await temporary.writeAsString(jsonEncode(json), flush: true);
    if (await _file.exists()) await _file.delete();
    await temporary.rename(_file.path);
  }
}
