import 'package:supabase_flutter/supabase_flutter.dart';

import '../../printing/data/account_statement.dart';

/// Compra con saldo pendiente de pago a un proveedor (cuenta por pagar).
/// Espejo de `ReceivableSale` del módulo de Cuentas por Cobrar.
class PayablePurchase {
  PayablePurchase({
    required this.id,
    required this.purchaseNumber,
    required this.invoiceNumber,
    required this.purchaseDate,
    required this.supplierId,
    required this.supplierName,
    required this.totalAmount,
    required this.paidAmount,
    required this.balanceDue,
    required this.status,
    required this.dueDate,
  });

  final String id;
  final String purchaseNumber;
  final String? invoiceNumber;
  final DateTime purchaseDate;
  final String? supplierId;
  final String supplierName;
  final double totalAmount;
  final double paidAmount;
  final double balanceDue;
  final String status;

  /// Fecha de vencimiento del crédito con el proveedor (null si es de contado
  /// o una compra vieja sin migrar).
  final DateTime? dueDate;

  int? get daysUntilDue {
    if (dueDate == null) return null;
    final today = DateTime.now();
    final t = DateTime(today.year, today.month, today.day);
    final d = DateTime(dueDate!.year, dueDate!.month, dueDate!.day);
    return d.difference(t).inDays;
  }

  bool get isOverdue {
    final d = daysUntilDue;
    return d != null && d < 0;
  }

  bool isNearDue(int warnDays) {
    final d = daysUntilDue;
    return d != null && d >= 0 && d <= warnDays;
  }

  /// Fila del PDF de la lista de cuentas por pagar.
  StatementDocument toStatementDocument() => StatementDocument(
        id: id,
        date: purchaseDate,
        number: purchaseNumber,
        reference: invoiceNumber,
        partyName: supplierName,
        dueDate: dueDate,
        total: totalAmount,
        paid: paidAmount,
        balance: balanceDue,
      );

  factory PayablePurchase.fromMap(
    Map<String, dynamic> map,
    Map<String, String> suppliersById,
  ) {
    final supplierId = map['supplier_id']?.toString();
    final rawDue = map['due_date']?.toString();

    return PayablePurchase(
      id: (map['id'] ?? '').toString(),
      purchaseNumber: (map['purchase_number'] ?? '-').toString(),
      invoiceNumber: map['invoice_number']?.toString(),
      purchaseDate:
          DateTime.tryParse((map['purchase_date'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      supplierId: supplierId,
      supplierName: supplierId == null
          ? 'Proveedor general'
          : (suppliersById[supplierId] ?? 'Proveedor general'),
      totalAmount: _toDouble(map['total_amount']),
      paidAmount: _toDouble(map['paid_amount']),
      balanceDue: _toDouble(map['balance_due']),
      status: (map['status'] ?? '').toString(),
      dueDate: rawDue == null || rawDue.isEmpty
          ? null
          : DateTime.tryParse(rawDue),
    );
  }
}

/// Abono registrado a un proveedor. Espejo de `ReceivedPayment`.
class SupplierPaymentRow {
  SupplierPaymentRow({
    required this.id,
    required this.purchaseId,
    required this.purchaseNumber,
    required this.supplierName,
    required this.amount,
    required this.paymentMethod,
    required this.paidAt,
    required this.reference,
  });

  final String id;
  final String? purchaseId;
  final String purchaseNumber;
  final String supplierName;
  final double amount;
  final String paymentMethod;
  final DateTime paidAt;
  final String? reference;

  factory SupplierPaymentRow.fromMap(
    Map<String, dynamic> map,
    Map<String, String> suppliersById,
    Map<String, String> purchasesById,
  ) {
    final supplierId = map['supplier_id']?.toString();
    final purchaseId = map['purchase_id']?.toString();

    return SupplierPaymentRow(
      id: (map['id'] ?? '').toString(),
      purchaseId: purchaseId,
      purchaseNumber: purchaseId == null ? '-' : (purchasesById[purchaseId] ?? '-'),
      supplierName: supplierId == null
          ? 'Proveedor general'
          : (suppliersById[supplierId] ?? 'Proveedor general'),
      amount: _toDouble(map['amount']),
      paymentMethod: (map['payment_method'] ?? '').toString(),
      paidAt:
          DateTime.tryParse((map['paid_at'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      reference: map['reference']?.toString(),
    );
  }
}

class PayablePaymentInput {
  PayablePaymentInput({
    required this.purchaseId,
    required this.amount,
    required this.paymentMethod,
    this.reference,
    this.notes,
  });

  final String purchaseId;
  final double amount;
  final String paymentMethod;
  final String? reference;
  final String? notes;
}

class PayablesRepository {
  PayablesRepository(this._client);

  final SupabaseClient _client;

  Future<List<PayablePurchase>> fetchPayables() async {
    final branchId = await _currentBranchId();
    if (branchId == null) return const [];

    final suppliersById = await _loadSuppliersById(branchId);

    final rows = await _client
        .from('purchases')
        .select(
          'id, purchase_number, invoice_number, purchase_date, supplier_id, '
          'total_amount, paid_amount, balance_due, status, due_date',
        )
        .eq('branch_id', branchId)
        .gt('balance_due', 0)
        .neq('status', 'cancelled')
        .order('due_date', ascending: true, nullsFirst: false)
        .order('purchase_date', ascending: false);

    return rows
        .map(
          (item) => PayablePurchase.fromMap(
            Map<String, dynamic>.from(item as Map),
            suppliersById,
          ),
        )
        .toList(growable: false);
  }

  Future<List<SupplierPaymentRow>> fetchSupplierPayments() async {
    final branchId = await _currentBranchId();
    if (branchId == null) return const [];

    final suppliersById = await _loadSuppliersById(branchId);
    final purchasesById = await _loadPurchasesById(branchId);

    final rows = await _client
        .from('supplier_payments')
        .select(
          'id, purchase_id, supplier_id, amount, payment_method, paid_at, reference',
        )
        .eq('branch_id', branchId)
        .order('paid_at', ascending: false)
        .limit(30);

    return rows
        .map(
          (item) => SupplierPaymentRow.fromMap(
            Map<String, dynamic>.from(item as Map),
            suppliersById,
            purchasesById,
          ),
        )
        .toList(growable: false);
  }

  Future<void> registerPayment(PayablePaymentInput input) async {
    final branchId = await _currentBranchId();
    if (branchId == null) {
      throw Exception('No hay sucursal asignada para este usuario.');
    }

    final purchase = await _client
        .from('purchases')
        .select('id, supplier_id, paid_amount, balance_due, total_amount')
        .eq('id', input.purchaseId)
        .eq('branch_id', branchId)
        .single();

    final currentBalance = _toDouble(purchase['balance_due']);
    if (currentBalance <= 0) {
      throw Exception('La compra no tiene saldo pendiente.');
    }
    if (input.amount <= 0) {
      throw Exception('El monto debe ser mayor que 0.');
    }
    if (input.amount > currentBalance) {
      throw Exception('El abono no puede exceder el saldo pendiente.');
    }

    final supplierId = purchase['supplier_id']?.toString();
    final openCashSessionId = await _currentOpenCashSessionId(branchId);

    await _client.from('supplier_payments').insert({
      'branch_id': branchId,
      'purchase_id': input.purchaseId,
      'supplier_id': supplierId,
      'cash_session_id': openCashSessionId,
      'payment_method': input.paymentMethod,
      'amount': input.amount,
      'paid_at': DateTime.now().toUtc().toIso8601String(),
      'reference': _nullIfEmpty(input.reference),
      'notes': _nullIfEmpty(input.notes),
    });

    final nextPaid = _round2(_toDouble(purchase['paid_amount']) + input.amount);
    final nextBalance = _round2(currentBalance - input.amount);

    await _client
        .from('purchases')
        .update({
          'paid_amount': nextPaid,
          'balance_due': nextBalance,
        })
        .eq('id', input.purchaseId)
        .eq('branch_id', branchId);

    // Rollup del saldo total adeudado al proveedor (como clients.balance_due).
    if (supplierId != null) {
      final supplierPurchases = await _client
          .from('purchases')
          .select('balance_due')
          .eq('branch_id', branchId)
          .eq('supplier_id', supplierId)
          .gt('balance_due', 0)
          .neq('status', 'cancelled');

      final supplierBalance = _round2(
        supplierPurchases.fold<double>(
          0,
          (sum, row) => sum + _toDouble((row as Map)['balance_due']),
        ),
      );

      await _client
          .from('suppliers')
          .update({'balance_due': supplierBalance})
          .eq('id', supplierId)
          .eq('branch_id', branchId);
    }
  }

  /// Estado de cuenta con un proveedor: las compras que le debemos (las
  /// mismas que lista Cuentas por pagar), solo las de [from]–[to] si se
  /// pasan, con los pagos que se les aplicaron.
  Future<AccountStatement> fetchSupplierStatement(
    String supplierId, {
    DateTime? from,
    DateTime? to,
  }) async {
    final branchId = await _currentBranchId();
    if (branchId == null) {
      throw Exception('No hay sucursal asignada para este usuario.');
    }

    final supplierRows = await _client
        .from('suppliers')
        .select('legal_name, trade_name, rnc, phone, address, email')
        .eq('id', supplierId)
        .eq('branch_id', branchId)
        .limit(1);
    final supplier = supplierRows.isEmpty
        ? const <String, dynamic>{}
        : Map<String, dynamic>.from(supplierRows.first as Map);
    final supplierName = _supplierName(supplier);
    final rnc = _nullIfEmpty(supplier['rnc']?.toString());

    // Mismo filtro que [fetchPayables]; las fechas se filtran aquí para
    // contar días completos en hora local.
    final rows = await _client
        .from('purchases')
        .select(
          'id, purchase_number, invoice_number, purchase_date, total_amount, '
          'paid_amount, balance_due, due_date',
        )
        .eq('branch_id', branchId)
        .eq('supplier_id', supplierId)
        .gt('balance_due', 0)
        .neq('status', 'cancelled')
        .order('purchase_date');
    final documents = <StatementDocument>[];
    for (final raw in rows) {
      final row = Map<String, dynamic>.from(raw as Map);
      final date =
          DateTime.tryParse((row['purchase_date'] ?? '').toString()) ??
              DateTime.fromMillisecondsSinceEpoch(0);
      if (!isWithinStatementDays(date, from, to)) continue;
      documents.add(StatementDocument(
        id: (row['id'] ?? '').toString(),
        date: date,
        number: (row['purchase_number'] ?? '-').toString(),
        reference: _nullIfEmpty(row['invoice_number']?.toString()),
        partyName: supplierName,
        dueDate: DateTime.tryParse((row['due_date'] ?? '').toString()),
        total: _toDouble(row['total_amount']),
        paid: _toDouble(row['paid_amount']),
        balance: _toDouble(row['balance_due']),
      ));
    }

    // Pagos de esas compras, en tandas: un `in.(...)` con cientos de ids
    // revienta el largo de la URL.
    final numberById = {for (final d in documents) d.id: d.number};
    final ids = numberById.keys.toList();
    final payments = <StatementPayment>[];
    for (var i = 0; i < ids.length; i += 100) {
      final chunk = ids.sublist(i, i + 100 > ids.length ? ids.length : i + 100);
      final paymentRows = await _client
          .from('supplier_payments')
          .select('purchase_id, amount, payment_method, paid_at, reference')
          .eq('branch_id', branchId)
          .inFilter('purchase_id', chunk);
      for (final raw in paymentRows) {
        final row = Map<String, dynamic>.from(raw as Map);
        payments.add(StatementPayment(
          date: DateTime.tryParse((row['paid_at'] ?? '').toString()) ??
              DateTime.fromMillisecondsSinceEpoch(0),
          documentNumber: numberById[row['purchase_id']?.toString()] ?? '-',
          method: statementPaymentMethodLabel(
            (row['payment_method'] ?? '').toString(),
          ),
          amount: _toDouble(row['amount']),
          reference: _nullIfEmpty(row['reference']?.toString()),
        ));
      }
    }
    payments.sort((a, b) => a.date.compareTo(b.date));

    return AccountStatement(
      kind: AccountStatementKind.payable,
      issuer: await loadStatementIssuer(_client, branchId),
      party: StatementParty(
        name: supplierName,
        document: rnc == null ? null : 'RNC: $rnc',
        phone: _nullIfEmpty(supplier['phone']?.toString()),
        address: _nullIfEmpty(supplier['address']?.toString()),
        email: _nullIfEmpty(supplier['email']?.toString()),
      ),
      documents: documents,
      payments: payments,
      generatedAt: DateTime.now(),
      from: from,
      to: to,
    );
  }

  Future<Map<String, String>> _loadSuppliersById(String branchId) async {
    final rows = await _client
        .from('suppliers')
        .select('id, legal_name, trade_name')
        .eq('branch_id', branchId)
        .order('legal_name');

    return {
      for (final row in rows)
        (row['id'] ?? '').toString(): _supplierName(row as Map),
    };
  }

  Future<Map<String, String>> _loadPurchasesById(String branchId) async {
    final rows = await _client
        .from('purchases')
        .select('id, purchase_number')
        .eq('branch_id', branchId)
        .order('purchase_date', ascending: false)
        .limit(200);

    return {
      for (final row in rows)
        (row['id'] ?? '').toString():
            (row['purchase_number'] ?? '-').toString(),
    };
  }

  Future<String?> _currentBranchId() async {
    final result = await _client.rpc('current_branch_id');
    if (result == null) return null;
    final value = result.toString();
    return value.isEmpty ? null : value;
  }

  Future<String?> _currentOpenCashSessionId(String branchId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return null;
    final rows = await _client
        .from('cash_sessions')
        .select('id')
        .eq('branch_id', branchId)
        .eq('status', 'open')
        .eq('opened_by', userId)
        .order('opened_at', ascending: false)
        .limit(1);

    if (rows.isEmpty) return null;
    return (rows.first as Map)['id']?.toString();
  }
}

String _supplierName(Map row) {
  final trade = (row['trade_name'] ?? '').toString().trim();
  final legal = (row['legal_name'] ?? '').toString().trim();
  if (trade.isNotEmpty) return trade;
  if (legal.isNotEmpty) return legal;
  return 'Proveedor';
}

String? _nullIfEmpty(String? value) {
  if (value == null) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

double _toDouble(dynamic value) {
  if (value == null) return 0;
  if (value is double) return value;
  if (value is int) return value.toDouble();
  return double.tryParse(value.toString()) ?? 0;
}

double _round2(double value) => (value * 100).roundToDouble() / 100;
