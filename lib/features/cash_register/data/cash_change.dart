import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/select_in.dart';

// La devuelta en efectivo.
//
// `payments.amount` guarda lo que el cliente ENTREGÓ (2,000 por una venta de
// 800) y la devuelta va aparte en `sales.change_amount` (1,200). Es el diseño
// de las RPC de venta compartidas con shop-plus, así que no se cambia: toda
// pantalla que muestre "efectivo cobrado" tiene que quitarle la devuelta.

/// Parte de la devuelta que el cajero sacó de la gaveta APARTE: solo pasa
/// cuando el cliente pagó de más con tarjeta o transferencia. El resto de la
/// devuelta sale del mismo efectivo que el cliente entregó. Una venta con
/// saldo pendiente no da devuelta.
double changeWithdrawnFromDrawer({
  required double total,
  required double change,
  required double nonCashPaid,
  required double balanceDue,
}) {
  if (change <= 0 || balanceDue > 0) return 0;
  final excess = nonCashPaid - total;
  if (excess <= 0) return 0;
  return excess > change ? change : excess;
}

/// Devuelta que salió del efectivo entregado por los clientes, en las ventas
/// de [branchId] con fecha en [[start], [end]). Restada del efectivo cobrado
/// da el efectivo que de verdad entró.
///
/// [completedOnly]: solo ventas pagadas, que son las que cuenta el
/// "Efectivo" de `dashboard_v2_closeout`.
Future<double> fetchChangeFromCustomerCash(
  SupabaseClient client, {
  required String branchId,
  required DateTime start,
  required DateTime end,
  bool completedOnly = false,
}) async {
  final base = client
      .from('sales')
      .select('id, total_amount, change_amount, balance_due')
      .eq('branch_id', branchId)
      // En UTC: sin la zona el servidor lee la medianoche local como UTC.
      .gte('sale_date', start.toUtc().toIso8601String())
      .lt('sale_date', end.toUtc().toIso8601String())
      .gt('change_amount', 0);
  final sales = completedOnly
      ? await base.eq('status', 'completed')
      : await base.neq('status', 'voided');
  if (sales.isEmpty) return 0;

  final payments = await selectIn(
    client,
    table: 'payments',
    columns: 'sale_id, amount, payment_method',
    column: 'sale_id',
    values: sales.map((sale) => sale['id'].toString()),
  );
  final nonCashBySale = <String, double>{};
  for (final payment in payments) {
    if (payment['payment_method']?.toString() == 'cash') continue;
    final saleId = payment['sale_id'].toString();
    nonCashBySale[saleId] =
        (nonCashBySale[saleId] ?? 0) + _toDouble(payment['amount']);
  }

  var fromCustomerCash = 0.0;
  for (final sale in sales) {
    final change = _toDouble(sale['change_amount']);
    fromCustomerCash += change -
        changeWithdrawnFromDrawer(
          total: _toDouble(sale['total_amount']),
          change: change,
          nonCashPaid: nonCashBySale[sale['id'].toString()] ?? 0,
          balanceDue: _toDouble(sale['balance_due']),
        );
  }
  return (fromCustomerCash * 100).roundToDouble() / 100;
}

/// El resultado de `dashboard_v2_closeout` (RPC compartido con shop-plus) con
/// `sales.cash_amount` neto: el RPC suma lo que el cliente entregó, devuelta
/// incluida. [day] es el mismo día que se le pidió al RPC; la sucursal, la
/// actual, como en el RPC.
Future<Map<String, dynamic>> closeoutWithNetCash(
  SupabaseClient client,
  Map<String, dynamic> closeout,
  DateTime day,
) async {
  final sales = closeout['sales'];
  if (sales is! Map) return closeout;
  final branchId = (await client.rpc('current_branch_id'))?.toString() ?? '';
  if (branchId.isEmpty) return closeout;

  final start = DateTime(day.year, day.month, day.day);
  final change = await fetchChangeFromCustomerCash(
    client,
    branchId: branchId,
    start: start,
    end: start.add(const Duration(days: 1)),
    completedOnly: true,
  );
  if (change <= 0) return closeout;

  final gross = _toDouble(sales['cash_amount']);
  return {
    ...closeout,
    'sales': {
      ...Map<String, dynamic>.from(sales),
      'cash_amount': ((gross - change) * 100).roundToDouble() / 100,
    },
  };
}

double _toDouble(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}
