import 'package:excel/excel.dart';
import 'package:flutter_app/features/taxes/data/taxes_repository.dart';
import 'package:flutter_app/features/taxes/export/taxes_excel_export.dart';
import 'package:flutter_test/flutter_test.dart';

num? _num(CellValue? value) => switch (value) {
      DoubleCellValue(:final value) => value,
      IntCellValue(:final value) => value,
      _ => null,
    };

void main() {
  final range = TaxesDateRange(
    start: DateTime(2026, 10, 1),
    end: DateTime(2026, 10, 15),
  );

  TaxSaleRecord sale(String ncf, double total, double tax) =>
      TaxSaleRecord.fromMap({
        'sale_date': '2026-10-14T16:00:00Z',
        'receipt_type': 'consumer_final',
        'ncf': ncf,
        'total_amount': total,
        'tax_amount': tax,
        'dgii_status': 'pending',
        'clients': {'full_name': 'yenfri duran'},
      });

  test('607: montos numéricos sin RD\$ y fila de totales', () {
    final bytes = TaxesExcelExport().sales607(
      [sale('B0200000381', 708, 108), sale('B0200000380', 4130, 0)],
      range,
    );
    final sheet = Excel.decodeBytes(bytes)['607'];
    final rows = sheet.rows;

    final header = rows.indexWhere(
        (r) => r.isNotEmpty && r.first?.value?.toString() == 'Fecha');
    expect(
      rows[header].map((c) => c?.value?.toString()).toList(),
      ['Fecha', 'Cliente', 'Tipo de comprobante', 'NCF', 'Total', 'ITBIS',
          'Estado DGII'],
    );

    final first = rows[header + 1];
    expect(first[1]?.value.toString(), 'yenfri duran');
    expect(first[2]?.value.toString(), 'Consumidor Final');
    expect(first[3]?.value.toString(), 'B0200000381');
    expect(_num(first[4]?.value), 708);
    expect(_num(first[5]?.value), 108);
    expect(first[6]?.value.toString(), 'Pendiente');

    final totals = rows.firstWhere((r) =>
        r.length > 3 && r[3]?.value?.toString() == 'Total (2)');
    expect(_num(totals[4]?.value), 4838);
    expect(_num(totals[5]?.value), 108);

    for (final row in rows) {
      for (final cell in row) {
        expect(cell?.value?.toString() ?? '', isNot(contains(r'RD$')));
      }
    }
  });

  test('606: Total e ITBIS como número', () {
    final bytes = TaxesExcelExport().purchases606([
      TaxPurchaseRecord.fromMap({
        'purchase_date': '2026-10-14',
        'invoice_number': '233243432',
        'total_amount': 295,
        'tax_amount': 0,
        'status': 'posted',
        'suppliers': {'trade_name': 'Suplidor X'},
      }),
    ], range);
    final sheet = Excel.decodeBytes(bytes)['606'];
    final row = sheet.rows.firstWhere(
        (r) => r.length > 2 && r[2]?.value?.toString() == '233243432');
    expect(row[1]?.value.toString(), 'Suplidor X');
    expect(_num(row[3]?.value), 295);
    expect(_num(row[4]?.value), 0);
    expect(row[5]?.value.toString(), 'Registrada');
  });
}
