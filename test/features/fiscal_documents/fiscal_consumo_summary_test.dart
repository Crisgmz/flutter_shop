import 'package:flutter_app/features/fiscal_documents/data/fiscal_consumo_summary.dart';
import 'package:flutter_app/features/fiscal_documents/data/fiscal_documents_repository.dart';
import 'package:flutter_app/features/fiscal_documents/data/fiscal_labels.dart';
import 'package:flutter_test/flutter_test.dart';

const _soldAt = '2026-07-10T14:00:00Z';

/// Comprobante con su venta embebida, como lo devuelve `fetchDocuments`.
FiscalDocument _doc({
  String receiptType = 'consumer_final',
  double total = 118,
  double tax = 18,
  String saleStatus = 'completed',
  List<Map<String, dynamic>> payments = const [],
  String? voidedAt,
  bool withSale = true,
}) {
  return FiscalDocument.fromMap({
    'id': 'doc',
    'branch_id': 'b1',
    'receipt_type': receiptType,
    'ncf': 'B0200000001',
    'fiscal_status': 'pending',
    'issued_at': _soldAt,
    'total_amount': total,
    'tax_amount': tax,
    'voided_at': voidedAt,
    if (withSale)
      'sales': {
        'sale_number': 'V-0001',
        'sale_date': _soldAt,
        'status': saleStatus,
        'payments': payments,
      },
  });
}

Map<String, dynamic> _pay(
  String method,
  double amount, {
  String? reference = 'V-0001',
  String paidAt = _soldAt,
}) =>
    {
      'payment_method': method,
      'amount': amount,
      'paid_at': paidAt,
      'reference': reference,
    };

void main() {
  group('FiscalDocument.paymentBreakdown', () {
    test('pago mixto al vender', () {
      final doc = _doc(payments: [_pay('cash', 100), _pay('card', 18)]);
      expect(doc.paymentBreakdown, {'cash': 100, 'card': 18});
      expect(fiscalPaymentLabel(doc), 'Efectivo + Tarjeta');
    });

    test('venta a crédito saldada después sigue siendo a crédito', () {
      final doc = _doc(
        payments: [
          _pay('cash', 118, reference: null, paidAt: '2026-07-20T10:00:00Z'),
        ],
      );
      expect(doc.paymentBreakdown, {'credit': 118});
      expect(fiscalPaymentLabel(doc), 'Crédito');
    });

    test('inicial en efectivo y el resto a crédito', () {
      final doc = _doc(saleStatus: 'credit', payments: [_pay('cash', 18)]);
      expect(doc.paymentBreakdown, {'cash': 18, 'credit': 100});
    });

    test('cotización convertida: pago sin referencia en el mismo instante', () {
      final doc = _doc(payments: [_pay('transfer', 118, reference: null)]);
      expect(doc.paymentBreakdown, {'transfer': 118});
    });

    test('venta vieja completada sin pagos cuenta como efectivo', () {
      expect(_doc().paymentBreakdown, {'cash': 118});
    });

    test('sin venta asociada no hay método', () {
      final doc = _doc(withSale: false);
      expect(doc.paymentBreakdown, isEmpty);
      expect(fiscalPaymentLabel(doc), '—');
    });
  });

  group('FiscalConsumoSummary', () {
    test('suma consumo por tipo de venta y deja fuera anulados y otros tipos',
        () {
      final summary = FiscalConsumoSummary.fromDocuments(
        [
          _doc(payments: [_pay('cash', 118)]),
          _doc(payments: [_pay('mobile', 59)], total: 59, tax: 9),
          _doc(payments: [_pay('card', 100), _pay('other', 18)]),
          _doc(saleStatus: 'credit'),
          _doc(saleStatus: 'voided', payments: [_pay('cash', 118)]),
          _doc(voidedAt: '2026-07-11T00:00:00Z', payments: [_pay('cash', 118)]),
          _doc(receiptType: 'fiscal_credit', payments: [_pay('cash', 118)]),
        ],
        from: DateTime(2026, 7, 1),
        to: DateTime(2026, 7, 31),
      );

      expect(summary.period, '202607');
      expect(summary.count, 4);
      expect(summary.cancelledCount, 2);
      expect(summary.taxAmount, 18 + 9 + 18 + 18);
      // Monto facturado sin ITBIS: 100 + 50 + 100 + 100.
      expect(summary.billedAmount, 350);

      final byLine = {
        for (final l in summary.saleTypeLines) l.line: l.amount,
      };
      expect(byLine[11], 118); // Efectivo
      expect(byLine[12], 59); // Pago móvil → cheque / transferencia
      expect(byLine[13], 100); // Tarjeta
      expect(byLine[14], 118); // A crédito
      expect(byLine[15], isNull);
      expect(byLine[16], isNull);
      expect(byLine[17], 18); // Otro

      // Las formas de venta cuadran con monto + ITBIS.
      final paid = byLine.values.whereType<double>().fold<double>(0, (a, b) => a + b);
      expect(paid, summary.billedAmount + summary.taxAmount);
    });

    test('rango que cruza meses', () {
      final summary = FiscalConsumoSummary.fromDocuments(
        const [],
        from: DateTime(2026, 6, 15),
        to: DateTime(2026, 7, 15),
      );
      expect(summary.period, '202606-202607');
      expect(summary.generalLines.first.amount, 0);
    });
  });

  group('FiscalSale (607)', () {
    FiscalSale sale(String ncf, String receiptType, String status,
            List<Map<String, dynamic>> payments) =>
        FiscalSale.fromMap({
          'id': ncf,
          'ncf': ncf,
          'receipt_type': receiptType,
          'status': status,
          'sale_number': 'V-0001',
          'sale_date': _soldAt,
          'total_amount': 118,
          'tax_amount': 18,
          'service_charge_amount': 0,
          'payments': payments,
        });

    test('método de pago y resumen desde las ventas del 607', () {
      final sales = [
        sale('B0200000001', 'consumer_final', 'completed',
            [_pay('cash', 50), _pay('transfer', 68)]),
        sale('B0200000002', 'consumer_final', 'credit', const []),
        sale('B0100000001', 'fiscal_credit', 'completed', [_pay('card', 118)]),
      ];
      expect(paymentBreakdownLabel(sales.first.paymentBreakdown),
          'Efectivo + Transferencia');
      expect(paymentBreakdownLabel(sales[1].paymentBreakdown), 'Crédito');

      final summary = FiscalConsumoSummary.fromDocuments(
        sales,
        from: DateTime(2026, 7, 1),
        to: DateTime(2026, 7, 31),
      );
      expect(summary.count, 2);
      final byLine = {for (final l in summary.saleTypeLines) l.line: l.amount};
      expect(byLine[11], 50);
      expect(byLine[12], 68);
      expect(byLine[13], isNull); // la B01 no entra
      expect(byLine[14], 118);
    });
  });
}
