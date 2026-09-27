import 'package:flutter_app/features/quotations/data/quotations_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('QuoteStatusX.fromDb', () {
    test('maps supported db values', () {
      expect(QuoteStatusX.fromDb('draft'), QuoteStatus.draft);
      expect(QuoteStatusX.fromDb('sent'), QuoteStatus.sent);
      expect(QuoteStatusX.fromDb('under_review'), QuoteStatus.underReview);
      expect(QuoteStatusX.fromDb('approved'), QuoteStatus.approved);
      expect(QuoteStatusX.fromDb('rejected'), QuoteStatus.rejected);
      expect(QuoteStatusX.fromDb('expired'), QuoteStatus.expired);
      expect(QuoteStatusX.fromDb('converted'), QuoteStatus.converted);
    });

    test('falls back to draft for unknown values', () {
      expect(QuoteStatusX.fromDb('weird'), QuoteStatus.draft);
      expect(QuoteStatusX.fromDb(null), QuoteStatus.draft);
    });
  });

  group('QuotationsMath', () {
    test('calculates subtotal tax and total from quote items', () {
      final items = [
        QuoteCreateItem(
          productId: 'p1',
          productName: 'Producto A',
          quantity: 2,
          unitPrice: 100,
          taxRate: 18,
        ),
        QuoteCreateItem(
          productId: 'p2',
          productName: 'Producto B',
          quantity: 1,
          unitPrice: 50,
          taxRate: 0,
        ),
      ];

      expect(QuotationsMath.subtotal(items), 250);
      expect(QuotationsMath.tax(items), 36);
      expect(QuotationsMath.total(items), 286);
    });

    test('ITBIS incluido: el total es el precio y el impuesto se extrae', () {
      final item = QuoteCreateItem(
        productId: 'p1',
        productName: 'Samsung A26',
        quantity: 1,
        unitPrice: 1000,
        taxRate: 18,
        priceIncludesTax: true,
      );

      expect(item.lineTotal, 1000);
      expect(item.lineTax, 152.54);
      expect(item.lineSubtotal, 847.46);
      expect(QuotationsMath.total([item]), 1000);
    });

    test('la línea borrador respeta ITBIS incluido y descuento', () {
      final line = QuoteDraftLine(
        product: QuoteCatalogProduct(
          id: 'p1',
          name: 'Samsung A26',
          price: 1000,
          taxRate: 18,
          stock: 7,
          isActive: true,
          priceIncludesTax: true,
        ),
        quantity: 2,
        discountPct: 10,
      );

      expect(line.lineTotal, 1800);
      expect(line.lineTax, 274.58);
      expect(line.discountAmount, 200);
    });

    test('fromMap deduce ITBIS incluido de los montos guardados', () {
      final inclusive = QuoteCreateItem.fromMap({
        'quantity': 1,
        'unit_price': 1000,
        'discount_amount': 0,
        'tax_rate': 18,
        'line_subtotal': 847.46,
        'line_tax': 152.54,
        'line_total': 1000,
      });
      final exclusive = QuoteCreateItem.fromMap({
        'quantity': 1,
        'unit_price': 1000,
        'discount_amount': 0,
        'tax_rate': 18,
        'line_subtotal': 1000,
        'line_tax': 180,
        'line_total': 1180,
      });

      expect(inclusive.priceIncludesTax, true);
      expect(inclusive.lineTotal, 1000);
      expect(exclusive.priceIncludesTax, false);
      expect(exclusive.lineTotal, 1180);
    });

    test('producto exento cobra 0% aunque tenga tasa', () {
      final product = QuoteCatalogProduct.fromMap({
        'id': 'p1',
        'name': 'Exento',
        'price': 100,
        'tax_rate': 18,
        'is_tax_exempt': true,
        'is_active': true,
      });

      expect(product.taxRate, 0);
    });
  });

  group('QuoteListItem state rules', () {
    test('marks non terminal past-due quotes as expired', () {
      final quote = QuoteListItem(
        id: 'q1',
        code: 'COT-1',
        clientName: 'Cliente',
        status: QuoteStatus.approved,
        createdAt: DateTime.now().subtract(const Duration(days: 2)),
        validUntil: DateTime.now().subtract(const Duration(days: 1)),
        total: 100,
        itemsCount: 1,
      );

      expect(quote.isExpired, true);
      expect(quote.effectiveStatus, QuoteStatus.expired);
      expect(quote.canConvert, false);
    });

    test('converted quote cannot be edited or deleted', () {
      final quote = QuoteListItem(
        id: 'q2',
        code: 'COT-2',
        clientName: 'Cliente',
        status: QuoteStatus.converted,
        createdAt: DateTime.now(),
        validUntil: DateTime.now().add(const Duration(days: 10)),
        total: 100,
        itemsCount: 1,
        saleId: 'sale-1',
      );

      expect(quote.canEdit, false);
      expect(quote.canDelete, false);
      expect(quote.canConvert, false);
    });
  });

  group('QuoteCreateItem serialization', () {
    test('toRpcMap preserves line math fields', () {
      final item = QuoteCreateItem(
        productId: 'p1',
        productName: 'Producto A',
        productSku: 'SKU-1',
        productDescription: 'Detalle',
        quantity: 2,
        unitPrice: 100,
        taxRate: 18,
      );

      expect(item.toRpcMap(), {
        'product_id': 'p1',
        'product_name': 'Producto A',
        'product_sku': 'SKU-1',
        'description': 'Detalle',
        'quantity': 2.0,
        'unit_price': 100.0,
        'discount_amount': 0,
        'tax_rate': 18.0,
        'line_subtotal': 200.0,
        'line_tax': 36.0,
        'line_total': 236.0,
      });
    });
  });
}
