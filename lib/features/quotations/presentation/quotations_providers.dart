import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_providers.dart';
import '../data/quotations_models.dart';
import '../data/quotations_repository.dart';

final quotationsRepositoryProvider = Provider<QuotationsRepositoryContract>((
  ref,
) {
  final client = ref.watch(supabaseClientProvider);
  return QuotationsRepository(client);
});

final quotationsSearchProvider = StateProvider<String>((ref) => '');

final quotationProductsProvider = FutureProvider<List<QuoteCatalogProduct>>((
  ref,
) async {
  final repository = ref.watch(quotationsRepositoryProvider);
  return repository.fetchProducts();
});

final quotationClientsProvider = FutureProvider<List<QuoteClientOption>>((
  ref,
) async {
  final repository = ref.watch(quotationsRepositoryProvider);
  return repository.fetchClients();
});

final quotationDetailProvider = FutureProvider.family<QuoteDetail, String>((
  ref,
  quoteId,
) async {
  final repository = ref.watch(quotationsRepositoryProvider);
  return repository.fetchQuoteDetail(quoteId);
});

final quotationsFoundationProvider = FutureProvider<QuoteFoundationBundle>((
  ref,
) async {
  final repository = ref.watch(quotationsRepositoryProvider);
  return repository.loadFoundation();
});
