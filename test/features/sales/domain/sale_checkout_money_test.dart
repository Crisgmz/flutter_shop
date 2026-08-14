import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/sales/domain/sale_checkout_service.dart';

/// Paridad centavo a centavo entre la aritmética de Dart y la del RPC
/// (`checkout_sale_transactional`, migración 76), que corre en `numeric`.
/// Cada caso trae el valor EXACTO que devuelve el SQL: si Dart se separa, el
/// pago dividido rebota con "Los pagos no cubren el total" o la caja queda
/// descuadrada por centavos.
void main() {
  const service = SaleCheckoutService();

  SaleCheckoutSourceProduct buildProduct({
    String id = 'p1',
    String name = 'Producto',
    double price = 100,
    double taxRate = 18,
    double stock = 1000,
    bool priceIncludesTax = false,
    bool isTaxExempt = false,
  }) {
    return SaleCheckoutSourceProduct(
      id: id,
      name: name,
      price: price,
      taxRate: taxRate,
      stock: stock,
      isActive: true,
      priceIncludesTax: priceIncludesTax,
      isTaxExempt: isTaxExempt,
    );
  }

  NormalizedSaleCheckout run(List<SaleCheckoutSourceItem> items) {
    return service.normalize(
      SaleCheckoutServiceInput(
        items: items,
        receiptType: 'consumer_final',
        asCredit: false,
        paymentMethod: 'cash',
      ),
    );
  }

  group('ITBIS en centavos enteros (paridad con numeric)', () {
    test('neto 100.25 al 18% → 18.05 y 118.30', () {
      final result = run([
        SaleCheckoutSourceItem(
          product: buildProduct(price: 100.25),
          quantity: 1,
        ),
      ]);

      expect(result.items.first.lineSubtotal, 100.25);
      expect(result.items.first.lineTax, 18.05);
      expect(result.items.first.lineTotal, 118.30);
      expect(result.total, 118.30);
    });

    test('150.00 con 33.5% (50.25) → neto 99.75, ITBIS 17.96, total 117.71', () {
      final result = run([
        SaleCheckoutSourceItem(
          product: buildProduct(price: 150),
          quantity: 1,
          discountAmount: 50.25,
        ),
      ]);

      expect(result.items.first.lineSubtotal, 99.75);
      expect(result.items.first.lineTax, 17.96);
      expect(result.total, 117.71);
    });

    test('33.35 × 7 con descuento 10.20 → neto 223.25, ITBIS 40.19', () {
      final result = run([
        SaleCheckoutSourceItem(
          product: buildProduct(price: 33.35),
          quantity: 7,
          discountAmount: 10.20,
        ),
      ]);

      expect(result.items.first.lineSubtotal, 223.25);
      expect(result.items.first.lineTax, 40.19);
      expect(result.total, 263.44);
    });

    test('tasa 10%: 526.69 × 10 con 50% (2633.45) → ITBIS 263.35', () {
      final result = run([
        SaleCheckoutSourceItem(
          product: buildProduct(price: 526.69, taxRate: 10),
          quantity: 10,
          discountAmount: 2633.45,
        ),
      ]);

      expect(result.items.first.lineSubtotal, 2633.45);
      expect(result.items.first.lineTax, 263.35);
      expect(result.total, 2896.80);
    });

    test('todo neto terminado en .25/.75 al 18% redondea como el SQL', () {
      // La regla que encontró el fuzzing: el medio centavo cae hacia arriba.
      for (final net in <double>[0.25, 0.75, 10.25, 50.75, 100.25, 1999.75]) {
        final result = run([
          SaleCheckoutSourceItem(
            product: buildProduct(price: net),
            quantity: 1,
          ),
        ]);
        final expected = ((net * 100).round() * 18 / 100).round() / 100;
        expect(
          result.items.first.lineTax,
          expected,
          reason: 'neto $net al 18%',
        );
      }
    });
  });

  group('Bruto con cantidades fraccionarias', () {
    test('0.5 × 2208.99 → bruto 1104.50 (no 1104.49)', () {
      final result = run([
        SaleCheckoutSourceItem(
          product: buildProduct(price: 2208.99),
          quantity: 0.5,
        ),
      ]);

      expect(result.items.first.lineSubtotal, 1104.50);
      expect(result.items.first.lineTax, 198.81);
      expect(result.total, 1303.31);
    });

    test('0.25 × 4470.90 al 16% excluido → total 1296.57', () {
      final result = run([
        SaleCheckoutSourceItem(
          product: buildProduct(price: 4470.90, taxRate: 16),
          quantity: 0.25,
        ),
      ]);

      expect(result.items.first.lineSubtotal, 1117.73);
      expect(result.items.first.lineTax, 178.84);
      expect(result.total, 1296.57);
    });

    test('0.5 × 2271.93 con descuento 1135.96 → neto 0.01, igual que el SQL', () {
      // El bruto es 1135.97 (round de 1135.965): el descuento de 1135.96 deja
      // un centavo. Antes Dart calculaba bruto 1135.96 y daba neto 0.00
      // mientras el backend cobraba 0.01.
      final result = run([
        SaleCheckoutSourceItem(
          product: buildProduct(price: 2271.93),
          quantity: 0.5,
          discountAmount: 1135.96,
        ),
      ]);

      expect(result.items.first.lineSubtotal, 0.01);
      expect(result.items.first.lineTax, 0);
      expect(result.total, 0.01);
    });

    test('el descuento se acota contra el MISMO bruto que el SQL', () {
      final result = run([
        SaleCheckoutSourceItem(
          product: buildProduct(price: 2271.93),
          quantity: 0.5,
          discountAmount: 5000,
        ),
      ]);

      // Bruto 1135.97 (no 1135.96): ese es el tope del descuento.
      expect(result.items.first.discountAmount, 1135.97);
      expect(result.total, 0);
    });
  });

  group('Producto exento de ITBIS', () {
    test('exento con tax_rate 18 no cobra impuesto (regla del RPC)', () {
      final result = run([
        SaleCheckoutSourceItem(
          product: buildProduct(taxRate: 18, isTaxExempt: true),
          quantity: 3,
          discountAmount: 50,
        ),
      ]);

      expect(result.items.first.taxRate, 0);
      expect(result.subtotal, 250);
      expect(result.taxAmount, 0);
      expect(result.total, 250);
    });

    test('exento con precio ITBIS-incluido tampoco extrae impuesto', () {
      final result = run([
        SaleCheckoutSourceItem(
          product: buildProduct(
            taxRate: 18,
            isTaxExempt: true,
            priceIncludesTax: true,
          ),
          quantity: 1,
        ),
      ]);

      expect(result.items.first.lineTax, 0);
      expect(result.items.first.lineSubtotal, 100);
      expect(result.total, 100);
    });
  });

  group('Líneas repetidas del mismo producto', () {
    test('no se consolidan: el impuesto se redondea línea por línea', () {
      // Dos líneas de 0.30 al 18%: 0.05 + 0.05 = 0.10. Consolidando daría
      // 0.11 sobre el neto sumado y la pantalla no cuadraría con el RPC.
      final result = run([
        SaleCheckoutSourceItem(
          product: buildProduct(price: 0.30),
          quantity: 1,
        ),
        SaleCheckoutSourceItem(
          product: buildProduct(price: 0.30),
          quantity: 1,
        ),
      ]);

      expect(result.items, hasLength(2));
      expect(result.items.every((i) => i.lineTax == 0.05), isTrue);
      expect(result.taxAmount, 0.10);
      expect(result.total, 0.70);
    });

    test('dos precios distintos del mismo producto no pierden dinero', () {
      final result = run([
        SaleCheckoutSourceItem(
          product: buildProduct(price: 100),
          quantity: 1,
        ),
        SaleCheckoutSourceItem(
          product: buildProduct(price: 250),
          quantity: 1,
        ),
      ]);

      expect(result.items, hasLength(2));
      expect(result.items.map((i) => i.unitPrice), [100, 250]);
      expect(result.subtotal, 350);
      expect(result.total, 413);

      final rpcItems = result.toRpcItems();
      expect(rpcItems.map((i) => i['unit_price']), [100, 250]);
    });

    test('el tope de existencia se valida sobre la suma de las líneas', () {
      expect(
        () => service.normalize(
          SaleCheckoutServiceInput(
            items: [
              SaleCheckoutSourceItem(
                product: buildProduct(stock: 3),
                quantity: 2,
              ),
              SaleCheckoutSourceItem(
                product: buildProduct(stock: 3),
                quantity: 2,
              ),
            ],
            receiptType: 'consumer_final',
            asCredit: false,
            disallowNoStock: true,
          ),
        ),
        throwsA(isA<SaleCheckoutValidationException>()),
      );
    });
  });

  group('helpers de centavos', () {
    test('grossCents reproduce round(unit_price × quantity, 2)', () {
      expect(grossCents(0.5, 2208.99), 110450);
      expect(grossCents(0.25, 4470.90), 111773);
      expect(grossCents(7, 33.35), 23345);
      expect(grossCents(1, 100.25), 10025);
    });

    test('taxCents reproduce round(neto × tasa / 100, 2)', () {
      expect(taxCents(10025, 18), 1805);
      expect(taxCents(9975, 18), 1796);
      expect(taxCents(22325, 18), 4019);
      expect(taxCents(263345, 10), 26335);
      expect(taxCents(10000, 18, inclusive: true), 1525);
      expect(taxCents(9000, 18, inclusive: true), 1373);
      expect(taxCents(5000, 0), 0);
    });
  });
}
