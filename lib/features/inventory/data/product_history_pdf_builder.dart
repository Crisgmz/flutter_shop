import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../shared/formatters/formatters.dart';
import 'inventory_repository.dart';

/// PDFs del historial de un producto: el listado de movimientos (carta) y el
/// comprobante de un ajuste, merma o traslado (ticket 80mm, el papel por
/// defecto de la caja).
///
/// Usa la Helvetica del paquete, igual que la factura, para no bajar fuentes
/// al imprimir. Los textos fijos se quedan en Latin-1.
class ProductHistoryPdfBuilder {
  const ProductHistoryPdfBuilder();

  static final _accent = PdfColor.fromInt(0xFF0D6EFD); // AppTokens.primary
  static final _muted = PdfColor.fromInt(0xFF66798E); // mutedForeground
  static final _border = PdfColor.fromInt(0xFFE9ECEF);
  static final _zebra = PdfColor.fromInt(0xFFF8F9FA);
  static final _success = PdfColor.fromInt(0xFF198754);
  static final _danger = PdfColor.fromInt(0xFFDC3545);

  /// Listado de [lines] (del más nuevo al más viejo). [from]/[to] solo
  /// rotulan el periodo; las líneas ya vienen filtradas.
  Future<Uint8List> buildHistory({
    required String productName,
    String? sku,
    required List<ProductMovementLine> lines,
    DateTime? from,
    DateTime? to,
    String? branchName,
  }) async {
    final doc = pw.Document(
      title: 'Historial $productName',
      author: branchName ?? 'Busi Pos Web',
    );

    final totalIn = lines
        .where((l) => l.entry.isIncoming)
        .fold<double>(0, (s, l) => s + l.entry.quantity);
    final totalOut = lines
        .where((l) => !l.entry.isIncoming)
        .fold<double>(0, (s, l) => s + l.entry.quantity.abs());
    final period = from == null || to == null
        ? 'Todos los movimientos'
        : 'Del ${formatDate(from)} al ${formatDate(to)}';
    final generatedAt = formatDateTime(DateTime.now());

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.symmetric(horizontal: 32, vertical: 28),
        header: (ctx) => pw.Container(
          margin: const pw.EdgeInsets.only(bottom: 10),
          padding: const pw.EdgeInsets.only(bottom: 8),
          decoration: pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(color: _accent, width: 1.5)),
          ),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'HISTORIAL DEL PRODUCTO',
                      style: pw.TextStyle(
                        fontSize: 14,
                        fontWeight: pw.FontWeight.bold,
                        color: _accent,
                      ),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      productName,
                      style: pw.TextStyle(
                        fontSize: 11,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    if (sku != null && sku.trim().isNotEmpty)
                      pw.Text(
                        'SKU: $sku',
                        style: pw.TextStyle(fontSize: 9, color: _muted),
                      ),
                  ],
                ),
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  if (branchName != null)
                    pw.Text(
                      branchName,
                      style: pw.TextStyle(
                        fontSize: 10,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  pw.Text(
                    'Periodo: $period',
                    style: pw.TextStyle(fontSize: 9, color: _muted),
                  ),
                  pw.Text(
                    'Generado: $generatedAt',
                    style: pw.TextStyle(fontSize: 9, color: _muted),
                  ),
                ],
              ),
            ],
          ),
        ),
        footer: (ctx) => pw.Container(
          margin: const pw.EdgeInsets.only(top: 10),
          padding: const pw.EdgeInsets.only(top: 6),
          decoration: pw.BoxDecoration(
            border: pw.Border(top: pw.BorderSide(color: _muted, width: 0.5)),
          ),
          child: pw.Row(
            children: [
              pw.Text(
                'Historial de $productName',
                style: pw.TextStyle(fontSize: 8, color: _muted),
              ),
              pw.Spacer(),
              pw.Text(
                'Página ${ctx.pageNumber} de ${ctx.pagesCount}',
                style: pw.TextStyle(fontSize: 8, color: _muted),
              ),
            ],
          ),
        ),
        build: (ctx) => [
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            margin: const pw.EdgeInsets.only(bottom: 14),
            decoration: pw.BoxDecoration(
              color: _zebra,
              borderRadius: pw.BorderRadius.circular(4),
              border: pw.Border.all(color: _border, width: 0.5),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
              children: [
                _kpi('Movimientos', '${lines.length}'),
                _kpi('Entradas', qty(totalIn), color: _success),
                _kpi('Salidas', qty(totalOut), color: _danger),
                // Stock antes del movimiento más viejo y después del más
                // nuevo del periodo.
                _kpi('Stock inicial', qty(lines.last.stockBefore)),
                _kpi('Stock final', qty(lines.first.stockAfter)),
              ],
            ),
          ),
          pw.Table(
            border: pw.TableBorder.all(color: _border, width: 0.5),
            defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
            columnWidths: const {
              0: pw.FlexColumnWidth(1.55), // Fecha
              1: pw.FlexColumnWidth(1.2), // Movimiento
              2: pw.FlexColumnWidth(3.3), // Detalle
              3: pw.FlexColumnWidth(0.85), // Entrada
              4: pw.FlexColumnWidth(0.85), // Salida
              5: pw.FlexColumnWidth(1.25), // Monto
              6: pw.FlexColumnWidth(0.8), // Stock
            },
            children: [
              pw.TableRow(
                repeat: true,
                decoration: pw.BoxDecoration(color: _accent),
                children: [
                  _headerCell('Fecha'),
                  _headerCell('Movimiento'),
                  _headerCell('Detalle / Concepto'),
                  _headerCell('Entrada', align: pw.TextAlign.right),
                  _headerCell('Salida', align: pw.TextAlign.right),
                  _headerCell('Monto', align: pw.TextAlign.right),
                  _headerCell('Stock', align: pw.TextAlign.right),
                ],
              ),
              for (var i = 0; i < lines.length; i++)
                _movementRow(lines[i], zebra: i.isOdd),
            ],
          ),
        ],
      ),
    );

    return doc.save();
  }

  pw.TableRow _movementRow(ProductMovementLine line, {required bool zebra}) {
    final e = line.entry;
    final detail = e.isManual
        ? (e.remarks ?? '-')
        : [e.party, e.reference].whereType<String>().join(' · ');
    return pw.TableRow(
      decoration: pw.BoxDecoration(color: zebra ? _zebra : PdfColors.white),
      children: [
        _cell(formatDateTime(e.when)),
        _cell(e.kind.label, bold: true),
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(detail.isEmpty ? '-' : detail,
                  style: const pw.TextStyle(fontSize: 8)),
              if (e.isManual && e.recordedBy != null)
                pw.Text(
                  'Por: ${e.recordedBy}',
                  style: pw.TextStyle(fontSize: 7, color: _muted),
                ),
            ],
          ),
        ),
        _cell(
          e.isIncoming ? '+${qty(e.quantity)}' : '',
          align: pw.TextAlign.right,
          bold: true,
          color: _success,
        ),
        _cell(
          e.isIncoming ? '' : '-${qty(e.quantity.abs())}',
          align: pw.TextAlign.right,
          bold: true,
          color: _danger,
        ),
        _cell(e.amount > 0 ? money(e.amount) : '-', align: pw.TextAlign.right),
        _cell(qty(line.stockAfter), align: pw.TextAlign.right, bold: true),
      ],
    );
  }

  /// Comprobante de un movimiento manual: qué se ajustó, cuánto, el stock
  /// antes y después, el motivo, la nota y quién lo hizo, con línea de firma.
  Future<Uint8List> buildMovementTicket({
    required String productName,
    String? sku,
    required ProductMovementLine line,
    String? branchName,
  }) async {
    final e = line.entry;
    final doc = pw.Document(
      title: 'Comprobante ${e.typeLabel}',
      author: branchName ?? 'Busi Pos Web',
    );
    final format = PdfPageFormat(
      80 * PdfPageFormat.mm,
      double.infinity,
      marginAll: 6 * PdfPageFormat.mm,
    );
    const base = pw.TextStyle(fontSize: 9);
    final bold = pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold);

    pw.Widget row(String label, String value, {pw.TextStyle? valueStyle}) {
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(width: 72, child: pw.Text(label, style: bold)),
            pw.Expanded(child: pw.Text(value, style: valueStyle ?? base)),
          ],
        ),
      );
    }

    // Una instancia por uso: los widgets del PDF guardan su posición y uno
    // repetido solo se pinta en el último lugar.
    pw.Widget divider() =>
        pw.Divider(height: 10, thickness: 0.6, color: _muted);
    final signed = e.isIncoming
        ? '+${qty(e.quantity)}'
        : '-${qty(e.quantity.abs())}';

    doc.addPage(
      pw.Page(
        pageFormat: format,
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            if (branchName != null)
              pw.Text(
                branchName.toUpperCase(),
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
              ),
            pw.SizedBox(height: 4),
            pw.Text(
              'COMPROBANTE DE INVENTARIO',
              textAlign: pw.TextAlign.center,
              style: bold,
            ),
            pw.Text(
              e.typeLabel.toUpperCase(),
              textAlign: pw.TextAlign.center,
              style: base,
            ),
            divider(),
            row('Fecha:', formatDateTime(e.when)),
            row('Producto:', productName),
            if (sku != null && sku.trim().isNotEmpty) row('SKU:', sku),
            row(
              'Cantidad:',
              signed,
              valueStyle: pw.TextStyle(
                fontSize: 10,
                fontWeight: pw.FontWeight.bold,
                color: e.isIncoming ? _success : _danger,
              ),
            ),
            row('Stock antes:', qty(line.stockBefore)),
            row('Stock después:', qty(line.stockAfter), valueStyle: bold),
            if (e.amount > 0) ...[
              row('Costo unit.:', money(e.unitCost)),
              row('Valor:', money(e.amount)),
            ],
            divider(),
            row('Motivo:', e.reason ?? '-'),
            row('Comentario:', e.notes ?? 'Sin comentario'),
            row('Realizado por:', e.recordedBy ?? 'No registrado'),
            divider(),
            pw.Text(
              'Impreso: ${formatDateTime(DateTime.now())}',
              style: pw.TextStyle(fontSize: 8, color: _muted),
            ),
            pw.SizedBox(height: 28),
            pw.Center(
              child: pw.Container(
                width: 140,
                padding: const pw.EdgeInsets.only(top: 3),
                decoration: const pw.BoxDecoration(
                  border: pw.Border(top: pw.BorderSide(width: 0.6)),
                ),
                child: pw.Text(
                  'Firma',
                  textAlign: pw.TextAlign.center,
                  style: const pw.TextStyle(fontSize: 8),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    return doc.save();
  }

  pw.Widget _kpi(String label, String value, {PdfColor? color}) {
    return pw.Column(
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        pw.Text(
          label,
          style: pw.TextStyle(
            fontSize: 8,
            color: _muted,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.SizedBox(height: 3),
        pw.Text(
          value,
          style: pw.TextStyle(
            fontSize: 12,
            fontWeight: pw.FontWeight.bold,
            color: color ?? _accent,
          ),
        ),
      ],
    );
  }

  pw.Widget _headerCell(String text, {pw.TextAlign align = pw.TextAlign.left}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
      child: pw.Text(
        text,
        textAlign: align,
        style: pw.TextStyle(
          fontSize: 8,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.white,
        ),
      ),
    );
  }

  pw.Widget _cell(
    String text, {
    pw.TextAlign align = pw.TextAlign.left,
    bool bold = false,
    PdfColor? color,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: pw.Text(
        text,
        textAlign: align,
        style: pw.TextStyle(
          fontSize: 8,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: color,
        ),
      ),
    );
  }
}
