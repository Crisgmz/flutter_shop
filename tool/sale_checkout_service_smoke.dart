import '../lib/features/sales/domain/sale_checkout_service.dart';

void main() {
  const service = SaleCheckoutService();

  const product = SaleCheckoutSourceProduct(
    id: 'p1',
    name: 'Producto Demo',
    price: 100,
    taxRate: 18,
    stock: 10,
    isActive: true,
  );

  final checkout = service.normalize(
    const SaleCheckoutServiceInput(
      items: [
        SaleCheckoutSourceItem(product: product, quantity: 1),
        SaleCheckoutSourceItem(product: product, quantity: 2),
      ],
      receiptType: 'Crédito Fiscal',
      asCredit: false,
      paymentMethod: 'cash',
      clientId: 'client-1',
    ),
  );

  if (checkout.receiptType != 'fiscal_credit') {
    throw StateError('receiptType no normalizado');
  }
  if (checkout.items.length != 1) {
    throw StateError('no consolidó líneas');
  }
  if (checkout.items.first.quantity != 3) {
    throw StateError('cantidad incorrecta');
  }
  if (checkout.total != 354) {
    throw StateError('total incorrecto: ${checkout.total}');
  }

  var threw = false;
  try {
    service.normalize(
      const SaleCheckoutServiceInput(
        items: [SaleCheckoutSourceItem(product: product, quantity: 11)],
        receiptType: 'consumer_final',
        asCredit: false,
      ),
    );
  } catch (_) {
    threw = true;
  }

  if (!threw) {
    throw StateError('no rechazó stock insuficiente');
  }

  print('sale_checkout_service_smoke: OK');
}
