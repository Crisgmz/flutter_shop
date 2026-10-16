// XLSX renderer para reportes (PRD 07 sub-fase 7.D).
//
// Diseño:
//   - 1 hoja "Reporte" por defecto.
//   - Fila 1-N: header (compañía, RNC, sucursal, título, rango).
//   - Fila N+1: línea en blanco.
//   - Por cada sección: título en bold (si existe), tabla con headers en
//     bold + filas, totales debajo.
//   - Montos: los modelos traen "RD\$ 1,234.00" (money()) porque el PDF los
//     muestra así; en el Excel van SIN el símbolo y como número, para que el
//     contable los sume y los suba a la DGII. Lo mismo con los números de las
//     columnas numéricas (moneyPlain(), qty()).

import 'dart:typed_data';

import 'package:excel/excel.dart';

import '../../../shared/formatters/live_settings.dart';
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

    _fitColumns(sheet, data.sections);

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
          _writeValue(sheet, row, i, r[i],
              numericColumn: t.numericColumns.contains(i));
        }
        row++;
      }
    }

    if (section.kv != null && section.kv!.isNotEmpty) {
      for (final entry in section.kv!) {
        _writeCell(sheet, row, 0, entry.label);
        _writeValue(
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
        _writeValue(sheet, row, 1, entry.value, bold: true);
        row++;
      }
    }

    if ((section.note ?? '').isNotEmpty) {
      _writeCell(sheet, row, 0, section.note!, italic: true);
      row++;
    }

    return row;
  }

  /// Escribe un valor de la tabla / totales: los montos ("RD\$ 1,234.00")
  /// salen como número sin el símbolo; en columnas numéricas también los
  /// números sin símbolo ("1,234.00", "12"). Lo demás queda como texto, sin
  /// el "RD\$" si lo trae metido (ej. "RD\$ 100.00 / RD\$ 200.00").
  void _writeValue(
    Sheet sheet,
    int row,
    int col,
    String value, {
    bool numericColumn = false,
    bool bold = false,
  }) {
    final stripped = stripCurrencySymbol(value);
    final hadSymbol = stripped != value;
    final number =
        hadSymbol || numericColumn ? parseFormattedNumber(stripped) : null;
    if (number == null) {
      _writeCell(sheet, row, col, stripped, bold: bold);
      return;
    }
    final cell = sheet.cell(
      CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row),
    );
    final decimals = _hasDecimals(stripped);
    cell.value = decimals
        ? DoubleCellValue(number)
        : IntCellValue(number.round());
    cell.cellStyle = CellStyle(
      bold: bold,
      horizontalAlign: HorizontalAlign.Right,
      numberFormat: decimals ? NumFormat.standard_4 : NumFormat.standard_3,
    );
  }

  /// Ancho de cada columna según lo más largo que trae (encabezado o
  /// celdas), para que la fecha o el cliente no queden cortados.
  void _fitColumns(Sheet sheet, List<ReportSection> sections) {
    final widths = <int, int>{};
    void measure(int col, String text) {
      final length = stripCurrencySymbol(text).length;
      if (length > (widths[col] ?? 0)) widths[col] = length;
    }

    for (final section in sections) {
      final t = section.table;
      if (t != null) {
        for (var i = 0; i < t.columns.length; i++) {
          measure(i, t.columns[i]);
        }
        for (final r in t.rows) {
          for (var i = 0; i < r.length; i++) {
            measure(i, r[i]);
          }
        }
      }
      for (final entry in [...?section.kv, ...?section.totals]) {
        measure(0, entry.label);
        measure(1, entry.value);
      }
    }
    widths.forEach((col, length) {
      sheet.setColumnWidth(col, (length + 2).clamp(8, 45).toDouble());
    });
  }

  bool _hasDecimals(String value) =>
      LiveSettings.decimalPoint.isNotEmpty &&
      value.contains(LiveSettings.decimalPoint) &&
      LiveSettings.currencyDecimals > 0;

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
    cell.value = TextCellValue(stripCurrencySymbol(value));
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

/// Quita el símbolo de moneda (el configurado y "RD\$") de un texto ya
/// formateado: "RD\$ 1,234.00" → "1,234.00", "RD\$ -5.00" → "-5.00".
String stripCurrencySymbol(String value) {
  var out = value;
  for (final symbol in {LiveSettings.currencySymbol, r'RD$'}) {
    if (symbol.isEmpty) continue;
    out = out.replaceAll('$symbol ', '').replaceAll(symbol, '');
  }
  return out == value ? value : out.trim();
}

/// Lee un número formateado con los separadores configurados ("1,234.50",
/// "-5.00", "12"). null si el texto no es solo un número.
double? parseFormattedNumber(String value) {
  final text = value.trim();
  if (text.isEmpty) return null;
  final thousands = LiveSettings.thousandsSep;
  final decimalPoint = LiveSettings.decimalPoint;
  var normalized = thousands.isEmpty ? text : text.replaceAll(thousands, '');
  if (decimalPoint.isNotEmpty && decimalPoint != '.') {
    normalized = normalized.replaceAll(decimalPoint, '.');
  }
  if (!RegExp(r'^-?\d+(\.\d+)?$').hasMatch(normalized)) return null;
  return double.tryParse(normalized);
}
