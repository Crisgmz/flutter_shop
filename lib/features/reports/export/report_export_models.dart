// Modelos comunes para exportación de reportes (PDF/XLSX/CSV).
//
// Un reporte exportable se describe como:
//   - Metadata: título, subtítulo, rango de fechas, sucursal, generado por.
//   - 0..N secciones, cada una con:
//       · título (opcional)
//       · tabla con columnas y filas
//       · totales (opcional)
//   - O 0..N pares key/value (para resúmenes tipo P&L).
//
// El renderer (PDF o XLSX) recibe este modelo y produce los bytes finales.

import 'package:flutter/foundation.dart';

@immutable
class ReportExportData {
  const ReportExportData({
    required this.title,
    required this.sections,
    this.subtitle,
    this.companyName,
    this.companyTaxId,
    this.branchName,
    this.dateFrom,
    this.dateTo,
    this.generatedBy,
  });

  final String title;
  final String? subtitle;
  final String? companyName;
  final String? companyTaxId;
  final String? branchName;
  final DateTime? dateFrom;
  final DateTime? dateTo;
  final String? generatedBy;
  final List<ReportSection> sections;
}

@immutable
class ReportSection {
  const ReportSection({
    this.title,
    this.table,
    this.kv,
    this.totals,
    this.note,
  });

  /// Encabezado de sección (opcional). Si null, la sección se renderiza
  /// sin separador adicional.
  final String? title;

  /// Tabla con columnas + filas. Mutuamente excluyente con `kv`.
  final ReportTable? table;

  /// Pares clave/valor (resumen). Mutuamente excluyente con `table`.
  final List<ReportKv>? kv;

  /// Totales al pie de la sección (debajo de la tabla o de los kv).
  final List<ReportKv>? totals;

  /// Texto adicional al final de la sección (notas, advertencias).
  final String? note;
}

@immutable
class ReportTable {
  const ReportTable({
    required this.columns,
    required this.rows,
    this.numericColumns = const {},
  });

  final List<String> columns;

  /// Cada fila es una lista de strings ya formateados (money(), qty(), etc.).
  /// El renderer NO formatea los valores — quien arma el modelo es responsable
  /// de aplicar `money()` / `formatDate()` antes.
  final List<List<String>> rows;

  /// Índices de columnas que deben alinearse a la derecha (numérico).
  final Set<int> numericColumns;
}

@immutable
class ReportKv {
  const ReportKv(this.label, this.value, {this.highlight = false});

  final String label;
  final String value;
  final bool highlight;
}
