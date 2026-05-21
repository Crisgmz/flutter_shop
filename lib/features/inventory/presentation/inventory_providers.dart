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

final inventoryProductsProvider = StreamProvider<List<InventoryProduct>>((ref) {
  final repository = ref.watch(inventoryRepositoryProvider);
  final categoriesAsync = ref.watch(inventoryCategoriesProvider);

  return categoriesAsync.when(
    data: (categories) {
      final categoryNames = {
        for (final c in categories) c.id: c.name,
      };
      return repository.productsStream(categoryNames);
    },
    error: (err, stack) => Stream.error(err, stack),
    loading: () => const Stream<List<InventoryProduct>>.empty(),
  );
});
