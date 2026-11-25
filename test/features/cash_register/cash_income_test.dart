import 'package:flutter_app/features/cash_register/data/cash_register_repository.dart';
import 'package:flutter_test/flutter_test.dart';

/// "Ingreso efectivo" es lo que se queda en la gaveta, no lo que el cliente
/// entregó: venta de 800 pagada con 2,000 → ingreso 800, devuelta 1,200.
void main() {
  double expectedFromCards(CashSessionMetrics m, double opening) =>
      opening +
      m.cashIncome -
      m.cashWithdrawnForChange -
      m.cashExpenses -
      m.cashRefunds +
      m.cashDeposits +
      m.cashAdjustments -
      m.cashWithdrawals;

  test('pago en efectivo de más: el ingreso es el total de la venta', () {
    final m = CashSessionMetrics(
      totalPayments: 2000,
      cashPayments: 2000,
      totalExpenses: 0,
      cashExpenses: 0,
      salesTotal: 800,
      changeGiven: 1200,
    );

    expect(m.cashIncome, 800);
    expect(m.netCollected, 800);
    expect(m.expectedCashFromOpening(0), 800);
  });

  test('devuelta de un pago con tarjeta sale de la gaveta aparte', () {
    // Venta de 800 cobrada con 1,000 por tarjeta: la devuelta de 200 sale
    // del efectivo de la caja.
    final m = CashSessionMetrics(
      totalPayments: 1000,
      cashPayments: 0,
      cardPayments: 1000,
      totalExpenses: 0,
      cashExpenses: 0,
      salesTotal: 800,
      changeGiven: 200,
      cashWithdrawnForChange: 200,
    );

    expect(m.cashIncome, 0);
    expect(m.netCollected, 800);
    expect(m.expectedCashFromOpening(500), 300);
  });

  test('las tarjetas de la caja suman el esperado', () {
    final m = CashSessionMetrics(
      totalPayments: 11020,
      cashPayments: 2920,
      transferPayments: 8100,
      totalExpenses: 200,
      cashExpenses: 200,
      salesTotal: 9800,
      changeGiven: 1300,
      cashWithdrawnForChange: 100,
      cashRefunds: 50,
      cashDeposits: 500,
      cashWithdrawals: 300,
    );

    expect(m.cashIncome, 1720);
    expect(expectedFromCards(m, 1000), m.expectedCashFromOpening(1000));
  });
}
