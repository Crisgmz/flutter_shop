import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter_app/features/inventory/data/inventory_excel_service.dart';
import 'package:flutter_app/features/inventory/data/inventory_repository.dart';
import 'package:flutter_test/flutter_test.dart';

InventoryProduct _product({String? sku, String? barcode}) => InventoryProduct(
      id: '3f1c2a9e-0000-4000-8000-000000000001',
      name: 'Pantalla A26',
      sku: sku,
      barcode: barcode,
      categoryId: null,
      categoryName: null,
      unit: 'unidad',
      cost: 700,
      price: 1000,
      taxRate: 18,
      stock: 4,
      minStock: 1,
      isActive: true,
    );

void main() {
  final service = InventoryExcelService();

  test('exportar y volver a subir conserva el id del producto', () {
    final bytes = service.buildExport(
      products: [_product()],
      categories: const [],
    );

    final parsed = service.parseImport(bytes: bytes, categories: const []);

    expect(parsed.errors, isEmpty);
    expect(parsed.inputs.single.id, '3f1c2a9e-0000-4000-8000-000000000001');
    expect(parsed.columns, containsAll(['id', 'stock', 'precio']));
  });

  test('un SKU que Excel guardó como número vuelve sin ".0"', () {
    final excel = Excel.createExcel();
    final sheet = excel['Productos'];
    sheet.appendRow([
      TextCellValue('sku'),
      TextCellValue('nombre'),
      TextCellValue('codigo_barras'),
      TextCellValue('precio'),
      TextCellValue('costo'),
    ]);
    sheet.appendRow([
      DoubleCellValue(12345),
      TextCellValue('Cable'),
      DoubleCellValue(7501055330034),
      DoubleCellValue(150),
      DoubleCellValue(80.5),
    ]);
    final bytes = Uint8List.fromList(excel.save()!);

    final input =
        service.parseImport(bytes: bytes, categories: const []).inputs.single;

    expect(input.sku, '12345');
    expect(input.barcode, '7501055330034');
    expect(input.cost, 80.5);
  });

  test('las columnas que el archivo no trae no se reportan', () {
    final excel = Excel.createExcel();
    final sheet = excel['Productos'];
    sheet.appendRow([
      TextCellValue('nombre'),
      TextCellValue('precio'),
      TextCellValue('costo'),
    ]);
    sheet.appendRow([
      TextCellValue('Cable'),
      DoubleCellValue(150),
      DoubleCellValue(80),
    ]);
    final bytes = Uint8List.fromList(excel.save()!);

    final parsed = service.parseImport(bytes: bytes, categories: const []);

    // Sin columna "stock", actualizar no debe dejar el stock en 0.
    expect(parsed.columns, isNot(contains('stock')));
  });
}
