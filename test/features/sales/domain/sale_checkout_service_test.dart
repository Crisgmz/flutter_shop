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
    bool priceIncludesTax = false,
    bool tracksStock = true,
  }) {
    return SaleCheckoutSourceProduct(
      id: id,
      name: name,
      price: price,
      taxRate: taxRate,
      stock: stock,
      isActive: isActive,
      priceIncludesTax: priceIncludesTax,
      tracksStock: tracksStock,
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
    test('mantiene una línea por item del carrito y calcula totales', () {
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

      // Las líneas repetidas NO se fusionan: el RPC liquida item por item y
      // consolidar en Dart cambiaba el redondeo (y perdía el precio unitario
      // de la segunda línea).
      expect(result.items, hasLength(2));
      expect(result.items.map((i) => i.quantity), [1, 2]);
      expect(result.subtotal, 300);
      expect(result.taxAmount, 54);
      expect(result.total, 354);
      expect(result.saleStatus, 'completed');
      expect(result.paidAmount, 354);
      expect(result.balanceDue, 0);
    });

    test('con ITBIS incluido extrae el impuesto y el total queda exacto', () {
      // 100 con ITBIS 18% adentro: total 100.00 exacto,
      // ITBIS = 100 × 18/118 = 15.25, base = 84.75.
      final result = service.normalize(
        SaleCheckoutServiceInput(
          items: [
            SaleCheckoutSourceItem(
              product: buildProduct(priceIncludesTax: true),
              quantity: 1,
            ),
          ],
          receiptType: 'consumer_final',
          asCredit: false,
          paymentMethod: 'cash',
        ),
      );

      expect(result.items.first.lineTotal, 100.00);
      expect(result.items.first.lineTax, 15.25);
      expect(result.items.first.lineSubtotal, 84.75);
      expect(result.subtotal, 84.75);
      expect(result.taxAmount, 15.25);
      expect(result.total, 100.00);
    });

    test('con ITBIS incluido y tasa 0 se comporta como exclusivo', () {
      final result = service.normalize(
        SaleCheckoutServiceInput(
          items: [
            SaleCheckoutSourceItem(
              product: buildProduct(priceIncludesTax: true, taxRate: 0),
              quantity: 2,
            ),
          ],
          receiptType: 'consumer_final',
          asCredit: false,
          paymentMethod: 'cash',
        ),
      );

      expect(result.subtotal, 200);
      expect(result.taxAmount, 0);
      expect(result.total, 200);
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
            // La validación de stock solo aplica cuando el negocio prohíbe
            // vender sin existencias (app_settings.inv_disallow_no_stock).
            disallowNoStock: true,
          ),
        ),
        throwsA(isA<SaleCheckoutValidationException>()),
      );
    });

    test('aplica el descuento de la línea con ITBIS excluido', () {
      // 2 × 100 = 200 bruto, descuento 50 → neto 150.
      // ITBIS 18% encima: 27.00. Total 177.00.
      final result = service.normalize(
        SaleCheckoutServiceInput(
          items: [
            SaleCheckoutSourceItem(
              product: buildProduct(),
              quantity: 2,
              discountAmount: 50,
            ),
          ],
          receiptType: 'consumer_final',
          asCredit: false,
          paymentMethod: 'cash',
        ),
      );

      expect(result.items.first.discountAmount, 50);
      expect(result.items.first.lineSubtotal, 150);
      expect(result.items.first.lineTax, 27);
      expect(result.items.first.lineTotal, 177);
      expect(result.subtotal, 150);
      expect(result.taxAmount, 27);
      expect(result.total, 177);
    });

    test('aplica el descuento con ITBIS incluido extrayendo el impuesto', () {
      // 100 con ITBIS adentro, descuento 10 → total exacto 90.00.
      // ITBIS = 90 × 18/118 = 13.73, base = 76.27.
      final result = service.normalize(
        SaleCheckoutServiceInput(
          items: [
            SaleCheckoutSourceItem(
              product: buildProduct(priceIncludesTax: true),
              quantity: 1,
              discountAmount: 10,
            ),
          ],
          receiptType: 'consumer_final',
          asCredit: false,
          paymentMethod: 'cash',
        ),
      );

      expect(result.items.first.lineTotal, 90.00);
      expect(result.items.first.lineTax, 13.73);
      expect(result.items.first.lineSubtotal, 76.27);
      expect(result.total, 90.00);
    });

    test('un descuento mayor que el bruto no deja la línea en negativo', () {
      final result = service.normalize(
        SaleCheckoutServiceInput(
          items: [
            SaleCheckoutSourceItem(
              product: buildProduct(),
              quantity: 1,
              discountAmount: 500,
            ),
          ],
          receiptType: 'consumer_final',
          asCredit: false,
          paymentMethod: 'cash',
        ),
      );

      // El descuento se acota al bruto (100): la línea queda en cero.
      expect(result.items.first.discountAmount, 100);
      expect(result.items.first.lineSubtotal, 0);
      expect(result.items.first.lineTax, 0);
      expect(result.items.first.lineTotal, 0);
      expect(result.total, 0);
      expect(result.paidAmount, 0);
    });

    test('cada línea del mismo producto conserva su propio descuento', () {
      // 1 × 100 con 10 de descuento + 2 × 100 con 30: netos 90 y 170.
      // Neto total 260, ITBIS 46.80, total 306.80 (igual que el RPC, que
      // liquida las dos líneas por separado).
      final result = service.normalize(
        SaleCheckoutServiceInput(
          items: [
            SaleCheckoutSourceItem(
              product: buildProduct(id: 'a', name: 'A'),
              quantity: 1,
              discountAmount: 10,
            ),
            SaleCheckoutSourceItem(
              product: buildProduct(id: 'a', name: 'A'),
              quantity: 2,
              discountAmount: 30,
            ),
          ],
          receiptType: 'consumer_final',
          asCredit: false,
          paymentMethod: 'cash',
        ),
      );

      expect(result.items, hasLength(2));
      expect(result.items.map((i) => i.discountAmount), [10, 30]);
      expect(result.items.map((i) => i.lineSubtotal), [90, 170]);
      expect(result.subtotal, 260);
      expect(result.taxAmount, 46.80);
      expect(result.total, 306.80);
    });

    test('el descuento viaja al RPC como discount_amount', () {
      final result = service.normalize(
        SaleCheckoutServiceInput(
          items: [
            SaleCheckoutSourceItem(
              product: buildProduct(),
              quantity: 2,
              discountAmount: 50,
            ),
          ],
          receiptType: 'consumer_final',
          asCredit: false,
          paymentMethod: 'cash',
        ),
      );

      final rpcItem = result.toRpcItems().single;
      expect(rpcItem['discount_amount'], 50);
      expect(rpcItem['unit_price'], 100);
      expect(rpcItem['quantity'], 2);
    });

    test('rechaza un descuento negativo', () {
      expect(
        () => service.normalize(
          SaleCheckoutServiceInput(
            items: [
              SaleCheckoutSourceItem(
                product: buildProduct(),
                quantity: 1,
                discountAmount: -5,
              ),
            ],
            receiptType: 'consumer_final',
            asCredit: false,
            paymentMethod: 'cash',
          ),
        ),
        throwsA(isA<SaleCheckoutValidationException>()),
      );
    });

    test('permite vender servicios aunque no haya stock', () {
      final result = service.normalize(
        SaleCheckoutServiceInput(
          items: [
            SaleCheckoutSourceItem(
              product: buildProduct(stock: 0, tracksStock: false),
              quantity: 3,
            ),
          ],
          receiptType: 'consumer_final',
          asCredit: false,
          disallowNoStock: true,
        ),
      );

      expect(result.items, hasLength(1));
      expect(result.items.first.quantity, 3);
    });
  });
}
