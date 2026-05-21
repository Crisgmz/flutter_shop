import 'dart:typed_data';

import 'package:excel/excel.dart';

import 'purchases_repository.dart';

const _purchasesSheet = 'Compras';

const List<String> _purchaseHeaders = [
  'Fecha',
  'Código Compra',
  'Código Factura',
  'Proveedor',
  'Categoría',
  'Estado',
  'Pago',
  'Progreso Recepción',
  'Monto Total',
];

class PurchasesExcelService {
  Uint8List buildExport({required List<PurchaseSummary> purchases}) {
    final excel = Excel.createExcel();
    _writeHeaders(excel);
    final sheet = excel[_purchasesSheet];
    var row = 1;
    for (final p in purchases) {
      _writePurchaseRow(sheet, row, p);
      row++;
    }
    excel.delete('Sheet1');
    excel.setDefaultSheet(_purchasesSheet);
    final bytes = excel.save();
    if (bytes == null) {
      throw Exception('No se pudo generar el archivo de compras.');
    }
    return Uint8List.fromList(bytes);
  }

  void _writeHeaders(Excel excel) {
    final sheet = excel[_purchasesSheet];
    for (var i = 0; i < _purchaseHeaders.length; i++) {
      final cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0),
      );
      cell.value = TextCellValue(_purchaseHeaders[i]);
      cell.cellStyle = CellStyle(bold: true);
    }
  }

  void _writePurchaseRow(Sheet sheet, int row, PurchaseSummary p) {
    final progress = '${(p.receiptProgress * 100).toStringAsFixed(0)}%';
    
    final values = <String, String>{
      'Fecha': p.purchaseDate.toIso8601String().split('T').first,
      'Código Compra': p.purchaseNumber ?? '-',
      'Código Factura': p.invoiceNumber ?? '-',
      'Proveedor': p.supplierName,
      'Categoría': p.purchaseCategory ?? '-',
      'Estado': _statusLabel(p.status),
      'Pago': _paymentStatusLabel(p.paymentStatus),
      'Progreso Recepción': progress,
      'Monto Total': p.totalAmount.toStringAsFixed(2),
    };

    for (var i = 0; i < _purchaseHeaders.length; i++) {
      final cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: i, rowIndex: row),
      );
      cell.value = TextCellValue(values[_purchaseHeaders[i]] ?? '');
    }
  }

  String _statusLabel(String status) {
    switch (status.toLowerCase()) {
      case 'draft':
        return 'Borrador';
      case 'ordered':
        return 'Pedido';
      case 'posted':
        return 'Registrado';
      case 'received':
        return 'Recibido';
      case 'cancelled':
        return 'Cancelado';
      default:
        return status;
    }
  }

  String _paymentStatusLabel(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return 'Pendiente';
      case 'partial':
        return 'Parcial';
      case 'paid':
        return 'Pagado';
      case 'overdue':
        return 'Vencido';
      default:
        return status;
    }
  }
}
