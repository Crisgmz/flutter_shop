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

/// Compras filtradas por búsqueda, memoizado. El filter ya no corre en
/// cada `build()` ni en cada keystroke.
final purchasesFilteredProvider = Provider<List<PurchaseSummary>>((ref) {
  final purchases = ref.watch(purchasesListProvider).valueOrNull ?? const [];
  final query = ref.watch(purchasesSearchProvider).trim().toLowerCase();
  if (query.isEmpty) return purchases;
  return purchases.where((p) {
    if ((p.purchaseNumber ?? '').toLowerCase().contains(query)) return true;
    if ((p.invoiceNumber ?? '').toLowerCase().contains(query)) return true;
    if (p.supplierName.toLowerCase().contains(query)) return true;
    if (p.status.toLowerCase().contains(query)) return true;
    return false;
  }).toList(growable: false);
});

/// Total de las compras filtradas, memoizado.
final purchasesFilteredTotalProvider = Provider<double>((ref) {
  final filtered = ref.watch(purchasesFilteredProvider);
  var total = 0.0;
  for (final p in filtered) {
    total += p.totalAmount;
  }
  return total;
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
