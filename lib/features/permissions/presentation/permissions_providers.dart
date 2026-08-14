import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_providers.dart';
import '../data/permissions_repository.dart';

final permissionsRepositoryProvider = Provider<PermissionsRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return PermissionsRepository(client);
});

final allPermissionsProvider =
    FutureProvider<List<PermissionDefinition>>((ref) async {
  final repo = ref.watch(permissionsRepositoryProvider);
  return repo.fetchAllPermissions();
});

final effectivePermissionsProvider = FutureProvider.family<
    List<EffectivePermission>,
    ({String userId, String branchId})>((ref, args) async {
  final repo = ref.watch(permissionsRepositoryProvider);
  return repo.fetchEffectivePermissions(
    userId: args.userId,
    branchId: args.branchId,
  );
});

/// Overrides de permisos del usuario autenticado en la sucursal activa
/// (`permission_code -> granted`). Se recalcula al cambiar de usuario, y al
/// cambiar de sucursal se invalida desde `invalidateBranchScopedData`.
///
/// Nunca lanza: ante cualquier error devuelve un mapa vacío, de modo que los
/// gates caigan al valor por rol en vez de bloquear pantallas.
final myPermissionOverridesProvider =
    FutureProvider<Map<String, bool>>((ref) async {
  ref.watch(authStateChangesProvider);
  final repo = ref.watch(permissionsRepositoryProvider);
  try {
    return await repo.fetchMyPermissionOverrides();
  } catch (_) {
    return const <String, bool>{};
  }
});
