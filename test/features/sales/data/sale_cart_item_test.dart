import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/sales/data/sales_repository.dart';
import 'package:flutter_app/features/sales/domain/sale_checkout_service.dart';

/// De los getters de [SaleCartItem] sale el total que ve el cajero y el monto
/// que se manda como pagos. Tienen que dar exactamente lo mismo que el RPC
/// (`numeric`): si la pantalla queda un centavo por debajo, el pago dividido
/// rebota con "Los pagos no cubren el total".
void main() {
  SalesProduct buildProduct({
    String id = 'p1',
    double price = 100,
    double taxRate = 18,
    bool priceIncludesTax = false,
    bool isTaxExempt = false,
  }) {
    return SalesProduct(
      id: id,
      name: 'Producto',
      price: price,
      cost: 0,
      taxRate: taxRate,
      stock: 1000,
      isActive: true,
      priceIncludesTax: priceIncludesTax,
      isTaxExempt: isTaxExempt,
    );
  }

  /// Total del carrito tal como lo suma la pantalla (en centavos enteros).
  double cartTotal(List<SaleCartItem> cart) =>
      fromCents(cart.fold<double>(0, (s, i) => s + i.lineTotalCents));

  group('ITBIS de la línea en centavos', () {
    test('100.25 al 18% → 18.05 y 118.30', () {
      final item = SaleCartItem(
        product: buildProduct(price: 100.25),
        quantity: 1,
      );

      expect(item.lineSubtotal, 100.25);
      expect(item.lineTax, 18.05);
      expect(item.lineTotal, 118.30);
    });

    test('150.00 con 33.5% de descuento → neto 99.75, ITBIS 17.96', () {
      final item = SaleCartItem(
        product: buildProduct(price: 150),
        quantity: 1,
        discountPct: 33.5,
      );

      expect(item.lineDiscount, 50.25);
      expect(item.lineSubtotal, 99.75);
      expect(item.lineTax, 17.96);
      expect(item.lineTotal, 117.71);
    });

    test('526.69 × 10 al 10% con 50% de descuento → ITBIS 263.35', () {
      final item = SaleCartItem(
        product: buildProduct(price: 526.69, taxRate: 10),
        quantity: 10,
        discountPct: 50,
      );

      expect(item.lineDiscount, 2633.45);
      expect(item.lineSubtotal, 2633.45);
      expect(item.lineTax, 263.35);
      expect(item.lineTotal, 2896.80);
    });
  });

  group('Bruto con cantidades fraccionarias', () {
    test('0.5 × 2208.99 → bruto 1104.50 (no 1104.49)', () {
      final item = SaleCartItem(
        product: buildProduct(price: 2208.99),
        quantity: 0.5,
      );

      expect(item.lineGross, 1104.50);
      expect(item.lineSubtotal, 1104.50);
      expect(item.lineTotal, 1303.31);
    });

    test('0.25 × 4470.90 al 16% → total 1296.57', () {
      final item = SaleCartItem(
        product: buildProduct(price: 4470.90, taxRate: 16),
        quantity: 0.25,
      );

      expect(item.lineGross, 1117.73);
      expect(item.lineTax, 178.84);
      expect(item.lineTotal, 1296.57);
    });

    test('0.5 × 2271.93 con 100% de descuento → bruto 1135.97 y línea en 0', () {
      // El descuento se calcula sobre el MISMO bruto que usa el SQL, así que
      // el 100% cubre la línea completa: ya no queda el centavo que el
      // backend cobraba por su cuenta.
      final item = SaleCartItem(
        product: buildProduct(price: 2271.93),
        quantity: 0.5,
        discountPct: 100,
      );

      expect(item.lineGross, 1135.97);
      expect(item.lineDiscount, 1135.97);
      expect(item.lineSubtotal, 0);
      expect(item.lineTotal, 0);
    });
  });

  group('Producto exento de ITBIS', () {
    test('exento con tax_rate 18 no cobra impuesto en pantalla', () {
      final item = SaleCartItem(
        product: buildProduct(taxRate: 18, isTaxExempt: true),
        quantity: 3,
      );

      expect(item.taxRate, 0);
      expect(item.lineSubtotal, 300);
      expect(item.lineTax, 0);
      expect(item.lineTotal, 300);
    });

    test('el select del POS trae is_tax_exempt y lo respeta', () {
      final product = SalesProduct.fromMap(const {
        'id': 'p1',
        'name': 'Arroz',
        'price': 100,
        'cost': 0,
        'tax_rate': 18,
        'stock': 10,
        'is_active': true,
        'is_tax_exempt': true,
      }, const {});

      expect(product.isTaxExempt, isTrue);
      expect(product.taxRate, 18);
      expect(product.effectiveTaxRate, 0);
    });
  });

  group('Paridad carrito ↔ normalizador ↔ RPC', () {
    test('dos líneas de 0.30 al 18%: pantalla y checkout dan 0.70', () {
      final product = buildProduct(price: 0.30);
      final cart = [
        SaleCartItem(product: product, quantity: 1),
        SaleCartItem(product: product, quantity: 1),
      ];

      expect(cartTotal(cart), 0.70);

      const service = SaleCheckoutService();
      final normalized = service.normalize(
        SaleCheckoutServiceInput(
          items: cart
              .map(
                (item) => SaleCheckoutSourceItem(
                  product: SaleCheckoutSourceProduct(
                    id: item.product.id,
                    name: item.product.name,
                    price: item.unitPrice,
                    taxRate: item.product.taxRate,
                    isTaxExempt: item.product.isTaxExempt,
                    stock: item.product.stock,
                    isActive: item.product.isActive,
                    priceIncludesTax: item.product.priceIncludesTax,
                    tracksStock: item.product.tracksStock,
                  ),
                  quantity: item.quantity,
                  discountAmount: item.lineDiscount,
                ),
              )
              .toList(growable: false),
          receiptType: 'consumer_final',
          asCredit: false,
          paymentMethod: 'cash',
        ),
      );

      expect(normalized.total, cartTotal(cart));
    });

    test('el exento cuadra pantalla y checkout (45 pesos de diferencia)', () {
      final product = buildProduct(taxRate: 18, isTaxExempt: true);
      final cart = [
        SaleCartItem(
          product: product,
          quantity: 3,
          discountPct: 50 / 300 * 100,
        ),
      ];

      expect(cart.single.lineDiscount, 50);
      expect(cartTotal(cart), 250);

      const service = SaleCheckoutService();
      final normalized = service.normalize(
        SaleCheckoutServiceInput(
          items: [
            SaleCheckoutSourceItem(
              product: SaleCheckoutSourceProduct(
                id: product.id,
                name: product.name,
                price: cart.single.unitPrice,
                taxRate: product.taxRate,
                isTaxExempt: product.isTaxExempt,
                stock: product.stock,
                isActive: product.isActive,
              ),
              quantity: 3,
              discountAmount: cart.single.lineDiscount,
            ),
          ],
          receiptType: 'consumer_final',
          asCredit: false,
          paymentMethod: 'cash',
        ),
      );

      expect(normalized.taxAmount, 0);
      expect(normalized.total, 250);
    });
  });
}
