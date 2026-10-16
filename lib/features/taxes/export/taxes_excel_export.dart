// Excel de los listados 606 (compras) y 607 (ventas) de Impuestos.
//
// Mismas columnas que el CSV, pero con Total e ITBIS como números SIN el
// "RD$" (el contable los suma y los sube a la DGII) y una fila de totales.

import 'dart:typed_data';

import 'package:excel/excel.dart' as xl;

import '../../../shared/formatters/formatters.dart';
import '../../fiscal_documents/data/fiscal_labels.dart';
import '../../settings/data/app_settings.dart';
import '../data/taxes_repository.dart';

const _purchaseStatusLabels = <String, String>{
  'draft': 'Borrador',
  'posted': 'Registrada',
  'cancelled': 'Cancelada',
};

class TaxesExcelExport {
  TaxesExcelExport({this.settings, this.branchName});

  final AppSettings? settings;
  final String? branchName;

  Uint8List sales607(List<TaxSaleRecord> rows, TaxesDateRange range) {
    return _build(
      sheetName: '607',
      title: '607 — Ventas',
      range: range,
      columns: const [
        'Fecha',
        'Cliente',
        'RNC',
        'Tipo de comprobante',
        'NCF',
        'Método de pago',
        'Total',
        'ITBIS',
        'Estado DGII',
      ],
      widths: const [12, 30, 14, 20, 16, 22, 14, 14, 14],
      amountColumns: const (6, 7),
      rows: [
        for (final row in rows)
          (
            text: [
              formatDate(row.saleDate),
              row.clientName,
              row.clientDocument ?? '',
              fiscalReceiptLabel(row.receiptType),
              row.ncf ?? '',
              paymentBreakdownLabel(row.paymentBreakdown),
              null,
              null,
              fiscalStatusLabels[row.dgiiStatus] ?? row.dgiiStatus,
            ],
            total: row.totalAmount,
            tax: row.taxAmount,
          ),
      ],
    );
  }

  Uint8List purchases606(List<TaxPurchaseRecord> rows, TaxesDateRange range) {
    return _build(
      sheetName: '606',
      title: '606 — Compras',
      range: range,
      columns: const [
        'Fecha',
        'Suplidor',
        'No. factura',
        'Total',
        'ITBIS',
        'Estado',
      ],
      widths: const [12, 30, 18, 14, 14, 14],
      amountColumns: const (3, 4),
      rows: [
        for (final row in rows)
          (
            text: [
              formatDate(row.purchaseDate),
              row.supplierName,
              row.invoiceNumber ?? '',
              null,
              null,
              _purchaseStatusLabels[row.status] ?? row.status,
            ],
            total: row.totalAmount,
            tax: row.taxAmount,
          ),
      ],
    );
  }

  /// `rows[i].text` trae null en las columnas de monto; Total e ITBIS van en
  /// `amountColumns` como número.
  Uint8List _build({
    required String sheetName,
    required String title,
    required TaxesDateRange range,
    required List<String> columns,
    required List<double> widths,
    required (int, int) amountColumns,
    required List<({List<String?> text, double total, double tax})> rows,
  }) {
    final book = xl.Excel.createExcel();
    final sheet = book[sheetName];
    book.delete('Sheet1');

    var row = 0;
    final companyName = settings?.companyName.trim() ?? '';
    final companyTaxId = settings?.companyTaxId?.trim() ?? '';
    if (companyName.isNotEmpty) {
      _text(sheet, row++, 0, companyName,
          style: xl.CellStyle(bold: true, fontSize: 12));
    }
    if (companyTaxId.isNotEmpty) _text(sheet, row++, 0, 'RNC $companyTaxId');
    if ((branchName ?? '').isNotEmpty) _text(sheet, row++, 0, branchName!);
    if (row > 0) row++;

    _text(sheet, row++, 0, title, style: xl.CellStyle(bold: true, fontSize: 12));
    _text(sheet, row++, 0,
        'Período: ${formatDate(range.start)} – ${formatDate(range.end)}');
    _text(sheet, row++, 0, 'Generado: ${formatDateTime(DateTime.now())}');
    row++;

    final (totalCol, taxCol) = amountColumns;
    for (var i = 0; i < columns.length; i++) {
      final isAmount = i == totalCol || i == taxCol;
      _text(sheet, row, i, columns[i],
          style: xl.CellStyle(
            bold: true,
            horizontalAlign:
                isAmount ? xl.HorizontalAlign.Right : xl.HorizontalAlign.Left,
          ));
    }
    row++;

    var total = 0.0;
    var tax = 0.0;
    for (final r in rows) {
      for (var i = 0; i < r.text.length; i++) {
        final value = r.text[i];
        if (value != null) _text(sheet, row, i, value);
      }
      _amount(sheet, row, totalCol, r.total);
      _amount(sheet, row, taxCol, r.tax);
      total += r.total;
      tax += r.tax;
      row++;
    }

    row++;
    _text(sheet, row, totalCol - 1, 'Total (${rows.length})',
        style: xl.CellStyle(bold: true));
    _amount(sheet, row, totalCol, total, bold: true);
    _amount(sheet, row, taxCol, tax, bold: true);

    for (var i = 0; i < widths.length; i++) {
      sheet.setColumnWidth(i, widths[i]);
    }

    book.setDefaultSheet(sheetName);
    final bytes = book.save();
    if (bytes == null) {
      throw Exception('No se pudo generar el archivo de Excel.');
    }
    return Uint8List.fromList(bytes);
  }

  static void _text(xl.Sheet sheet, int row, int col, String value,
      {xl.CellStyle? style}) {
    final cell = sheet.cell(
      xl.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row),
    );
    cell.value = xl.TextCellValue(value);
    if (style != null) cell.cellStyle = style;
  }

  static void _amount(xl.Sheet sheet, int row, int col, double value,
      {bool bold = false}) {
    final cell = sheet.cell(
      xl.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row),
    );
    cell.value = xl.DoubleCellValue((value * 100).roundToDouble() / 100);
    cell.cellStyle = xl.CellStyle(
      bold: bold,
      horizontalAlign: xl.HorizontalAlign.Right,
      numberFormat: xl.NumFormat.standard_4,
    );
  }
}
