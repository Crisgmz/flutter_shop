import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../features/printing/data/printing.dart';

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
  final _templateService = const PrintingTemplateService();

  @override
  void initState() {
    super.initState();
    _selectedSize = widget.printData.paperSize;
  }

  ThermalTicketTemplate get _thermalTemplate =>
      widget.printData.thermalTemplate ??
      _templateService.buildThermal80Template(widget.printData.document);

  A4DocumentTemplate get _a4Template =>
      widget.printData.a4Template ??
      _templateService.buildA4Template(widget.printData.document);

  String get _docTitle => switch (widget.printData.document.documentType) {
        PrintDocumentType.quote => 'Cotización',
        PrintDocumentType.fiscalInvoice => 'Factura Fiscal',
        _ => 'Recibo de venta',
      };

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
        width: isThermal ? 320 : 560,
        height: 480,
        child: ClipRect(
          child: isThermal
              ? _ThermalPreview(template: _thermalTemplate)
              : _A4Preview(
                  template: _a4Template,
                  document: widget.printData.document,
                ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cerrar'),
        ),
        FilledButton.icon(
          onPressed: () async {
            final doc = widget.printData.document;
            final name = doc.documentNumber;
            Navigator.pop(context);
            await Printing.layoutPdf(
              name: name,
              onLayout: (format) =>
                  const PdfReceiptBuilder().buildBytes(doc, pageFormat: format),
            );
          },
          icon: const Icon(Icons.print_rounded, size: 18),
          label: const Text('Imprimir'),
        ),
      ],
    );
  }
}

// ── Thermal preview ─────────────────────────────────────────────────────────

class _ThermalPreview extends StatelessWidget {
  const _ThermalPreview({required this.template});

  final ThermalTicketTemplate template;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF8FAFC),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(8),
        child: Center(
          child: Container(
            width: 280,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: Colors.white,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: template.rows.map(_buildRow).toList(growable: false),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRow(ThermalTicketRow row) {
    if (row.isDivider) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 5),
        child: Divider(height: 1, thickness: 1, color: Color(0xFF334155)),
      );
    }

    if (row.center != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Text(
          row.center!,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 13,
            fontWeight:
                row.emphasized ? FontWeight.w800 : FontWeight.normal,
            letterSpacing: 0.2,
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (row.left != null)
            Expanded(
              child: Text(
                row.left!,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  fontWeight:
                      row.emphasized ? FontWeight.w800 : FontWeight.normal,
                ),
              ),
            ),
          if (row.right != null)
            Text(
              row.right!,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                fontWeight:
                    row.emphasized ? FontWeight.w800 : FontWeight.normal,
              ),
            ),
        ],
      ),
    );
  }
}

// ── A4 preview ───────────────────────────────────────────────────────────────

class _A4Preview extends StatelessWidget {
  const _A4Preview({required this.template, required this.document});

  final A4DocumentTemplate template;
  final PrintDocumentData document;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: issuer + doc meta
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      document.branch.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                    if (document.branch.address != null)
                      Text(
                        document.branch.address!,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    if (document.branch.phone != null)
                      Text(
                        'Tel: ${document.branch.phone}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF64748B),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    template.title.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF2563EB),
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  for (final row in template.headerRows)
                    _KVLine(
                      label: row.label,
                      value: row.value,
                      emphasized: row.emphasized,
                    ),
                ],
              ),
            ],
          ),

          if (template.customerRows.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'DATOS DEL CLIENTE',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF64748B),
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 6),
                  for (final row in template.customerRows)
                    _KVLine(
                      label: row.label,
                      value: row.value,
                      emphasized: row.emphasized,
                    ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 16),

          // Items table
          Table(
            columnWidths: const {
              0: FlexColumnWidth(4),
              1: FlexColumnWidth(1),
              2: FlexColumnWidth(2),
              3: FlexColumnWidth(2),
            },
            children: [
              TableRow(
                decoration: const BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: Color(0xFF334155), width: 1.5),
                  ),
                ),
                children: [
                  _tableHeader('Descripción'),
                  _tableHeader('Cant.', numeric: true),
                  _tableHeader('Precio', numeric: true),
                  _tableHeader('Total', numeric: true),
                ],
              ),
              for (int i = 0; i < template.itemRows.length; i++)
                TableRow(
                  decoration: BoxDecoration(
                    color: i.isOdd
                        ? const Color(0xFFF8FAFC)
                        : Colors.transparent,
                  ),
                  children: [
                    _tableCell(template.itemRows[i].description),
                    _tableCell(
                      template.itemRows[i].quantityLabel,
                      numeric: true,
                    ),
                    _tableCell(
                      template.itemRows[i].unitPriceLabel,
                      numeric: true,
                    ),
                    _tableCell(
                      template.itemRows[i].totalLabel,
                      numeric: true,
                      bold: true,
                    ),
                  ],
                ),
            ],
          ),

          const SizedBox(height: 12),
          const Divider(height: 1, color: Color(0xFFE2E8F0)),
          const SizedBox(height: 8),

          // Totals
          Align(
            alignment: Alignment.centerRight,
            child: SizedBox(
              width: 220,
              child: Column(
                children: [
                  for (final row in template.totalRows)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            row.label,
                            style: TextStyle(
                              fontSize: row.emphasized ? 14 : 12,
                              fontWeight: row.emphasized
                                  ? FontWeight.w800
                                  : FontWeight.w500,
                              color: const Color(0xFF475569),
                            ),
                          ),
                          Text(
                            row.value,
                            style: TextStyle(
                              fontSize: row.emphasized ? 15 : 12,
                              fontWeight: row.emphasized
                                  ? FontWeight.w900
                                  : FontWeight.w600,
                              color: row.emphasized
                                  ? const Color(0xFF2563EB)
                                  : const Color(0xFF1E293B),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),

          if (template.notes != null) ...[
            const SizedBox(height: 16),
            const Text(
              'NOTAS',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: Color(0xFF64748B),
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              template.notes!,
              style: const TextStyle(fontSize: 12, color: Color(0xFF475569)),
            ),
          ],

          if (template.footer != null) ...[
            const SizedBox(height: 20),
            Center(
              child: Text(
                template.footer!,
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF94A3B8),
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],

          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _tableHeader(String label, {bool numeric = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: Text(
        label,
        textAlign: numeric ? TextAlign.right : TextAlign.left,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Color(0xFF334155),
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  Widget _tableCell(
    String value, {
    bool numeric = false,
    bool bold = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
      child: Text(
        value,
        textAlign: numeric ? TextAlign.right : TextAlign.left,
        style: TextStyle(
          fontSize: 12,
          fontWeight: bold ? FontWeight.w700 : FontWeight.normal,
          color: const Color(0xFF1E293B),
        ),
      ),
    );
  }
}

class _KVLine extends StatelessWidget {
  const _KVLine({
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  final String label;
  final String value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight:
                  emphasized ? FontWeight.w800 : FontWeight.w600,
              color: const Color(0xFF1E293B),
            ),
          ),
        ],
      ),
    );
  }
}

