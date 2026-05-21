import 'dart:typed_data';

import 'package:excel/excel.dart';

import 'expenses_repository.dart';

const _expensesSheet = 'Gastos';

const List<String> _expenseHeaders = [
  'fecha',
  'categoria',
  'proveedor',
  'metodo_pago',
  'descripcion',
  'monto',
];

class ExpensesExcelService {
  Uint8List buildExport({required List<ExpenseEntity> expenses}) {
    final excel = Excel.createExcel();
    _writeHeaders(excel);
    final sheet = excel[_expensesSheet];
    var row = 1;
    for (final e in expenses) {
      _writeExpenseRow(sheet, row, e);
      row++;
    }
    excel.delete('Sheet1');
    excel.setDefaultSheet(_expensesSheet);
    final bytes = excel.save();
    if (bytes == null) {
      throw Exception('No se pudo generar el archivo de gastos.');
    }
    return Uint8List.fromList(bytes);
  }

  void _writeHeaders(Excel excel) {
    final sheet = excel[_expensesSheet];
    for (var i = 0; i < _expenseHeaders.length; i++) {
      final cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0),
      );
      cell.value = TextCellValue(_expenseHeaders[i]);
      cell.cellStyle = CellStyle(bold: true);
    }
  }

  void _writeExpenseRow(Sheet sheet, int row, ExpenseEntity e) {
    final values = <String, String>{
      'fecha': '${e.expenseDate.year}-${e.expenseDate.month.toString().padLeft(2, '0')}-${e.expenseDate.day.toString().padLeft(2, '0')}',
      'categoria': e.category,
      'proveedor': e.supplierName ?? '-',
      'metodo_pago': _pretty(e.paymentMethod),
      'descripcion': e.description ?? '',
      'monto': e.amount.toStringAsFixed(2),
    };
    for (var i = 0; i < _expenseHeaders.length; i++) {
      final cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: i, rowIndex: row),
      );
      cell.value = TextCellValue(values[_expenseHeaders[i]] ?? '');
    }
  }

  String _pretty(String value) {
    if (value.isEmpty) return '-';
    return value
        .split('_')
        .map((part) => part.isEmpty ? part : '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }
}
