import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_providers.dart';
import '../data/dashboard_repository.dart';

final dashboardRepositoryProvider = Provider<DashboardRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return DashboardRepository(client);
});

/// Toggle Mes / Semana del gráfico F3.
final dashboardChartRangeProvider = StateProvider<DashboardChartRange>(
  (ref) => DashboardChartRange.month,
);

/// Fecha de referencia del Cierre del día F4 (default: hoy en RD).
final dashboardCloseoutDateProvider = StateProvider<DateTime>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
});

final dashboardKpisProvider = FutureProvider<DashboardKpisV2>((ref) async {
  final repo = ref.watch(dashboardRepositoryProvider);
  return repo.fetchKpis();
});

final dashboardHeroKpisProvider =
    FutureProvider<DashboardHeroKpis>((ref) async {
  final repo = ref.watch(dashboardRepositoryProvider);
  return repo.fetchHeroKpis();
});

final dashboardChartProvider =
    FutureProvider<List<DashboardChartPoint>>((ref) async {
  final range = ref.watch(dashboardChartRangeProvider);
  final repo = ref.watch(dashboardRepositoryProvider);
  return repo.fetchSalesChart(range);
});

final dashboardCloseoutProvider =
    FutureProvider<DashboardCloseout>((ref) async {
  final date = ref.watch(dashboardCloseoutDateProvider);
  final repo = ref.watch(dashboardRepositoryProvider);
  return repo.fetchCloseout(date);
});
