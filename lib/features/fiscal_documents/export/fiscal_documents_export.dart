// Exportación de Comprobantes Fiscales a PDF y Excel, en dos vistas:
//
//   - Detallado: un renglón por comprobante. El PDF usa el renderer común de
//     reportes; el Excel se arma aquí para que Total e ITBIS salgan como
//     números (el contable los suma), no como texto "RD$ 1,234.00".
//   - Resumen: "Resumen Facturas Consumo" con el formato del formulario de la
//     DGII (líneas 1-6 y 11-17, encabezados en verde), como lo pidió el
//     contable.

import 'dart:typed_data';

import 'package:excel/excel.dart' as xl;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../shared/formatters/formatters.dart';
import '../../reports/export/report_export_models.dart';
import '../../reports/export/report_export_service.dart';
import '../../settings/data/app_settings.dart';
import '../data/fiscal_consumo_summary.dart';
import '../data/fiscal_documents_repository.dart';
import '../data/fiscal_labels.dart';

const _detailColumns = <String>[
  'NCF',
  'Tipo',
  'Estado',
  'RNC',
  'Cliente',
  'Método de pago',
  'Emisión',
  'Total',
  'ITBIS',
];

/// Verde de los encabezados del formulario DGII.
const _dgiiGreenHex = 'FF00E640';

class FiscalDocumentsExport {
  FiscalDocumentsExport({this.settings, this.branchName});

  final AppSettings? settings;
  final String? branchName;

  String? get _companyName =>
      settings?.companyName.isNotEmpty == true ? settings!.companyName : null;

  String? get _companyTaxId {
    final value = settings?.companyTaxId?.trim() ?? '';
    return value.isEmpty ? null : value;
  }

  // ─── Detallado ──────────────────────────────────────────────────────────

  Future<Uint8List> detailPdf(
    List<FiscalDocument> docs, {
    DateTime? from,
    DateTime? to,
    String? filterLabel,
  }) {
    final active = docs.where((d) => !d.isCancelled);
    final cancelled = docs.length - active.length;
    final data = ReportExportData(
      title: 'Comprobantes Fiscales',
      subtitle: ['Detallado', ?filterLabel].join(' · '),
      dateFrom: from,
      dateTo: to,
      sections: [
        ReportSection(
          table: ReportTable(
            columns: _detailColumns,
            numericColumns: const {7, 8},
            rows: [
              for (final doc in docs)
                [
                  doc.ncf,
                  fiscalReceiptLabel(doc.receiptType),
                  fiscalStatusLabel(doc),
                  _rnc(doc),
                  doc.customerName ?? '—',
                  fiscalPaymentLabel(doc),
                  formatDate(doc.issuedAt),
                  moneyPlain(doc.totalAmount),
                  moneyPlain(doc.taxAmount),
                ],
            ],
          ),
          totals: [
            ReportKv('Comprobantes', qty(active.length)),
            ReportKv('Total',
                money(active.fold<double>(0, (s, d) => s + d.totalAmount))),
            ReportKv('ITBIS',
                money(active.fold<double>(0, (s, d) => s + d.taxAmount))),
            if (cancelled > 0) ReportKv('Anulados', qty(cancelled)),
          ],
          note: cancelled > 0
              ? 'Los comprobantes anulados no suman en los totales.'
              : null,
        ),
      ],
    );
    return ReportExportService().renderBytes(
      data: data,
      format: ReportExportFormat.pdf,
      settings: settings,
      branchName: branchName,
    );
  }

  Uint8List detailXlsx(
    List<FiscalDocument> docs, {
    DateTime? from,
    DateTime? to,
    String? filterLabel,
  }) {
    final book = xl.Excel.createExcel();
    const sheetName = 'Comprobantes';
    final sheet = book[sheetName];
    book.delete('Sheet1');

    var row = _writeHeaderBlock(
      sheet,
      title: 'Comprobantes Fiscales — Detallado',
      subtitle: filterLabel,
      from: from,
      to: to,
    );

    for (var i = 0; i < _detailColumns.length; i++) {
      _text(sheet, row, i, _detailColumns[i],
          style: xl.CellStyle(
            bold: true,
            horizontalAlign:
                i >= 7 ? xl.HorizontalAlign.Right : xl.HorizontalAlign.Left,
          ));
    }
    row++;

    var total = 0.0;
    var tax = 0.0;
    var cancelled = 0;
    for (final doc in docs) {
      _text(sheet, row, 0, doc.ncf);
      _text(sheet, row, 1, fiscalReceiptLabel(doc.receiptType));
      _text(sheet, row, 2, fiscalStatusLabel(doc));
      _text(sheet, row, 3, _rnc(doc));
      _text(sheet, row, 4, doc.customerName ?? '—');
      _text(sheet, row, 5, fiscalPaymentLabel(doc));
      _text(sheet, row, 6, formatDate(doc.issuedAt));
      _amount(sheet, row, 7, doc.totalAmount);
      _amount(sheet, row, 8, doc.taxAmount);
      if (doc.isCancelled) {
        cancelled++;
      } else {
        total += doc.totalAmount;
        tax += doc.taxAmount;
      }
      row++;
    }

    row++;
    final bold = xl.CellStyle(bold: true);
    _text(sheet, row, 6, 'Total', style: bold);
    _amount(sheet, row, 7, total, bold: true);
    _amount(sheet, row, 8, tax, bold: true);
    row++;
    if (cancelled > 0) {
      _text(sheet, row, 0,
          'Anulados: $cancelled (no suman en los totales).',
          style: xl.CellStyle(italic: true));
    }

    const widths = [16.0, 18.0, 12.0, 14.0, 30.0, 22.0, 12.0, 14.0, 14.0];
    for (var i = 0; i < widths.length; i++) {
      sheet.setColumnWidth(i, widths[i]);
    }

    return _save(book, sheetName);
  }

  // ─── Resumen ────────────────────────────────────────────────────────────

  Future<Uint8List> summaryPdf(FiscalConsumoSummary summary) async {
    final pdf = pw.Document(
      title: FiscalConsumoSummary.title,
      author: _companyName ?? 'Busi Pos Web',
    );
    final theme = pw.ThemeData.withFont(
      base: await PdfGoogleFonts.robotoRegular(),
      bold: await PdfGoogleFonts.robotoBold(),
      italic: await PdfGoogleFonts.robotoItalic(),
      boldItalic: await PdfGoogleFonts.robotoBoldItalic(),
    );
    final muted = PdfColor.fromInt(0xFF66798E);
    final green = PdfColor.fromInt(0xFF00E640);
    const cellPadding = pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6);

    pw.TableRow sectionRow(String title) => pw.TableRow(
          decoration: pw.BoxDecoration(color: green),
          children: [
            pw.Padding(
              padding: cellPadding,
              child: pw.Text('*', textAlign: pw.TextAlign.right),
            ),
            pw.Padding(padding: cellPadding, child: pw.Text(title)),
            pw.SizedBox(),
          ],
        );

    pw.TableRow lineRow(FiscalSummaryLine line) => pw.TableRow(
          children: [
            pw.Padding(
              padding: cellPadding,
              child: pw.Text('${line.line}', textAlign: pw.TextAlign.right),
            ),
            pw.Padding(padding: cellPadding, child: pw.Text(line.label)),
            pw.Padding(
              padding: cellPadding,
              child: pw.Text(_lineValue(line), textAlign: pw.TextAlign.right),
            ),
          ],
        );

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.letter,
        theme: theme,
        margin: const pw.EdgeInsets.symmetric(horizontal: 40, vertical: 36),
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            if (_companyName != null)
              pw.Text(
                _companyName!,
                style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
              ),
            if (_companyTaxId != null)
              pw.Text('RNC $_companyTaxId',
                  style: pw.TextStyle(fontSize: 9, color: muted)),
            if ((branchName ?? '').isNotEmpty)
              pw.Text(branchName!,
                  style: pw.TextStyle(fontSize: 9, color: muted)),
            pw.SizedBox(height: 14),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Expanded(
                  child: pw.Text(
                    FiscalConsumoSummary.title,
                    style: pw.TextStyle(
                      fontSize: 24,
                      fontWeight: pw.FontWeight.bold,
                      fontStyle: pw.FontStyle.italic,
                    ),
                  ),
                ),
                pw.Text(
                  summary.period,
                  style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
                ),
              ],
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              '${formatDate(summary.from)} – ${formatDate(summary.to)}',
              style: pw.TextStyle(fontSize: 9, color: muted),
            ),
            pw.SizedBox(height: 18),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.black, width: 0.6),
              columnWidths: const {
                0: pw.FixedColumnWidth(44),
                1: pw.FlexColumnWidth(),
                2: pw.FixedColumnWidth(150),
              },
              children: [
                sectionRow(FiscalConsumoSummary.generalSectionTitle),
                for (final line in summary.generalLines) lineRow(line),
                sectionRow(FiscalConsumoSummary.saleTypeSectionTitle),
                for (final line in summary.saleTypeLines) lineRow(line),
              ],
            ),
            if (summary.cancelledCount > 0) ...[
              pw.SizedBox(height: 8),
              pw.Text(
                'No incluye ${summary.cancelledCount} comprobante(s) anulado(s).',
                style: pw.TextStyle(
                  fontSize: 8,
                  fontStyle: pw.FontStyle.italic,
                  color: muted,
                ),
              ),
            ],
            pw.Spacer(),
            pw.Text(
              'Generado ${formatDateTime(DateTime.now())} · Busi Pos Web',
              style: pw.TextStyle(fontSize: 8, color: muted),
            ),
          ],
        ),
      ),
    );
    return pdf.save();
  }

  Uint8List summaryXlsx(FiscalConsumoSummary summary) {
    final book = xl.Excel.createExcel();
    const sheetName = 'Resumen';
    final sheet = book[sheetName];
    book.delete('Sheet1');

    var row = 0;
    if (_companyName != null) {
      _text(sheet, row++, 0, _companyName!,
          style: xl.CellStyle(bold: true, fontSize: 12));
    }
    if (_companyTaxId != null) _text(sheet, row++, 0, 'RNC $_companyTaxId');
    if ((branchName ?? '').isNotEmpty) _text(sheet, row++, 0, branchName!);
    if (row > 0) row++;

    _text(sheet, row, 0, FiscalConsumoSummary.title,
        style: xl.CellStyle(bold: true, italic: true, fontSize: 16));
    _text(sheet, row, 2, summary.period,
        style: xl.CellStyle(
          bold: true,
          fontSize: 14,
          horizontalAlign: xl.HorizontalAlign.Right,
        ));
    row++;
    _text(sheet, row++, 0,
        '${formatDate(summary.from)} – ${formatDate(summary.to)}');
    row++;

    final border = xl.Border(borderStyle: xl.BorderStyle.Thin);
    xl.CellStyle boxed({
      bool section = false,
      xl.HorizontalAlign align = xl.HorizontalAlign.Left,
      xl.NumFormat numberFormat = xl.NumFormat.standard_0,
    }) =>
        xl.CellStyle(
          backgroundColorHex: section
              ? xl.ExcelColor.fromHexString(_dgiiGreenHex)
              : xl.ExcelColor.none,
          horizontalAlign: align,
          numberFormat: numberFormat,
          leftBorder: border,
          rightBorder: border,
          topBorder: border,
          bottomBorder: border,
        );

    void section(String title) {
      _text(sheet, row, 0, '*',
          style: boxed(section: true, align: xl.HorizontalAlign.Right));
      _text(sheet, row, 1, title, style: boxed(section: true));
      _text(sheet, row, 2, '', style: boxed(section: true));
      row++;
    }

    void line(FiscalSummaryLine line) {
      _cell(sheet, row, 0, xl.IntCellValue(line.line),
          boxed(align: xl.HorizontalAlign.Right));
      _text(sheet, row, 1, line.label, style: boxed());
      final value = line.amount;
      if (value == null) {
        _text(sheet, row, 2, '', style: boxed());
      } else if (line.isCount) {
        _cell(sheet, row, 2, xl.IntCellValue(value.round()),
            boxed(numberFormat: xl.NumFormat.standard_3));
      } else {
        _cell(sheet, row, 2, xl.DoubleCellValue(_round2(value)),
            boxed(numberFormat: xl.NumFormat.standard_4));
      }
      row++;
    }

    section(FiscalConsumoSummary.generalSectionTitle);
    summary.generalLines.forEach(line);
    section(FiscalConsumoSummary.saleTypeSectionTitle);
    summary.saleTypeLines.forEach(line);

    if (summary.cancelledCount > 0) {
      row++;
      _text(sheet, row, 0,
          'No incluye ${summary.cancelledCount} comprobante(s) anulado(s).',
          style: xl.CellStyle(italic: true));
    }

    sheet.setColumnWidth(0, 6);
    sheet.setColumnWidth(1, 44);
    sheet.setColumnWidth(2, 20);

    return _save(book, sheetName);
  }

  // ─── Helpers ────────────────────────────────────────────────────────────

  /// Encabezado común del Excel detallado (empresa, título, rango).
  /// Devuelve la fila donde empieza la tabla.
  int _writeHeaderBlock(
    xl.Sheet sheet, {
    required String title,
    String? subtitle,
    DateTime? from,
    DateTime? to,
  }) {
    var row = 0;
    if (_companyName != null) {
      _text(sheet, row++, 0, _companyName!,
          style: xl.CellStyle(bold: true, fontSize: 12));
    }
    if (_companyTaxId != null) _text(sheet, row++, 0, 'RNC $_companyTaxId');
    if ((branchName ?? '').isNotEmpty) _text(sheet, row++, 0, branchName!);
    if (row > 0) row++;

    _text(sheet, row++, 0, title, style: xl.CellStyle(bold: true, fontSize: 12));
    if ((subtitle ?? '').isNotEmpty) _text(sheet, row++, 0, subtitle!);
    if (from != null || to != null) {
      _text(sheet, row++, 0,
          'Rango: ${from != null ? formatDate(from) : '…'} – ${to != null ? formatDate(to) : '…'}');
    }
    _text(sheet, row++, 0, 'Generado: ${formatDateTime(DateTime.now())}');
    return row + 1;
  }

  static String _rnc(FiscalDocument doc) {
    final value = doc.customerDocumentNumber?.trim() ?? '';
    return value.isEmpty ? '—' : value;
  }

  static String _lineValue(FiscalSummaryLine line) {
    final value = line.amount;
    if (value == null) return '';
    return line.isCount ? qty(value.round()) : moneyPlain(value);
  }

  static void _text(xl.Sheet sheet, int row, int col, String value,
      {xl.CellStyle? style}) {
    _cell(sheet, row, col, xl.TextCellValue(value), style);
  }

  static void _amount(xl.Sheet sheet, int row, int col, double value,
      {bool bold = false}) {
    _cell(
      sheet,
      row,
      col,
      xl.DoubleCellValue(_round2(value)),
      xl.CellStyle(
        bold: bold,
        horizontalAlign: xl.HorizontalAlign.Right,
        numberFormat: xl.NumFormat.standard_4,
      ),
    );
  }

  static void _cell(xl.Sheet sheet, int row, int col, xl.CellValue value,
      xl.CellStyle? style) {
    final cell = sheet.cell(
      xl.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row),
    );
    cell.value = value;
    if (style != null) cell.cellStyle = style;
  }

  static Uint8List _save(xl.Excel book, String sheetName) {
    book.setDefaultSheet(sheetName);
    final bytes = book.save();
    if (bytes == null) {
      throw Exception('No se pudo generar el archivo de Excel.');
    }
    return Uint8List.fromList(bytes);
  }

  static double _round2(double value) => (value * 100).roundToDouble() / 100;
}
