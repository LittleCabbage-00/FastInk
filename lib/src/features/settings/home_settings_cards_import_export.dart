part of '../../app/fastink_app.dart';

extension _FastInkImportExportSettingsCards on _FastInkHomeState {
  /// 构建与实际导入/导出路径相连的有效设置，不暴露只增加困惑的内部批次参数。
  Widget _importExportSettingsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.tune_rounded),
              title: Text(
                tr('导入与导出', 'Import and export'),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined),
              title: Text(
                tr(
                  '新导入 PDF 的分辨率 ${_settings.pdfImportDpi} DPI',
                  'New PDF import resolution: ${_settings.pdfImportDpi} DPI',
                ),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    tr(
                      '仅影响之后导入的 PDF；降低分辨率可减少转换负载，但会降低放大后的清晰度',
                      'Applies only to future PDF imports; lower DPI reduces rendering work but softens zoomed pages',
                    ),
                  ),
                  Slider(
                    value: _settings.pdfImportDpi.toDouble(),
                    min: 96,
                    max: 180,
                    divisions: 7,
                    label: '${_settings.pdfImportDpi} DPI',
                    onChanged: (double value) => _updateState(
                      () => _settings.pdfImportDpi = value.round(),
                    ),
                    onChangeEnd: _setPdfImportDpi,
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
