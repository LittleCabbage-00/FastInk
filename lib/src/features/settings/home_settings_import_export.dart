part of '../../app/fastink_app.dart';

extension _FastInkImportExportSettings on _FastInkHomeState {
  /// pressureCurve：压力映射曲线名称，用于笔迹宽度计算。
  Future<void> _setPressureCurve(PressureCurve value) async {
    _updateState(() => _settings.pressureCurve = value.name);
    await _settings.saveString('pressureCurve', value.name);
  }

  /// pdfImportDpi 用于 PDF 页面栅格化，单位为 DPI。
  Future<void> _setPdfImportDpi(double value) async {
    final int dpi = value.round().clamp(96, 180);
    _repository.pdfImportDpi = dpi;
    _updateState(() => _settings.pdfImportDpi = dpi);
    await _settings.saveNum('pdfImportDpi', dpi);
  }

  /// 更新显式传入的激光参数并保存，其余激光值和持久笔迹不变。
  Future<void> _setLaserDefaults({
    LaserMode? mode,
    Color? color,
    double? width,
    int? fadeMs,
  }) async {
    _updateState(() {
      if (mode != null) _settings.laserMode = mode.name;
      if (color != null) _settings.laserColor = color.toARGB32();
      if (width != null) _settings.laserWidth = width.clamp(3, 18);
      if (fadeMs != null) _settings.laserFadeMs = fadeMs.clamp(300, 1600);
    });
    await _settings.saveAll({
      'laserMode': _settings.laserMode,
      'laserColor': _settings.laserColor,
      'laserWidth': _settings.laserWidth,
      'laserFadeMs': _settings.laserFadeMs,
    });
  }
}
