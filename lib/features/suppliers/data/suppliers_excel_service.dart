import 'dart:typed_data';

import 'package:excel/excel.dart';

import 'suppliers_repository.dart';

const _suppliersSheet = 'Proveedores';

const List<String> _supplierHeaders = [
  'nombre_legal',
  'nombre_comercial',
  'rnc',
  'contacto',
  'telefono',
  'telefono_secundario',
  'email',
  'direccion',
  'ciudad',
  'provincia',
  'pais',
  'dias_credito',
  'activo',
  'comentarios',
];

class SuppliersExcelService {
  Uint8List buildExport({required List<SupplierEntity> suppliers}) {
    final excel = Excel.createExcel();
    _writeHeaders(excel);
    final sheet = excel[_suppliersSheet];
    var row = 1;
    for (final s in suppliers) {
      _writeSupplierRow(sheet, row, s);
      row++;
    }
    excel.delete('Sheet1');
    excel.setDefaultSheet(_suppliersSheet);
    final bytes = excel.save();
    if (bytes == null) {
      throw Exception('No se pudo generar el archivo de proveedores.');
    }
    return Uint8List.fromList(bytes);
  }

  void _writeHeaders(Excel excel) {
    final sheet = excel[_suppliersSheet];
    for (var i = 0; i < _supplierHeaders.length; i++) {
      final cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0),
      );
      cell.value = TextCellValue(_supplierHeaders[i]);
      cell.cellStyle = CellStyle(bold: true);
    }
  }

  void _writeSupplierRow(Sheet sheet, int row, SupplierEntity s) {
    final values = <String, String>{
      'nombre_legal': s.legalName,
      'nombre_comercial': s.tradeName ?? '',
      'rnc': s.rnc ?? '',
      'contacto': s.contactName ?? '',
      'telefono': s.phone ?? '',
      'telefono_secundario': s.secondaryPhone ?? '',
      'email': s.email ?? '',
      'direccion': s.address ?? '',
      'ciudad': s.city ?? '',
      'provincia': s.province ?? '',
      'pais': s.countryCode,
      'dias_credito': s.paymentTermsDays.toString(),
      'activo': s.isActive ? 'si' : 'no',
      'comentarios': s.comments ?? '',
    };
    for (var i = 0; i < _supplierHeaders.length; i++) {
      final cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: i, rowIndex: row),
      );
      cell.value = TextCellValue(values[_supplierHeaders[i]] ?? '');
    }
  }
}
