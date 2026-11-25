import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../shared/formatters/formatters.dart';
import 'pdf_receipt_builder.dart'
    show printDocumentTitle, printPendingNcfNotice, printReceiptHeadline;
import 'printing_models.dart';

/// La factura de venta sale en el formato A4 clásico: la empresa lo eligió
/// (`app_settings.invoice_a4_style`) y es una venta, no una cotización,
/// devolución ni otro documento. Público porque la vista previa decide con
/// la misma regla.
bool usesClassicA4(PrintDocumentData data) =>
    data.classicA4 &&
    (data.documentType == PrintDocumentType.fiscalInvoice ||
        data.documentType == PrintDocumentType.saleReceipt);

const _navy = PdfColor.fromInt(0xFF1F3864);
const _blue = PdfColor.fromInt(0xFF2E75B6);
const _tint = PdfColor.fromInt(0xFFEEF3FA);
const _border = PdfColor.fromInt(0xFFC9D3E3);
const _rule = PdfColor.fromInt(0xFFDCE3EE);
const _zebra = PdfColor.fromInt(0xFFF5F8FC);
const _muted = PdfColor.fromInt(0xFF5B6576);
const _ink = PdfColor.fromInt(0xFF1A1A1A);

/// Filas mínimas del detalle: con pocas líneas la tabla igual llena su
/// espacio, como el formulario que el cliente usaba.
const _minTableRows = 14;

const _checkSvg =
    '<svg viewBox="0 0 12 12" xmlns="http://www.w3.org/2000/svg">'
    '<path d="M2 6.5l2.6 2.5L10 3.5" fill="none" stroke="#FFFFFF" '
    'stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>';

/// Factura A4 clásica (GeotecnicaMQ, 12 nov 2026): encabezado con giro,
/// bloque fiscal, cuadros de Cliente y Proyecto, Concepto, detalle con
/// Unidad, forma de pago marcada, cuenta para depositar, totales con el ITBIS
/// de la Norma 07-2007 y "Preparado por" con el sello.
class ClassicInvoiceLayout {
  const ClassicInvoiceLayout();

  pw.Page page(
    PrintDocumentData data, {
    PdfPageFormat pageFormat = PdfPageFormat.a4,
    Uint8List? logoBytes,
    Uint8List? stampBytes,
  }) {
    return pw.Page(
      pageFormat: pageFormat,
      margin: pw.EdgeInsets.zero,
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Container(height: 6, color: _navy),
          pw.Expanded(
            child: pw.Padding(
              padding: const pw.EdgeInsets.fromLTRB(30, 20, 30, 26),
              child: _content(data, logoBytes, stampBytes),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _content(
    PrintDocumentData data,
    Uint8List? logoBytes,
    Uint8List? stampBytes,
  ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(child: _company(data, logoBytes)),
            pw.SizedBox(width: 16),
            _fiscalCard(data),
          ],
        ),
        pw.SizedBox(height: 13),
        _titleRule(data),
        pw.SizedBox(height: 10),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(child: _clientCard(data)),
            pw.SizedBox(width: 12),
            pw.Expanded(child: _projectCard(data)),
          ],
        ),
        if (_has(data.invoiceConcept)) ...[
          pw.SizedBox(height: 10),
          _conceptBand(data.invoiceConcept!),
        ],
        pw.SizedBox(height: 10),
        _itemsTable(data),
        pw.SizedBox(height: 12),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(child: _paymentAndBank(data)),
            pw.SizedBox(width: 18),
            _totalsCard(data),
          ],
        ),
        if (_has(data.notes)) ...[
          pw.SizedBox(height: 8),
          pw.Text(
            'Notas: ${data.notes}',
            style: const pw.TextStyle(fontSize: 8, color: _muted),
          ),
        ],
        pw.Spacer(),
        _signatures(data, stampBytes),
        if (_has(data.legalFooterText)) ...[
          pw.SizedBox(height: 8),
          pw.Text(
            data.legalFooterText!,
            textAlign: pw.TextAlign.center,
            maxLines: 3,
            style: const pw.TextStyle(fontSize: 7, color: _muted),
          ),
        ],
        if ((data.isPendingAccount || data.isProforma) &&
            _has(data.footerMessage)) ...[
          pw.SizedBox(height: 6),
          pw.Center(
            child: pw.Text(
              data.footerMessage!,
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(
                fontSize: 8,
                fontWeight: pw.FontWeight.bold,
                color: _muted,
              ),
            ),
          ),
        ],
      ],
    );
  }

  // ── Encabezado ──────────────────────────────────────────────────────────

  pw.Widget _company(PrintDocumentData data, Uint8List? logoBytes) {
    final b = data.branch;
    final contact = [
      if (_has(b.phone)) 'Tel. ${b.phone}',
      if (_has(b.email)) b.email!,
    ].join('  ·  ');
    final texts = pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          b.name.toUpperCase(),
          style: pw.TextStyle(
            fontSize: 19,
            fontWeight: pw.FontWeight.bold,
            color: _navy,
          ),
        ),
        if (_has(b.tagline))
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 2),
            child: pw.Text(
              b.tagline!,
              style: pw.TextStyle(
                fontSize: 8.5,
                fontWeight: pw.FontWeight.bold,
                color: _blue,
              ),
            ),
          ),
        pw.SizedBox(height: 5),
        if (_has(b.taxId))
          pw.RichText(
            text: pw.TextSpan(
              style: const pw.TextStyle(fontSize: 8.5, color: _ink),
              children: [
                pw.TextSpan(
                  text: 'RNC ',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                ),
                pw.TextSpan(text: b.taxId!),
              ],
            ),
          ),
        if (_has(b.address))
          pw.Text(
            b.address!.replaceAll('\n', ', '),
            style: const pw.TextStyle(fontSize: 8.5, color: _ink),
          ),
        if (contact.isNotEmpty)
          pw.Text(
            contact,
            style: const pw.TextStyle(fontSize: 8.5, color: _ink),
          ),
      ],
    );
    if (logoBytes == null) return texts;
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Image(
          pw.MemoryImage(logoBytes),
          width: 58,
          height: 58,
          fit: pw.BoxFit.contain,
        ),
        pw.SizedBox(width: 10),
        pw.Expanded(child: texts),
      ],
    );
  }

  pw.Widget _fiscalCard(PrintDocumentData data) {
    final pendingNcf = printPendingNcfNotice(data);
    pw.Widget row(String label, String value, {bool bold = false}) =>
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 4),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              _label(label),
              pw.Text(
                value,
                style: pw.TextStyle(
                  fontSize: 9,
                  color: _ink,
                  fontWeight: bold ? pw.FontWeight.bold : null,
                ),
              ),
            ],
          ),
        );

    return pw.Container(
      width: 178,
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _border, width: 0.8),
        borderRadius: pw.BorderRadius.circular(7),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: const pw.BoxDecoration(
              color: _navy,
              borderRadius: pw.BorderRadius.only(
                topLeft: pw.Radius.circular(6),
                topRight: pw.Radius.circular(6),
              ),
            ),
            child: pw.Text(
              printReceiptHeadline(data).toUpperCase(),
              style: pw.TextStyle(
                fontSize: 8,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
                letterSpacing: 0.4,
              ),
            ),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.fromLTRB(9, 2, 9, 7),
            child: pw.Column(
              children: [
                row('Nº factura', data.documentNumber, bold: true),
                if (_has(data.ncf))
                  row('NCF', data.ncf!, bold: true)
                else if (pendingNcf != null)
                  row('NCF', pendingNcf.replaceFirst('NCF: ', '')),
                if (data.ncfValidUntil != null)
                  row('Válida hasta', formatDate(data.ncfValidUntil)),
                row('Fecha', formatDate(data.issuedAt)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _titleRule(PrintDocumentData data) {
    final title = data.isPendingAccount
        ? 'CUENTA GUARDADA'
        : data.isProforma
            ? 'FACTURA PROFORMA'
            : (printDocumentTitle(data) == 'NOTA DE VENTA'
                ? 'NOTA DE VENTA'
                : 'FACTURA');
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Text(
          title,
          style: pw.TextStyle(
            fontSize: 16,
            fontWeight: pw.FontWeight.bold,
            color: _navy,
            letterSpacing: 3,
          ),
        ),
        pw.SizedBox(width: 10),
        pw.Expanded(child: pw.Container(height: 1.5, color: _navy)),
      ],
    );
  }

  // ── Cliente / Proyecto / Concepto ───────────────────────────────────────

  pw.Widget _card(String title, List<pw.Widget> children) {
    return pw.Container(
      padding: const pw.EdgeInsets.fromLTRB(10, 8, 10, 9),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _border, width: 0.8),
        borderRadius: pw.BorderRadius.circular(7),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            title.toUpperCase(),
            style: pw.TextStyle(
              fontSize: 8,
              fontWeight: pw.FontWeight.bold,
              color: _navy,
              letterSpacing: 0.5,
            ),
          ),
          ...children,
        ],
      ),
    );
  }

  pw.Widget _field(String label, String? value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 5),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _label(label),
          pw.SizedBox(height: 1),
          pw.Text(
            _has(value) ? value!.trim() : ' ',
            maxLines: 2,
            style: const pw.TextStyle(fontSize: 9, color: _ink),
          ),
        ],
      ),
    );
  }

  pw.Widget _clientCard(PrintDocumentData data) {
    final c = data.customer;
    return _card('Cliente', [
      _field('Nombre', c?.name ?? 'Consumidor final'),
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(child: _field('RNC / Cédula', c?.document)),
          pw.SizedBox(width: 8),
          pw.Expanded(child: _field('Teléfono', c?.phone)),
        ],
      ),
      _field('Dirección', c?.address?.replaceAll('\n', ', ')),
    ]);
  }

  pw.Widget _projectCard(PrintDocumentData data) {
    return _card('Proyecto', [
      _field('Nombre del proyecto', data.invoiceProject),
      _field('Localización', data.invoiceLocation),
    ]);
  }

  pw.Widget _conceptBand(String concept) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: pw.BoxDecoration(
        color: _tint,
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 1.5),
            child: _label('Concepto', color: _navy),
          ),
          pw.SizedBox(width: 8),
          pw.Expanded(
            child: pw.Text(
              concept.trim(),
              maxLines: 2,
              style: const pw.TextStyle(fontSize: 9, color: _ink),
            ),
          ),
        ],
      ),
    );
  }

  // ── Detalle ─────────────────────────────────────────────────────────────

  static const _colNo = 26.0;
  static const _colQty = 50.0;
  static const _colUnit = 50.0;
  static const _colPrice = 60.0;
  static const _colTotal = 70.0;

  pw.Widget _itemsTable(PrintDocumentData data) {
    pw.Widget cell(
      String text, {
      double? width,
      pw.TextAlign align = pw.TextAlign.left,
      bool header = false,
    }) {
      final child = pw.Text(
        text,
        textAlign: align,
        maxLines: header ? 1 : 2,
        style: header
            ? pw.TextStyle(
                fontSize: 7.5,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
                letterSpacing: 0.4,
              )
            : const pw.TextStyle(fontSize: 8.5, color: _ink),
      );
      final padded = pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 5),
        child: child,
      );
      return width == null
          ? pw.Expanded(child: padded)
          : pw.SizedBox(width: width, child: padded);
    }

    pw.Widget row(List<pw.Widget> cells, {required int index}) {
      return pw.Container(
        constraints: const pw.BoxConstraints(minHeight: 16.5),
        padding: const pw.EdgeInsets.symmetric(vertical: 3),
        decoration: pw.BoxDecoration(
          color: index.isOdd ? _zebra : null,
          border: const pw.Border(
            bottom: pw.BorderSide(color: _rule, width: 0.6),
          ),
        ),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: cells,
        ),
      );
    }

    final header = pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 5),
      decoration: const pw.BoxDecoration(
        color: _navy,
        borderRadius: pw.BorderRadius.only(
          topLeft: pw.Radius.circular(4),
          topRight: pw.Radius.circular(4),
        ),
      ),
      child: pw.Row(
        children: [
          cell('Nº', width: _colNo, align: pw.TextAlign.center, header: true),
          cell('DESCRIPCIÓN', header: true),
          cell('CANT.', width: _colQty, align: pw.TextAlign.right, header: true),
          cell('UNIDAD', width: _colUnit, align: pw.TextAlign.center, header: true),
          cell('P.U.', width: _colPrice, align: pw.TextAlign.right, header: true),
          cell('VALOR', width: _colTotal, align: pw.TextAlign.right, header: true),
        ],
      ),
    );

    final rows = <pw.Widget>[];
    for (var i = 0; i < data.items.length; i++) {
      final item = data.items[i];
      final description = [
        item.descriptionTitle,
        if (item.imeis.isNotEmpty) 'IMEI: ${item.imeis.join(', ')}',
      ].join('\n');
      rows.add(row([
        cell('${i + 1}', width: _colNo, align: pw.TextAlign.center),
        cell(description),
        cell(moneyPlain(item.quantity), width: _colQty, align: pw.TextAlign.right),
        cell(item.unitLabel ?? '', width: _colUnit, align: pw.TextAlign.center),
        cell(moneyPlain(item.unitPrice), width: _colPrice, align: pw.TextAlign.right),
        // Valor = base de la línea (sin ITBIS): el ITBIS va abajo, en totales.
        cell(moneyPlain(item.lineSubtotal), width: _colTotal, align: pw.TextAlign.right),
      ], index: i));
    }
    for (var i = data.items.length; i < _minTableRows; i++) {
      rows.add(row([pw.SizedBox(height: 10)], index: i));
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [header, ...rows],
    );
  }

  // ── Pago, banco y totales ───────────────────────────────────────────────

  pw.Widget _paymentAndBank(PrintDocumentData data) {
    final used = data.payments.map((p) => p.method.toLowerCase()).toSet();
    final isCredit = data.paymentTermsLabel == 'CRÉDITO';
    final options = [
      'Efectivo',
      'Transferencia',
      'Tarjeta',
      if (used.contains('otro')) 'Otro',
      if (isCredit) 'Crédito',
    ];

    pw.Widget pill(String label) {
      final checked = used.contains(label.toLowerCase()) ||
          (label == 'Crédito' && isCredit);
      return pw.Container(
        margin: const pw.EdgeInsets.only(right: 5, bottom: 4),
        padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: pw.BoxDecoration(
          color: checked ? _tint : null,
          border: pw.Border.all(
            color: checked ? _navy : _border,
            width: checked ? 1.1 : 0.8,
          ),
          borderRadius: pw.BorderRadius.circular(4),
        ),
        child: pw.Row(
          mainAxisSize: pw.MainAxisSize.min,
          children: [
            pw.Container(
              width: 9,
              height: 9,
              padding: const pw.EdgeInsets.all(1.2),
              decoration: pw.BoxDecoration(
                color: checked ? _navy : null,
                border: checked
                    ? null
                    : pw.Border.all(color: _muted, width: 1),
                borderRadius: pw.BorderRadius.circular(2),
              ),
              child: checked ? pw.SvgImage(svg: _checkSvg) : null,
            ),
            pw.SizedBox(width: 4),
            pw.Text(
              label,
              style: pw.TextStyle(
                fontSize: 8.5,
                color: checked ? _navy : _ink,
                fontWeight: checked ? pw.FontWeight.bold : null,
              ),
            ),
          ],
        ),
      );
    }

    final bankLines = (data.branch.bankInfo ?? '')
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList(growable: false);

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _label('Forma de pago'),
        pw.SizedBox(height: 5),
        pw.Wrap(children: options.map(pill).toList(growable: false)),
        if (bankLines.isNotEmpty) ...[
          pw.SizedBox(height: 8),
          pw.Container(
            padding: const pw.EdgeInsets.only(left: 8, top: 1, bottom: 1),
            decoration: const pw.BoxDecoration(
              border: pw.Border(left: pw.BorderSide(color: _blue, width: 2.2)),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _label('Depositar en cuenta'),
                pw.SizedBox(height: 2),
                for (var i = 0; i < bankLines.length; i++)
                  pw.Text(
                    bankLines[i],
                    style: pw.TextStyle(
                      fontSize: 8.5,
                      color: _ink,
                      fontWeight: i == 0 ? pw.FontWeight.bold : null,
                    ),
                  ),
              ],
            ),
          ),
        ],
        if (_has(data.observation)) ...[
          pw.SizedBox(height: 6),
          pw.Text(
            data.observation!,
            maxLines: 3,
            style: const pw.TextStyle(fontSize: 7.5, color: _muted),
          ),
        ],
      ],
    );
  }

  pw.Widget _totalsCard(PrintDocumentData data) {
    final totals = data.totals;
    double taxOf(bool norma) => data.items
        .where((i) => i.isItbisNorma0707 == norma)
        .fold<double>(0, (s, i) => s + i.lineTax);
    final normaTax = taxOf(true);
    final regularTax = taxOf(false);

    // La primera línea no lleva raya arriba: la da el borde del cuadro.
    var first = true;
    pw.Widget line(String label, String value, {String? note}) {
      final top = first;
      first = false;
      return pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: top
              ? null
              : const pw.BoxDecoration(
                  border: pw.Border(
                    top: pw.BorderSide(color: _rule, width: 0.6),
                  ),
                ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.RichText(
                text: pw.TextSpan(
                  style: const pw.TextStyle(fontSize: 9, color: _ink),
                  children: [
                    pw.TextSpan(text: label),
                    if (note != null)
                      pw.TextSpan(
                        text: ' $note',
                        style: const pw.TextStyle(fontSize: 7.5, color: _muted),
                      ),
                  ],
                ),
              ),
              pw.Text(value, style: const pw.TextStyle(fontSize: 9, color: _ink)),
            ],
          ),
        );
    }

    final lines = <pw.Widget>[
      line('Sub-total', moneyPlain(totals.subtotal)),
      if (totals.discount > 0.0049)
        line('Descuento', '-${moneyPlain(totals.discount)}'),
      if (data.showTax && regularTax > 0.0049)
        line('ITBIS', moneyPlain(regularTax)),
      if (data.showTax && normaTax > 0.0049)
        line('ITBIS 18%', moneyPlain(normaTax), note: '(Norma 07-2007)'),
    ];

    return pw.Container(
      width: 205,
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _border, width: 0.8),
        borderRadius: pw.BorderRadius.circular(7),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          ...lines,
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: const pw.BoxDecoration(
              color: _navy,
              borderRadius: pw.BorderRadius.only(
                bottomLeft: pw.Radius.circular(6),
                bottomRight: pw.Radius.circular(6),
              ),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Text(
                  'TOTAL RD\$',
                  style: pw.TextStyle(
                    fontSize: 9,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.white,
                    letterSpacing: 0.4,
                  ),
                ),
                pw.Text(
                  moneyPlain(totals.total),
                  style: pw.TextStyle(
                    fontSize: 13,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.white,
                  ),
                ),
              ],
            ),
          ),
          if (totals.balance > 0.0049)
            pw.Padding(
              padding: const pw.EdgeInsets.fromLTRB(10, 4, 10, 5),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'Balance pendiente',
                    style: const pw.TextStyle(fontSize: 8.5, color: _ink),
                  ),
                  pw.Text(
                    moneyPlain(totals.balance),
                    style: pw.TextStyle(
                      fontSize: 8.5,
                      fontWeight: pw.FontWeight.bold,
                      color: _ink,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ── Firmas y e-CF ───────────────────────────────────────────────────────

  pw.Widget _signatures(PrintDocumentData data, Uint8List? stampBytes) {
    pw.Widget slot(String label, {pw.Widget? above, String? name}) {
      return pw.Column(
        children: [
          pw.SizedBox(
            height: 70,
            child: pw.Center(child: above ?? pw.SizedBox()),
          ),
          pw.Container(height: 0.8, color: _ink),
          pw.SizedBox(height: 3),
          if (_has(name))
            pw.Text(name!, style: const pw.TextStyle(fontSize: 8.5, color: _ink)),
          _label(label),
        ],
      );
    }

    final ecf = data.ecf;
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: [
        pw.Expanded(
          child: slot(
            'Preparado por',
            above: stampBytes == null
                ? null
                : pw.Image(
                    pw.MemoryImage(stampBytes),
                    height: 68,
                    fit: pw.BoxFit.contain,
                  ),
            name: data.branch.signatoryName,
          ),
        ),
        pw.SizedBox(width: 45),
        pw.Expanded(child: slot('Recibido por')),
        // e-CF: la representación impresa lleva el QR de verificación DGII.
        if (ecf != null && ecf.hasQr) ...[
          pw.SizedBox(width: 18),
          pw.Column(
            children: [
              pw.BarcodeWidget(
                barcode: pw.Barcode.qrCode(),
                data: ecf.qrUrl!,
                width: 78,
                height: 78,
              ),
              if (_has(ecf.securityCode))
                pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 3),
                  child: pw.Text(
                    'Código de Seguridad: ${ecf.securityCode}',
                    style: const pw.TextStyle(fontSize: 7),
                  ),
                ),
              if (ecf.signedAt != null)
                pw.Text(
                  'Firma Digital: ${formatDateTime(ecf.signedAt!)}',
                  style: const pw.TextStyle(fontSize: 7, color: _muted),
                ),
            ],
          ),
        ] else if (ecf?.statusMessage != null) ...[
          pw.SizedBox(width: 18),
          pw.SizedBox(
            width: 110,
            child: pw.Text(
              ecf!.statusMessage!,
              style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
            ),
          ),
        ],
      ],
    );
  }

  pw.Widget _label(String text, {PdfColor color = _muted}) => pw.Text(
        text.toUpperCase(),
        style: pw.TextStyle(
          fontSize: 6.8,
          fontWeight: pw.FontWeight.bold,
          color: color,
          letterSpacing: 0.6,
        ),
      );
}

bool _has(String? value) => value != null && value.trim().isNotEmpty;
