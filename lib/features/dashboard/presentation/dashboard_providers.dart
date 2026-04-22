import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_providers.dart';
import '../data/dashboard_repository.dart';

final dashboardPeriodProvider =
    StateProvider<DashboardPeriod>((ref) => DashboardPeriod.monthly);

final dashboardRepositoryProvider = Provider<DashboardRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return DashboardRepository(client);
});

final dashboardDataProvider = FutureProvider<DashboardData>((ref) async {
  final period = ref.watch(dashboardPeriodProvider);
  final repository = ref.watch(dashboardRepositoryProvider);
  return repository.fetchDashboard(period);
});
