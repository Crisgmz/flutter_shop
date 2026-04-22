import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_providers.dart';
import '../data/sales_repository.dart';

final salesSearchProvider = StateProvider<String>((ref) => '');
final salesSelectedCategoryProvider = StateProvider<String?>((ref) => null);

final salesRepositoryProvider = Provider<SalesRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return SalesRepository(client);
});

final salesCategoriesProvider = FutureProvider<List<SalesCategory>>((
  ref,
) async {
  final repository = ref.watch(salesRepositoryProvider);
  return repository.fetchCategories();
});

final salesProductsProvider = FutureProvider<List<SalesProduct>>((ref) async {
  final repository = ref.watch(salesRepositoryProvider);
  return repository.fetchProducts();
});

final salesClientsProvider = FutureProvider<List<SalesClient>>((ref) async {
  final repository = ref.watch(salesRepositoryProvider);
  return repository.fetchClients();
});
