// Servicio orquestador para exportar un reporte:
//   1. Toma `ReportExportData` ya armado por la presentation layer.
//   2. Inyecta automáticamente companyName/RNC/branchName desde
//      `app_settings` + sucursal actual.
//   3. Genera PDF o XLSX según el formato pedido.
//   4. Devuelve los bytes para que el caller los guarde o comparta.
//
// El servicio NO toca filesystem ni share — eso lo hace `FileIoHelper`
// del módulo inventory (reutilizado).

import 'dart:typed_data';

import '../../settings/data/app_settings.dart';
import 'report_export_models.dart';
import 'report_pdf_renderer.dart';
import 'report_xlsx_renderer.dart';

enum ReportExportFormat { pdf, xlsx }

class ReportExportService {
  ReportExportService({
    ReportPdfRenderer? pdfRenderer,
    ReportXlsxRenderer? xlsxRenderer,
  })  : _pdfRenderer = pdfRenderer ?? ReportPdfRenderer(),
        _xlsxRenderer = xlsxRenderer ?? ReportXlsxRenderer();

  final ReportPdfRenderer _pdfRenderer;
  final ReportXlsxRenderer _xlsxRenderer;

  /// Enriquece el modelo del reporte con metadata de la empresa y produce
  /// los bytes en el formato pedido.
  Future<Uint8List> renderBytes({
    required ReportExportData data,
    required ReportExportFormat format,
    AppSettings? settings,
    String? branchName,
  }) async {
    final enriched = ReportExportData(
      title: data.title,
      subtitle: data.subtitle,
      sections: data.sections,
      dateFrom: data.dateFrom,
      dateTo: data.dateTo,
      generatedBy: data.generatedBy,
      companyName: data.companyName ??
          (settings?.companyName.isNotEmpty == true
              ? settings!.companyName
              : null),
      companyTaxId: data.companyTaxId ?? settings?.companyTaxId,
      branchName: data.branchName ?? branchName,
    );

    switch (format) {
      case ReportExportFormat.pdf:
        return _pdfRenderer.render(enriched);
      case ReportExportFormat.xlsx:
        return _xlsxRenderer.render(enriched);
    }
  }
}
