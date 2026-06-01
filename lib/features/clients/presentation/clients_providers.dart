import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_providers.dart';
import '../data/clients_repository.dart';

final clientsSearchProvider = StateProvider<String>((ref) => '');
final clientsShowInactiveProvider = StateProvider<bool>((ref) => false);

/// IDs de clientes marcados para borrado masivo. Vive en un provider para
/// que la selección no se pierda al navegar a otra sección y volver.
final clientsSelectionProvider =
    StateProvider<Set<String>>((ref) => <String>{});

final clientsRepositoryProvider = Provider<ClientsRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return ClientsRepository(client);
});

final clientsListProvider = FutureProvider<List<ClientEntity>>((ref) async {
  final repository = ref.watch(clientsRepositoryProvider);
  return repository.fetchClients();
});

/// Clientes filtrados por búsqueda + showInactive, memoizado. Antes el
/// filter corría en cada `build()` y por cada keystroke.
final clientsFilteredProvider = Provider<List<ClientEntity>>((ref) {
  final clients = ref.watch(clientsListProvider).valueOrNull ?? const [];
  final query = ref.watch(clientsSearchProvider).trim().toLowerCase();
  final showInactive = ref.watch(clientsShowInactiveProvider);

  return clients.where((c) {
    if (!showInactive && !c.isActive) return false;
    if (query.isEmpty) return true;
    if (c.fullName.toLowerCase().contains(query)) return true;
    if ((c.firstName ?? '').toLowerCase().contains(query)) return true;
    if ((c.lastName ?? '').toLowerCase().contains(query)) return true;
    if ((c.companyName ?? '').toLowerCase().contains(query)) return true;
    if ((c.documentNumber ?? '').toLowerCase().contains(query)) return true;
    if ((c.email ?? '').toLowerCase().contains(query)) return true;
    if ((c.phone ?? '').toLowerCase().contains(query)) return true;
    return false;
  }).toList(growable: false);
});

/// Suma de balances pendientes de los clientes ya filtrados. Memoizado
/// para no recorrer la lista en cada rebuild.
final clientsFilteredBalanceProvider = Provider<double>((ref) {
  final filtered = ref.watch(clientsFilteredProvider);
  var total = 0.0;
  for (final c in filtered) {
    total += c.balanceDue;
  }
  return total;
});

final customerBalancesProvider =
    FutureProvider<List<CustomerBalanceItem>>((ref) async {
  final repository = ref.watch(clientsRepositoryProvider);
  return repository.fetchCustomerBalances();
});
