import 'package:excel/excel.dart';
import 'package:flutter_app/features/reports/export/report_export_models.dart';
import 'package:flutter_app/features/reports/export/report_xlsx_renderer.dart';
import 'package:flutter_test/flutter_test.dart';

/// Todas las celdas de la hoja como texto, para buscar "RD$".
Iterable<String> _texts(Sheet sheet) sync* {
  for (final row in sheet.rows) {
    for (final cell in row) {
      final value = cell?.value;
      if (value is TextCellValue) yield value.value.text ?? '';
    }
  }
}

List<Data?> _rowStartingWith(Sheet sheet, String first) => sheet.rows
    .firstWhere((r) => r.isNotEmpty && r.first?.value?.toString() == first);

num? _num(CellValue? value) => switch (value) {
      DoubleCellValue(:final value) => value,
      IntCellValue(:final value) => value,
      _ => null,
    };

void main() {
  test('stripCurrencySymbol / parseFormattedNumber', () {
    expect(stripCurrencySymbol(r'RD$ 1,234.50'), '1,234.50');
    expect(stripCurrencySymbol(r'RD$ -5.00'), '-5.00');
    expect(stripCurrencySymbol('B0200000381'), 'B0200000381');
    expect(parseFormattedNumber('1,234.50'), 1234.5);
    expect(parseFormattedNumber('-5.00'), -5);
    expect(parseFormattedNumber('12'), 12);
    expect(parseFormattedNumber('15.2%'), isNull);
    expect(parseFormattedNumber('—'), isNull);
  });

  test('el Excel no lleva RD\$ y los montos salen como número', () {
    final bytes = ReportXlsxRenderer().render(
      const ReportExportData(
        title: 'Ventas detalladas',
        sections: [
          ReportSection(
            table: ReportTable(
              columns: ['Fecha', 'Hora', '#', 'NCF', 'Total', 'Cant.'],
              numericColumns: {4, 5},
              rows: [
                [
                  '14-10-2026',
                  '12:13 PM',
                  'FA-000137',
                  'B0200000381',
                  r'RD$ 7,058.00',
                  '1,200',
                ],
              ],
            ),
            totals: [
              ReportKv('Ventas', '1'),
              ReportKv('Total', r'RD$ 7,058.00', highlight: true),
            ],
            note: r'Incluye RD$ 100.00 de propina.',
          ),
        ],
      ),
    );

    final sheet = Excel.decodeBytes(bytes)['Reporte'];
    expect(_texts(sheet).where((t) => t.contains(r'RD$')), isEmpty);

    final row = _rowStartingWith(sheet, '14-10-2026');
    expect(row[1]?.value.toString(), '12:13 PM');
    expect(row[3]?.value.toString(), 'B0200000381');
    expect(_num(row[4]?.value), 7058);
    expect(_num(row[5]?.value), 1200);

    final total = _rowStartingWith(sheet, 'Total');
    expect(_num(total[1]?.value), 7058);
    // Un conteo en totales sin símbolo queda como texto (no se adivina).
    expect(_rowStartingWith(sheet, 'Ventas')[1]?.value, isA<TextCellValue>());
  });
}
