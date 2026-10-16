import 'package:excel/excel.dart';
import 'package:flutter_app/features/fiscal_documents/data/fiscal_consumo_summary.dart';
import 'package:flutter_app/features/fiscal_documents/data/fiscal_documents_repository.dart';
import 'package:flutter_app/features/fiscal_documents/export/fiscal_documents_export.dart';
import 'package:flutter_test/flutter_test.dart';

FiscalDocument _doc(String ncf, String method, double total, double tax) =>
    FiscalDocument.fromMap({
      'id': ncf,
      'branch_id': 'b1',
      'receipt_type': 'consumer_final',
      'ncf': ncf,
      'fiscal_status': 'pending',
      'issued_at': '2026-07-10T14:00:00Z',
      'customer_document_number': '131000001',
      'customer_name': 'Cliente',
      'total_amount': total,
      'tax_amount': tax,
      'sales': {
        'sale_number': 'V-$ncf',
        'sale_date': '2026-07-10T14:00:00Z',
        'status': 'completed',
        'payments': [
          {
            'payment_method': method,
            'amount': total,
            'paid_at': '2026-07-10T14:00:00Z',
            'reference': 'V-$ncf',
          },
        ],
      },
    });

/// Valor de la columna `col` en la fila cuya columna `keyCol` dice `key`.
CellValue? _find(Sheet sheet, int keyCol, String key, int col) {
  for (final row in sheet.rows) {
    if (row.length > keyCol && row[keyCol]?.value?.toString() == key) {
      return row.length > col ? row[col]?.value : null;
    }
  }
  return null;
}

/// Número de una celda numérica (el lector devuelve 1180.00 como entero).
num? _num(CellValue? value) => switch (value) {
      DoubleCellValue(:final value) => value,
      IntCellValue(:final value) => value,
      _ => null,
    };

void main() {
  final docs = [
    _doc('B0200000001', 'cash', 1180, 180),
    _doc('B0200000002', 'card', 590.5, 90.08),
  ];
  final export = FiscalDocumentsExport();

  test('Excel detallado: RNC, método de pago y montos numéricos', () {
    final book = Excel.decodeBytes(export.detailXlsx(docs));
    final sheet = book['Comprobantes'];
    expect(_find(sheet, 0, 'B0200000001', 3).toString(), '131000001');
    expect(_find(sheet, 0, 'B0200000002', 5).toString(), 'Tarjeta');
    expect(_num(_find(sheet, 0, 'B0200000002', 7)), 590.5);
    expect(_num(_find(sheet, 6, 'Total', 7)), 1770.5);
  });

  test('Excel resumen: líneas DGII con valores numéricos', () {
    final summary = FiscalConsumoSummary.fromDocuments(
      docs,
      from: DateTime(2026, 7, 1),
      to: DateTime(2026, 7, 31),
    );
    final book = Excel.decodeBytes(export.summaryXlsx(summary));
    final sheet = book['Resumen'];
    expect(_find(sheet, 1, 'Cantidad NCFs Emitidos de F.C.', 2).toString(), '2');
    expect(_num(_find(sheet, 1, 'Total Itbis Facturado', 2)), 270.08);
    expect(_num(_find(sheet, 1, 'EFECTIVO', 2)), 1180);
    expect(_num(_find(sheet, 1, 'TARJETA DÉBITO / CRÉDITO', 2)), 590.5);
    expect(_find(sheet, 1, 'PERMUTA', 2).toString(), '');
  });
}
