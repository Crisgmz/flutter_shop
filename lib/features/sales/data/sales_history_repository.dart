import 'package:supabase_flutter/supabase_flutter.dart';

import 'sales_repository.dart' show SalePaymentLine;

export 'sales_repository.dart' show SalePaymentLine;

/// Resultado de reescribir la forma de cobro de una venta ([SalesHistoryRepository.setSalePayments]).
class SalePaymentsResult {
  const SalePaymentsResult({
    required this.status,
    required this.paidAmount,
    required this.balanceDue,
  });

  final String status;
  final double paidAmount;
  final double balanceDue;

  /// La venta quedó con saldo: aparece en Cuentas por cobrar.
  bool get isCredit => balanceDue > 0;
}

class SalesHistoryRow {
  SalesHistoryRow({
    required this.id,
    required this.branchId,
    required this.saleNumber,
    required this.saleDate,
    required this.status,
    required this.receiptType,
    required this.totalAmount,
    required this.paidAmount,
    required this.balanceDue,
    required this.itemsCount,
    this.entryKind = 'sale',
    this.ncf,
    this.clientId,
    this.clientName,
    this.cashierName,
    this.cashRegisterName,
    this.profit = 0,
    this.paymentMethod,
    this.notes,
    this.dueDate,
  });

  final String id;
  final String branchId;
  final String saleNumber;
  final DateTime saleDate;
  final String status;
  final String receiptType;
  final double totalAmount;
  final double paidAmount;
  final double balanceDue;
  final int itemsCount;

  /// `'sale'` o `'return'` — de qué tabla viene la fila en la vista
  /// `public.sales_history_entries`. Las devoluciones traen los montos ya
  /// negados desde la vista.
  final String entryKind;

  final String? ncf;
  final String? clientId;
  final String? clientName;
  final String? cashierName;
  final String? cashRegisterName;
  final double profit;
  final String? paymentMethod;
  final String? notes;
  final DateTime? dueDate;

  bool get isReturn => entryKind == 'return';

  factory SalesHistoryRow.fromMap(Map<String, dynamic> map) {
    final rawDue = map['due_date']?.toString();
    // `doc_number`/`doc_date` vienen de la vista unificada; `sale_number`/
    // `sale_date` de las consultas directas a `sales` (detalle).
    final number = map['doc_number'] ?? map['sale_number'];
    final date = map['doc_date'] ?? map['sale_date'];
    return SalesHistoryRow(
      id: (map['id'] ?? '').toString(),
      branchId: (map['branch_id'] ?? '').toString(),
      saleNumber: (number ?? '-').toString(),
      saleDate:
          DateTime.tryParse((date ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      status: (map['status'] ?? '').toString(),
      receiptType: (map['receipt_type'] ?? '').toString(),
      totalAmount: _d(map['total_amount']),
      paidAmount: _d(map['paid_amount']),
      balanceDue: _d(map['balance_due']),
      itemsCount: _i(map['items_count']),
      entryKind: (map['entry_kind'] ?? 'sale').toString(),
      ncf: _s(map['ncf']),
      clientId: _s(map['client_id']),
      clientName: _s(map['client_name']),
      cashierName: _s(map['cashier_name']),
      cashRegisterName: _s(map['cash_register_name']),
      profit: _d(map['profit']),
      paymentMethod: _s(map['payment_method']),
      notes: _s(map['notes']),
      dueDate: rawDue == null || rawDue.isEmpty
          ? null
          : DateTime.tryParse(rawDue),
    );
  }
}

class SalesHistoryPage {
  SalesHistoryPage({
    required this.rows,
    required this.hasMore,
  });

  final List<SalesHistoryRow> rows;
  final bool hasMore;
}

class SalesHistoryFilter {
  const SalesHistoryFilter({
    this.from,
    this.to,
    this.search = '',
    this.statuses = const <String>[],
    this.cashRegisterId,
  });

  final DateTime? from;
  final DateTime? to;
  final String search;
  final List<String> statuses;

  /// Caja (cash_register) cuyos documentos se quieren ver. `null` = todas.
  final String? cashRegisterId;

  SalesHistoryFilter copyWith({
    DateTime? from,
    DateTime? to,
    String? search,
    List<String>? statuses,
    String? cashRegisterId,
    bool clearFrom = false,
    bool clearTo = false,
    bool clearCashRegister = false,
  }) {
    return SalesHistoryFilter(
      from: clearFrom ? null : (from ?? this.from),
      to: clearTo ? null : (to ?? this.to),
      search: search ?? this.search,
      statuses: statuses ?? this.statuses,
      cashRegisterId:
          clearCashRegister ? null : (cashRegisterId ?? this.cashRegisterId),
    );
  }
}

class SalesHistoryRepository {
  SalesHistoryRepository(this._client);

  final SupabaseClient _client;

  /// Tamaño de página estándar para la lista de ventas anteriores.
  static const pageSize = 25;

  /// Trae una página del historial UNIFICADO (ventas + devoluciones) desde la
  /// vista `public.sales_history_entries`, con filtros y enriquecimiento
  /// (conteo de líneas, cliente, cajero, caja, ganancia, método de cobro).
  ///
  /// Las filas de devolución llegan con los montos ya NEGADOS desde la vista.
  Future<SalesHistoryPage> fetchPage({
    required int pageIndex,
    SalesHistoryFilter filter = const SalesHistoryFilter(),
  }) async {
    final branchId = await _currentBranchId();
    if (branchId == null) {
      return SalesHistoryPage(rows: const [], hasMore: false);
    }

    final clientsById = await _loadClientsById(branchId);
    final cashiersById = await _loadCashiersById();

    final from = pageIndex * pageSize;
    final to = from + pageSize; // pedimos 1 extra para saber si hay más

    var query = _client
        .from('sales_history_entries')
        .select(
          'entry_kind, id, branch_id, doc_number, doc_date, status, '
          'receipt_type, ncf, subtotal, tax_amount, total_amount, '
          'paid_amount, balance_due, due_date, client_id, cashier_id, '
          'cash_session_id, notes, refund_method',
        )
        .eq('branch_id', branchId);
    // Nota: las ventas anuladas (voided) SÍ se incluyen — deben quedar en el
    // historial marcadas como "Anulada", no desaparecer.

    if (filter.from != null) {
      query = query.gte('doc_date', filter.from!.toIso8601String());
    }
    if (filter.to != null) {
      // incluir todo el día
      final endOfDay = DateTime(
        filter.to!.year,
        filter.to!.month,
        filter.to!.day,
        23,
        59,
        59,
      );
      query = query.lte('doc_date', endOfDay.toIso8601String());
    }
    if (filter.statuses.isNotEmpty) {
      query = query.inFilter('status', filter.statuses);
    }
    final search = filter.search.trim();
    if (search.isNotEmpty) {
      // Número de documento, NCF o IMEI. Si el texto parece un IMEI (6+
      // caracteres) resolvemos primero IMEI → ids y los sumamos al OR.
      final conditions = <String>[
        'doc_number.ilike.%$search%',
        'ncf.ilike.%$search%',
      ];
      if (search.length >= 6) {
        final ids = await _resolveIdsByImei(branchId, search);
        if (ids.isNotEmpty) {
          conditions.add('id.in.(${ids.join(",")})');
        }
      }
      query = query.or(conditions.join(','));
    }

    // Filtro por caja: los documentos guardan `cash_session_id`, así que se
    // traducen las sesiones de esa caja a ids. Si la caja nunca abrió sesión,
    // no hay nada que mostrar.
    final registerId = filter.cashRegisterId;
    if (registerId != null && registerId.isNotEmpty) {
      final sessionIds = await _sessionIdsForRegister(
        branchId: branchId,
        cashRegisterId: registerId,
        filter: filter,
      );
      if (sessionIds.isEmpty) {
        return SalesHistoryPage(rows: const [], hasMore: false);
      }
      query = query.inFilter('cash_session_id', sessionIds);
    }

    final rows = await query
        .order('doc_date', ascending: false)
        .range(from, to);

    final list = rows
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList(growable: false);

    final hasMore = list.length > pageSize;
    final page = hasMore ? list.sublist(0, pageSize) : list;

    bool isReturnRow(Map<String, dynamic> m) =>
        (m['entry_kind'] ?? 'sale').toString() == 'return';

    final saleIds = page
        .where((m) => !isReturnRow(m))
        .map((m) => (m['id'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .toList(growable: false);
    final returnIds = page
        .where(isReturnRow)
        .map((m) => (m['id'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .toList(growable: false);

    // Conteo de líneas: las ventas viven en sale_items, las devoluciones en
    // return_items. Una query por tabla.
    final itemsCount = <String, int>{
      ...await _loadLineCounts('sale_items', 'sale_id', branchId, saleIds),
      ...await _loadLineCounts(
        'return_items',
        'return_id',
        branchId,
        returnIds,
      ),
    };

    // Caja (registro) que hizo cada documento, ganancia y método de cobro.
    final sessionIds = page
        .map((m) => m['cash_session_id']?.toString())
        .whereType<String>()
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList(growable: false);
    final registerBySession = await _loadRegisterNames(sessionIds);
    final cogsById = <String, double>{
      ...await _loadCogs('sale_items', 'sale_id', branchId, saleIds),
      ...await _loadCogs('return_items', 'return_id', branchId, returnIds),
    };
    final methodBySale = await _loadPaymentMethods(branchId, saleIds);

    final result = page.map((m) {
      final id = (m['id'] ?? '').toString();
      final isReturn = isReturnRow(m);
      final clientId = m['client_id']?.toString();
      final cashierId = m['cashier_id']?.toString();
      final sessionId = m['cash_session_id']?.toString();
      m['items_count'] = itemsCount[id] ?? 0;
      m['client_name'] =
          clientId == null ? null : clientsById[clientId];
      m['cashier_name'] =
          cashierId == null ? null : cashiersById[cashierId];
      m['cash_register_name'] =
          sessionId == null ? null : registerBySession[sessionId];
      // Venta: ganancia = subtotal − COGS. Devolución: el subtotal ya viene
      // NEGADO desde la vista, así que sumar el costo devuelto deja la
      // ganancia en negativo (que es lo correcto: se revierte la utilidad).
      final cogs = cogsById[id] ?? 0;
      final subtotal = _d(m['subtotal']);
      m['profit'] = isReturn ? subtotal + cogs : subtotal - cogs;
      // En una devolución el "cobro" es por dónde salió el reembolso.
      m['payment_method'] =
          isReturn ? _s(m['refund_method']) : methodBySale[id];
      return SalesHistoryRow.fromMap(m);
    }).toList(growable: false);

    return SalesHistoryPage(rows: result, hasMore: hasMore);
  }

  /// Sesiones (cash_sessions) de una caja, para traducir "caja 1" a los
  /// `cash_session_id` que llevan las ventas y devoluciones.
  ///
  /// Se acota al rango de fechas del filtro cuando lo hay: una caja acumula
  /// una sesión por día y por cajero, y mandar años de ids en la URL sería
  /// una consulta enorme. Sin rango se toman las 500 sesiones más recientes,
  /// que es mucho más de lo que cubre el historial paginado en pantalla.
  Future<List<String>> _sessionIdsForRegister({
    required String branchId,
    required String cashRegisterId,
    required SalesHistoryFilter filter,
  }) async {
    var query = _client
        .from('cash_sessions')
        .select('id')
        .eq('branch_id', branchId)
        .eq('cash_register_id', cashRegisterId);

    if (filter.to != null) {
      final endOfDay = DateTime(
        filter.to!.year,
        filter.to!.month,
        filter.to!.day,
        23,
        59,
        59,
      );
      query = query.lte('opened_at', endOfDay.toIso8601String());
    }
    if (filter.from != null) {
      // Una sesión abierta antes del rango puede seguir facturando dentro de
      // él: solo se descartan las que ya habían cerrado antes de empezar.
      query = query.or(
        'closed_at.is.null,closed_at.gte.${filter.from!.toIso8601String()}',
      );
    }

    final rows = await query.order('opened_at', ascending: false).limit(500);
    return rows
        .map((row) => ((row as Map)['id'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .toList(growable: false);
  }

  /// Ids (de venta y de devolución) que contienen un IMEI dado. Usa los índices
  /// GIN `sale_items_imeis_gin` / `return_items_imeis_gin`.
  Future<List<String>> _resolveIdsByImei(String branchId, String imei) async {
    final ids = <String>{};

    final saleRows = await _client
        .from('sale_items')
        .select('sale_id')
        .eq('branch_id', branchId)
        .contains('imeis', [imei]);
    for (final raw in saleRows) {
      final id = (raw as Map)['sale_id']?.toString();
      if (id != null && id.isNotEmpty) ids.add(id);
    }

    final returnRows = await _client
        .from('return_items')
        .select('return_id')
        .eq('branch_id', branchId)
        .contains('imeis', [imei]);
    for (final raw in returnRows) {
      final id = (raw as Map)['return_id']?.toString();
      if (id != null && id.isNotEmpty) ids.add(id);
    }

    return ids.toList(growable: false);
  }

  /// Edita la venta completa: reemplaza items, ajusta stock y recalcula
  /// totales. Vía RPC `edit_sale_transactional` para que todo ocurra en una
  /// sola transacción del backend.
  ///
  /// `items` debe ser una lista de mapas con: product_id, description,
  /// quantity, unit_price, `discount_amount` e `imeis`.
  ///
  /// El descuento viaja en MONTO, igual que en checkout/hold (migraciones 76 y
  /// 77). El RPC todavía acepta `discount_pct` como fallback, pero mandarlo
  /// desde aquí perdía plata: en productos con ITBIS incluido el porcentaje
  /// reconstruido leía el impuesto como descuento y bajaba el total al guardar.
  ///
  /// `imeis` NO es opcional en la práctica: el RPC devuelve al inventario los
  /// IMEIs de las líneas viejas antes de borrarlas y solo los vuelve a sacar
  /// si el payload nuevo los trae. Si se omiten, los equipos ya entregados
  /// quedan disponibles y se pueden vender a un segundo cliente.
  Future<SalesEditResult> editSale({
    required String saleId,
    required List<Map<String, dynamic>> items,
    String? clientId,
    bool clearClient = false,
    String? notes,
    bool clearNotes = false,
  }) async {
    final result = await _client.rpc(
      'edit_sale_transactional',
      params: {
        'p_sale_id': saleId,
        'p_items': items,
        'p_client_id': clientId,
        'p_clear_client': clearClient,
        'p_notes': notes,
        'p_clear_notes': clearNotes,
      },
    );
    final map = Map<String, dynamic>.from(result as Map);
    return SalesEditResult(
      saleId: (map['sale_id'] ?? saleId).toString(),
      subtotal: _d(map['subtotal']),
      taxAmount: _d(map['tax_amount']),
      totalAmount: _d(map['total_amount']),
      paidAmount: _d(map['paid_amount']),
      balanceDue: _d(map['balance_due']),
      itemsCount: _i(map['items_count']),
    );
  }

  /// Anula una venta y devuelve el stock + borra los pagos asociados.
  /// Llama al RPC `void_sale_with_stock_return` que hace todo atómicamente
  /// dentro de una transacción. El trigger trg_sale_items_stock se encarga
  /// de sumar el stock devuelto al producto.
  Future<void> voidSaleWithStockReturn(String saleId) async {
    await _client.rpc(
      'void_sale_with_stock_return',
      params: {'p_sale_id': saleId},
    );
  }

  /// Actualiza notas y/o cliente de una venta. No toca items ni totales.
  Future<void> updateSaleMetadata({
    required String saleId,
    String? notes,
    String? clientId,
    bool clearClient = false,
  }) async {
    final branchId = await _currentBranchId();
    if (branchId == null) {
      throw Exception('No hay sucursal asignada.');
    }
    final patch = <String, dynamic>{};
    if (notes != null) {
      final trimmed = notes.trim();
      patch['notes'] = trimmed.isEmpty ? null : trimmed;
    }
    if (clearClient) {
      patch['client_id'] = null;
    } else if (clientId != null) {
      patch['client_id'] = clientId;
    }
    if (patch.isEmpty) return;

    await _client
        .from('sales')
        .update(patch)
        .eq('id', saleId)
        .eq('branch_id', branchId);
  }

  /// Detalle de una venta con sus items, para mostrar en el viewer / edit.
  Future<SalesHistoryDetail?> fetchDetail(String saleId) async {
    final branchId = await _currentBranchId();
    if (branchId == null) return null;

    final saleRows = await _client
        .from('sales')
        .select(
          'id, branch_id, sale_number, sale_date, status, receipt_type, '
          'ncf, subtotal, tax_amount, total_amount, paid_amount, '
          'balance_due, due_date, client_id, cashier_id, notes',
        )
        .eq('id', saleId)
        .eq('branch_id', branchId)
        .limit(1);
    if (saleRows.isEmpty) return null;
    final sale = Map<String, dynamic>.from(saleRows.first as Map);

    final itemRows = await _client
        .from('sale_items')
        .select(
          'id, product_id, description, quantity, unit_price, '
          'discount_amount, tax_rate, line_subtotal, line_tax, line_total, '
          // Los IMEIs de la línea son obligatorios al editar: el RPC los
          // devuelve al inventario y solo los vuelve a sacar si el payload
          // nuevo los trae. Sin esta columna la edición libera los equipos.
          'imeis',
        )
        .eq('sale_id', saleId)
        .order('created_at');

    final clientId = sale['client_id']?.toString();
    String? clientName;
    if (clientId != null && clientId.isNotEmpty) {
      final clientRows = await _client
          .from('clients')
          .select('full_name')
          .eq('id', clientId)
          .limit(1);
      if (clientRows.isNotEmpty) {
        clientName =
            (clientRows.first as Map)['full_name']?.toString();
      }
    }

    // TODAS las filas de pago de la venta: el editor necesita el desglose
    // completo para poder corregirlo sin aplastar un pago mixto.
    final paymentRows = await _client
        .from('payments')
        .select('payment_method, amount')
        .eq('sale_id', saleId)
        .eq('branch_id', branchId)
        .order('created_at');

    final payments = paymentRows
        .map((row) {
          final item = Map<String, dynamic>.from(row as Map);
          return SalesHistoryPayment(
            method: (item['payment_method'] ?? 'cash').toString(),
            amount: _d(item['amount']),
          );
        })
        .toList(growable: false);

    // Método primario (el primero registrado), que es lo que muestran el
    // listado y la reimpresión cuando no hace falta el desglose.
    final paymentMethod = payments.isEmpty ? null : payments.first.method;

    return SalesHistoryDetail(
      sale: SalesHistoryRow.fromMap({
        ...sale,
        'client_name': clientName,
        'items_count': itemRows.length,
      }),
      items: itemRows
          .map((row) => SalesHistoryItem.fromMap(
                Map<String, dynamic>.from(row as Map),
              ))
          .toList(growable: false),
      subtotal: _d(sale['subtotal']),
      taxAmount: _d(sale['tax_amount']),
      paymentMethod: paymentMethod,
      payments: payments,
    );
  }

  /// Detalle de una DEVOLUCIÓN con sus líneas, para el mismo visor del
  /// historial. Los montos se devuelven en positivo (es lo que se reintegró);
  /// la fila del listado es la que los muestra negados.
  Future<SalesHistoryDetail?> fetchReturnDetail(String returnId) async {
    final branchId = await _currentBranchId();
    if (branchId == null) return null;

    final rows = await _client
        .from('returns')
        .select(
          'id, branch_id, return_number, return_date, client_id, cashier_id, '
          'notes, subtotal, tax_amount, total_amount, refund_method',
        )
        .eq('id', returnId)
        .eq('branch_id', branchId)
        .limit(1);
    if (rows.isEmpty) return null;
    final ret = Map<String, dynamic>.from(rows.first as Map);

    final itemRows = await _client
        .from('return_items')
        .select(
          'id, product_id, description, quantity, unit_price, tax_rate, '
          'line_subtotal, line_tax, line_total, imeis',
        )
        .eq('branch_id', branchId)
        .eq('return_id', returnId)
        .order('created_at');

    final clientId = ret['client_id']?.toString();
    String? clientName;
    if (clientId != null && clientId.isNotEmpty) {
      final clientRows = await _client
          .from('clients')
          .select('full_name')
          .eq('id', clientId)
          .limit(1);
      if (clientRows.isNotEmpty) {
        clientName = (clientRows.first as Map)['full_name']?.toString();
      }
    }

    final total = _d(ret['total_amount']);
    return SalesHistoryDetail(
      sale: SalesHistoryRow.fromMap({
        'entry_kind': 'return',
        'id': ret['id'],
        'branch_id': ret['branch_id'],
        'doc_number': ret['return_number'],
        'doc_date': ret['return_date'],
        'status': 'returned',
        'receipt_type': null,
        'total_amount': total,
        'paid_amount': total,
        'balance_due': 0,
        'client_id': clientId,
        'client_name': clientName,
        'notes': ret['notes'],
        'items_count': itemRows.length,
      }),
      items: itemRows
          .map((row) => SalesHistoryItem.fromMap(
                Map<String, dynamic>.from(row as Map),
              ))
          .toList(growable: false),
      subtotal: _d(ret['subtotal']),
      taxAmount: _d(ret['tax_amount']),
      paymentMethod: _s(ret['refund_method']),
    );
  }

  /// Cambia el método de pago de todos los `payments` de una venta.
  /// Llama al RPC `update_sale_payment_method` que valida acceso y rol.
  ///
  /// Solo corrige la ETIQUETA del método sin tocar montos ni estado. Para
  /// cambiar cómo se cobró de verdad (pasar a crédito, dividir en varios
  /// métodos, cobrar un crédito) usar [setSalePayments], que además recalcula
  /// balance, estado y saldo del cliente.
  Future<int> updateSalePaymentMethod({
    required String saleId,
    required String paymentMethod,
  }) async {
    final result = await _client.rpc(
      'update_sale_payment_method',
      params: {
        'p_sale_id': saleId,
        'p_payment_method': paymentMethod,
      },
    );
    if (result is int) return result;
    return int.tryParse(result?.toString() ?? '') ?? 0;
  }

  /// Reemplaza la forma de cobro completa de una venta (migración 82).
  ///
  /// [payments] son las líneas {método, monto} que quedan cobradas. Lo que no
  /// cubran queda como saldo pendiente: la venta pasa a `credit`, entra en
  /// Cuentas por cobrar y suma al balance del cliente. Una lista vacía deja la
  /// venta entera a crédito.
  Future<SalePaymentsResult> setSalePayments({
    required String saleId,
    required List<SalePaymentLine> payments,
    int? creditDueDays,
  }) async {
    final result = await _client.rpc(
      'set_sale_payments',
      params: {
        'p_sale_id': saleId,
        'p_payments':
            payments.map((p) => p.toJson()).toList(growable: false),
        'p_credit_due_days': ?creditDueDays,
      },
    );

    final map = Map<String, dynamic>.from(result as Map);
    return SalePaymentsResult(
      status: (map['status'] ?? '').toString(),
      paidAmount: _d(map['paid_amount']),
      balanceDue: _d(map['balance_due']),
    );
  }

  /// Cantidad de líneas por documento. Sirve igual para `sale_items`
  /// (`sale_id`) que para `return_items` (`return_id`).
  Future<Map<String, int>> _loadLineCounts(
    String table,
    String idColumn,
    String branchId,
    List<String> ids,
  ) async {
    if (ids.isEmpty) return const {};
    final rows = await _client
        .from(table)
        .select(idColumn)
        .eq('branch_id', branchId)
        .inFilter(idColumn, ids);

    final counts = <String, int>{};
    for (final row in rows) {
      final key = ((row as Map)[idColumn] ?? '').toString();
      if (key.isEmpty) continue;
      counts[key] = (counts[key] ?? 0) + 1;
    }
    return counts;
  }

  /// Nombre de la caja (cash_register) por cada cash_session_id.
  /// sales.cash_session_id -> cash_sessions.cash_register_id -> cash_registers.name
  Future<Map<String, String>> _loadRegisterNames(
    List<String> sessionIds,
  ) async {
    if (sessionIds.isEmpty) return const {};
    final rows = await _client
        .from('cash_sessions')
        .select('id, cash_registers(name)')
        .inFilter('id', sessionIds);
    final result = <String, String>{};
    for (final raw in rows) {
      final row = Map<String, dynamic>.from(raw as Map);
      final id = row['id']?.toString();
      final reg = row['cash_registers'];
      final name = reg is Map ? reg['name']?.toString() : null;
      if (id != null && name != null && name.isNotEmpty) {
        result[id] = name;
      }
    }
    return result;
  }

  /// COGS (costo de lo vendido / devuelto) por documento =
  /// Σ(cantidad × costo del producto). Sirve para `sale_items` (`sale_id`) y
  /// para `return_items` (`return_id`). La ganancia se calcula luego como
  /// subtotal − COGS, igual que las vistas de márgenes del sistema.
  Future<Map<String, double>> _loadCogs(
    String table,
    String idColumn,
    String branchId,
    List<String> ids,
  ) async {
    if (ids.isEmpty) return const {};
    final items = await _client
        .from(table)
        .select('$idColumn, product_id, quantity')
        .eq('branch_id', branchId)
        .inFilter(idColumn, ids);

    final productIds = <String>{};
    for (final raw in items) {
      final pid = (raw as Map)['product_id']?.toString();
      if (pid != null && pid.isNotEmpty) productIds.add(pid);
    }

    final productCosts = <String, double>{};
    if (productIds.isNotEmpty) {
      final products = await _client
          .from('products')
          .select('id, cost')
          .inFilter('id', productIds.toList(growable: false));
      for (final raw in products) {
        final row = Map<String, dynamic>.from(raw as Map);
        final id = row['id']?.toString();
        if (id != null) productCosts[id] = _d(row['cost']);
      }
    }

    final cogs = <String, double>{};
    for (final raw in items) {
      final row = Map<String, dynamic>.from(raw as Map);
      final key = row[idColumn]?.toString();
      if (key == null || key.isEmpty) continue;
      final qty = _d(row['quantity']);
      final cost = productCosts[row['product_id']?.toString()] ?? 0;
      cogs[key] = (cogs[key] ?? 0) + qty * cost;
    }
    return cogs;
  }

  /// Método de cobro por venta. Si hay varios métodos distintos en una misma
  /// venta lo marca como 'mixed'. Si no hay pagos registrados, queda null.
  Future<Map<String, String>> _loadPaymentMethods(
    String branchId,
    List<String> saleIds,
  ) async {
    if (saleIds.isEmpty) return const {};
    final rows = await _client
        .from('payments')
        .select('sale_id, payment_method')
        .eq('branch_id', branchId)
        .inFilter('sale_id', saleIds);

    final methods = <String, Set<String>>{};
    for (final raw in rows) {
      final row = Map<String, dynamic>.from(raw as Map);
      final sid = row['sale_id']?.toString();
      final method = row['payment_method']?.toString();
      if (sid == null || method == null || method.isEmpty) continue;
      methods.putIfAbsent(sid, () => <String>{}).add(method);
    }

    // Devolvemos los métodos usados unidos por coma (en orden de inserción),
    // ej. "cash,transfer". La UI los traduce y muestra "Efectivo + Transferencia".
    return {
      for (final entry in methods.entries) entry.key: entry.value.join(','),
    };
  }

  Future<Map<String, String>> _loadClientsById(String branchId) async {
    final rows = await _client
        .from('clients')
        .select('id, full_name')
        .eq('branch_id', branchId);
    return {
      for (final row in rows)
        ((row as Map)['id'] ?? '').toString():
            (row['full_name'] ?? '').toString(),
    };
  }

  Future<Map<String, String>> _loadCashiersById() async {
    final rows = await _client.from('profiles').select('id, full_name');
    return {
      for (final row in rows)
        ((row as Map)['id'] ?? '').toString():
            (row['full_name'] ?? '').toString(),
    };
  }

  Future<String?> _currentBranchId() async {
    final result = await _client.rpc('current_branch_id');
    if (result == null) return null;
    final value = result.toString();
    return value.isEmpty ? null : value;
  }
}

/// Una fila de `payments` de la venta, para el editor de forma de cobro.
class SalesHistoryPayment {
  const SalesHistoryPayment({required this.method, required this.amount});

  final String method;
  final double amount;
}

class SalesHistoryDetail {
  SalesHistoryDetail({
    required this.sale,
    required this.items,
    required this.subtotal,
    required this.taxAmount,
    this.paymentMethod,
    this.payments = const <SalesHistoryPayment>[],
  });

  final SalesHistoryRow sale;
  final List<SalesHistoryItem> items;
  final double subtotal;
  final double taxAmount;

  /// Método de pago primario de la venta (de la primera fila en `payments`).
  /// Null si la venta no tiene pagos registrados todavía.
  final String? paymentMethod;

  /// TODAS las filas de `payments` de la venta. Una venta con pago mixto tiene
  /// varias; el editor las carga tal cual para no destruir el desglose al
  /// guardar (antes solo se leía la primera y se reescribían todas iguales).
  final List<SalesHistoryPayment> payments;
}

class SalesEditResult {
  SalesEditResult({
    required this.saleId,
    required this.subtotal,
    required this.taxAmount,
    required this.totalAmount,
    required this.paidAmount,
    required this.balanceDue,
    required this.itemsCount,
  });

  final String saleId;
  final double subtotal;
  final double taxAmount;
  final double totalAmount;
  final double paidAmount;
  final double balanceDue;
  final int itemsCount;
}

class SalesHistoryItem {
  SalesHistoryItem({
    required this.id,
    required this.productId,
    required this.description,
    required this.quantity,
    required this.unitPrice,
    required this.taxRate,
    required this.lineSubtotal,
    required this.lineTax,
    required this.lineTotal,
    this.discountAmount = 0,
    this.imeis = const <String>[],
  });

  final String id;
  final String? productId;
  final String description;
  final double quantity;
  final double unitPrice;
  final double taxRate;

  /// Descuento de la línea en MONTO (no porcentaje), tal como lo guardó el
  /// backend. Es el dato que se reenvía al editar: reconstruir un porcentaje
  /// desde `line_subtotal` leía el ITBIS incluido como si fuera descuento.
  final double discountAmount;

  final double lineSubtotal;
  final double lineTax;
  final double lineTotal;

  /// Equipos serializados que salieron en esta línea. Si no está vacío, la
  /// cantidad de la línea equivale a la cantidad de IMEIs.
  final List<String> imeis;

  factory SalesHistoryItem.fromMap(Map<String, dynamic> map) {
    return SalesHistoryItem(
      id: (map['id'] ?? '').toString(),
      productId: _s(map['product_id']),
      description: (map['description'] ?? '').toString(),
      quantity: _d(map['quantity']),
      unitPrice: _d(map['unit_price']),
      taxRate: _d(map['tax_rate']),
      discountAmount: _d(map['discount_amount']),
      lineSubtotal: _d(map['line_subtotal']),
      lineTax: _d(map['line_tax']),
      lineTotal: _d(map['line_total']),
      imeis: _strList(map['imeis']),
    );
  }
}

/// Lista de textos no vacíos de una columna `text[]` de PostgREST.
List<String> _strList(dynamic v) {
  if (v is! List) return const <String>[];
  return v
      .map((e) => e.toString().trim())
      .where((e) => e.isNotEmpty)
      .toList(growable: false);
}

double _d(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? 0;
}

int _i(dynamic v) {
  if (v == null) return 0;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString()) ?? 0;
}

String? _s(dynamic v) {
  if (v == null) return null;
  final s = v.toString().trim();
  return s.isEmpty ? null : s;
}
