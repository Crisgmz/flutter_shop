import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../shared/formatters/formatters.dart';
import 'printing_models.dart';

class PdfReceiptBuilder {
  const PdfReceiptBuilder();

  Future<Uint8List> buildBytes(
    PrintDocumentData data, {
    PdfPageFormat pageFormat = PdfPageFormat.a4,
  }) async {
    final doc = pw.Document(
      title: data.documentNumber,
      author: data.branch.name,
    );

    doc.addPage(
      pw.Page(
        pageFormat: pageFormat,
        margin: const pw.EdgeInsets.all(40),
        build: (context) => _buildContent(data),
      ),
    );

    return doc.save();
  }

  /// Construye el PDF en formato ticket térmico ~80mm de ancho.
  /// Layout vertical: logo → empresa centrada → bloque metadata derecha →
  /// "Factura a:" → cliente → items → totales → barcode.
  Future<Uint8List> buildThermalBytes(PrintDocumentData data) async {
    final doc = pw.Document(
      title: data.documentNumber,
      author: data.branch.name,
    );

    // 80mm = 226.77pt; usamos altura infinita (roll continuo).
    final format = PdfPageFormat(
      80 * PdfPageFormat.mm,
      double.infinity,
      marginAll: 8 * PdfPageFormat.mm,
    );

    doc.addPage(
      pw.Page(
        pageFormat: format,
        build: (context) => _buildThermalContent(data),
      ),
    );

    return doc.save();
  }

  pw.Widget _buildContent(PrintDocumentData data) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _header(data),
        pw.SizedBox(height: 20),
        if (data.customer != null) ...[
          _customerBlock(data.customer!),
          pw.SizedBox(height: 16),
        ],
        _itemsTable(data),
        pw.SizedBox(height: 12),
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: _totalsBlock(data),
        ),
        if (_hasText(data.notes)) ...[
          pw.SizedBox(height: 16),
          pw.Text(
            'Notas: ${data.notes}',
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
          ),
        ],
        pw.Spacer(),
        if (_hasText(data.footerMessage))
          pw.Center(
            child: pw.Text(
              data.footerMessage!,
              style: pw.TextStyle(
                fontSize: 10,
                color: PdfColors.grey600,
                fontStyle: pw.FontStyle.italic,
              ),
            ),
          ),
      ],
    );
  }

  // ────────────────────────────────────────────────────────────────────────
  // Thermal (80mm) layout — sigue el formato del ticket de la foto.
  // ────────────────────────────────────────────────────────────────────────

  pw.Widget _buildThermalContent(PrintDocumentData data) {
    final mutedColor = PdfColors.grey700;
    final base = const pw.TextStyle(fontSize: 8.5);
    final muted = pw.TextStyle(fontSize: 8.5, color: mutedColor);
    final bold = pw.TextStyle(
      fontSize: 8.5,
      fontWeight: pw.FontWeight.bold,
    );
    final big = pw.TextStyle(
      fontSize: 11,
      fontWeight: pw.FontWeight.bold,
    );

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        // ── 1) Encabezado centrado: logo + empresa + dirección + teléfono ──
        if (data.branch.logoBytes != null)
          pw.Center(
            child: pw.SizedBox(
              width: 60,
              height: 60,
              child: pw.Image(pw.MemoryImage(
                Uint8List.fromList(data.branch.logoBytes!),
              )),
            ),
          ),
        if (data.branch.logoBytes != null) pw.SizedBox(height: 4),
        pw.Center(
          child: pw.Text(
            data.branch.name.toUpperCase(),
            textAlign: pw.TextAlign.center,
            style: big,
          ),
        ),
        if (_hasText(data.branch.address))
          pw.Center(
            child: pw.Text(
              data.branch.address!,
              textAlign: pw.TextAlign.center,
              style: base,
            ),
          ),
        if (_hasText(data.branch.phone))
          pw.Center(
            child: pw.Text(
              data.branch.phone!,
              textAlign: pw.TextAlign.center,
              style: base,
            ),
          ),
        if (_hasText(data.branch.taxId))
          pw.Center(
            child: pw.Text(
              'RNC ${data.branch.taxId}',
              textAlign: pw.TextAlign.center,
              style: base,
            ),
          ),
        _thermalDashedDivider(),

        // ── 2) Fecha centrada ─────────────────────────────────────────────
        pw.Center(
          child: pw.Text(
            formatDateTime(data.issuedAt),
            style: base,
          ),
        ),
        _thermalDashedDivider(),

        // ── 3) Metadata centrada: serie, caja, tipo precio, empleado, NCF ─
        _thermalMetaRow('Serie y Número:', data.documentNumber, bold: bold, base: base),
        if (_hasText(data.cashRegisterName))
          _thermalMetaRow('Caja registradora:', data.cashRegisterName!, bold: bold, base: base),
        if (_hasText(data.priceTierLabel))
          _thermalMetaRow('Tipo de precio:', data.priceTierLabel!, bold: bold, base: base),
        if (_hasText(data.cashierName))
          _thermalMetaRow('Empleado:', data.cashierName!, bold: bold, base: base),
        if (_hasText(data.ncf))
          _thermalMetaRow('NCF:', data.ncf!, bold: bold, base: base),
        if (_hasText(data.receiptTypeLabel))
          _thermalMetaRow('Tipo comprobante:', data.receiptTypeLabel!, bold: bold, base: base),

        // ── 4) Bloque cliente "Factura a:" ────────────────────────────────
        if (data.customer != null) ...[
          _thermalDashedDivider(),
          pw.Text('Factura a:', style: bold),
          pw.SizedBox(height: 2),
          pw.Text('Cliente: ${data.customer!.name}', style: base),
          if (_hasText(data.customer!.address))
            pw.Text('Dirección : ${data.customer!.address}', style: base),
          if (_hasText(data.customer!.document))
            pw.Text('Doc: ${data.customer!.document}', style: base),
          if (_hasText(data.customer!.phone))
            pw.Text('Teléfono : ${data.customer!.phone}', style: base),
        ],

        // ── 5) Tabla de items ─────────────────────────────────────────────
        _thermalDashedDivider(),
        _thermalItemsTable(data, base: base, bold: bold, muted: muted),

        // ── 6) Totales alineados a la derecha ─────────────────────────────
        _thermalDashedDivider(),
        _thermalTotals(data, base: base, bold: bold),

        // ── 7) Notas / footer / barcode ───────────────────────────────────
        if (_hasText(data.notes)) ...[
          _thermalDashedDivider(),
          pw.Text('Notas: ${data.notes}', style: muted),
        ],
        if (_hasText(data.footerMessage)) ...[
          pw.SizedBox(height: 6),
          pw.Center(
            child: pw.Text(
              data.footerMessage!,
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(
                fontSize: 8.5,
                fontStyle: pw.FontStyle.italic,
                color: mutedColor,
              ),
            ),
          ),
        ],
        if (data.showBarcode) ...[
          _thermalDashedDivider(),
          pw.Center(
            child: pw.BarcodeWidget(
              barcode: pw.Barcode.code128(),
              data: data.documentNumber,
              width: 180,
              height: 40,
              drawText: true,
              textStyle: const pw.TextStyle(fontSize: 8),
            ),
          ),
        ],
      ],
    );
  }

  /// Separador discontinuo estilo ticket térmico clásico (- - - - -).
  /// Se renderiza como texto plano para no depender de `BorderStyle.dashed`
  /// (que no existe en `pdf ^3.12`).
  pw.Widget _thermalDashedDivider() {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 4),
      child: pw.Text(
        '- ' * 32,
        textAlign: pw.TextAlign.center,
        overflow: pw.TextOverflow.clip,
        style: pw.TextStyle(
          fontSize: 7,
          color: PdfColors.grey600,
        ),
      ),
    );
  }

  pw.Widget _thermalMetaRow(
    String label,
    String value, {
    required pw.TextStyle bold,
    required pw.TextStyle base,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1),
      child: pw.Center(
        child: pw.RichText(
          textAlign: pw.TextAlign.center,
          text: pw.TextSpan(
            children: [
              pw.TextSpan(text: '$label  ', style: bold),
              pw.TextSpan(text: value, style: base),
            ],
          ),
        ),
      ),
    );
  }

  pw.Widget _thermalItemsTable(
    PrintDocumentData data, {
    required pw.TextStyle base,
    required pw.TextStyle bold,
    required pw.TextStyle muted,
  }) {
    return pw.Table(
      columnWidths: const {
        0: pw.FlexColumnWidth(1),   // Nombre (toma el espacio restante)
        1: pw.FixedColumnWidth(50), // Precio (suficiente para "RD$ 1,000.00")
        2: pw.FixedColumnWidth(32), // Cant. — centrado, con aire a los lados
        3: pw.FixedColumnWidth(55), // Total
      },
      children: [
        // Header
        pw.TableRow(
          decoration: const pw.BoxDecoration(
            border: pw.Border(
              bottom: pw.BorderSide(color: PdfColors.grey700, width: 0.5),
            ),
          ),
          children: [
            _thermalCell('Nombre', style: bold),
            _thermalCell('Precio', style: bold, align: pw.Alignment.centerRight),
            _thermalCell('Cant.', style: bold, align: pw.Alignment.center),
            _thermalCell('Total', style: bold, align: pw.Alignment.centerRight),
          ],
        ),
        for (final item in data.items)
          pw.TableRow(
            children: [
              _thermalCell(item.description, style: base),
              _thermalCell(
                money(item.unitPrice),
                style: base,
                align: pw.Alignment.centerRight,
              ),
              _thermalCell(
                _qty(item.quantity),
                style: base,
                align: pw.Alignment.center,
              ),
              _thermalCell(
                money(item.lineTotal),
                style: base,
                align: pw.Alignment.centerRight,
              ),
            ],
          ),
      ],
    );
  }

  pw.Widget _thermalCell(
    String text, {
    required pw.TextStyle style,
    pw.Alignment align = pw.Alignment.centerLeft,
  }) {
    return pw.Padding(
      // Padding interno mayor: separa visualmente columnas (antes 1pt
      // hacía que "2" tocara "RD$ 1,100.00").
      padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 3),
      child: pw.Align(
        alignment: align,
        child: pw.Text(text, style: style),
      ),
    );
  }

  pw.Widget _thermalTotals(
    PrintDocumentData data, {
    required pw.TextStyle base,
    required pw.TextStyle bold,
  }) {
    pw.Widget line(String label, String value, {bool emphasized = false}) {
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 1),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.end,
          children: [
            pw.Text(label, style: emphasized ? bold : base),
            pw.SizedBox(width: 12),
            pw.SizedBox(
              width: 80,
              child: pw.Text(
                value,
                textAlign: pw.TextAlign.right,
                style: emphasized ? bold : base,
              ),
            ),
          ],
        ),
      );
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        line('Subtotal', money(data.totals.subtotal)),
        if (data.totals.discount > 0)
          line('Descuento', '-${money(data.totals.discount)}'),
        if (data.totals.serviceCharge > 0)
          line('Servicio', money(data.totals.serviceCharge)),
        if (data.totals.tax > 0) line('ITBIS', money(data.totals.tax)),
        line('Total', money(data.totals.total), emphasized: true),
        if (data.changeAmount != null && data.changeAmount! >= 0)
          line('Cambio', money(data.changeAmount!)),
        if (data.totals.balance > 0)
          line('Pendiente', money(data.totals.balance), emphasized: true),
        for (final payment in data.payments)
          line(payment.method, money(payment.amount)),
      ],
    );
  }

  pw.Widget _header(PrintDocumentData data) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                data.branch.name,
                style: pw.TextStyle(
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              if (_hasText(data.branch.address))
                pw.Text(
                  data.branch.address!,
                  style: const pw.TextStyle(
                    fontSize: 10,
                    color: PdfColors.grey700,
                  ),
                ),
              if (_hasText(data.branch.phone))
                pw.Text(
                  'Tel: ${data.branch.phone}',
                  style: const pw.TextStyle(
                    fontSize: 10,
                    color: PdfColors.grey700,
                  ),
                ),
              if (_hasText(data.branch.taxId))
                pw.Text(
                  'RNC: ${data.branch.taxId}',
                  style: const pw.TextStyle(
                    fontSize: 10,
                    color: PdfColors.grey700,
                  ),
                ),
            ],
          ),
        ),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text(
              _docTypeLabel(data.documentType),
              style: pw.TextStyle(
                fontSize: 20,
                fontWeight: pw.FontWeight.bold,
                color: const PdfColor.fromInt(0xFF2563EB),
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              data.documentNumber,
              style: pw.TextStyle(
                fontSize: 11,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.Text(
              formatDateTime(data.issuedAt),
              style: const pw.TextStyle(
                fontSize: 10,
                color: PdfColors.grey700,
              ),
            ),
            if (_hasText(data.receiptTypeLabel))
              pw.Text(
                data.receiptTypeLabel!,
                style: const pw.TextStyle(
                  fontSize: 10,
                  color: PdfColors.grey700,
                ),
              ),
            if (_hasText(data.ncf))
              pw.Text(
                'NCF: ${data.ncf}',
                style: const pw.TextStyle(
                  fontSize: 10,
                  color: PdfColors.grey700,
                ),
              ),
            if (_hasText(data.cashierName))
              pw.Text(
                'Cajero: ${data.cashierName}',
                style: const pw.TextStyle(
                  fontSize: 10,
                  color: PdfColors.grey700,
                ),
              ),
            if (_hasText(data.referenceNumber))
              pw.Text(
                data.referenceNumber!,
                style: const pw.TextStyle(
                  fontSize: 10,
                  color: PdfColors.grey600,
                ),
              ),
          ],
        ),
      ],
    );
  }

  pw.Widget _customerBlock(PrintParty customer) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'DATOS DEL CLIENTE',
            style: pw.TextStyle(
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.grey600,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            customer.name,
            style: pw.TextStyle(
              fontSize: 11,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          if (_hasText(customer.document))
            pw.Text(
              'Doc: ${customer.document}',
              style: const pw.TextStyle(
                fontSize: 10,
                color: PdfColors.grey700,
              ),
            ),
          if (_hasText(customer.address))
            pw.Text(
              customer.address!,
              style: const pw.TextStyle(
                fontSize: 10,
                color: PdfColors.grey700,
              ),
            ),
          if (_hasText(customer.phone))
            pw.Text(
              'Tel: ${customer.phone}',
              style: const pw.TextStyle(
                fontSize: 10,
                color: PdfColors.grey700,
              ),
            ),
          if (_hasText(customer.email))
            pw.Text(
              customer.email!,
              style: const pw.TextStyle(
                fontSize: 10,
                color: PdfColors.grey700,
              ),
            ),
        ],
      ),
    );
  }

  pw.Widget _itemsTable(PrintDocumentData data) {
    const headerStyle = pw.TextStyle(fontSize: 10, color: PdfColors.grey800);
    const cellStyle = pw.TextStyle(fontSize: 10);

    return pw.Table(
      border: pw.TableBorder(
        bottom: const pw.BorderSide(color: PdfColors.grey400),
        horizontalInside: const pw.BorderSide(
          color: PdfColors.grey200,
          width: 0.5,
        ),
      ),
      columnWidths: const {
        0: pw.FlexColumnWidth(4),
        1: pw.FixedColumnWidth(50),
        2: pw.FixedColumnWidth(72),
        3: pw.FixedColumnWidth(72),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(
            border: pw.Border(
              bottom: pw.BorderSide(color: PdfColors.grey800, width: 1.5),
            ),
          ),
          children: [
            _tableCell(
              'Descripción',
              style: pw.TextStyle(
                fontSize: 10,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.grey800,
              ),
            ),
            _tableCell(
              'Cant.',
              style: pw.TextStyle(
                fontSize: 10,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.grey800,
              ),
              align: pw.Alignment.centerRight,
            ),
            _tableCell(
              'Precio unit.',
              style: pw.TextStyle(
                fontSize: 10,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.grey800,
              ),
              align: pw.Alignment.centerRight,
            ),
            _tableCell(
              'Total',
              style: pw.TextStyle(
                fontSize: 10,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.grey800,
              ),
              align: pw.Alignment.centerRight,
            ),
          ],
        ),
        for (int i = 0; i < data.items.length; i++)
          pw.TableRow(
            decoration: i.isOdd
                ? const pw.BoxDecoration(color: PdfColors.grey50)
                : null,
            children: [
              _tableCell(data.items[i].description, style: cellStyle),
              _tableCell(
                _qty(data.items[i].quantity),
                style: headerStyle,
                align: pw.Alignment.centerRight,
              ),
              _tableCell(
                money(data.items[i].unitPrice),
                style: cellStyle,
                align: pw.Alignment.centerRight,
              ),
              _tableCell(
                money(data.items[i].lineTotal),
                style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                ),
                align: pw.Alignment.centerRight,
              ),
            ],
          ),
      ],
    );
  }

  pw.Widget _tableCell(
    String text, {
    pw.TextStyle? style,
    pw.Alignment? align,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 4),
      child: pw.Align(
        alignment: align ?? pw.Alignment.centerLeft,
        child: pw.Text(text, style: style),
      ),
    );
  }

  pw.Widget _totalsBlock(PrintDocumentData data) {
    return pw.SizedBox(
      width: 190,
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          _totalLine('Subtotal', money(data.totals.subtotal)),
          if (data.totals.discount > 0)
            _totalLine('Descuento', '-${money(data.totals.discount)}'),
          if (data.totals.serviceCharge > 0)
            _totalLine('Ley / Servicio', money(data.totals.serviceCharge)),
          _totalLine('ITBIS', money(data.totals.tax)),
          pw.Divider(color: PdfColors.grey400, height: 8),
          _totalLine(
            'TOTAL',
            money(data.totals.total),
            bold: true,
            large: true,
          ),
          if (data.totals.paid > 0)
            _totalLine('Pagado', money(data.totals.paid)),
          if (data.totals.balance > 0)
            _totalLine(
              'Balance pendiente',
              money(data.totals.balance),
              bold: true,
            ),
          if (data.payments.isNotEmpty) ...[
            pw.SizedBox(height: 6),
            for (final p in data.payments)
              _totalLine(p.method, money(p.amount)),
          ],
        ],
      ),
    );
  }

  pw.Widget _totalLine(
    String label,
    String value, {
    bool bold = false,
    bool large = false,
  }) {
    final fontSize = large ? 13.0 : 10.0;
    final weight = bold ? pw.FontWeight.bold : null;

    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(
              fontSize: fontSize,
              fontWeight: weight,
              color: PdfColors.grey700,
            ),
          ),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: fontSize,
              fontWeight: weight,
              color: large
                  ? const PdfColor.fromInt(0xFF2563EB)
                  : PdfColors.grey800,
            ),
          ),
        ],
      ),
    );
  }
}

String _docTypeLabel(PrintDocumentType type) {
  return switch (type) {
    PrintDocumentType.quote => 'COTIZACIÓN',
    PrintDocumentType.fiscalInvoice => 'FACTURA FISCAL',
    PrintDocumentType.saleReceipt => 'RECIBO DE VENTA',
    PrintDocumentType.cashClose => 'CIERRE DE CAJA',
    PrintDocumentType.purchaseOrder => 'ORDEN DE COMPRA',
    PrintDocumentType.creditNote => 'NOTA DE CRÉDITO',
  };
}

bool _hasText(String? value) => value != null && value.trim().isNotEmpty;

String _qty(double value) {
  if (value == value.roundToDouble()) return value.toStringAsFixed(0);
  return value.toStringAsFixed(2);
}
