import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_providers.dart';
import '../data/reports_repository.dart';

final reportPeriodProvider =
    StateProvider<ReportPeriod>((ref) => ReportPeriod.monthly);

final reportsRepositoryProvider = Provider<ReportsRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return ReportsRepository(client);
});

final reportsDataProvider = FutureProvider<ReportsData>((ref) async {
  final repository = ref.watch(reportsRepositoryProvider);
  final period = ref.watch(reportPeriodProvider);
  return repository.fetchReports(period);
});

final reportPresetsProvider = FutureProvider<List<ReportPreset>>((ref) async {
  final repository = ref.watch(reportsRepositoryProvider);
  return repository.fetchPresets();
});

final reportExportsProvider = FutureProvider<List<ReportExport>>((ref) async {
  final repository = ref.watch(reportsRepositoryProvider);
  return repository.fetchRecentExports();
});

final taxBreakdownFromProvider = StateProvider<DateTime?>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, 1);
});
final taxBreakdownToProvider = StateProvider<DateTime?>((ref) => null);

final salesTaxBreakdownProvider =
    FutureProvider<List<SalesTaxRow>>((ref) async {
  final repository = ref.watch(reportsRepositoryProvider);
  final from = ref.watch(taxBreakdownFromProvider);
  final to = ref.watch(taxBreakdownToProvider);
  return repository.fetchSalesTaxBreakdown(from: from, to: to);
});
