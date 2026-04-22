import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_providers.dart';
import '../data/inventory_repository.dart';

final inventorySearchProvider = StateProvider<String>((ref) => '');
final inventoryLowStockOnlyProvider = StateProvider<bool>((ref) => false);
final inventorySelectedCategoryProvider = StateProvider<String?>((ref) => null);

final inventoryRepositoryProvider = Provider<InventoryRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return InventoryRepository(client);
});

final inventoryCategoriesProvider = FutureProvider<List<InventoryCategory>>((
  ref,
) async {
  final repository = ref.watch(inventoryRepositoryProvider);
  return repository.fetchCategories();
});

final inventoryProductsProvider = FutureProvider<List<InventoryProduct>>((
  ref,
) async {
  final repository = ref.watch(inventoryRepositoryProvider);
  return repository.fetchProducts();
});
