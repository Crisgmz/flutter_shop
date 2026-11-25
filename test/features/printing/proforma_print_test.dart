import 'package:flutter_app/features/fiscal_documents/data/fiscal_labels.dart';
import 'package:flutter_app/features/printing/data/printing.dart';
import 'package:flutter_test/flutter_test.dart';

/// La proforma se imprime rotulada, con su número PRF y sin validez fiscal;
/// ya convertida (con NCF) se imprime como cualquier factura.
void main() {
  const adapter = SalePrintDocumentAdapter();

  SalePrintSource sale({String receiptType = 'proforma', String? ncf}) =>
      SalePrintSource(
        saleId: 's1',
        branchId: 'b1',
        saleNumber: 'FA-000010',
        status: 'completed',
        saleDate: DateTime(2026, 11, 24),
        receiptType: receiptType,
        branchName: 'Principal',
        items: const [
          SalePrintItemSource(
            description: 'Producto',
            quantity: 1,
            unitPrice: 100,
            lineSubtotal: 100,
            lineTax: 18,
            lineTotal: 118,
          ),
        ],
        subtotal: 100,
        taxAmount: 18,
        totalAmount: 118,
        paidAmount: 118,
        ncf: ncf,
        proformaNumber: 'PRF-000001',
      );

  test('proforma: título, número PRF, aviso y pie sin validez fiscal', () {
    final data = adapter.toDocumentData(sale());

    expect(data.isProforma, isTrue);
    expect(data.documentNumber, 'PRF-000001');
    expect(printDocumentTitle(data), 'FACTURA PROFORMA');
    expect(printPendingNcfNotice(data), 'SIN VALIDEZ FISCAL');
    expect(data.footerMessage, contains('DOCUMENTO SIN VALIDEZ FISCAL'));
    expect(data.totals.tax, 18);
    expect(data.receiptTypeLabel, 'Factura proforma');
  });

  test('proforma convertida se imprime como factura con su NCF', () {
    final data = adapter.toDocumentData(
      sale(receiptType: 'consumer_final', ncf: 'B0200000123'),
    );

    expect(data.isProforma, isFalse);
    expect(data.documentNumber, 'FA-000010');
    expect(printDocumentTitle(data), isNot('FACTURA PROFORMA'));
    expect(printPendingNcfNotice(data), isNull);
  });

  test('códigos de comprobante según la modalidad e-CF', () {
    expect(fiscalReceiptCode('consumer_final', electronic: false), 'B02');
    expect(fiscalReceiptCode('fiscal_credit', electronic: true), 'E31');
    expect(fiscalReceiptCode('proforma', electronic: false), isNull);
    expect(fiscalReceiptLabel('proforma'), 'Proforma');
  });
}
