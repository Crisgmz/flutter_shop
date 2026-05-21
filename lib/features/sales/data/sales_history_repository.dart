import 'package:supabase_flutter/supabase_flutter.dart';

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
    this.ncf,
    this.clientId,
    this.clientName,
    this.cashierName,
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
  final String? ncf;
  final String? clientId;
  final String? clientName;
  final String? cashierName;
  final String? notes;
  final DateTime? dueDate;

  factory SalesHistoryRow.fromMap(Map<String, dynamic> map) {
    final rawDue = map['due_date']?.toString();
    return SalesHistoryRow(
      id: (map['id'] ?? '').toString(),
      branchId: (map['branch_id'] ?? '').toString(),
      saleNumber: (map['sale_number'] ?? '-').toString(),
      saleDate:
          DateTime.tryParse((map['sale_date'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      status: (map['status'] ?? '').toString(),
      receiptType: (map['receipt_type'] ?? '').toString(),
      totalAmount: _d(map['total_amount']),
      paidAmount: _d(map['paid_amount']),
      balanceDue: _d(map['balance_due']),
      itemsCount: _i(map['items_count']),
      ncf: _s(map['ncf']),
      clientId: _s(map['client_id']),
      clientName: _s(map['client_name']),
      cashierName: _s(map['cashier_name']),
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
  });

  final DateTime? from;
  final DateTime? to;
  final String search;
  final List<String> statuses;

  SalesHistoryFilter copyWith({
    DateTime? from,
    DateTime? to,
    String? search,
    List<String>? statuses,
    bool clearFrom = false,
    bool clearTo = false,
  }) {
    return SalesHistoryFilter(
      from: clearFrom ? null : (from ?? this.from),
      to: clearTo ? null : (to ?? this.to),
      search: search ?? this.search,
      statuses: statuses ?? this.statuses,
    );
  }
}

class SalesHistoryRepository {
  SalesHistoryRepository(this._client);

  final SupabaseClient _client;

  /// Tamaño de página estándar para la lista de ventas anteriores.
  static const pageSize = 25;

  /// Trae una página de ventas con filtros + cantidad de items por venta.
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
        .from('sales')
        .select(
          'id, branch_id, sale_number, sale_date, status, receipt_type, '
          'ncf, total_amount, paid_amount, balance_due, due_date, '
          'client_id, cashier_id, notes',
        )
        .eq('branch_id', branchId)
        .neq('status', 'voided');

    if (filter.from != null) {
      query = query.gte('sale_date', filter.from!.toIso8601String());
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
      query = query.lte('sale_date', endOfDay.toIso8601String());
    }
    if (filter.statuses.isNotEmpty) {
      query = query.inFilter('status', filter.statuses);
    }
    final search = filter.search.trim();
    if (search.isNotEmpty) {
      // sale_number o ncf
      query = query.or(
        'sale_number.ilike.%$search%,ncf.ilike.%$search%',
      );
    }

    final rows = await query
        .order('sale_date', ascending: false)
        .range(from, to);

    final list = rows
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList(growable: false);

    final hasMore = list.length > pageSize;
    final page = hasMore ? list.sublist(0, pageSize) : list;

    // Conteo de items por venta — una sola query con IN.
    final saleIds = page.map((m) => (m['id'] ?? '').toString()).toList();
    final itemsCount = await _loadItemsCount(branchId, saleIds);

    final result = page.map((m) {
      final id = (m['id'] ?? '').toString();
      final clientId = m['client_id']?.toString();
      final cashierId = m['cashier_id']?.toString();
      m['items_count'] = itemsCount[id] ?? 0;
      m['client_name'] =
          clientId == null ? null : clientsById[clientId];
      m['cashier_name'] =
          cashierId == null ? null : cashiersById[cashierId];
      return SalesHistoryRow.fromMap(m);
    }).toList(growable: false);

    return SalesHistoryPage(rows: result, hasMore: hasMore);
  }

  /// Edita la venta completa: reemplaza items, ajusta stock y recalcula
  /// totales. Vía RPC `edit_sale_transactional` para que todo ocurra en una
  /// sola transacción del backend.
  ///
  /// `items` debe ser una lista de mapas con: product_id, description,
  /// quantity, unit_price, discount_pct.
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
          'discount_amount, tax_rate, line_subtotal, line_tax, line_total',
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
    );
  }

  Future<Map<String, int>> _loadItemsCount(
    String branchId,
    List<String> saleIds,
  ) async {
    if (saleIds.isEmpty) return const {};
    final rows = await _client
        .from('sale_items')
        .select('sale_id')
        .eq('branch_id', branchId)
        .inFilter('sale_id', saleIds);

    final counts = <String, int>{};
    for (final row in rows) {
      final sid = ((row as Map)['sale_id'] ?? '').toString();
      counts[sid] = (counts[sid] ?? 0) + 1;
    }
    return counts;
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

class SalesHistoryDetail {
  SalesHistoryDetail({
    required this.sale,
    required this.items,
    required this.subtotal,
    required this.taxAmount,
  });

  final SalesHistoryRow sale;
  final List<SalesHistoryItem> items;
  final double subtotal;
  final double taxAmount;
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
  });

  final String id;
  final String? productId;
  final String description;
  final double quantity;
  final double unitPrice;
  final double taxRate;
  final double lineSubtotal;
  final double lineTax;
  final double lineTotal;

  factory SalesHistoryItem.fromMap(Map<String, dynamic> map) {
    return SalesHistoryItem(
      id: (map['id'] ?? '').toString(),
      productId: _s(map['product_id']),
      description: (map['description'] ?? '').toString(),
      quantity: _d(map['quantity']),
      unitPrice: _d(map['unit_price']),
      taxRate: _d(map['tax_rate']),
      lineSubtotal: _d(map['line_subtotal']),
      lineTax: _d(map['line_tax']),
      lineTotal: _d(map['line_total']),
    );
  }
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
