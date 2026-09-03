import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_providers.dart';
import '../data/users_repository.dart';

final usersSearchProvider = StateProvider<String>((ref) => '');
final usersShowInactiveProvider = StateProvider<bool>((ref) => false);
final selectedUserIdProvider = StateProvider<String?>((ref) => null);

final usersRepositoryProvider = Provider<UsersRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return UsersRepository(client);
});

final usersListProvider = FutureProvider<List<UserEntity>>((ref) async {
  final repository = ref.watch(usersRepositoryProvider);
  return repository.fetchUsers();
});

final usersBranchOptionsProvider = FutureProvider<List<BranchOption>>((
  ref,
) async {
  final repository = ref.watch(usersRepositoryProvider);
  return repository.fetchActiveBranches();
});

/// Empleados que quedaron sin sucursal y por eso no salen en el listado
/// (migración 84). Nunca lanza: si el RPC todavía no está en la base, devuelve
/// vacío y la pantalla se comporta como antes.
final orphanEmployeesProvider =
    FutureProvider<List<OrphanEmployee>>((ref) async {
  final repository = ref.watch(usersRepositoryProvider);
  try {
    return await repository.fetchOrphanEmployees();
  } catch (_) {
    return const <OrphanEmployee>[];
  }
});
