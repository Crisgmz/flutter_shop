import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/sales/domain/sale_checkout_service.dart';

void main() {
  const service = SaleCheckoutService();

  SaleCheckoutSourceProduct buildProduct({
    String id = 'p1',
    String name = 'Producto',
    double price = 100,
    double taxRate = 18,
    double stock = 10,
    bool isActive = true,
  }) {
    return SaleCheckoutSourceProduct(
      id: id,
      name: name,
      price: price,
      taxRate: taxRate,
      stock: stock,
      isActive: isActive,
    );
  }

  group('normalizeReceiptType', () {
    test('normaliza aliases en español al enum canónico', () {
      expect(normalizeReceiptType('consumidor_final'), 'consumer_final');
      expect(normalizeReceiptType('Crédito Fiscal'), 'fiscal_credit');
      expect(normalizeReceiptType('gubernamental'), 'governmental');
      expect(normalizeReceiptType('régimen especial'), 'special');
      expect(normalizeReceiptType('exportación'), 'export');
    });

    test('rechaza tipos no soportados', () {
      expect(
        () => normalizeReceiptType('otro'),
        throwsA(isA<SaleCheckoutValidationException>()),
      );
    });
  });

  group('SaleCheckoutService', () {
    test('consolida líneas repetidas y calcula totales', () {
      final result = service.normalize(
        SaleCheckoutServiceInput(
          items: [
            SaleCheckoutSourceItem(
              product: buildProduct(id: 'a', name: 'A'),
              quantity: 1,
            ),
            SaleCheckoutSourceItem(
              product: buildProduct(id: 'a', name: 'A'),
              quantity: 2,
            ),
          ],
          receiptType: 'consumer_final',
          asCredit: false,
          paymentMethod: 'cash',
        ),
      );

      expect(result.items, hasLength(1));
      expect(result.items.first.quantity, 3);
      expect(result.subtotal, 300);
      expect(result.taxAmount, 54);
      expect(result.total, 354);
      expect(result.saleStatus, 'completed');
      expect(result.paidAmount, 354);
      expect(result.balanceDue, 0);
    });

    test('exige cliente para crédito y para comprobantes fiscales', () {
      expect(
        () => service.normalize(
          SaleCheckoutServiceInput(
            items: [
              SaleCheckoutSourceItem(product: buildProduct(), quantity: 1),
            ],
            receiptType: 'consumer_final',
            asCredit: true,
          ),
        ),
        throwsA(isA<SaleCheckoutValidationException>()),
      );

      expect(
        () => service.normalize(
          SaleCheckoutServiceInput(
            items: [
              SaleCheckoutSourceItem(product: buildProduct(), quantity: 1),
            ],
            receiptType: 'fiscal_credit',
            asCredit: false,
          ),
        ),
        throwsA(isA<SaleCheckoutValidationException>()),
      );
    });

    test('rechaza productos sin stock suficiente', () {
      expect(
        () => service.normalize(
          SaleCheckoutServiceInput(
            items: [
              SaleCheckoutSourceItem(
                product: buildProduct(stock: 1),
                quantity: 2,
              ),
            ],
            receiptType: 'consumer_final',
            asCredit: false,
          ),
        ),
        throwsA(isA<SaleCheckoutValidationException>()),
      );
    });
  });
}
