import 'package:flutter_app/features/cash_register/data/cash_change.dart';
import 'package:flutter_test/flutter_test.dart';

/// Cuánto de la devuelta sale de la gaveta aparte. El resto sale del mismo
/// efectivo que entregó el cliente y no es ingreso.
void main() {
  test('pagó de más en efectivo: nada sale aparte de la gaveta', () {
    expect(
      changeWithdrawnFromDrawer(
        total: 800,
        change: 1200,
        nonCashPaid: 0,
        balanceDue: 0,
      ),
      0,
    );
  });

  test('pagó de más con tarjeta: la devuelta sale de la gaveta', () {
    expect(
      changeWithdrawnFromDrawer(
        total: 800,
        change: 200,
        nonCashPaid: 1000,
        balanceDue: 0,
      ),
      200,
    );
  });

  test('pago mixto: solo el exceso de la tarjeta sale de la gaveta', () {
    // Venta de 800: tarjeta 900 + efectivo 100, devuelta 200.
    expect(
      changeWithdrawnFromDrawer(
        total: 800,
        change: 200,
        nonCashPaid: 900,
        balanceDue: 0,
      ),
      100,
    );
  });

  test('venta con saldo pendiente no da devuelta', () {
    expect(
      changeWithdrawnFromDrawer(
        total: 800,
        change: 200,
        nonCashPaid: 1000,
        balanceDue: 50,
      ),
      0,
    );
  });
}
