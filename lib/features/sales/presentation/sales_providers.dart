import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_providers.dart';
import '../data/sales_repository.dart';

final salesSearchProvider = StateProvider<String>((ref) => '');
final salesSelectedCategoryProvider = StateProvider<String?>((ref) => null);

/// Modo del POS: venta normal o registro de devolución (PRD F5).
enum PosMode { sale, returnMode }

final posModeProvider = StateProvider<PosMode>((ref) => PosMode.sale);

/// Snapshot del carrito + cabecera de la venta en curso.
///
/// El POS guarda este snapshot al salir de la pantalla (en `dispose`) y lo
/// restaura al volver (en `initState`). Así, si el cajero arma una venta y
/// navega a otra sección, no pierde lo que estaba haciendo. El provider NO es
/// autoDispose a propósito: debe sobrevivir mientras la app esté abierta.
class SaleDraft {
  const SaleDraft({
    this.items = const [],
    this.receiptType = 'consumer_final',
    this.paymentMethod,
    this.clientId,
    this.notes = '',
  });

  final List<SaleCartItem> items;
  final String receiptType;
  final String? paymentMethod;
  final String? clientId;
  final String notes;

  bool get isEmpty => items.isEmpty;
}

final saleDraftProvider = StateProvider<SaleDraft>((ref) => const SaleDraft());

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

/// Productos filtrados por búsqueda + categoría, memoizado.
///
/// Antes el POS llamaba `_filterProducts(...)` en cada `build()` — un
/// O(n) por keystroke aunque la búsqueda no hubiera cambiado. Riverpod
/// cachea el resultado mientras los inputs no cambien.
final salesFilteredProductsProvider =
    Provider<List<SalesProduct>>((ref) {
  final productsAsync = ref.watch(salesProductsProvider);
  final products = productsAsync.valueOrNull;
  if (products == null) return const <SalesProduct>[];

  final rawQuery = ref.watch(salesSearchProvider).trim().toLowerCase();
  final categoryId = ref.watch(salesSelectedCategoryProvider);

  return products.where((p) {
    // Mostramos productos aunque tengan stock 0 (se ven con cantidad 0); solo
    // ocultamos los inactivos. El bloqueo de venta sin stock, si aplica, lo
    // maneja el setting "No permitir venta sin stock" al agregar al carrito.
    if (!p.isActive) return false;
    if (categoryId != null && p.categoryId != categoryId) return false;
    if (rawQuery.isEmpty) return true;
    return p.name.toLowerCase().contains(rawQuery) ||
        (p.sku?.toLowerCase().contains(rawQuery) ?? false) ||
        (p.barcode?.toLowerCase().contains(rawQuery) ?? false);
  }).toList(growable: false);
});

/// Map clientId → SalesClient para lookups O(1) en el POS.
/// Antes el POS hacía `clients.firstWhere((c) => c.id == _clientId)` en
/// cada cambio de cliente; con 1000+ clientes era O(n).
final salesClientsByIdProvider = Provider<Map<String, SalesClient>>((ref) {
  final clients = ref.watch(salesClientsProvider).valueOrNull ?? const [];
  return {for (final c in clients) c.id: c};
});
