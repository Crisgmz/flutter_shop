import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_providers.dart';
import '../data/cash_register_repository.dart';

final cashRegisterRepositoryProvider = Provider<CashRegisterRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return CashRegisterRepository(client);
});

final cashRegisterDataProvider = FutureProvider<CashRegisterData>((ref) async {
  final repository = ref.watch(cashRegisterRepositoryProvider);
  return repository.fetchData();
});

/// Vista admin/supervisor: todas las cajas abiertas en la sucursal con
/// nombre del cajero + métricas (cuánto lleva vendido cada uno).
final allOpenCashSessionsProvider =
    FutureProvider<List<CashSessionOverview>>((ref) async {
  final repository = ref.watch(cashRegisterRepositoryProvider);
  return repository.fetchOpenSessionsOverview();
});

/// Catálogo completo de cajas activas de la sucursal con sus usuarios
/// asignados. Lo usa el editor en /configuracion.
final cashRegistersProvider =
    FutureProvider<List<CashRegisterEntity>>((ref) async {
  final repository = ref.watch(cashRegisterRepositoryProvider);
  return repository.fetchCashRegisters();
});

/// Solo las cajas a las que el usuario actual está asignado. Lo usa el
/// picker de "abrir caja".
final myCashRegistersProvider =
    FutureProvider<List<CashRegisterEntity>>((ref) async {
  final repository = ref.watch(cashRegisterRepositoryProvider);
  return repository.fetchMyCashRegisters();
});

/// Sesión de caja activa del usuario actual.
///
/// Como un usuario puede tener varias cajas abiertas a la vez
/// (migration 42), este provider guarda cuál es "la activa" para
/// ventas. Null = ninguna seleccionada (el picker se muestra).
///
/// Se setea cuando:
/// - El usuario abre una caja (apertura nueva).
/// - El usuario entra a una caja que ya tenía abierta desde el picker.
///
/// Se limpia cuando:
/// - El usuario cierra la caja activa.
/// - El usuario toca "Cambiar de caja" en el POS.
final activeCashSessionIdProvider = StateProvider<String?>((ref) => null);

/// Sesiones abiertas del usuario actual con info de la caja asociada.
/// Útil para el picker (marca cuáles ya tienen sesión abierta).
final myOpenCashSessionsProvider =
    FutureProvider<List<MyOpenCashSession>>((ref) async {
  final repository = ref.watch(cashRegisterRepositoryProvider);
  return repository.fetchMyOpenSessions();
});

/// Nombre de la caja sobre la que el usuario tiene una sesión abierta.
/// Null si no hay sesión abierta o si la sesión es legacy (sin caja).
/// Lo usa el header del POS para mostrar el nombre de la caja activa.
final currentOpenCashRegisterNameProvider =
    FutureProvider<String?>((ref) async {
  final activeSessionId = ref.watch(activeCashSessionIdProvider);
  final sessions = await ref.watch(myOpenCashSessionsProvider.future);
  if (sessions.isEmpty) return null;

  // Si hay una activa seleccionada, mostrar esa.
  if (activeSessionId != null) {
    for (final s in sessions) {
      if (s.sessionId == activeSessionId) return s.registerName;
    }
  }

  // Fallback: la primera sesión abierta (legacy).
  return sessions.first.registerName;
});
