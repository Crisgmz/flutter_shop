import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_providers.dart';
import '../data/purchases_repository.dart';

final purchasesSearchProvider = StateProvider<String>((ref) => '');

final purchasesRepositoryProvider = Provider<PurchasesRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return PurchasesRepository(client);
});

final purchasesListProvider = FutureProvider<List<PurchaseSummary>>((
  ref,
) async {
  final repository = ref.watch(purchasesRepositoryProvider);
  return repository.fetchPurchases();
});

final purchaseSuppliersProvider = FutureProvider<List<PurchaseSupplier>>((
  ref,
) async {
  final repository = ref.watch(purchasesRepositoryProvider);
  return repository.fetchSuppliers();
});

final purchaseProductsProvider = FutureProvider<List<PurchaseProduct>>((
  ref,
) async {
  final repository = ref.watch(purchasesRepositoryProvider);
  return repository.fetchProducts();
});
