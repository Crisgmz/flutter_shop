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

/// Compras que trajeron el IMEI escrito en el buscador — para saber a qué
/// proveedor se le compró un equipo. Solo consulta con 6+ caracteres (mismo
/// umbral que el historial de ventas) y espera a que se deje de teclear.
final purchasesImeiMatchesProvider =
    FutureProvider.autoDispose<List<PurchaseSummary>>((ref) async {
  final imei = ref.watch(purchasesSearchProvider).trim();
  if (imei.length < 6) return const [];

  var disposed = false;
  ref.onDispose(() => disposed = true);
  await Future<void>.delayed(const Duration(milliseconds: 350));
  if (disposed) return const [];

  final repository = ref.watch(purchasesRepositoryProvider);
  return repository.searchPurchasesByImei(imei);
});

/// Compras filtradas por búsqueda, memoizado. El filter ya no corre en
/// cada `build()` ni en cada keystroke. Suma las que coinciden por IMEI.
final purchasesFilteredProvider = Provider<List<PurchaseSummary>>((ref) {
  final purchases = ref.watch(purchasesListProvider).valueOrNull ?? const [];
  final query = ref.watch(purchasesSearchProvider).trim().toLowerCase();
  if (query.isEmpty) return purchases;
  final byText = purchases.where((p) {
    if ((p.purchaseNumber ?? '').toLowerCase().contains(query)) return true;
    if ((p.invoiceNumber ?? '').toLowerCase().contains(query)) return true;
    if (p.supplierName.toLowerCase().contains(query)) return true;
    if (p.status.toLowerCase().contains(query)) return true;
    return false;
  }).toList();

  final byImei =
      ref.watch(purchasesImeiMatchesProvider).valueOrNull ?? const [];
  final seen = {for (final p in byText) p.id};
  for (final p in byImei) {
    if (seen.add(p.id)) byText.add(p);
  }
  return List.unmodifiable(byText);
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
