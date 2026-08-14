import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../features/printing/data/printing.dart';
import '../formatters/formatters.dart';
import 'app_snackbar.dart';

class PrintReceiptDialog extends StatefulWidget {
  const PrintReceiptDialog({super.key, required this.printData});

  final PreparedPrintJobData printData;

  static Future<void> show(BuildContext context, PreparedPrintJobData data) {
    return showDialog(
      context: context,
      builder: (_) => PrintReceiptDialog(printData: data),
    );
  }

  @override
  State<PrintReceiptDialog> createState() => _PrintReceiptDialogState();
}

class _PrintReceiptDialogState extends State<PrintReceiptDialog> {
  late PrintPaperSize _selectedSize;

  @override
  void initState() {
    super.initState();
    _selectedSize = widget.printData.paperSize;
  }

  String get _docTitle => switch (widget.printData.document.documentType) {
        PrintDocumentType.quote => 'Cotización',
        PrintDocumentType.fiscalInvoice => 'Factura Fiscal',
        PrintDocumentType.purchaseOrder => 'Orden de compra',
        PrintDocumentType.paymentReceipt => 'Recibo de abono',
        PrintDocumentType.expenseVoucher => 'Comprobante de gasto',
        _ => 'Recibo de venta',
      };

  /// Disparador del botón Imprimir.
  ///
  /// Importante para Flutter Web: NO hacemos Navigator.pop antes de llamar
  /// a `Printing.layoutPdf`. Antes lo hacíamos y en algunos navegadores
  /// (Chrome/Edge en Windows 10 con el bloqueador de pop-ups activo) el
  /// "user gesture" del click se consideraba consumido por el pop y la
  /// ventana de impresión nunca aparecía — sin error visible.
  ///
  /// Ahora:
  ///   1. Llamamos `layoutPdf` directamente en el callback del click.
  ///   2. Capturamos cualquier excepción y la mostramos con AppSnackBar
  ///      (antes una falla era completamente silenciosa).
  ///   3. Si retorna false (usuario canceló o el navegador bloqueó la
  ///      ventana), mostramos un hint sobre el bloqueador de pop-ups.
  ///   4. Solo cerramos el diálogo si la operación se completó OK.
  Future<void> _onPrintPressed(BuildContext context) async {
    final doc = widget.printData.document;
    final name = doc.documentNumber;
    final useThermal = _selectedSize == PrintPaperSize.thermal80mm;
    final navigator = Navigator.of(context);
    final messengerContext = context;

    try {
      final ok = await Printing.layoutPdf(
        name: name,
        onLayout: (format) => useThermal
            ? const PdfReceiptBuilder().buildThermalBytes(doc)
            : const PdfReceiptBuilder().buildBytes(doc, pageFormat: format),
      );
      if (!ok) {
        if (messengerContext.mounted) {
          AppSnackBar.info(
            messengerContext,
            'No se abrió la ventana de impresión. Si tu navegador la bloqueó, '
            'permite las ventanas emergentes para este sitio.',
          );
        }
        return;
      }
      if (navigator.mounted) navigator.pop();
    } catch (error) {
      if (messengerContext.mounted) {
        AppSnackBar.error(messengerContext, 'No se pudo imprimir', error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isThermal = _selectedSize == PrintPaperSize.thermal80mm;

    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      title: Row(
        children: [
          Expanded(
            child: Text(
              'Vista previa · $_docTitle',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
          SegmentedButton<PrintPaperSize>(
            style: SegmentedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              textStyle: const TextStyle(fontSize: 12),
            ),
            segments: const [
              ButtonSegment(
                value: PrintPaperSize.thermal80mm,
                label: Text('Ticket'),
                icon: Icon(Icons.receipt_outlined, size: 14),
              ),
              ButtonSegment(
                value: PrintPaperSize.a4,
                label: Text('A4'),
                icon: Icon(Icons.article_outlined, size: 14),
              ),
            ],
            selected: {_selectedSize},
            onSelectionChanged: (set) =>
                setState(() => _selectedSize = set.first),
          ),
        ],
      ),
      content: SizedBox(
        width: isThermal ? 340 : 620,
        height: 480,
        child: ClipRect(
          child: isThermal
              ? _ThermalPreview(document: widget.printData.document)
              : _A4Preview(document: widget.printData.document),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cerrar'),
        ),
        FilledButton.icon(
          onPressed: () => _onPrintPressed(context),
          icon: const Icon(Icons.print_rounded, size: 18),
          label: const Text('Imprimir'),
        ),
      ],
    );
  }
}

// ── Thermal preview ─────────────────────────────────────────────────────────
//
// Refleja visualmente el PDF que produce `PdfReceiptBuilder.buildThermalBytes`:
// logo + empresa centrada → metadata derecha → "Factura a:" → tabla items →
// totales → código de barras. Lee directamente de `PrintDocumentData` para
// que el preview y el PDF se mantengan en sincronía.

class _ThermalPreview extends StatelessWidget {
  const _ThermalPreview({required this.document});

  final PrintDocumentData document;

  static const _mono = TextStyle(fontFamily: 'monospace', fontSize: 10.5);
  static const _monoBold = TextStyle(
    fontFamily: 'monospace',
    fontSize: 10.5,
    fontWeight: FontWeight.w800,
  );

  @override
  Widget build(BuildContext context) {
    final d = document;
    final customer = d.customer;
    return Container(
      color: _kPaperBg,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(8),
        child: Center(
          child: Container(
            width: 300,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            color: Colors.white,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header centrado
                if (d.branch.logoBytes != null) ...[
                  Center(
                    child: Image.memory(
                      Uint8List.fromList(d.branch.logoBytes!),
                      width: 60,
                      height: 60,
                      fit: BoxFit.contain,
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
                Text(
                  d.branch.name.toUpperCase(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (_hasText(d.branch.address))
                  Text(
                    d.branch.address!,
                    textAlign: TextAlign.center,
                    style: _mono,
                  ),
                if (_hasText(d.branch.phone))
                  Text(
                    d.branch.phone!,
                    textAlign: TextAlign.center,
                    style: _mono,
                  ),
                if (_hasText(d.branch.taxId))
                  Text(
                    'RNC ${d.branch.taxId}',
                    textAlign: TextAlign.center,
                    style: _mono,
                  ),
                const SizedBox(height: 10),

                // Título del documento: sin esto una cotización o una cuenta
                // guardada se leen como factura.
                const Divider(height: 12, color: _kInkMuted),
                Text(
                  printDocumentTitle(d),
                  textAlign: TextAlign.center,
                  style: _monoBold,
                ),
                const Divider(height: 12, color: _kInkMuted),

                // Fecha derecha
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(formatDateTime(d.issuedAt), style: _mono),
                ),
                const SizedBox(height: 8),

                // Metadata derecha
                _metaRow('Serie y Número:', d.documentNumber),
                if (_hasText(d.cashRegisterName))
                  _metaRow('Caja registradora:', d.cashRegisterName!),
                if (_hasText(d.priceTierLabel))
                  _metaRow('Tipo de precio:', d.priceTierLabel!),
                if (_hasText(d.cashierName))
                  _metaRow('Empleado:', d.cashierName!),
                if (_hasText(d.ncf)) _metaRow('NCF:', d.ncf!),
                if (d.ncfValidUntil != null)
                  _metaRow('NCF válido hasta:', formatDate(d.ncfValidUntil!)),
                if (_hasText(d.receiptTypeLabel))
                  _metaRow(_receiptTypeRowLabel(d), d.receiptTypeLabel!),
                if (printPendingNcfNotice(d) != null)
                  Text(
                    printPendingNcfNotice(d)!,
                    textAlign: TextAlign.center,
                    style: _monoBold,
                  ),
                const SizedBox(height: 10),

                // Cliente
                if (customer != null) ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(_customerBlockTitle(d), style: _monoBold),
                  ),
                  const SizedBox(height: 2),
                  Text('Cliente: ${customer.name}', style: _mono),
                  if (_hasText(customer.address))
                    Text('Dirección : ${customer.address}', style: _mono),
                  if (_hasText(customer.document))
                    Text('Doc: ${customer.document}', style: _mono),
                  if (_hasText(customer.phone))
                    Text('Teléfono : ${customer.phone}', style: _mono),
                  const SizedBox(height: 10),
                ],

                // Tabla items
                _itemsTable(d),
                const SizedBox(height: 10),

                // Totales
                _totals(d),

                if (_hasText(d.notes)) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Notas: ${d.notes}',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 9.5,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ],
                if (_hasText(d.footerMessage)) ...[
                  const SizedBox(height: 12),
                  Text(
                    d.footerMessage!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 10,
                      fontStyle: FontStyle.italic,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ],
                if (d.showBarcode) ...[
                  const SizedBox(height: 14),
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Column(
                        children: [
                          // Representación visual sencilla del barcode
                          // (en el PDF real se usa Code128).
                          SizedBox(
                            width: 180,
                            height: 30,
                            child: Row(
                              children: [
                                for (var i = 0; i < d.documentNumber.length; i++)
                                  Expanded(
                                    child: Container(
                                      color: d.documentNumber.codeUnitAt(i)
                                                  .isOdd
                                          ? Colors.black
                                          : Colors.white,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(d.documentNumber, style: _mono),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _metaRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(label, style: _monoBold),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: _mono,
            ),
          ),
        ],
      ),
    );
  }

  Widget _itemsTable(PrintDocumentData d) {
    return Table(
      columnWidths: const {
        0: FlexColumnWidth(5),
        1: FixedColumnWidth(56),
        2: FixedColumnWidth(38),
        3: FixedColumnWidth(60),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.top,
      children: [
        TableRow(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: Colors.grey.shade400, width: 0.6),
            ),
          ),
          children: const [
            _Cell('Nombre', style: _monoBold),
            _Cell('Precio', style: _monoBold, align: Alignment.centerRight),
            _Cell('Cant.', style: _monoBold, align: Alignment.center),
            _Cell('Total', style: _monoBold, align: Alignment.centerRight),
          ],
        ),
        for (final item in d.items)
          TableRow(
            children: [
              _Cell(item.description, style: _mono),
              _Cell(money(item.unitPrice),
                  style: _mono, align: Alignment.centerRight),
              _Cell(_qtyLabel(item.quantity),
                  style: _mono, align: Alignment.center),
              _Cell(money(item.lineTotal),
                  style: _mono, align: Alignment.centerRight),
            ],
          ),
      ],
    );
  }

  Widget _totals(PrintDocumentData d) {
    Widget line(String label, String value, {bool bold = false}) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(label, style: bold ? _monoBold : _mono),
            const SizedBox(width: 12),
            SizedBox(
              width: 90,
              child: Text(
                value,
                textAlign: TextAlign.right,
                style: bold ? _monoBold : _mono,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        line('Subtotal', money(d.totals.subtotal)),
        if (d.totals.discount > 0)
          line('Descuento', '-${money(d.totals.discount)}'),
        if (d.totals.serviceCharge > 0)
          line('Servicio', money(d.totals.serviceCharge)),
        if (d.totals.tax > 0) line('ITBIS', money(d.totals.tax)),
        line('Total', money(d.totals.total), bold: true),
        if (d.changeAmount != null && d.changeAmount! >= 0)
          line('Cambio', money(d.changeAmount!)),
        if (d.totals.balance > 0)
          line('Pendiente', money(d.totals.balance), bold: true),
        for (final payment in d.payments)
          line(payment.method, money(payment.amount)),
      ],
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell(this.text, {required this.style, this.align = Alignment.centerLeft});

  final String text;
  final TextStyle style;
  final Alignment align;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      child: Align(alignment: align, child: Text(text, style: style)),
    );
  }
}

// ── A4 preview ───────────────────────────────────────────────────────────────
//
// Replica en pantalla lo que imprime `PdfReceiptBuilder.buildBytes`: bloque
// fiscal (tipo de comprobante + NCF + vigencia) arriba a la derecha, banda de
// título, datos del cliente, tabla de 7 columnas y — al pie, a la izquierda de
// los totales — datos bancarios y nota legal. Lee de `PrintDocumentData` para
// no desincronizarse del PDF.

class _A4Preview extends StatelessWidget {
  const _A4Preview({required this.document});

  final PrintDocumentData document;

  @override
  Widget build(BuildContext context) {
    final d = document;
    return Container(
      color: _kPaperBg,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(8),
        child: Container(
          color: Colors.white,
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(d),
              const SizedBox(height: 14),
              _titleBand(d),
              const SizedBox(height: 12),
              _clientBlock(d),
              const SizedBox(height: 12),
              _itemsTable(d),
              const SizedBox(height: 14),
              _bankAndTotal(d),
              if (_hasText(d.notes)) ...[
                const SizedBox(height: 10),
                Text(
                  'Notas: ${d.notes}',
                  style: const TextStyle(fontSize: 10, color: _kInkMuted),
                ),
              ],
              const SizedBox(height: 14),
              _observationBlock(d),
              if (_hasText(d.footerMessage)) ...[
                const SizedBox(height: 10),
                Center(
                  child: Text(
                    d.footerMessage!,
                    style: const TextStyle(
                      fontSize: 10,
                      fontStyle: FontStyle.italic,
                      color: _kInkMuted,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Emisor a la izquierda; logo, nombre, número y bloque fiscal a la derecha.
  Widget _header(PrintDocumentData d) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_hasText(d.branch.taxId))
                Text(
                  'RNC: ${d.branch.taxId}',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              for (final line in _textLines(d.branch.address))
                Text(line, style: const TextStyle(fontSize: 10, color: _kInkMuted)),
              if (_hasText(d.branch.phone))
                Text(
                  d.branch.phone!,
                  style: const TextStyle(fontSize: 10, color: _kInkMuted),
                ),
              if (_hasText(d.branch.email))
                Text(
                  d.branch.email!,
                  style: const TextStyle(fontSize: 10, color: _kInkMuted),
                ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (d.branch.logoBytes != null) ...[
              Image.memory(
                Uint8List.fromList(d.branch.logoBytes!),
                height: 46,
                fit: BoxFit.contain,
              ),
              const SizedBox(height: 3),
            ],
            Text(
              d.branch.name,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: _kNavy,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              d.documentNumber,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: _kNavy,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              printReceiptHeadline(d),
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
            ),
            if (_hasText(d.ncf))
              Text(
                'NCF: ${d.ncf}',
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            if (printPendingNcfNotice(d) != null)
              Text(
                printPendingNcfNotice(d)!,
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 9, color: _kInkMuted),
              ),
            if (d.ncfValidUntil != null)
              Text(
                'NCF válido hasta ${formatDate(d.ncfValidUntil!)}',
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 9, color: _kInkMuted),
              ),
          ],
        ),
      ],
    );
  }

  Widget _titleBand(PrintDocumentData d) {
    return Column(
      children: [
        const Divider(height: 1, thickness: 0.8, color: _kHairline),
        const SizedBox(height: 7),
        Text(
          printDocumentTitle(d),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: _kNavy,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 7),
        const Divider(height: 1, thickness: 0.8, color: _kHairline),
      ],
    );
  }

  Widget _clientBlock(PrintDocumentData d) {
    final c = d.customer;
    Widget row(String label, String value) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 1.5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 96,
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Expanded(
              child: Text(value, style: const TextStyle(fontSize: 10)),
            ),
          ],
        ),
      );
    }

    // Misma etiqueta que el PDF: RNC salvo que el documento diga cédula/pasaporte.
    final docRaw = (c?.document ?? '').toLowerCase();
    final docLabel = docRaw.contains('céd') || docRaw.contains('ced')
        ? 'Cédula:'
        : docRaw.contains('pasa')
            ? 'Pasaporte:'
            : 'RNC:';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        row('Cliente:', c?.name ?? 'Consumidor Final'),
        row(docLabel, _docNumberOnly(c?.document) ?? 'N/A'),
        if (_hasText(c?.address)) row('Dirección:', c!.address!),
        if (_hasText(c?.phone)) row('Teléfono:', c!.phone!),
        if (_hasText(c?.email)) row('Email:', c!.email!),
        row('Fecha:', formatDate(d.issuedAt)),
        if (_hasText(d.paymentTermsLabel))
          row('Forma de pago:', d.paymentTermsLabel!),
        if (_hasText(d.referenceNumber)) row('', d.referenceNumber!),
      ],
    );
  }

  /// PRODUCTO/SERVICIO · PRECIO · CANTIDAD · DESCUENTO · SUBTOTAL · [ITBIS] ·
  /// VALOR TOTAL, igual que el PDF. SUBTOTAL es la base imponible de la línea.
  Widget _itemsTable(PrintDocumentData d) {
    final showTax = d.showTax;

    Widget header(String text, {TextAlign align = TextAlign.left}) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 3),
        child: Text(
          text,
          textAlign: align,
          style: const TextStyle(
            fontSize: 8.5,
            fontWeight: FontWeight.w700,
            color: _kInkMuted,
          ),
        ),
      );
    }

    Widget cell(String text, {TextAlign align = TextAlign.left, bool bold = false}) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 3),
        child: Text(
          text,
          textAlign: align,
          style: TextStyle(
            fontSize: 9.5,
            fontWeight: bold ? FontWeight.w700 : FontWeight.normal,
          ),
        ),
      );
    }

    // La nota de la línea va dentro de la misma celda de la descripción.
    Widget descriptionCell(PrintDocumentItem it) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(it.description, style: const TextStyle(fontSize: 9.5)),
            if (_hasText(it.notes))
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Text(
                  it.notes!,
                  style: const TextStyle(
                    fontSize: 8,
                    fontStyle: FontStyle.italic,
                    color: _kInkMuted,
                  ),
                ),
              ),
          ],
        ),
      );
    }

    final columnWidths = showTax
        ? const <int, TableColumnWidth>{
            0: FlexColumnWidth(3.4),
            1: FlexColumnWidth(1.35),
            2: FlexColumnWidth(1),
            3: FlexColumnWidth(1.35),
            4: FlexColumnWidth(1.4),
            5: FlexColumnWidth(1.15),
            6: FlexColumnWidth(1.5),
          }
        : const <int, TableColumnWidth>{
            0: FlexColumnWidth(3.4),
            1: FlexColumnWidth(1.45),
            2: FlexColumnWidth(1),
            3: FlexColumnWidth(1.45),
            4: FlexColumnWidth(1.5),
            5: FlexColumnWidth(1.6),
          };

    return Table(
      columnWidths: columnWidths,
      defaultVerticalAlignment: TableCellVerticalAlignment.top,
      children: [
        TableRow(
          decoration: const BoxDecoration(
            border: Border(
              top: BorderSide(color: _kInkMuted, width: 0.8),
              bottom: BorderSide(color: _kInkMuted, width: 0.8),
            ),
          ),
          children: [
            header('PRODUCTO/SERVICIO'),
            header('PRECIO', align: TextAlign.right),
            header('CANTIDAD', align: TextAlign.center),
            header('DESCUENTO', align: TextAlign.right),
            header('SUBTOTAL', align: TextAlign.right),
            if (showTax) header('ITBIS', align: TextAlign.right),
            header('VALOR TOTAL', align: TextAlign.right),
          ],
        ),
        for (final it in d.items)
          TableRow(
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: _kHairline, width: 0.5),
              ),
            ),
            children: [
              descriptionCell(it),
              cell(money(it.unitPrice), align: TextAlign.right),
              cell(_qtyLabel(it.quantity), align: TextAlign.center),
              cell(
                it.lineDiscount > 0.0049 ? money(it.lineDiscount) : '-',
                align: TextAlign.right,
              ),
              cell(money(it.lineSubtotal), align: TextAlign.right),
              if (showTax)
                cell(
                  it.lineTax > 0.0049 ? money(it.lineTax) : '-',
                  align: TextAlign.right,
                ),
              cell(money(it.lineTotal), align: TextAlign.right, bold: true),
            ],
          ),
      ],
    );
  }

  /// Banco + nota legal (izquierda) y totales con "TOTAL A PAGAR" (derecha).
  Widget _bankAndTotal(PrintDocumentData d) {
    final bankLines = _textLines(d.branch.bankInfo);
    final legalLines = _textLines(d.legalFooterText).take(8).toList();
    final legalTitle = d.documentType == PrintDocumentType.quote
        ? 'Términos y condiciones:'
        : 'Nota:';
    final showBreakdown = (d.showTax && d.totals.tax > 0.0049) ||
        d.totals.discount > 0.0049 ||
        d.totals.serviceCharge > 0.0049;

    Widget miniTotal(String label, String value) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$label:',
              style: const TextStyle(fontSize: 10, color: _kInkMuted),
            ),
            const SizedBox(width: 8),
            Text(value, style: const TextStyle(fontSize: 10)),
          ],
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final line in bankLines)
                Text(
                  line,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: _kInkMuted,
                  ),
                ),
              if (legalLines.isNotEmpty) ...[
                SizedBox(height: bankLines.isEmpty ? 0 : 8),
                Text(
                  legalTitle,
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: _kInkMuted,
                  ),
                ),
                for (final line in legalLines)
                  Text(
                    line,
                    style: const TextStyle(fontSize: 9, color: _kInkMuted),
                  ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 16),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (showBreakdown) ...[
              miniTotal('Subtotal', money(d.totals.subtotal)),
              if (d.totals.discount > 0.0049)
                miniTotal('Descuento', '-${money(d.totals.discount)}'),
              if (d.totals.serviceCharge > 0.0049)
                miniTotal('Ley / Servicio', money(d.totals.serviceCharge)),
              if (d.showTax && d.totals.tax > 0.0049)
                miniTotal('ITBIS', money(d.totals.tax)),
              const SizedBox(height: 3),
            ],
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'TOTAL A\nPAGAR',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: _kInkMuted,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  money(d.totals.total),
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: _kRed,
                  ),
                ),
              ],
            ),
            if (d.totals.balance > 0.0049)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: miniTotal('Balance pendiente', money(d.totals.balance)),
              ),
          ],
        ),
      ],
    );
  }

  Widget _observationBlock(PrintDocumentData d) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_hasText(d.branch.signatoryName)) ...[
          Center(
            child: Column(
              children: [
                Container(
                  width: 220,
                  decoration: const BoxDecoration(
                    border: Border(
                      top: BorderSide(color: _kHairline, width: 0.8),
                    ),
                  ),
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    d.branch.signatoryName!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 10,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
                if (_hasText(d.branch.signatoryTitle))
                  Text(
                    d.branch.signatoryTitle!,
                    style: const TextStyle(fontSize: 9, color: _kInkMuted),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        const Text(
          'OBSERVACIÓN:',
          style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700),
        ),
        if (_hasText(d.observation))
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              d.observation!,
              style: const TextStyle(fontSize: 9, color: _kInkMuted),
            ),
          ),
      ],
    );
  }
}

// ── Helpers compartidos por las dos vistas previas ───────────────────────────
//
// Tintas del papel: son las mismas que usa `PdfReceiptBuilder` al imprimir, no
// colores de tema — la hoja se ve igual en claro y en oscuro.
const Color _kPaperBg = Color(0xFFF8FAFC);
const Color _kNavy = Color(0xFF1B3A6B);
const Color _kRed = Color(0xFFC0202A);
const Color _kInkMuted = Color(0xFF64748B);
const Color _kHairline = Color(0xFFCBD5E1);

bool _hasText(String? value) => value != null && value.trim().isNotEmpty;

/// Una cotización o una cuenta guardada no entregan el comprobante que rotula
/// esa fila: se emitirá después. Espeja el rótulo del ticket impreso.
String _receiptTypeRowLabel(PrintDocumentData d) =>
    d.documentType == PrintDocumentType.quote || d.isPendingAccount
        ? 'Se facturará como:'
        : 'Tipo comprobante:';

String _customerBlockTitle(PrintDocumentData d) =>
    d.documentType == PrintDocumentType.quote || d.isPendingAccount
        ? 'Datos del cliente:'
        : 'Factura a:';

List<String> _textLines(String? text) {
  if (text == null) return const [];
  return text
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList(growable: false);
}

/// Quita el prefijo "RNC:"/"CÉDULA:" del documento del cliente.
String? _docNumberOnly(String? doc) {
  if (!_hasText(doc)) return null;
  final idx = doc!.indexOf(':');
  return idx >= 0 ? doc.substring(idx + 1).trim() : doc.trim();
}

String _qtyLabel(double value) {
  if (value == value.roundToDouble()) return value.toStringAsFixed(0);
  return value.toStringAsFixed(2);
}
