// Dashboard repository (PRD Dashboard 06).
//
// Tres RPCs Supabase:
//   - dashboard_v2_kpis(branch_id)         → 4 contadores (F1)
//   - dashboard_v2_sales_chart(branch_id, range) → serie temporal (F3)
//   - dashboard_v2_closeout(branch_id, date)     → 6 bloques (F4)
//
// El repositorio mantiene los DTOs ya públicos (`DashboardKpis`, `LatestSale`,
// `SalesSummaryPoint`) por compatibilidad con código legacy si lo hubiera,
// pero las nuevas pantallas usan los DTOs v2 (DashboardKpisV2, etc.).

import 'package:supabase_flutter/supabase_flutter.dart';

enum DashboardChartRange { month, week }

/// Hero KPIs (las 4 tarjetas de colores fuertes del Panel).
/// Origen: vista `dashboard_kpis_by_branch` en `03_reports_views.sql`.
class DashboardHeroKpis {
  const DashboardHeroKpis({
    required this.salesTodayAmount,
    required this.salesTodayCount,
    required this.salesMonthAmount,
    required this.salesMonthCount,
    required this.productsActive,
    required this.clientsActive,
  });

  factory DashboardHeroKpis.fromMap(Map<String, dynamic> map) {
    return DashboardHeroKpis(
      salesTodayAmount: _toDouble(map['sales_today_amount']),
      salesTodayCount: _toInt(map['sales_today_count']),
      salesMonthAmount: _toDouble(map['sales_month_amount']),
      salesMonthCount: _toInt(map['sales_month_count']),
      productsActive: _toInt(map['products_active']),
      clientsActive: _toInt(map['clients_active']),
    );
  }

  final double salesTodayAmount;
  final int salesTodayCount;
  final double salesMonthAmount;
  final int salesMonthCount;
  final int productsActive;
  final int clientsActive;

  static const empty = DashboardHeroKpis(
    salesTodayAmount: 0,
    salesTodayCount: 0,
    salesMonthAmount: 0,
    salesMonthCount: 0,
    productsActive: 0,
    clientsActive: 0,
  );
}

// ─────────────────────────────────────────────────────────────────────────
// DTOs v2 (PRD Dashboard 06)
// ─────────────────────────────────────────────────────────────────────────

class DashboardKpisV2 {
  const DashboardKpisV2({
    required this.totalVentas,
    required this.totalInventario,
    required this.totalClientes,
    required this.totalKits,
    this.partial = false,
  });

  factory DashboardKpisV2.fromMap(Map<String, dynamic> map) {
    return DashboardKpisV2(
      totalVentas: _toInt(map['total_ventas']),
      totalInventario: _toInt(map['total_inventario']),
      totalClientes: _toInt(map['total_clientes']),
      totalKits: _toInt(map['total_kits']),
      partial: map['partial'] == true,
    );
  }

  final int totalVentas;
  final int totalInventario;
  final int totalClientes;
  final int totalKits;
  final bool partial;
}

class DashboardChartPoint {
  const DashboardChartPoint({
    required this.date,
    required this.transactions,
    required this.total,
  });

  factory DashboardChartPoint.fromMap(Map<String, dynamic> map) {
    return DashboardChartPoint(
      date: DateTime.tryParse((map['date'] ?? '').toString()) ?? DateTime.now(),
      transactions: _toInt(map['transactions']),
      total: _toDouble(map['total']),
    );
  }

  final DateTime date;
  final int transactions;
  final double total;
}

class DashboardCloseoutSales {
  const DashboardCloseoutSales({
    required this.salesTotalNoTax,
    required this.salesTotalWithTax,
    required this.profit,
    required this.inventoryQtyOnHand,
    required this.inventoryValue,
    required this.breakdownByCategory,
    required this.transactionsCount,
    required this.avgTicket,
    required this.itemsSold,
    required this.taxAmount,
    required this.noTaxAmount,
    required this.cashAmount,
  });

  factory DashboardCloseoutSales.fromMap(Map<String, dynamic> map) {
    return DashboardCloseoutSales(
      salesTotalNoTax: _toDouble(map['sales_total_no_tax']),
      salesTotalWithTax: _toDouble(map['sales_total_with_tax']),
      profit: _toDouble(map['profit']),
      inventoryQtyOnHand: _toDouble(map['inventory_qty_on_hand']),
      inventoryValue: _toDouble(map['inventory_value']),
      breakdownByCategory: _toCategoryList(map['breakdown_by_category']),
      transactionsCount: _toInt(map['transactions_count']),
      avgTicket: _toDouble(map['avg_ticket']),
      itemsSold: _toDouble(map['items_sold']),
      taxAmount: _toDouble(map['tax_amount']),
      noTaxAmount: _toDouble(map['no_tax_amount']),
      cashAmount: _toDouble(map['cash_amount']),
    );
  }

  final double salesTotalNoTax;
  final double salesTotalWithTax;
  final double profit;
  final double inventoryQtyOnHand;
  final double inventoryValue;
  final List<DashboardCategoryAmount> breakdownByCategory;
  final int transactionsCount;
  final double avgTicket;
  final double itemsSold;
  final double taxAmount;
  final double noTaxAmount;
  final double cashAmount;
}

class DashboardCategoryAmount {
  const DashboardCategoryAmount({required this.name, required this.amount});

  factory DashboardCategoryAmount.fromMap(Map<String, dynamic> map) {
    return DashboardCategoryAmount(
      name: (map['name'] ?? '').toString(),
      amount: _toDouble(map['amount']),
    );
  }

  final String name;
  final double amount;
}

/// Distribución de la venta del día agrupada por método de pago.
/// Se calcula desde la tabla `payments` en `fetchPaymentBreakdown`.
class DashboardPaymentBreakdown {
  const DashboardPaymentBreakdown({
    required this.entries,
    required this.total,
  });

  final List<DashboardPaymentEntry> entries;
  final double total;

  static const empty = DashboardPaymentBreakdown(entries: [], total: 0);
}

class DashboardPaymentEntry {
  const DashboardPaymentEntry({
    required this.method,
    required this.label,
    required this.amount,
    required this.count,
  });

  final String method;
  final String label;
  final double amount;
  final int count;
}

/// Una caja (cash_register) con lo que vendió y ganó en el día.
class DashboardRegisterSalesEntry {
  const DashboardRegisterSalesEntry({
    required this.registerId,
    required this.registerName,
    required this.salesTotal,
    required this.creditTotal,
    required this.profit,
    required this.transactionsCount,
  });

  /// Vacío para la cubeta "Sin caja asignada".
  final String registerId;
  final String registerName;

  /// Venta con impuestos (`sales.total_amount`), igual que el ticket.
  /// Incluye las ventas a crédito de esa caja.
  final double salesTotal;

  /// Parte de [salesTotal] que quedó a crédito (ventas en estado `credit`).
  /// Es justo la diferencia contra la fila "Ventas totales (con impuestos)"
  /// del bloque Ventas, que solo cuenta las `completed`.
  final double creditTotal;

  /// Ganancia = subtotal − COGS. SIN ITBIS: el impuesto no es ganancia.
  final double profit;

  final int transactionsCount;
}

/// Desagregación "Venta por caja" del Cierre del día.
class DashboardSalesByRegister {
  const DashboardSalesByRegister({
    required this.entries,
    required this.salesTotal,
    required this.creditTotal,
    required this.profit,
  });

  final List<DashboardRegisterSalesEntry> entries;

  /// Total vendido por todas las cajas, crédito incluido.
  final double salesTotal;

  /// Cuánto de [salesTotal] quedó a crédito. Se muestra aparte para que el
  /// total del bloque sea reconciliable con el bloque Ventas.
  final double creditTotal;

  final double profit;

  static const empty = DashboardSalesByRegister(
    entries: [],
    salesTotal: 0,
    creditTotal: 0,
    profit: 0,
  );
}

class DashboardCloseoutCredit {
  const DashboardCloseoutCredit({
    required this.debits,
    required this.credits,
    required this.storeAccountBalanceTotal,
  });

  factory DashboardCloseoutCredit.fromMap(Map<String, dynamic> map) {
    return DashboardCloseoutCredit(
      debits: _toDouble(map['debits']),
      credits: _toDouble(map['credits']),
      storeAccountBalanceTotal: _toDouble(map['store_account_balance_total']),
    );
  }

  final double debits;
  final double credits;
  final double storeAccountBalanceTotal;
}

class DashboardCloseoutReturns {
  const DashboardCloseoutReturns({
    required this.returnsTotal,
    required this.breakdownByItem,
    required this.transactionsCount,
    required this.itemsReturned,
    required this.taxAmount,
    required this.returnsTableAvailable,
  });

  factory DashboardCloseoutReturns.fromMap(Map<String, dynamic> map) {
    final raw = map['breakdown_by_item'];
    final items = raw is List
        ? raw
              .map(
                (item) => DashboardReturnItem.fromMap(
                  Map<String, dynamic>.from(item as Map),
                ),
              )
              .toList(growable: false)
        : const <DashboardReturnItem>[];
    return DashboardCloseoutReturns(
      returnsTotal: _toDouble(map['returns_total']),
      breakdownByItem: items,
      transactionsCount: _toInt(map['transactions_count']),
      itemsReturned: _toDouble(map['items_returned']),
      taxAmount: _toDouble(map['tax_amount']),
      returnsTableAvailable: map['returns_table_available'] == true,
    );
  }

  final double returnsTotal;
  final List<DashboardReturnItem> breakdownByItem;
  final int transactionsCount;
  final double itemsReturned;
  final double taxAmount;

  /// Cuando false, los datos provienen del proxy `sales.status = voided` —
  /// la tabla `returns` (PRD F5) aún no existe.
  final bool returnsTableAvailable;
}

class DashboardReturnItem {
  const DashboardReturnItem({
    required this.description,
    required this.quantity,
    required this.amount,
  });

  factory DashboardReturnItem.fromMap(Map<String, dynamic> map) {
    return DashboardReturnItem(
      description: (map['description'] ?? '').toString(),
      quantity: _toDouble(map['quantity']),
      amount: _toDouble(map['amount']),
    );
  }

  final String description;
  final double quantity;
  final double amount;
}

class DashboardCloseoutPurchases {
  const DashboardCloseoutPurchases({
    required this.receivingsTotalNoTax,
    required this.receivingsTotalWithTax,
    required this.transactionsCount,
    required this.avgTicket,
    required this.itemsReceived,
    required this.taxAmount,
    required this.noTaxAmount,
  });

  factory DashboardCloseoutPurchases.fromMap(Map<String, dynamic> map) {
    return DashboardCloseoutPurchases(
      receivingsTotalNoTax: _toDouble(map['receivings_total_no_tax']),
      receivingsTotalWithTax: _toDouble(map['receivings_total_with_tax']),
      transactionsCount: _toInt(map['transactions_count']),
      avgTicket: _toDouble(map['avg_ticket']),
      itemsReceived: _toDouble(map['items_received']),
      taxAmount: _toDouble(map['tax_amount']),
      noTaxAmount: _toDouble(map['no_tax_amount']),
    );
  }

  final double receivingsTotalNoTax;
  final double receivingsTotalWithTax;
  final int transactionsCount;
  final double avgTicket;
  final double itemsReceived;
  final double taxAmount;
  final double noTaxAmount;
}

class DashboardCloseoutExpenses {
  const DashboardCloseoutExpenses({
    required this.expensesTotal,
    required this.transactionsCount,
  });

  factory DashboardCloseoutExpenses.fromMap(Map<String, dynamic> map) {
    return DashboardCloseoutExpenses(
      expensesTotal: _toDouble(map['expenses_total']),
      transactionsCount: _toInt(map['transactions_count']),
    );
  }

  final double expensesTotal;
  final int transactionsCount;
}

class DashboardCashMonitoring {
  const DashboardCashMonitoring({
    required this.enabled,
    this.sessionId,
    this.openedAt,
    this.closedAt,
    this.openingAmount,
    this.expectedAmount,
    this.closingAmount,
    this.differenceAmount,
    this.status,
  });

  factory DashboardCashMonitoring.fromMap(Map<String, dynamic> map) {
    return DashboardCashMonitoring(
      enabled: map['enabled'] == true,
      sessionId: map['session_id']?.toString(),
      openedAt: DateTime.tryParse(map['opened_at']?.toString() ?? ''),
      closedAt: DateTime.tryParse(map['closed_at']?.toString() ?? ''),
      openingAmount:
          map['opening_amount'] == null ? null : _toDouble(map['opening_amount']),
      expectedAmount:
          map['expected_amount'] == null ? null : _toDouble(map['expected_amount']),
      closingAmount:
          map['closing_amount'] == null ? null : _toDouble(map['closing_amount']),
      differenceAmount: map['difference_amount'] == null
          ? null
          : _toDouble(map['difference_amount']),
      status: map['status']?.toString(),
    );
  }

  final bool enabled;
  final String? sessionId;
  final DateTime? openedAt;
  final DateTime? closedAt;
  final double? openingAmount;
  final double? expectedAmount;
  final double? closingAmount;
  final double? differenceAmount;
  final String? status;
}

class DashboardCloseout {
  const DashboardCloseout({
    required this.date,
    required this.sales,
    required this.credit,
    required this.returns,
    required this.purchases,
    required this.expenses,
    required this.cashMonitoring,
    this.partial = false,
  });

  factory DashboardCloseout.fromMap(Map<String, dynamic> map) {
    return DashboardCloseout(
      date: DateTime.tryParse(map['date']?.toString() ?? '') ?? DateTime.now(),
      sales: DashboardCloseoutSales.fromMap(
        Map<String, dynamic>.from(map['sales'] as Map? ?? {}),
      ),
      credit: DashboardCloseoutCredit.fromMap(
        Map<String, dynamic>.from(map['credit'] as Map? ?? {}),
      ),
      returns: DashboardCloseoutReturns.fromMap(
        Map<String, dynamic>.from(map['returns'] as Map? ?? {}),
      ),
      purchases: DashboardCloseoutPurchases.fromMap(
        Map<String, dynamic>.from(map['purchases'] as Map? ?? {}),
      ),
      expenses: DashboardCloseoutExpenses.fromMap(
        Map<String, dynamic>.from(map['expenses'] as Map? ?? {}),
      ),
      cashMonitoring: DashboardCashMonitoring.fromMap(
        Map<String, dynamic>.from(map['cash_monitoring'] as Map? ?? {}),
      ),
      partial: map['partial'] == true,
    );
  }

  final DateTime date;
  final DashboardCloseoutSales sales;
  final DashboardCloseoutCredit credit;
  final DashboardCloseoutReturns returns;
  final DashboardCloseoutPurchases purchases;
  final DashboardCloseoutExpenses expenses;
  final DashboardCashMonitoring cashMonitoring;
  final bool partial;
}

// ─────────────────────────────────────────────────────────────────────────
// Repository
// ─────────────────────────────────────────────────────────────────────────

class DashboardRepository {
  DashboardRepository(this._client);

  final SupabaseClient _client;

  Future<DashboardKpisV2> fetchKpis() async {
    final result = await _client.rpc('dashboard_v2_kpis');
    final map = result is Map
        ? Map<String, dynamic>.from(result)
        : <String, dynamic>{};
    return DashboardKpisV2.fromMap(map);
  }

  /// KPIs del panel. Preferimos el RPC `dashboard_hero_kpis` (migración 65):
  /// SECURITY DEFINER que valida el acceso una vez y consulta por índices —
  /// la vista `dashboard_kpis_by_branch` ejecutaba la RLS fila por fila y en
  /// instalaciones con datos cancelaba por statement_timeout (57014). Si el
  /// RPC aún no existe en la BD, caemos a la vista como antes.
  Future<DashboardHeroKpis> fetchHeroKpis() async {
    try {
      final result = await _client.rpc('dashboard_hero_kpis');
      if (result is Map) {
        final map = Map<String, dynamic>.from(result);
        if (map.isEmpty) return DashboardHeroKpis.empty;
        return DashboardHeroKpis.fromMap(map);
      }
    } on PostgrestException catch (error) {
      // PGRST202 = función no encontrada (migración 65 sin correr): fallback.
      if (error.code != 'PGRST202' && error.code != '42883') rethrow;
    }

    final branchIdResult = await _client.rpc('current_branch_id');
    final branchId = branchIdResult?.toString();
    if (branchId == null || branchId.isEmpty) {
      return DashboardHeroKpis.empty;
    }

    final rows = await _client
        .from('dashboard_kpis_by_branch')
        .select()
        .eq('branch_id', branchId)
        .limit(1);

    if (rows.isEmpty) return DashboardHeroKpis.empty;
    return DashboardHeroKpis.fromMap(
      Map<String, dynamic>.from(rows.first as Map),
    );
  }

  Future<List<DashboardChartPoint>> fetchSalesChart(
    DashboardChartRange range,
  ) async {
    final result = await _client.rpc(
      'dashboard_v2_sales_chart',
      params: {'p_range': range == DashboardChartRange.week ? 'week' : 'month'},
    );
    if (result is! List) return const [];
    return result
        .map((item) => DashboardChartPoint.fromMap(
              Map<String, dynamic>.from(item as Map),
            ))
        .toList(growable: false);
  }

  Future<DashboardCloseout> fetchCloseout(DateTime date) async {
    final iso = '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
    final result = await _client.rpc(
      'dashboard_v2_closeout',
      params: {'p_date': iso},
    );
    final map = result is Map
        ? Map<String, dynamic>.from(result)
        : <String, dynamic>{};
    return DashboardCloseout.fromMap(map);
  }

  /// Distribución de los cobros del día agrupada por método de pago.
  /// Lee directamente de `payments` filtrando por la sucursal del usuario
  /// y el rango [day 00:00, day+1 00:00) en hora local.
  Future<DashboardPaymentBreakdown> fetchPaymentBreakdown(DateTime date) async {
    final start = DateTime(date.year, date.month, date.day);
    final end = start.add(const Duration(days: 1));

    final rows = await _client
        .from('payments')
        .select('payment_method, amount')
        .gte('paid_at', start.toIso8601String())
        .lt('paid_at', end.toIso8601String());

    final totals = <String, double>{};
    final counts = <String, int>{};
    for (final row in rows) {
      final map = Map<String, dynamic>.from(row as Map);
      final method = (map['payment_method'] ?? '').toString();
      if (method.isEmpty) continue;
      final amount = _toDouble(map['amount']);
      totals[method] = (totals[method] ?? 0) + amount;
      counts[method] = (counts[method] ?? 0) + 1;
    }

    final entries = totals.entries
        .map((e) => DashboardPaymentEntry(
              method: e.key,
              label: _paymentMethodLabel(e.key),
              amount: e.value,
              count: counts[e.key] ?? 0,
            ))
        .toList()
      ..sort((a, b) => b.amount.compareTo(a.amount));

    final total = totals.values.fold<double>(0, (a, b) => a + b);
    return DashboardPaymentBreakdown(entries: entries, total: total);
  }

  /// "Venta por caja": cada caja de la sucursal con su venta y su ganancia
  /// del día. Todo en Dart, sin RPC nuevo.
  ///
  /// - Venta = `sales.total_amount` (con ITBIS), lo mismo que el ticket.
  /// - Ganancia = `sales.subtotal` − COGS, o sea SIN ITBIS. Es el mismo
  ///   criterio de la columna "Ganancia" del Historial de ventas. OJO: la fila
  ///   "Beneficios" del bloque Ventas viene del RPC `dashboard_v2_closeout`,
  ///   que usa total_amount − COGS (CON ITBIS), así que va a dar más alto.
  /// - Las ventas sin `cash_session_id` caen en "Sin caja asignada" para que
  ///   ninguna venta del día quede fuera del bloque.
  ///
  /// OJO: el total de este bloque NO cuadra con "Ventas totales (con
  /// impuestos)" del bloque Ventas. Aquí se cuentan `completed` + `credit`
  /// (la venta a crédito sí se despachó por esa caja), mientras que el RPC
  /// `dashboard_v2_closeout` solo cuenta `completed`. La diferencia es
  /// exactamente [DashboardSalesByRegister.creditTotal], que se expone aparte
  /// para que el dueño pueda reconciliar ambos números.
  ///
  /// El rango se manda en UTC (`toUtc()`), a diferencia de
  /// `fetchPaymentBreakdown`, que manda un ISO local sin offset y PostgREST
  /// interpreta como UTC.
  Future<DashboardSalesByRegister> fetchSalesByCashRegister(
    DateTime date,
  ) async {
    final branchId = await _currentBranchId();
    if (branchId == null) return DashboardSalesByRegister.empty;

    final start = DateTime(date.year, date.month, date.day);
    final end = start.add(const Duration(days: 1));

    // Paginado: en un día con muchas ventas una sola consulta se cortaría en
    // el tope de PostgREST y el resto quedaría fuera del bloque.
    final saleRows = await _fetchAllPages(
      (from, to) => _client
          .from('sales')
          .select('id, cash_session_id, status, subtotal, total_amount')
          .eq('branch_id', branchId)
          // Se excluyen anuladas y borradores (cuentas guardadas).
          // Las cuentas guardadas ('pending') NO son ventas todavía: no tienen
          // cobro ni caja, así que no entran en la venta del día.
          .inFilter('status', const ['completed', 'credit'])
          .gte('sale_date', start.toUtc().toIso8601String())
          .lt('sale_date', end.toUtc().toIso8601String())
          // Orden estable: sin ORDER BY el paginado puede repetir o saltar.
          .order('id')
          .range(from, to),
    );

    if (saleRows.isEmpty) return DashboardSalesByRegister.empty;

    final saleIds = <String>[];
    final sessionIds = <String>{};
    for (final row in saleRows) {
      final id = (row['id'] ?? '').toString();
      if (id.isNotEmpty) saleIds.add(id);
      final sessionId = (row['cash_session_id'] ?? '').toString();
      if (sessionId.isNotEmpty) sessionIds.add(sessionId);
    }

    final registerNames = await _loadRegisterNames(sessionIds.toList());
    final cogsBySale = await _loadCogsBySale(branchId, saleIds);

    // Agrupación por caja. La clave es el id de la caja; '' = sin caja.
    final names = <String, String>{};
    final sales = <String, double>{};
    final credits = <String, double>{};
    final profits = <String, double>{};
    final counts = <String, int>{};

    for (final row in saleRows) {
      final saleId = (row['id'] ?? '').toString();
      final sessionId = (row['cash_session_id'] ?? '').toString();
      final register = registerNames[sessionId];
      final key = register?.id ?? '';
      final total = _toDouble(row['total_amount']);
      names[key] = register?.name ?? 'Sin caja asignada';
      sales[key] = (sales[key] ?? 0) + total;
      if ((row['status'] ?? '').toString() == 'credit') {
        credits[key] = (credits[key] ?? 0) + total;
      }
      profits[key] = (profits[key] ?? 0) +
          (_toDouble(row['subtotal']) - (cogsBySale[saleId] ?? 0));
      counts[key] = (counts[key] ?? 0) + 1;
    }

    final entries = names.keys
        .map((key) => DashboardRegisterSalesEntry(
              registerId: key,
              registerName: names[key] ?? 'Sin caja asignada',
              salesTotal: sales[key] ?? 0,
              creditTotal: credits[key] ?? 0,
              profit: profits[key] ?? 0,
              transactionsCount: counts[key] ?? 0,
            ))
        .toList()
      ..sort((a, b) => b.salesTotal.compareTo(a.salesTotal));

    return DashboardSalesByRegister(
      entries: entries,
      salesTotal: sales.values.fold<double>(0, (a, b) => a + b),
      creditTotal: credits.values.fold<double>(0, (a, b) => a + b),
      profit: profits.values.fold<double>(0, (a, b) => a + b),
    );
  }

  /// Caja (id + nombre) por cada `cash_session_id`.
  /// sales.cash_session_id → cash_sessions.cash_register_id → cash_registers.
  Future<Map<String, _RegisterRef>> _loadRegisterNames(
    List<String> sessionIds,
  ) async {
    if (sessionIds.isEmpty) return const {};
    final rows = await _fetchByIdBatches(
      sessionIds,
      (batch, from, to) => _client
          .from('cash_sessions')
          .select('id, cash_register_id, cash_registers(name)')
          .inFilter('id', batch)
          .order('id')
          .range(from, to),
    );

    final result = <String, _RegisterRef>{};
    for (final row in rows) {
      final sessionId = (row['id'] ?? '').toString();
      final registerId = (row['cash_register_id'] ?? '').toString();
      final register = row['cash_registers'];
      final name = register is Map ? register['name']?.toString() : null;
      if (sessionId.isEmpty || registerId.isEmpty) continue;
      if (name == null || name.isEmpty) continue;
      result[sessionId] = _RegisterRef(id: registerId, name: name);
    }
    return result;
  }

  /// COGS por venta = Σ(cantidad × costo del producto). Mismo criterio que el
  /// Historial de ventas.
  Future<Map<String, double>> _loadCogsBySale(
    String branchId,
    List<String> saleIds,
  ) async {
    if (saleIds.isEmpty) return const {};
    // Un día con muchas ventas pasa fácil de 1000 líneas: sin paginar, las
    // líneas que faltan se tratarían como costo 0 e inflarían la ganancia en
    // silencio. El troceo de ids además evita URLs enormes (error 414).
    final items = await _fetchByIdBatches(
      saleIds,
      (batch, from, to) => _client
          .from('sale_items')
          .select('sale_id, product_id, quantity')
          .eq('branch_id', branchId)
          .inFilter('sale_id', batch)
          .order('id')
          .range(from, to),
    );

    final productIds = <String>{};
    for (final row in items) {
      final pid = (row['product_id'] ?? '').toString();
      if (pid.isNotEmpty) productIds.add(pid);
    }

    final productCosts = <String, double>{};
    if (productIds.isNotEmpty) {
      final products = await _fetchByIdBatches(
        productIds.toList(growable: false),
        (batch, from, to) => _client
            .from('products')
            .select('id, cost')
            .inFilter('id', batch)
            .order('id')
            .range(from, to),
      );
      for (final row in products) {
        final id = (row['id'] ?? '').toString();
        if (id.isNotEmpty) productCosts[id] = _toDouble(row['cost']);
      }
    }

    final cogs = <String, double>{};
    for (final row in items) {
      final saleId = (row['sale_id'] ?? '').toString();
      if (saleId.isEmpty) continue;
      final cost = productCosts[(row['product_id'] ?? '').toString()] ?? 0;
      cogs[saleId] = (cogs[saleId] ?? 0) + _toDouble(row['quantity']) * cost;
    }
    return cogs;
  }

  /// Recorre una consulta pidiendo páginas de [_pageSize] filas hasta que se
  /// agotan. Supabase corta cada consulta en su tope (1000 filas por defecto)
  /// sin avisar, así que sin esto los datos faltantes se leerían como cero.
  /// [page] recibe el rango inclusivo que hay que pasarle a `.range()`.
  Future<List<Map<String, dynamic>>> _fetchAllPages(
    Future<List<dynamic>> Function(int from, int to) page,
  ) async {
    final rows = <Map<String, dynamic>>[];
    var from = 0;
    while (true) {
      final chunk = await page(from, from + _pageSize - 1);
      if (chunk.isEmpty) break;
      rows.addAll(chunk.map((e) => Map<String, dynamic>.from(e as Map)));
      from += chunk.length;
      if (chunk.length < _pageSize) break;
    }
    return rows;
  }

  /// Igual que [_fetchAllPages] pero troceando la lista de ids del `inFilter`
  /// en lotes de [_idBatchSize]: un `in.(...)` con ~1000 UUIDs arma una URL de
  /// decenas de KB que un gateway puede rechazar con 414.
  Future<List<Map<String, dynamic>>> _fetchByIdBatches(
    List<String> ids,
    Future<List<dynamic>> Function(List<String> batch, int from, int to) page,
  ) async {
    final rows = <Map<String, dynamic>>[];
    for (var start = 0; start < ids.length; start += _idBatchSize) {
      final end = start + _idBatchSize;
      final batch = ids.sublist(start, end > ids.length ? ids.length : end);
      rows.addAll(
        await _fetchAllPages((from, to) => page(batch, from, to)),
      );
    }
    return rows;
  }

  Future<String?> _currentBranchId() async {
    final result = await _client.rpc('current_branch_id');
    if (result == null) return null;
    final value = result.toString();
    return value.isEmpty ? null : value;
  }

  String _paymentMethodLabel(String method) {
    switch (method) {
      case 'cash':
        return 'Efectivo';
      case 'card':
        return 'Tarjeta';
      case 'transfer':
        return 'Transferencia';
      case 'mobile':
        return 'Pago móvil';
      case 'credit':
        return 'Crédito';
      case 'mixed':
        return 'Mixto';
      default:
        return method;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────

/// Filas que devuelve PostgREST por consulta antes de cortar (tope por
/// defecto de Supabase). Las consultas grandes se piden por páginas de este
/// tamaño.
const int _pageSize = 1000;

/// Máximo de ids por `inFilter`. Con lotes chicos la URL se mantiene corta y
/// no la rechaza un gateway intermedio.
const int _idBatchSize = 200;

/// Caja resuelta a partir de una sesión (uso interno de "Venta por caja").
class _RegisterRef {
  const _RegisterRef({required this.id, required this.name});

  final String id;
  final String name;
}

double _toDouble(dynamic value) {
  if (value == null) return 0;
  if (value is double) return value;
  if (value is int) return value.toDouble();
  return double.tryParse(value.toString()) ?? 0;
}

int _toInt(dynamic value) {
  if (value == null) return 0;
  if (value is int) return value;
  if (value is double) return value.toInt();
  return int.tryParse(value.toString()) ?? 0;
}

List<DashboardCategoryAmount> _toCategoryList(dynamic value) {
  if (value is! List) return const [];
  return value
      .map((item) => DashboardCategoryAmount.fromMap(
            Map<String, dynamic>.from(item as Map),
          ))
      .toList(growable: false);
}
