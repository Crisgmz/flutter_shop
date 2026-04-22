import 'package:supabase_flutter/supabase_flutter.dart';

class ReceivableSale {
  ReceivableSale({
    required this.id,
    required this.saleNumber,
    required this.saleDate,
    required this.clientId,
    required this.clientName,
    required this.receiptType,
    required this.ncf,
    required this.totalAmount,
    required this.paidAmount,
    required this.balanceDue,
    required this.status,
  });

  final String id;
  final String saleNumber;
  final DateTime saleDate;
  final String? clientId;
  final String clientName;
  final String receiptType;
  final String? ncf;
  final double totalAmount;
  final double paidAmount;
  final double balanceDue;
  final String status;

  factory ReceivableSale.fromMap(
    Map<String, dynamic> map,
    Map<String, String> clientsById,
  ) {
    final clientId = map['client_id']?.toString();

    return ReceivableSale(
      id: (map['id'] ?? '').toString(),
      saleNumber: (map['sale_number'] ?? '-').toString(),
      saleDate:
          DateTime.tryParse((map['sale_date'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      clientId: clientId,
      clientName: clientId == null
          ? 'Cliente General'
          : (clientsById[clientId] ?? 'Cliente General'),
      receiptType: (map['receipt_type'] ?? '').toString(),
      ncf: map['ncf']?.toString(),
      totalAmount: _toDouble(map['total_amount']),
      paidAmount: _toDouble(map['paid_amount']),
      balanceDue: _toDouble(map['balance_due']),
      status: (map['status'] ?? '').toString(),
    );
  }
}

class ReceivedPayment {
  ReceivedPayment({
    required this.id,
    required this.saleId,
    required this.saleNumber,
    required this.clientName,
    required this.amount,
    required this.paymentMethod,
    required this.paidAt,
    required this.reference,
  });

  final String id;
  final String? saleId;
  final String saleNumber;
  final String clientName;
  final double amount;
  final String paymentMethod;
  final DateTime paidAt;
  final String? reference;

  factory ReceivedPayment.fromMap(
    Map<String, dynamic> map,
    Map<String, String> clientsById,
    Map<String, String> salesById,
  ) {
    final clientId = map['client_id']?.toString();
    final saleId = map['sale_id']?.toString();

    return ReceivedPayment(
      id: (map['id'] ?? '').toString(),
      saleId: saleId,
      saleNumber: saleId == null ? '-' : (salesById[saleId] ?? '-'),
      clientName: clientId == null
          ? 'Cliente General'
          : (clientsById[clientId] ?? 'Cliente General'),
      amount: _toDouble(map['amount']),
      paymentMethod: (map['payment_method'] ?? '').toString(),
      paidAt:
          DateTime.tryParse((map['paid_at'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      reference: map['reference']?.toString(),
    );
  }
}

class CobrosPaymentInput {
  CobrosPaymentInput({
    required this.saleId,
    required this.amount,
    required this.paymentMethod,
    this.reference,
    this.notes,
  });

  final String saleId;
  final double amount;
  final String paymentMethod;
  final String? reference;
  final String? notes;
}

class CobrosRepository {
  CobrosRepository(this._client);

  final SupabaseClient _client;

  Future<List<ReceivableSale>> fetchReceivables() async {
    final branchId = await _currentBranchId();
    if (branchId == null) return const [];

    final clientsById = await _loadClientsById(branchId);

    final rows = await _client
        .from('sales')
        .select(
          'id, sale_number, sale_date, client_id, receipt_type, ncf, total_amount, paid_amount, balance_due, status',
        )
        .eq('branch_id', branchId)
        .gt('balance_due', 0)
        .inFilter('status', ['credit', 'pending', 'completed'])
        .order('sale_date', ascending: false);

    return rows
        .map(
          (item) => ReceivableSale.fromMap(
            Map<String, dynamic>.from(item as Map),
            clientsById,
          ),
        )
        .toList(growable: false);
  }

  Future<List<ReceivedPayment>> fetchReceivedPayments() async {
    final branchId = await _currentBranchId();
    if (branchId == null) return const [];

    final clientsById = await _loadClientsById(branchId);
    final salesById = await _loadSalesById(branchId);

    final rows = await _client
        .from('payments')
        .select(
          'id, sale_id, client_id, amount, payment_method, paid_at, reference',
        )
        .eq('branch_id', branchId)
        .order('paid_at', ascending: false)
        .limit(30);

    return rows
        .map(
          (item) => ReceivedPayment.fromMap(
            Map<String, dynamic>.from(item as Map),
            clientsById,
            salesById,
          ),
        )
        .toList(growable: false);
  }

  Future<void> registerPayment(CobrosPaymentInput input) async {
    final branchId = await _currentBranchId();
    if (branchId == null) {
      throw Exception('No hay sucursal asignada para este usuario.');
    }

    final sale = await _client
        .from('sales')
        .select('id, client_id, paid_amount, balance_due, status')
        .eq('id', input.saleId)
        .eq('branch_id', branchId)
        .single();

    final currentBalance = _toDouble(sale['balance_due']);
    if (currentBalance <= 0) {
      throw Exception('La venta no tiene balance pendiente.');
    }

    if (input.amount <= 0) {
      throw Exception('El monto debe ser mayor que 0.');
    }

    if (input.amount > currentBalance) {
      throw Exception('El abono no puede exceder el balance pendiente.');
    }

    final clientId = sale['client_id']?.toString();
    final openCashSessionId = await _currentOpenCashSessionId(branchId);

    await _client.from('payments').insert({
      'branch_id': branchId,
      'sale_id': input.saleId,
      'client_id': clientId,
      'cash_session_id': openCashSessionId,
      'payment_method': input.paymentMethod,
      'amount': input.amount,
      'paid_at': DateTime.now().toUtc().toIso8601String(),
      'reference': _nullIfEmpty(input.reference),
      'notes': _nullIfEmpty(input.notes),
    });

    final nextPaid = _round2(_toDouble(sale['paid_amount']) + input.amount);
    final nextBalance = _round2(currentBalance - input.amount);
    final nextStatus = nextBalance <= 0 ? 'completed' : 'credit';

    await _client
        .from('sales')
        .update({
          'paid_amount': nextPaid,
          'balance_due': nextBalance,
          'status': nextStatus,
        })
        .eq('id', input.saleId)
        .eq('branch_id', branchId);

    if (clientId != null) {
      final clientSales = await _client
          .from('sales')
          .select('balance_due')
          .eq('branch_id', branchId)
          .eq('client_id', clientId)
          .gt('balance_due', 0)
          .neq('status', 'voided');

      final clientBalance = _round2(
        clientSales.fold<double>(
          0,
          (sum, row) => sum + _toDouble((row as Map)['balance_due']),
        ),
      );

      await _client
          .from('clients')
          .update({'balance_due': clientBalance})
          .eq('id', clientId)
          .eq('branch_id', branchId);
    }
  }

  Future<Map<String, String>> _loadClientsById(String branchId) async {
    final rows = await _client
        .from('clients')
        .select('id, full_name')
        .eq('branch_id', branchId)
        .order('full_name');

    return {
      for (final row in rows)
        (row['id'] ?? '').toString(): (row['full_name'] ?? '').toString(),
    };
  }

  Future<Map<String, String>> _loadSalesById(String branchId) async {
    final rows = await _client
        .from('sales')
        .select('id, sale_number')
        .eq('branch_id', branchId)
        .order('sale_date', ascending: false)
        .limit(200);

    return {
      for (final row in rows)
        (row['id'] ?? '').toString(): (row['sale_number'] ?? '-').toString(),
    };
  }

  Future<String?> _currentBranchId() async {
    final result = await _client.rpc('current_branch_id');
    if (result == null) return null;
    final value = result.toString();
    return value.isEmpty ? null : value;
  }

  Future<String?> _currentOpenCashSessionId(String branchId) async {
    final rows = await _client
        .from('cash_sessions')
        .select('id')
        .eq('branch_id', branchId)
        .eq('status', 'open')
        .order('opened_at', ascending: false)
        .limit(1);

    if (rows.isEmpty) return null;
    return (rows.first as Map)['id']?.toString();
  }
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
