import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_providers.dart';
import '../data/clients_repository.dart';

final clientsSearchProvider = StateProvider<String>((ref) => '');
final clientsShowInactiveProvider = StateProvider<bool>((ref) => false);

final clientsRepositoryProvider = Provider<ClientsRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return ClientsRepository(client);
});

final clientsListProvider = FutureProvider<List<ClientEntity>>((ref) async {
  final repository = ref.watch(clientsRepositoryProvider);
  return repository.fetchClients();
});

final customerBalancesProvider =
    FutureProvider<List<CustomerBalanceItem>>((ref) async {
  final repository = ref.watch(clientsRepositoryProvider);
  return repository.fetchCustomerBalances();
});
