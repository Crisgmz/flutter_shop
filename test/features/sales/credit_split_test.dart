import 'package:flutter_app/features/sales/domain/sale_checkout_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Los ejemplos del pedido del 6 oct 2026 (saldo a favor por nota de crédito).
void main() {
  void expectSplit(
    double available,
    double total, {
    required double applied,
    required double due,
    required double remaining,
  }) {
    final split = CreditSplit.of(total: total, available: available);
    expect(split.applied, applied, reason: 'usa');
    expect(split.due, due, reason: 'paga');
    expect(split.remaining, remaining, reason: 'le queda');
  }

  test('nota de 1,000 y compra de 800: paga 0 y le quedan 200', () {
    expectSplit(1000, 800, applied: 800, due: 0, remaining: 200);
  });

  test('vuelve con 200 y compra 700: paga 500', () {
    expectSplit(200, 700, applied: 200, due: 500, remaining: 0);
  });

  test('1,000 a favor y producto de 1,400: paga 400', () {
    expectSplit(1000, 1400, applied: 1000, due: 400, remaining: 0);
  });

  test('1,000 a favor y producto de 400: paga 0 y le quedan 600', () {
    expectSplit(1000, 400, applied: 400, due: 0, remaining: 600);
  });

  test('sin saldo o sin carrito no descuenta nada', () {
    expectSplit(0, 700, applied: 0, due: 700, remaining: 0);
    expectSplit(500, 0, applied: 0, due: 0, remaining: 500);
  });

  test('centavos exactos (sin error de doubles)', () {
    expectSplit(100.10, 100.20, applied: 100.10, due: 0.10, remaining: 0);
    expectSplit(0.3, 0.1, applied: 0.1, due: 0, remaining: 0.2);
  });
}
