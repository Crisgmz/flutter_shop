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
