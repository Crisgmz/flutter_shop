import 'dart:typed_data';

import 'package:excel/excel.dart';

import 'quotations_models.dart';

const _quotesSheet = 'Cotizaciones';

const List<String> _quoteHeaders = [
  'Código',
  'Cliente',
  'Estado',
  'Fecha Emisión',
  'Vigente Hasta',
  'Días Restantes',
  'Monto Total',
  'Resumen',
];

class QuotationsExcelService {
  Uint8List buildExport({required List<QuoteListItem> quotes}) {
    final excel = Excel.createExcel();
    _writeHeaders(excel);
    final sheet = excel[_quotesSheet];
    var row = 1;
    for (final q in quotes) {
      _writeQuoteRow(sheet, row, q);
      row++;
    }
    excel.delete('Sheet1');
    excel.setDefaultSheet(_quotesSheet);
    final bytes = excel.save();
    if (bytes == null) {
      throw Exception('No se pudo generar el archivo de cotizaciones.');
    }
    return Uint8List.fromList(bytes);
  }

  void _writeHeaders(Excel excel) {
    final sheet = excel[_quotesSheet];
    for (var i = 0; i < _quoteHeaders.length; i++) {
      final cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0),
      );
      cell.value = TextCellValue(_quoteHeaders[i]);
      cell.cellStyle = CellStyle(bold: true);
    }
  }

  void _writeQuoteRow(Sheet sheet, int row, QuoteListItem q) {
    final values = <String, String>{
      'Código': q.code,
      'Cliente': q.clientName,
      'Estado': q.effectiveStatus.label,
      'Fecha Emisión': q.createdAt.toIso8601String().split('T').first,
      'Vigente Hasta': q.validUntil.toIso8601String().split('T').first,
      'Días Restantes': q.daysRemaining.toString(),
      'Monto Total': q.total.toStringAsFixed(2),
      'Resumen': q.summary,
    };

    for (var i = 0; i < _quoteHeaders.length; i++) {
      final cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: i, rowIndex: row),
      );
      cell.value = TextCellValue(values[_quoteHeaders[i]] ?? '');
    }
  }
}
