import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../shared/formatters/formatters.dart';
import 'account_statement.dart';
import 'pdf_receipt_builder.dart' show shrinkImageForPdf;

/// PDFs de Cuentas por cobrar y Cuentas por pagar:
///   - [buildStatement]: estado de cuenta de un cliente o proveedor, para
///     entregárselo o mandárselo.
///   - [buildPendingReport]: la lista de facturas pendientes de la pantalla.
///
/// Carta, con la Helvetica del paquete como la factura: los textos fijos se
/// quedan en Latin-1.
class AccountStatementPdfBuilder {
  const AccountStatementPdfBuilder();

  static final _accent = PdfColor.fromInt(0xFF0D6EFD); // AppTokens.primary
  static final _muted = PdfColor.fromInt(0xFF66798E); // mutedForeground
  static final _border = PdfColor.fromInt(0xFFE9ECEF);
  static final _zebra = PdfColor.fromInt(0xFFF8F9FA);
  static final _danger = PdfColor.fromInt(0xFFDC3545);

  static const _margin = pw.EdgeInsets.symmetric(horizontal: 32, vertical: 28);

  Future<Uint8List> buildStatement(AccountStatement s) async {
    final receivable = s.kind == AccountStatementKind.receivable;
    final logo = await shrinkImageForPdf(s.issuer.logoBytes, maxDim: 320);
    final asOf = formatDate(s.generatedAt);
    final period = _periodLabel(s.from, s.to, 'Todas las facturas pendientes');
    final doc = pw.Document(
      title: 'Estado de cuenta ${s.party.name}',
      author: s.issuer.name,
    );

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter,
        margin: _margin,
        // El encabezado completo va en la primera página; las siguientes
        // solo llevan a quién pertenece la hoja.
        header: (ctx) => ctx.pageNumber == 1
            ? pw.SizedBox()
            : pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 8),
                child: pw.Text(
                  'Estado de cuenta - ${s.party.name}',
                  style: pw.TextStyle(fontSize: 9, color: _muted),
                ),
              ),
        footer: (ctx) => _footer(ctx, '${s.issuer.name} - Estado de cuenta'),
        build: (ctx) => [
          _issuerHeader(s.issuer, logo, asOf: asOf, period: period),
          pw.SizedBox(height: 12),
          _partyBox(s.party, receivable ? 'CLIENTE' : 'PROVEEDOR'),
          pw.SizedBox(height: 12),
          _summaryBox([
            ('Facturas', '${s.documents.length}', null),
            ('Total facturado', money(s.totalAmount), null),
            ('Abonado', money(s.totalPaid), null),
            ('Saldo pendiente', money(s.totalBalance), _danger),
            ('Vencido', money(s.overdueBalance), _danger),
          ]),
          pw.SizedBox(height: 8),
          _agingTable(s.agingBuckets),
          pw.SizedBox(height: 14),
          _sectionTitle('Facturas pendientes'),
          if (s.documents.isEmpty)
            _emptyNote('No hay facturas pendientes en este periodo.')
          else
            _documentsTable(
              s.documents,
              asOf: s.generatedAt,
              referenceLabel: receivable ? 'NCF' : 'Factura prov.',
            ),
          if (s.payments.isNotEmpty) ...[
            pw.SizedBox(height: 14),
            _sectionTitle('Abonos aplicados a estas facturas'),
            _paymentsTable(s.payments),
          ],
          pw.SizedBox(height: 16),
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: _border, width: 0.8),
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: pw.Row(
              children: [
                pw.Expanded(
                  child: pw.Text(
                    receivable
                        ? 'Saldo pendiente al $asOf. Si ya realizó su pago, '
                            'favor hacer caso omiso de este estado de cuenta.'
                        : 'Saldo pendiente con el proveedor al $asOf, según '
                            'nuestros registros.',
                    style: pw.TextStyle(fontSize: 9, color: _muted),
                  ),
                ),
                pw.SizedBox(width: 12),
                pw.Text(
                  money(s.totalBalance),
                  style: pw.TextStyle(
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                    color: _danger,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return doc.save();
  }

  /// Historial del cliente (ventas, pagos y devoluciones) como estado de
  /// cuenta. [debt] y [creditBalance] son al día de hoy; los totales de
  /// comprado, pagado y devuelto son del periodo.
  Future<Uint8List> buildClientHistory({
    required StatementIssuer issuer,
    required StatementParty party,
    required List<StatementMovement> movements,
    required double debt,
    required double creditBalance,
    DateTime? from,
    DateTime? to,
  }) async {
    final logo = await shrinkImageForPdf(issuer.logoBytes, maxDim: 320);
    final now = DateTime.now();
    final asOf = formatDate(now);
    double sum(StatementMovementKind kind) => movements
        .where((m) => m.kind == kind)
        .fold<double>(0, (s, m) => s + m.amount);
    final bought = sum(StatementMovementKind.sale);
    final paid = sum(StatementMovementKind.payment);
    final refunded = sum(StatementMovementKind.refund);
    final doc = pw.Document(
      title: 'Estado de cuenta ${party.name}',
      author: issuer.name,
    );

    PdfColor? amountColor(StatementMovementKind kind) => switch (kind) {
          StatementMovementKind.payment => PdfColor.fromInt(0xFF198754),
          StatementMovementKind.refund => _danger,
          StatementMovementKind.voided => _muted,
          StatementMovementKind.sale => null,
        };

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter,
        margin: _margin,
        header: (ctx) => ctx.pageNumber == 1
            ? pw.SizedBox()
            : pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 8),
                child: pw.Text(
                  'Estado de cuenta - ${party.name}',
                  style: pw.TextStyle(fontSize: 9, color: _muted),
                ),
              ),
        footer: (ctx) => _footer(ctx, '${issuer.name} - Estado de cuenta'),
        build: (ctx) => [
          _issuerHeader(
            issuer,
            logo,
            asOf: asOf,
            period: _periodLabel(from, to, 'Todo el historial'),
          ),
          pw.SizedBox(height: 12),
          _partyBox(party, 'CLIENTE'),
          pw.SizedBox(height: 12),
          _summaryBox([
            ('Comprado', money(bought), null),
            ('Pagado', money(paid), PdfColor.fromInt(0xFF198754)),
            ('Devuelto', money(refunded), null),
            ('Deuda actual', money(debt), _danger),
            ('Saldo a favor', money(creditBalance), PdfColor.fromInt(0xFF198754)),
          ]),
          pw.SizedBox(height: 14),
          _sectionTitle('Movimientos'),
          if (movements.isEmpty)
            _emptyNote('No hay movimientos en este periodo.')
          else
            pw.Table(
              border: pw.TableBorder.all(color: _border, width: 0.5),
              defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
              columnWidths: const {
                0: pw.FlexColumnWidth(1.5), // Fecha
                1: pw.FlexColumnWidth(1.4), // Documento
                2: pw.FlexColumnWidth(2.2), // Movimiento
                3: pw.FlexColumnWidth(2.4), // Detalle
                4: pw.FlexColumnWidth(1.3), // Monto
              },
              children: [
                pw.TableRow(
                  repeat: true,
                  decoration: pw.BoxDecoration(color: _accent),
                  children: [
                    _headerCell('Fecha'),
                    _headerCell('Documento'),
                    _headerCell('Movimiento'),
                    _headerCell('Detalle'),
                    _headerCell('Monto', right: true),
                  ],
                ),
                for (var i = 0; i < movements.length; i++)
                  pw.TableRow(
                    decoration: pw.BoxDecoration(
                      color: i.isOdd ? _zebra : PdfColors.white,
                    ),
                    children: [
                      _cell(formatDateTime(movements[i].date)),
                      _cell(movements[i].document, bold: true),
                      _cell(movements[i].type),
                      _cell(movements[i].detail ?? '-'),
                      _cell(
                        '${movements[i].kind == StatementMovementKind.refund ? '-' : ''}'
                        '${money(movements[i].amount)}',
                        right: true,
                        bold: true,
                        color: amountColor(movements[i].kind),
                      ),
                    ],
                  ),
              ],
            ),
          pw.SizedBox(height: 16),
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: _border, width: 0.8),
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: pw.Row(
              children: [
                pw.Expanded(
                  child: pw.Text(
                    'Deuda al $asOf. Las ventas anuladas no suman en los '
                    'totales.',
                    style: pw.TextStyle(fontSize: 9, color: _muted),
                  ),
                ),
                pw.SizedBox(width: 12),
                pw.Text(
                  money(debt),
                  style: pw.TextStyle(
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                    color: _danger,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return doc.save();
  }

  /// Lista de facturas pendientes tal como está filtrada en pantalla.
  /// [filterLabel] describe los filtros activos (pestaña, búsqueda).
  Future<Uint8List> buildPendingReport({
    required AccountStatementKind kind,
    required List<StatementDocument> documents,
    String? branchName,
    DateTime? from,
    DateTime? to,
    String? filterLabel,
  }) async {
    final receivable = kind == AccountStatementKind.receivable;
    final title = receivable ? 'CUENTAS POR COBRAR' : 'CUENTAS POR PAGAR';
    final now = DateTime.now();
    final total = documents.fold<double>(0, (s, d) => s + d.total);
    final paid = documents.fold<double>(0, (s, d) => s + d.paid);
    final balance = documents.fold<double>(0, (s, d) => s + d.balance);
    final overdue = documents
        .where((d) => d.daysOverdue(now) > 0)
        .fold<double>(0, (s, d) => s + d.balance);
    final doc = pw.Document(title: title, author: branchName ?? 'Busi Pos Web');

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter,
        margin: _margin,
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
                      title,
                      style: pw.TextStyle(
                        fontSize: 14,
                        fontWeight: pw.FontWeight.bold,
                        color: _accent,
                      ),
                    ),
                    if (branchName != null)
                      pw.Text(
                        branchName,
                        style: pw.TextStyle(
                          fontSize: 10,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                  ],
                ),
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(
                    'Periodo: ${_periodLabel(from, to, 'Todas las fechas')}',
                    style: pw.TextStyle(fontSize: 9, color: _muted),
                  ),
                  if (filterLabel != null)
                    pw.Text(
                      filterLabel,
                      style: pw.TextStyle(fontSize: 9, color: _muted),
                    ),
                  pw.Text(
                    'Generado: ${formatDateTime(now)}',
                    style: pw.TextStyle(fontSize: 9, color: _muted),
                  ),
                ],
              ),
            ],
          ),
        ),
        footer: (ctx) => _footer(
          ctx,
          receivable ? 'Cuentas por cobrar' : 'Cuentas por pagar',
        ),
        build: (ctx) => [
          _summaryBox([
            ('Facturas', '${documents.length}', null),
            ('Total', money(total), null),
            ('Pagado', money(paid), null),
            ('Balance', money(balance), _danger),
            ('Vencido', money(overdue), _danger),
          ]),
          pw.SizedBox(height: 14),
          pw.Table(
            border: pw.TableBorder.all(color: _border, width: 0.5),
            defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
            columnWidths: const {
              0: pw.FlexColumnWidth(1.1), // Fecha
              1: pw.FlexColumnWidth(1.2), // Documento
              2: pw.FlexColumnWidth(2.4), // Cliente / Proveedor
              3: pw.FlexColumnWidth(1.5), // NCF / Factura
              4: pw.FlexColumnWidth(1.1), // Vence
              5: pw.FlexColumnWidth(1.3), // Total
              6: pw.FlexColumnWidth(1.3), // Pagado
              7: pw.FlexColumnWidth(1.3), // Balance
            },
            children: [
              pw.TableRow(
                repeat: true,
                decoration: pw.BoxDecoration(color: _accent),
                children: [
                  _headerCell('Fecha'),
                  _headerCell(receivable ? 'Venta' : 'Compra'),
                  _headerCell(receivable ? 'Cliente' : 'Proveedor'),
                  _headerCell(receivable ? 'NCF' : 'Factura prov.'),
                  _headerCell('Vence'),
                  _headerCell('Total', right: true),
                  _headerCell('Pagado', right: true),
                  _headerCell('Balance', right: true),
                ],
              ),
              for (var i = 0; i < documents.length; i++)
                _reportRow(documents[i], zebra: i.isOdd, asOf: now),
              pw.TableRow(
                decoration: pw.BoxDecoration(color: _zebra),
                children: [
                  _cell('Total', bold: true),
                  for (var i = 0; i < 4; i++) _cell(''),
                  _cell(money(total), right: true, bold: true),
                  _cell(money(paid), right: true, bold: true),
                  _cell(money(balance), right: true, bold: true, color: _danger),
                ],
              ),
            ],
          ),
        ],
      ),
    );

    return doc.save();
  }

  pw.TableRow _reportRow(
    StatementDocument d, {
    required bool zebra,
    required DateTime asOf,
  }) {
    final late = d.daysOverdue(asOf);
    return pw.TableRow(
      decoration: pw.BoxDecoration(color: zebra ? _zebra : PdfColors.white),
      children: [
        _cell(formatDate(d.date)),
        _cell(d.number),
        _cell(d.partyName, bold: true),
        _cell(d.reference ?? '-'),
        // Sin plazo el atraso se cuenta desde la fecha de la factura (ver
        // StatementDocument.daysOverdue); se muestra para que cuadre con el
        // total "Vencido".
        _cell(
          '${d.dueDate == null ? 'Sin plazo' : formatDate(d.dueDate!)}'
          '${late > 0 ? '\n$late d vencido' : ''}',
          color: late > 0 ? _danger : null,
        ),
        _cell(money(d.total), right: true),
        _cell(money(d.paid), right: true),
        _cell(money(d.balance), right: true, bold: true, color: _danger),
      ],
    );
  }

  pw.Widget _issuerHeader(
    StatementIssuer issuer,
    Uint8List? logo, {
    required String asOf,
    required String period,
  }) {
    pw.Widget line(String text) =>
        pw.Text(text, style: pw.TextStyle(fontSize: 9, color: _muted));
    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 10),
      decoration: pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: _accent, width: 1.5)),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          if (logo != null) ...[
            pw.SizedBox(
              width: 64,
              height: 64,
              child: pw.Image(pw.MemoryImage(logo), fit: pw.BoxFit.contain),
            ),
            pw.SizedBox(width: 10),
          ],
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  issuer.name,
                  style: pw.TextStyle(
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 2),
                if (issuer.address != null) line(issuer.address!),
                if (issuer.phone != null) line('Teléfono: ${issuer.phone}'),
                if (issuer.email != null) line(issuer.email!),
                if (issuer.taxId != null) line('RNC: ${issuer.taxId}'),
              ],
            ),
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(
                'ESTADO DE CUENTA',
                style: pw.TextStyle(
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                  color: _accent,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text('Fecha: $asOf', style: const pw.TextStyle(fontSize: 9)),
              pw.Text(
                period,
                style: pw.TextStyle(fontSize: 9, color: _muted),
              ),
            ],
          ),
        ],
      ),
    );
  }

  pw.Widget _partyBox(StatementParty party, String label) {
    final details = [
      ?party.document,
      if (party.phone != null) 'Tel.: ${party.phone}',
      ?party.email,
    ];
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: _zebra,
        borderRadius: pw.BorderRadius.circular(4),
        border: pw.Border.all(color: _border, width: 0.5),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(
              fontSize: 8,
              fontWeight: pw.FontWeight.bold,
              color: _muted,
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            party.name,
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
          ),
          if (details.isNotEmpty)
            pw.Text(details.join('   ·   '),
                style: const pw.TextStyle(fontSize: 9)),
          if (party.address != null)
            pw.Text(party.address!, style: const pw.TextStyle(fontSize: 9)),
        ],
      ),
    );
  }

  pw.Widget _summaryBox(List<(String, String, PdfColor?)> items) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 10, horizontal: 6),
      decoration: pw.BoxDecoration(
        color: _zebra,
        borderRadius: pw.BorderRadius.circular(4),
        border: pw.Border.all(color: _border, width: 0.5),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
        children: [
          for (final (label, value, color) in items)
            pw.Column(
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
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold,
                    color: color ?? _accent,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  pw.Widget _agingTable(List<double> buckets) {
    const labels = [
      'Por vencer',
      '1 - 30 días',
      '31 - 60 días',
      '61 - 90 días',
      'Más de 90 días',
    ];
    return pw.Table(
      border: pw.TableBorder.all(color: _border, width: 0.5),
      children: [
        pw.TableRow(
          decoration: pw.BoxDecoration(color: _zebra),
          children: [
            for (final label in labels)
              _cell(label, bold: true, center: true, color: _muted),
          ],
        ),
        pw.TableRow(
          children: [
            for (var i = 0; i < buckets.length; i++)
              _cell(
                money(buckets[i]),
                center: true,
                bold: buckets[i] > 0,
                color: i > 0 && buckets[i] > 0 ? _danger : null,
              ),
          ],
        ),
      ],
    );
  }

  pw.Widget _documentsTable(
    List<StatementDocument> documents, {
    required DateTime asOf,
    required String referenceLabel,
  }) {
    final total = documents.fold<double>(0, (s, d) => s + d.total);
    final paid = documents.fold<double>(0, (s, d) => s + d.paid);
    final balance = documents.fold<double>(0, (s, d) => s + d.balance);
    return pw.Table(
      border: pw.TableBorder.all(color: _border, width: 0.5),
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
      columnWidths: const {
        0: pw.FlexColumnWidth(1.1), // Fecha
        1: pw.FlexColumnWidth(1.25), // Factura
        2: pw.FlexColumnWidth(1.6), // NCF
        3: pw.FlexColumnWidth(1.1), // Vence
        4: pw.FlexColumnWidth(0.8), // Días
        5: pw.FlexColumnWidth(1.3), // Total
        6: pw.FlexColumnWidth(1.3), // Abonado
        7: pw.FlexColumnWidth(1.3), // Pendiente
      },
      children: [
        pw.TableRow(
          repeat: true,
          decoration: pw.BoxDecoration(color: _accent),
          children: [
            _headerCell('Fecha'),
            _headerCell('Factura'),
            _headerCell(referenceLabel),
            _headerCell('Vence'),
            _headerCell('Días venc.', right: true),
            _headerCell('Total', right: true),
            _headerCell('Abonado', right: true),
            _headerCell('Pendiente', right: true),
          ],
        ),
        for (var i = 0; i < documents.length; i++)
          () {
            final d = documents[i];
            final late = d.daysOverdue(asOf);
            return pw.TableRow(
              decoration: pw.BoxDecoration(
                color: i.isOdd ? _zebra : PdfColors.white,
              ),
              children: [
                _cell(formatDate(d.date)),
                _cell(d.number, bold: true),
                _cell(d.reference ?? '-'),
                _cell(d.dueDate == null ? 'Sin plazo' : formatDate(d.dueDate!)),
                _cell(
                  late > 0 ? '$late' : '-',
                  right: true,
                  color: late > 0 ? _danger : null,
                ),
                _cell(money(d.total), right: true),
                _cell(money(d.paid), right: true),
                _cell(money(d.balance), right: true, bold: true, color: _danger),
              ],
            );
          }(),
        pw.TableRow(
          decoration: pw.BoxDecoration(color: _zebra),
          children: [
            _cell('Total', bold: true),
            for (var i = 0; i < 4; i++) _cell(''),
            _cell(money(total), right: true, bold: true),
            _cell(money(paid), right: true, bold: true),
            _cell(money(balance), right: true, bold: true, color: _danger),
          ],
        ),
      ],
    );
  }

  pw.Widget _paymentsTable(List<StatementPayment> payments) {
    final total = payments.fold<double>(0, (s, p) => s + p.amount);
    return pw.Table(
      border: pw.TableBorder.all(color: _border, width: 0.5),
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
      columnWidths: const {
        0: pw.FlexColumnWidth(1.3), // Fecha
        1: pw.FlexColumnWidth(1.3), // Factura
        2: pw.FlexColumnWidth(1.4), // Método
        3: pw.FlexColumnWidth(2.4), // Referencia
        4: pw.FlexColumnWidth(1.4), // Monto
      },
      children: [
        pw.TableRow(
          repeat: true,
          decoration: pw.BoxDecoration(color: _accent),
          children: [
            _headerCell('Fecha'),
            _headerCell('Factura'),
            _headerCell('Método'),
            _headerCell('Referencia'),
            _headerCell('Monto', right: true),
          ],
        ),
        for (var i = 0; i < payments.length; i++)
          pw.TableRow(
            decoration: pw.BoxDecoration(
              color: i.isOdd ? _zebra : PdfColors.white,
            ),
            children: [
              _cell(formatDate(payments[i].date)),
              _cell(payments[i].documentNumber),
              _cell(payments[i].method),
              _cell(payments[i].reference ?? '-'),
              _cell(money(payments[i].amount), right: true, bold: true),
            ],
          ),
        pw.TableRow(
          decoration: pw.BoxDecoration(color: _zebra),
          children: [
            _cell('Total abonado', bold: true),
            _cell(''),
            _cell(''),
            _cell(''),
            _cell(money(total), right: true, bold: true),
          ],
        ),
      ],
    );
  }

  pw.Widget _sectionTitle(String text) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 6),
        child: pw.Text(
          text,
          style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
        ),
      );

  pw.Widget _emptyNote(String text) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 8),
        child: pw.Text(text, style: pw.TextStyle(fontSize: 9, color: _muted)),
      );

  pw.Widget _footer(pw.Context ctx, String label) => pw.Container(
        margin: const pw.EdgeInsets.only(top: 10),
        padding: const pw.EdgeInsets.only(top: 6),
        decoration: pw.BoxDecoration(
          border: pw.Border(top: pw.BorderSide(color: _muted, width: 0.5)),
        ),
        child: pw.Row(
          children: [
            pw.Text(label, style: pw.TextStyle(fontSize: 8, color: _muted)),
            pw.Spacer(),
            pw.Text(
              'Página ${ctx.pageNumber} de ${ctx.pagesCount}',
              style: pw.TextStyle(fontSize: 8, color: _muted),
            ),
          ],
        ),
      );

  pw.Widget _headerCell(String text, {bool right = false}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
        child: pw.Text(
          text,
          textAlign: right ? pw.TextAlign.right : pw.TextAlign.left,
          style: pw.TextStyle(
            fontSize: 8,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.white,
          ),
        ),
      );

  pw.Widget _cell(
    String text, {
    bool right = false,
    bool center = false,
    bool bold = false,
    PdfColor? color,
  }) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: pw.Text(
          text,
          textAlign: center
              ? pw.TextAlign.center
              : right
                  ? pw.TextAlign.right
                  : pw.TextAlign.left,
          style: pw.TextStyle(
            fontSize: 8,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
            color: color,
          ),
        ),
      );

  String _periodLabel(DateTime? from, DateTime? to, String all) =>
      from == null || to == null
          ? all
          : 'Del ${formatDate(from)} al ${formatDate(to)}';
}
