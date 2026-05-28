import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_providers.dart';
import '../../settings/presentation/app_settings_providers.dart';
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

/// Resumen de cuentas por cobrar: lista entera + conteos por categoría
/// (todos, próximos a vencer, vencidos). Memoizado por
/// (receivables, warnDays). Los counts se calculan UNA sola vez,
/// independientes del filtro de búsqueda.
class CobrosCategorySummary {
  const CobrosCategorySummary({
    required this.all,
    required this.countAll,
    required this.countNearDue,
    required this.countOverdue,
  });

  final List<ReceivableSale> all;
  final int countAll;
  final int countNearDue;
  final int countOverdue;
}

final cobrosCategorySummaryProvider =
    Provider<CobrosCategorySummary>((ref) {
  final all = ref.watch(cobrosReceivablesProvider).valueOrNull ?? const [];
  final warnDays =
      ref.watch(appSettingsProvider).valueOrNull?.creditWarnDays ?? 7;
  var nearDue = 0;
  var overdue = 0;
  for (final r in all) {
    if (r.isOverdue) overdue++;
    if (r.isNearDue(warnDays)) nearDue++;
  }
  return CobrosCategorySummary(
    all: all,
    countAll: all.length,
    countNearDue: nearDue,
    countOverdue: overdue,
  );
});

/// Cuentas por cobrar filtradas por búsqueda + modo, memoizado.
final cobrosFilteredProvider = Provider<List<ReceivableSale>>((ref) {
  final all = ref.watch(cobrosReceivablesProvider).valueOrNull ?? const [];
  final query = ref.watch(cobrosSearchProvider).trim().toLowerCase();
  final mode = ref.watch(cobrosFilterProvider);
  final warnDays =
      ref.watch(appSettingsProvider).valueOrNull?.creditWarnDays ?? 7;

  return all.where((item) {
    if (query.isNotEmpty) {
      if (!item.saleNumber.toLowerCase().contains(query) &&
          !item.clientName.toLowerCase().contains(query) &&
          !(item.ncf?.toLowerCase().contains(query) ?? false)) {
        return false;
      }
    }
    switch (mode) {
      case ReceivablesFilter.nearDue:
        return item.isNearDue(warnDays);
      case ReceivablesFilter.overdue:
        return item.isOverdue;
      case ReceivablesFilter.all:
        return true;
    }
  }).toList(growable: false);
});

/// Total adeudado sobre la lista filtrada, memoizado.
final cobrosFilteredTotalDueProvider = Provider<double>((ref) {
  final filtered = ref.watch(cobrosFilteredProvider);
  var total = 0.0;
  for (final r in filtered) {
    total += r.balanceDue;
  }
  return total;
});

final cobrosPaymentsProvider = FutureProvider<List<ReceivedPayment>>((
  ref,
) async {
  final repository = ref.watch(cobrosRepositoryProvider);
  return repository.fetchReceivedPayments();
});
