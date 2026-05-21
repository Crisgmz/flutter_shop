import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_providers.dart';
import '../data/cobros_repository.dart';

final cobrosSearchProvider = StateProvider<String>((ref) => '');

/// Filtro activo en la tabla de cuentas por cobrar.
///   - `all`: todos los créditos pendientes.
///   - `nearDue`: próximos a vencer (dentro de `credit_warn_days`).
///   - `overdue`: ya vencidos.
enum ReceivablesFilter { all, nearDue, overdue }

final cobrosFilterProvider =
    StateProvider<ReceivablesFilter>((ref) => ReceivablesFilter.all);

final cobrosRepositoryProvider = Provider<CobrosRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return CobrosRepository(client);
});

final cobrosReceivablesProvider = FutureProvider<List<ReceivableSale>>((
  ref,
) async {
  final repository = ref.watch(cobrosRepositoryProvider);
  return repository.fetchReceivables();
});

final cobrosPaymentsProvider = FutureProvider<List<ReceivedPayment>>((
  ref,
) async {
  final repository = ref.watch(cobrosRepositoryProvider);
  return repository.fetchReceivedPayments();
});
