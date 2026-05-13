// XLSX renderer para reportes (PRD 07 sub-fase 7.D).
//
// Diseño:
//   - 1 hoja "Reporte" por defecto.
//   - Fila 1-N: header (compañía, RNC, sucursal, título, rango).
//   - Fila N+1: línea en blanco.
//   - Por cada sección: título en bold (si existe), tabla con headers en
//     bold + filas, totales debajo.

import 'dart:typed_data';

import 'package:excel/excel.dart';

import 'report_export_models.dart';

const _sheetName = 'Reporte';

class ReportXlsxRenderer {
  Uint8List render(ReportExportData data) {
    final excel = Excel.createExcel();
    final sheet = excel[_sheetName];
    excel.delete('Sheet1');

    var row = 0;

    // Header metadata
    if ((data.companyName ?? '').isNotEmpty) {
      _writeCell(sheet, row, 0, data.companyName!, bold: true, fontSize: 14);
      row++;
    }
    if ((data.companyTaxId ?? '').isNotEmpty) {
      _writeCell(sheet, row, 0, 'RNC ${data.companyTaxId}');
      row++;
    }
    if ((data.branchName ?? '').isNotEmpty) {
      _writeCell(sheet, row, 0, data.branchName!);
      row++;
    }
    if (row > 0) row++; // blank line

    _writeCell(sheet, row, 0, data.title, bold: true, fontSize: 12);
    row++;
    if ((data.subtitle ?? '').isNotEmpty) {
      _writeCell(sheet, row, 0, data.subtitle!);
      row++;
    }
    if (data.dateFrom != null && data.dateTo != null) {
      _writeCell(
        sheet,
        row,
        0,
        'Rango: ${_fmtDate(data.dateFrom!)} → ${_fmtDate(data.dateTo!)}',
      );
      row++;
    }
    _writeCell(
      sheet,
      row,
      0,
      'Generado: ${_fmtDateTime(DateTime.now())}',
    );
    row++;
    row++; // blank line

    // Secciones
    for (final section in data.sections) {
      row = _writeSection(sheet, section, row);
      row++; // blank line between sections
    }

    excel.setDefaultSheet(_sheetName);
    final bytes = excel.save();
    if (bytes == null) {
      throw Exception('No se pudo generar el archivo XLSX.');
    }
    return Uint8List.fromList(bytes);
  }

  int _writeSection(Sheet sheet, ReportSection section, int startRow) {
    var row = startRow;
    if ((section.title ?? '').isNotEmpty) {
      _writeCell(sheet, row, 0, section.title!, bold: true);
      row++;
    }

    if (section.table != null) {
      final t = section.table!;
      // Header
      for (var i = 0; i < t.columns.length; i++) {
        _writeCell(sheet, row, i, t.columns[i], bold: true);
      }
      row++;
      // Rows
      for (final r in t.rows) {
        for (var i = 0; i < r.length; i++) {
          _writeCell(sheet, row, i, r[i]);
        }
        row++;
      }
    }

    if (section.kv != null && section.kv!.isNotEmpty) {
      for (final entry in section.kv!) {
        _writeCell(sheet, row, 0, entry.label);
        _writeCell(
          sheet,
          row,
          1,
          entry.value,
          bold: entry.highlight,
        );
        row++;
      }
    }

    if (section.totals != null && section.totals!.isNotEmpty) {
      row++; // blank line before totals
      for (final entry in section.totals!) {
        _writeCell(sheet, row, 0, entry.label, bold: true);
        _writeCell(sheet, row, 1, entry.value, bold: true);
        row++;
      }
    }

    if ((section.note ?? '').isNotEmpty) {
      _writeCell(sheet, row, 0, section.note!, italic: true);
      row++;
    }

    return row;
  }

  void _writeCell(
    Sheet sheet,
    int row,
    int col,
    String value, {
    bool bold = false,
    bool italic = false,
    int? fontSize,
  }) {
    final cell = sheet.cell(
      CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row),
    );
    cell.value = TextCellValue(value);
    if (bold || italic || fontSize != null) {
      cell.cellStyle = CellStyle(
        bold: bold,
        italic: italic,
        fontSize: fontSize,
      );
    }
  }

  String _fmtDate(DateTime d) {
    return '${d.day.toString().padLeft(2, '0')}/'
        '${d.month.toString().padLeft(2, '0')}/'
        '${d.year}';
  }

  String _fmtDateTime(DateTime d) {
    final local = d.isUtc ? d.toLocal() : d;
    return '${_fmtDate(local)} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }
}
