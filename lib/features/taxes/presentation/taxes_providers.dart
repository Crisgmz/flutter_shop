import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_providers.dart';
import '../data/taxes_repository.dart';

final taxesRangeProvider = StateProvider<TaxesDateRange>((ref) {
  final now = DateTime.now();
  final start = DateTime(now.year, now.month, 1);
  final end = DateTime(now.year, now.month, now.day);
  return TaxesDateRange(start: start, end: end);
});

final taxesRepositoryProvider = Provider<TaxesRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return TaxesRepository(client);
});

final taxesDataProvider = FutureProvider<TaxesData>((ref) async {
  final repository = ref.watch(taxesRepositoryProvider);
  final range = ref.watch(taxesRangeProvider);
  return repository.fetchTaxes(range);
});
