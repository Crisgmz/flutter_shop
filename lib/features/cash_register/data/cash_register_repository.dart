import 'package:supabase_flutter/supabase_flutter.dart';

class CashSessionEntity {
  CashSessionEntity({
    required this.id,
    required this.status,
    required this.openedAt,
    required this.openingAmount,
    required this.expectedAmount,
    required this.closingAmount,
    required this.differenceAmount,
    required this.notes,
    required this.closedAt,
  });

  final String id;
  final String status;
  final DateTime openedAt;
  final DateTime? closedAt;
  final double openingAmount;
  final double expectedAmount;
  final double? closingAmount;
  final double? differenceAmount;
  final String? notes;

  bool get isOpen => status == 'open';

  factory CashSessionEntity.fromMap(Map<String, dynamic> map) {
    return CashSessionEntity(
      id: (map['id'] ?? '').toString(),
      status: (map['status'] ?? '').toString(),
      openedAt:
          DateTime.tryParse((map['opened_at'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      closedAt: map['closed_at'] == null
          ? null
          : DateTime.tryParse(map['closed_at'].toString()),
      openingAmount: _toDouble(map['opening_amount']),
      expectedAmount: _toDouble(map['expected_amount']),
      closingAmount: map['closing_amount'] == null
          ? null
          : _toDouble(map['closing_amount']),
      differenceAmount: map['difference_amount'] == null
          ? null
          : _toDouble(map['difference_amount']),
      notes: map['notes']?.toString(),
    );
  }
}

class CashSessionMetrics {
  CashSessionMetrics({
    required this.totalPayments,
    required this.cashPayments,
    required this.totalExpenses,
    required this.cashExpenses,
  });

  final double totalPayments;
  final double cashPayments;
  final double totalExpenses;
  final double cashExpenses;

  double get netPayments => _round2(totalPayments - totalExpenses);

  double expectedCashFromOpening(double openingAmount) {
    return _round2(openingAmount + cashPayments - cashExpenses);
  }
}

class CashRegisterData {
  CashRegisterData({
    required this.openSession,
    required this.openMetrics,
    required this.recentSessions,
  });

  final CashSessionEntity? openSession;
  final CashSessionMetrics? openMetrics;
  final List<CashSessionEntity> recentSessions;
}

class OpenCashInput {
  OpenCashInput({required this.openingAmount, this.notes});

  final double openingAmount;
  final String? notes;
}

/// Movimiento manual de efectivo dentro de la sesión activa.
class CashMovementInput {
  CashMovementInput({
    required this.movementType,
    required this.amount,
    this.reason,
    this.notes,
  });

  /// 'deposit' | 'withdrawal' | 'adjustment' | 'opening_top_up'.
  final String movementType;
  final double amount;
  final String? reason;
  final String? notes;
}

class CashMovementEntity {
  CashMovementEntity({
    required this.id,
    required this.movementType,
    required this.amount,
    required this.occurredAt,
    this.reason,
    this.notes,
    this.performedBy,
  });

  factory CashMovementEntity.fromMap(Map<String, dynamic> map) {
    return CashMovementEntity(
      id: (map['id'] ?? '').toString(),
      movementType: (map['movement_type'] ?? '').toString(),
      amount: _toDouble(map['amount']),
      occurredAt:
          DateTime.tryParse((map['occurred_at'] ?? '').toString()) ??
              DateTime.now(),
      reason: map['reason']?.toString(),
      notes: map['notes']?.toString(),
      performedBy: map['performed_by']?.toString(),
    );
  }

  final String id;

  /// 'deposit' | 'withdrawal' | 'adjustment' | 'opening_top_up'.
  final String movementType;
  final double amount;
  final DateTime occurredAt;
  final String? reason;
  final String? notes;
  final String? performedBy;

  /// Delta con signo: positivo si suma a la caja, negativo si resta.
  double get signedAmount {
    switch (movementType) {
      case 'deposit':
      case 'opening_top_up':
      case 'adjustment':
        return amount;
      case 'withdrawal':
        return -amount;
      default:
        return 0;
    }
  }

  String get typeLabel {
    switch (movementType) {
      case 'deposit':
        return 'Depósito';
      case 'withdrawal':
        return 'Sangría';
      case 'adjustment':
        return 'Ajuste';
      case 'opening_top_up':
        return 'Refuerzo de apertura';
      default:
        return movementType;
    }
  }
}

class CloseCashInput {
  CloseCashInput({required this.closingAmount, this.notes});

  final double closingAmount;
  final String? notes;
}

class CashRegisterRepository {
  CashRegisterRepository(this._client);

  final SupabaseClient _client;

  Future<CashRegisterData> fetchData() async {
    final branchId = await _currentBranchId();
    if (branchId == null) {
      return CashRegisterData(
        openSession: null,
        openMetrics: null,
        recentSessions: const [],
      );
    }

    final openSession = await _fetchOpenSession(branchId);
    final recentSessions = await _fetchRecentSessions(branchId);

    CashSessionMetrics? metrics;
    if (openSession != null) {
      metrics = await _fetchSessionMetrics(openSession.id, branchId);
    }

    return CashRegisterData(
      openSession: openSession,
      openMetrics: metrics,
      recentSessions: recentSessions,
    );
  }

  Future<void> openSession(OpenCashInput input) async {
    final branchId = await _currentBranchId();
    if (branchId == null) {
      throw Exception('No hay sucursal asignada para este usuario.');
    }

    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw Exception('Sesión inválida. Inicia sesión de nuevo.');
    }

    final existing = await _fetchOpenSession(branchId);
    if (existing != null) {
      throw Exception('Ya existe una sesión de caja abierta.');
    }

    final openingAmount = _round2(input.openingAmount);

    await _client.from('cash_sessions').insert({
      'branch_id': branchId,
      'opened_by': userId,
      'status': 'open',
      'opened_at': DateTime.now().toUtc().toIso8601String(),
      'opening_amount': openingAmount,
      'expected_amount': openingAmount,
      'notes': _nullIfEmpty(input.notes),
    });
  }

  Future<void> closeSession(CloseCashInput input) async {
    final branchId = await _currentBranchId();
    if (branchId == null) {
      throw Exception('No hay sucursal asignada para este usuario.');
    }

    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw Exception('Sesión inválida. Inicia sesión de nuevo.');
    }

    final openSession = await _fetchOpenSession(branchId);
    if (openSession == null) {
      throw Exception('No hay una sesión de caja abierta.');
    }

    final metrics = await _fetchSessionMetrics(openSession.id, branchId);
    final expected = metrics.expectedCashFromOpening(openSession.openingAmount);
    final closingAmount = _round2(input.closingAmount);
    final difference = _round2(closingAmount - expected);

    await _client
        .from('cash_sessions')
        .update({
          'status': 'closed',
          'closed_by': userId,
          'closed_at': DateTime.now().toUtc().toIso8601String(),
          'expected_amount': expected,
          'closing_amount': closingAmount,
          'difference_amount': difference,
          'notes': _nullIfEmpty(input.notes) ?? openSession.notes,
        })
        .eq('id', openSession.id)
        .eq('branch_id', branchId);
  }

  Future<CashSessionEntity?> _fetchOpenSession(String branchId) async {
    final rows = await _client
        .from('cash_sessions')
        .select(
          'id, status, opened_at, closed_at, opening_amount, expected_amount, closing_amount, difference_amount, notes',
        )
        .eq('branch_id', branchId)
        .eq('status', 'open')
        .order('opened_at', ascending: false)
        .limit(1);

    if (rows.isEmpty) return null;
    return CashSessionEntity.fromMap(
      Map<String, dynamic>.from(rows.first as Map),
    );
  }

  Future<List<CashSessionEntity>> _fetchRecentSessions(String branchId) async {
    final rows = await _client
        .from('cash_sessions')
        .select(
          'id, status, opened_at, closed_at, opening_amount, expected_amount, closing_amount, difference_amount, notes',
        )
        .eq('branch_id', branchId)
        .order('opened_at', ascending: false)
        .limit(15);

    return rows
        .map(
          (item) =>
              CashSessionEntity.fromMap(Map<String, dynamic>.from(item as Map)),
        )
        .toList(growable: false);
  }

  Future<CashSessionMetrics> _fetchSessionMetrics(
    String cashSessionId,
    String branchId,
  ) async {
    final payments = await _client
        .from('payments')
        .select('amount, payment_method')
        .eq('branch_id', branchId)
        .eq('cash_session_id', cashSessionId);

    final expenses = await _client
        .from('expenses')
        .select('amount, payment_method')
        .eq('branch_id', branchId)
        .eq('cash_session_id', cashSessionId);

    final totalPayments = _round2(
      payments.fold<double>(
        0,
        (sum, item) => sum + _toDouble((item as Map)['amount']),
      ),
    );

    final cashPayments = _round2(
      payments.fold<double>(0, (sum, item) {
        final row = item as Map;
        final method = (row['payment_method'] ?? '').toString();
        if (method != 'cash') return sum;
        return sum + _toDouble(row['amount']);
      }),
    );

    final totalExpenses = _round2(
      expenses.fold<double>(
        0,
        (sum, item) => sum + _toDouble((item as Map)['amount']),
      ),
    );

    final cashExpenses = _round2(
      expenses.fold<double>(0, (sum, item) {
        final row = item as Map;
        final method = (row['payment_method'] ?? '').toString();
        if (method != 'cash') return sum;
        return sum + _toDouble(row['amount']);
      }),
    );

    return CashSessionMetrics(
      totalPayments: totalPayments,
      cashPayments: cashPayments,
      totalExpenses: totalExpenses,
      cashExpenses: cashExpenses,
    );
  }

  /// Registra un movimiento manual de efectivo en la sesión activa.
  /// El trigger SQL ajusta `cash_sessions.expected_amount` automáticamente.
  Future<void> addMovement(CashMovementInput input) async {
    final branchId = await _currentBranchId();
    if (branchId == null) {
      throw Exception('No hay sucursal asignada para este usuario.');
    }
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw Exception('Sesión inválida. Inicia sesión de nuevo.');
    }
    final openSession = await _fetchOpenSession(branchId);
    if (openSession == null) {
      throw Exception(
        'No hay una sesión de caja abierta. Abre la caja primero.',
      );
    }
    if (input.amount <= 0) {
      throw Exception('El monto debe ser mayor que cero.');
    }

    await _client.from('cash_register_movements').insert({
      'branch_id': branchId,
      'cash_session_id': openSession.id,
      'movement_type': input.movementType,
      'amount': _round2(input.amount),
      'reason': _nullIfEmpty(input.reason),
      'notes': _nullIfEmpty(input.notes),
      'performed_by': userId,
    });
  }

  Future<List<CashMovementEntity>> fetchMovementsForSession(
    String cashSessionId,
  ) async {
    final branchId = await _currentBranchId();
    if (branchId == null) return const [];

    final rows = await _client
        .from('cash_register_movements')
        .select(
          'id, movement_type, amount, reason, notes, occurred_at, performed_by',
        )
        .eq('branch_id', branchId)
        .eq('cash_session_id', cashSessionId)
        .order('occurred_at', ascending: false);

    return rows
        .map((item) => CashMovementEntity.fromMap(
              Map<String, dynamic>.from(item as Map),
            ))
        .toList(growable: false);
  }

  /// Sella un cierre Z fiscal (inmutable) para una sesión de caja cerrada.
  /// Llama al RPC `seal_fiscal_z_closure` que valida que la sesión esté
  /// cerrada y que no exista ya un cierre Z primario para ella.
  /// Devuelve el UUID del cierre Z creado.
  Future<String> sealFiscalZClosure(String cashSessionId) async {
    final branchId = await _currentBranchId();
    if (branchId == null) {
      throw Exception('No hay sucursal asignada.');
    }
    final result = await _client.rpc(
      'seal_fiscal_z_closure',
      params: {
        'p_branch_id': branchId,
        'p_cash_session_id': cashSessionId,
      },
    );
    if (result == null) {
      throw Exception('No se pudo sellar el cierre Z.');
    }
    return result.toString();
  }

  Future<String?> currentOpenSessionId() async {
    final branchId = await _currentBranchId();
    if (branchId == null) return null;

    final openSession = await _fetchOpenSession(branchId);
    return openSession?.id;
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
