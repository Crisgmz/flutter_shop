import 'package:supabase_flutter/supabase_flutter.dart';

class ExpenseSupplier {
  ExpenseSupplier({required this.id, required this.name});

  final String id;
  final String name;

  factory ExpenseSupplier.fromMap(Map<String, dynamic> map) {
    return ExpenseSupplier(
      id: (map['id'] ?? '').toString(),
      name: (map['legal_name'] ?? '').toString(),
    );
  }
}

class ExpenseEntity {
  ExpenseEntity({
    required this.id,
    required this.category,
    required this.description,
    required this.paymentMethod,
    required this.amount,
    required this.expenseDate,
    required this.supplierName,
  });

  final String id;
  final String category;
  final String? description;
  final String paymentMethod;
  final double amount;
  final DateTime expenseDate;
  final String? supplierName;

  factory ExpenseEntity.fromMap(
    Map<String, dynamic> map,
    Map<String, String> suppliersById,
  ) {
    final supplierId = map['supplier_id']?.toString();

    return ExpenseEntity(
      id: (map['id'] ?? '').toString(),
      category: (map['category'] ?? '').toString(),
      description: map['description']?.toString(),
      paymentMethod: (map['payment_method'] ?? '').toString(),
      amount: _toDouble(map['amount']),
      expenseDate:
          DateTime.tryParse((map['expense_date'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      supplierName: supplierId == null ? null : suppliersById[supplierId],
    );
  }
}

class ExpenseInput {
  ExpenseInput({
    required this.category,
    required this.paymentMethod,
    required this.amount,
    required this.expenseDate,
    this.description,
    this.supplierId,
  });

  final String category;
  final String paymentMethod;
  final double amount;
  final DateTime expenseDate;
  final String? description;
  final String? supplierId;
}

class ExpensesRepository {
  ExpensesRepository(this._client);

  final SupabaseClient _client;

  Future<List<ExpenseSupplier>> fetchSuppliers() async {
    final branchId = await _currentBranchId();
    if (branchId == null) return const [];

    final rows = await _client
        .from('suppliers')
        .select('id, legal_name')
        .eq('branch_id', branchId)
        .eq('is_active', true)
        .order('legal_name');

    return rows
        .map(
          (item) =>
              ExpenseSupplier.fromMap(Map<String, dynamic>.from(item as Map)),
        )
        .toList(growable: false);
  }

  Future<List<ExpenseEntity>> fetchExpenses() async {
    final branchId = await _currentBranchId();
    if (branchId == null) return const [];

    final suppliers = await fetchSuppliers();
    final suppliersById = {
      for (final supplier in suppliers) supplier.id: supplier.name,
    };

    final rows = await _client
        .from('expenses')
        .select(
          'id, supplier_id, category, description, payment_method, amount, expense_date',
        )
        .eq('branch_id', branchId)
        .order('expense_date', ascending: false)
        .limit(100);

    return rows
        .map(
          (item) => ExpenseEntity.fromMap(
            Map<String, dynamic>.from(item as Map),
            suppliersById,
          ),
        )
        .toList(growable: false);
  }

  Future<void> createExpense(ExpenseInput input) async {
    final branchId = await _currentBranchId();
    if (branchId == null) {
      throw Exception('No hay sucursal asignada para este usuario.');
    }

    if (input.amount <= 0) {
      throw Exception('El monto debe ser mayor que 0.');
    }

    final cashSessionId = await _currentOpenCashSessionId(branchId);

    await _client.from('expenses').insert({
      'branch_id': branchId,
      'cash_session_id': cashSessionId,
      'supplier_id': _nullIfEmpty(input.supplierId),
      'category': input.category.trim(),
      'description': _nullIfEmpty(input.description),
      'payment_method': input.paymentMethod,
      'amount': _round2(input.amount),
      'expense_date': input.expenseDate.toIso8601String().split('T').first,
    });
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

  Future<String?> _currentBranchId() async {
    final result = await _client.rpc('current_branch_id');
    if (result == null) return null;
    final value = result.toString();
    return value.isEmpty ? null : value;
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
