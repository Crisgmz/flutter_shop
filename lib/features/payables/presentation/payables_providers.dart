import 'package:flutter/material.dart' show DateTimeRange;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/widgets/date_range_filter_button.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../settings/presentation/app_settings_providers.dart';
import '../data/payables_repository.dart';

final payablesSearchProvider = StateProvider<String>((ref) => '');

/// Filtro activo en la tabla de cuentas por pagar.
enum PayablesFilter { all, nearDue, overdue }

final payablesFilterProvider =
    StateProvider<PayablesFilter>((ref) => PayablesFilter.all);

/// Rango "Desde – hasta" sobre la fecha de la compra. Null = todas.
final payablesDateRangeProvider = StateProvider<DateTimeRange?>((ref) => null);

final payablesRepositoryProvider = Provider<PayablesRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return PayablesRepository(client);
});

final payablesListProvider = FutureProvider<List<PayablePurchase>>((ref) async {
  final repository = ref.watch(payablesRepositoryProvider);
  return repository.fetchPayables();
});

class PayablesCategorySummary {
  const PayablesCategorySummary({
    required this.all,
    required this.countAll,
    required this.countNearDue,
    required this.countOverdue,
  });

  final List<PayablePurchase> all;
  final int countAll;
  final int countNearDue;
  final int countOverdue;
}

final payablesCategorySummaryProvider =
    Provider<PayablesCategorySummary>((ref) {
  final all = ref.watch(payablesListProvider).valueOrNull ?? const [];
  final warnDays =
      ref.watch(appSettingsProvider).valueOrNull?.creditWarnDays ?? 7;
  var nearDue = 0;
  var overdue = 0;
  for (final r in all) {
    if (r.isOverdue) overdue++;
    if (r.isNearDue(warnDays)) nearDue++;
  }
  return PayablesCategorySummary(
    all: all,
    countAll: all.length,
    countNearDue: nearDue,
    countOverdue: overdue,
  );
});

/// Cuentas por pagar filtradas por búsqueda + modo + fechas, memoizado.
final payablesFilteredProvider = Provider<List<PayablePurchase>>((ref) {
  final all = ref.watch(payablesListProvider).valueOrNull ?? const [];
  final query = ref.watch(payablesSearchProvider).trim().toLowerCase();
  final mode = ref.watch(payablesFilterProvider);
  final range = ref.watch(payablesDateRangeProvider);
  final warnDays =
      ref.watch(appSettingsProvider).valueOrNull?.creditWarnDays ?? 7;

  return all.where((item) {
    if (!isWithinDateRange(item.purchaseDate, range)) return false;
    if (query.isNotEmpty) {
      if (!item.purchaseNumber.toLowerCase().contains(query) &&
          !item.supplierName.toLowerCase().contains(query) &&
          !(item.invoiceNumber?.toLowerCase().contains(query) ?? false)) {
        return false;
      }
    }
    switch (mode) {
      case PayablesFilter.nearDue:
        return item.isNearDue(warnDays);
      case PayablesFilter.overdue:
        return item.isOverdue;
      case PayablesFilter.all:
        return true;
    }
  }).toList(growable: false);
});

/// Total adeudado sobre la lista filtrada, memoizado.
final payablesFilteredTotalDueProvider = Provider<double>((ref) {
  final filtered = ref.watch(payablesFilteredProvider);
  var total = 0.0;
  for (final r in filtered) {
    total += r.balanceDue;
  }
  return total;
});

final supplierPaymentsProvider =
    FutureProvider<List<SupplierPaymentRow>>((ref) async {
  final repository = ref.watch(payablesRepositoryProvider);
  return repository.fetchSupplierPayments();
});
