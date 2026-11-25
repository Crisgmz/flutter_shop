import 'dart:io';

import 'package:flutter_app/features/printing/data/printing.dart';
import 'package:flutter_test/flutter_test.dart';

/// Factura A4 clásica (GeotecnicaMQ): se elige por empresa, solo cubre la
/// venta y el ITBIS de la Norma 07-2007 cuadra con su factura de papel
/// (44,400.00 + 799.20 = 45,199.20).
void main() {
  PrintDocumentItem service(String name, double qty, double price, String unit) {
    final base = qty * price;
    // 18% sobre el 10% del monto.
    final tax = double.parse((base * 0.018).toStringAsFixed(2));
    return PrintDocumentItem(
      description: name,
      quantity: qty,
      unitPrice: price,
      unitLabel: unit,
      lineSubtotal: base,
      lineTax: tax,
      lineTotal: base + tax,
      isService: true,
      isItbisNorma0707: true,
    );
  }

  PrintDocumentData buildDocument({
    bool classic = true,
    PrintDocumentType type = PrintDocumentType.fiscalInvoice,
  }) {
    final items = [
      service('Transporte de probetas, manejo, curado y informe', 3, 7000,
          'Visitas'),
      service('Rotura de probetas de hormigón 10x20cm', 15, 350, 'U'),
      service('Rotura de probetas de hormigón 15x30cm', 33, 550, 'U'),
    ];
    final tax = items.fold<double>(0, (s, i) => s + i.lineTax);
    return PrintDocumentData(
      classicA4: classic,
      invoiceProject: 'Torre Residencial Los Cerros',
      invoiceLocation: 'Los Cerros de Gurabo, Santiago',
      invoiceConcept: 'Control de calidad del hormigón.',
      documentType: type,
      documentNumber: 'FA-003546',
      issuedAt: DateTime(2026, 11, 12),
      receiptTypeLabel: 'Crédito Fiscal',
      ncf: 'B0100001243',
      ncfValidUntil: DateTime(2026, 12, 31),
      paymentTermsLabel: 'CONTADO',
      branch: const PrintBranchIdentity(
        name: 'GEOTECNICA MQ, S.R.L.',
        tagline: 'Diseño · Construcción · Consultoría de Obras Civiles',
        taxId: '130246432',
        address: 'Calle 10 #2, Embrujo I, Santiago de los Caballeros, R.D.',
        phone: '(809) 581-1626 / (809) 284-7871',
        bankInfo: 'GEOTECNICA MQ, S.R.L.\nBanco Banreservas · Cta. Nº 9600864709',
      ),
      customer: const PrintParty(
        name: 'Constructora Cliente, SRL',
        document: 'RNC 101000000',
        address: 'Av. Juan Pablo Duarte, Santiago',
      ),
      items: items,
      payments: const [PrintPaymentLine(method: 'Transferencia', amount: 45199.20)],
      totals: PrintTotals(
        subtotal: 44400,
        tax: tax,
        total: 44400 + tax,
        paid: 44400 + tax,
      ),
    );
  }

  test('el ITBIS de la Norma 07-2007 da lo mismo que su factura', () {
    final doc = buildDocument();
    final tax = doc.items.fold<double>(0, (s, i) => s + i.lineTax);
    expect(tax.toStringAsFixed(2), '799.20');
    expect(doc.totals.total.toStringAsFixed(2), '45199.20');
  });

  test('el formato clásico solo cubre la factura de venta', () {
    expect(usesClassicA4(buildDocument()), isTrue);
    expect(
      usesClassicA4(buildDocument(type: PrintDocumentType.saleReceipt)),
      isTrue,
    );
    expect(usesClassicA4(buildDocument(classic: false)), isFalse);
    expect(
      usesClassicA4(buildDocument(type: PrintDocumentType.quote)),
      isFalse,
    );
    expect(
      usesClassicA4(buildDocument(type: PrintDocumentType.creditNote)),
      isFalse,
    );
  });

  test('arma el PDF clásico en una página', () async {
    final bytes = await const PdfReceiptBuilder().buildBytes(buildDocument());
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(
      RegExp(r'/Type\s*/Page\b').allMatches(String.fromCharCodes(bytes)).length,
      1,
    );

    // Para revisarlo a ojo: CLASSIC_PDF_OUT=/ruta/factura.pdf flutter test …
    final out = Platform.environment['CLASSIC_PDF_OUT'];
    if (out != null && out.isNotEmpty) File(out).writeAsBytesSync(bytes);
  });
}
