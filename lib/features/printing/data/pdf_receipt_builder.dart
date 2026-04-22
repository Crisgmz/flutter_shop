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
