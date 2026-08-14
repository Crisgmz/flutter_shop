import 'package:supabase_flutter/supabase_flutter.dart';

class PermissionDefinition {
  PermissionDefinition({
    required this.id,
    required this.code,
    required this.name,
    this.description,
    this.module,
    this.actionType,
  });

  final String id;
  final String code;
  final String name;
  final String? description;
  final String? module;
  final String? actionType;

  factory PermissionDefinition.fromMap(Map<String, dynamic> map) {
    return PermissionDefinition(
      id: (map['id'] ?? '').toString(),
      code: (map['code'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      description: map['description']?.toString(),
      module: map['module']?.toString(),
      actionType: map['action_type']?.toString(),
    );
  }
}

class EffectivePermission {
  EffectivePermission({
    required this.userId,
    required this.branchId,
    required this.permissionCode,
    required this.permissionName,
    required this.module,
    required this.actionType,
    required this.roleGrant,
    required this.userOverride,
    required this.effectiveGrant,
  });

  final String userId;
  final String branchId;
  final String permissionCode;
  final String permissionName;
  final String? module;
  final String? actionType;
  final bool roleGrant;
  final bool? userOverride;
  final bool effectiveGrant;

  bool get hasOverride => userOverride != null;
}

class PermissionsRepository {
  PermissionsRepository(this._client);

  final SupabaseClient _client;

  Future<List<PermissionDefinition>> fetchAllPermissions() async {
    final rows = await _client
        .from('permissions')
        .select('id, code, name, description, module, action_type')
        .order('module')
        .order('name');

    return rows
        .map(
          (row) => PermissionDefinition.fromMap(
            Map<String, dynamic>.from(row as Map),
          ),
        )
        .toList(growable: false);
  }

  Future<List<EffectivePermission>> fetchEffectivePermissions({
    required String userId,
    required String branchId,
  }) async {
    final rows = await _client
        .from('employee_effective_permissions_view')
        .select(
          'user_id, branch_id, permission_code, permission_name, module, '
          'action_type, role_grant, user_override, effective_grant',
        )
        .eq('user_id', userId)
        .eq('branch_id', branchId)
        .order('module')
        .order('permission_name');

    return rows.map((row) {
      final item = Map<String, dynamic>.from(row as Map);
      return EffectivePermission(
        userId: (item['user_id'] ?? '').toString(),
        branchId: (item['branch_id'] ?? '').toString(),
        permissionCode: (item['permission_code'] ?? '').toString(),
        permissionName: (item['permission_name'] ?? '').toString(),
        module: item['module']?.toString(),
        actionType: item['action_type']?.toString(),
        roleGrant: item['role_grant'] == true,
        userOverride: item['user_override'] as bool?,
        effectiveGrant: item['effective_grant'] == true,
      );
    }).toList(growable: false);
  }

  Future<void> setUserPermissionOverride({
    required String userId,
    required String branchId,
    required String permissionCode,
    required bool granted,
  }) async {
    final permission = await _client
        .from('permissions')
        .select('id')
        .eq('code', permissionCode)
        .limit(1);

    if (permission.isEmpty) {
      throw Exception('Permiso no encontrado: $permissionCode');
    }

    final permissionId = (permission.first as Map)['id'].toString();

    await _client.from('user_permissions').upsert(
      {
        'user_id': userId,
        'branch_id': branchId,
        'permission_id': permissionId,
        'granted': granted,
      },
      onConflict: 'user_id,branch_id,permission_id',
    );
  }

  Future<void> removeUserPermissionOverride({
    required String userId,
    required String branchId,
    required String permissionCode,
  }) async {
    final permission = await _client
        .from('permissions')
        .select('id')
        .eq('code', permissionCode)
        .limit(1);

    if (permission.isEmpty) {
      throw Exception('Permiso no encontrado: $permissionCode');
    }

    final permissionId = (permission.first as Map)['id'].toString();

    final deleted = await _client
        .from('user_permissions')
        .delete()
        .eq('user_id', userId)
        .eq('branch_id', branchId)
        .eq('permission_id', permissionId)
        .select('id');

    if (deleted.isEmpty) {
      throw Exception(
        'No se quitó el override. No tienes permiso para modificar los '
        'permisos de este usuario, o el override es global (sin sucursal).',
      );
    }
  }

  /// Overrides de permisos del usuario autenticado en la sucursal activa,
  /// como `permission_code -> granted`.
  ///
  /// Solo devuelve los overrides propios (no los grants del rol): el valor
  /// por defecto del rol lo resuelve el cliente con `allowedRoles`/`RoleAccess`.
  Future<Map<String, bool>> fetchMyPermissionOverrides() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return const <String, bool>{};

    final branchResult = await _client.rpc('current_branch_id');
    final branchId = branchResult?.toString();
    // Sin sucursal activa no se sabe qué override aplica. Devolver vacío deja
    // los permisos en el valor por rol, que es el comportamiento base.
    if (branchId == null || branchId.isEmpty) return const <String, bool>{};

    final rows = await _client
        .from('user_permissions')
        .select('granted, branch_id, permissions!inner(code)')
        .eq('user_id', userId)
        .eq('is_active', true)
        .or('branch_id.eq.$branchId,branch_id.is.null');

    final result = <String, bool>{};
    final branchScoped = <String>{};
    for (final row in rows) {
      final item = Map<String, dynamic>.from(row as Map);
      final code = _embeddedCode(item['permissions']);
      if (code.isEmpty) continue;

      // El override de la sucursal gana sobre el global (branch_id null).
      final isBranchScoped = (item['branch_id'] ?? '').toString() == branchId;
      if (!isBranchScoped && branchScoped.contains(code)) continue;
      if (isBranchScoped) branchScoped.add(code);
      result[code] = item['granted'] == true;
    }
    return result;
  }

  /// Lee `code` del embed `permissions(...)`, que PostgREST puede devolver
  /// como objeto o como lista de un elemento según la cardinalidad detectada.
  String _embeddedCode(dynamic embedded) {
    final value = embedded is List
        ? (embedded.isEmpty ? null : embedded.first)
        : embedded;
    if (value is! Map) return '';
    return (value['code'] ?? '').toString();
  }

  /// Borra TODOS los overrides del usuario en la sucursal indicada, de
  /// forma que sus permisos vuelvan a derivarse 100% del rol base.
  /// Devuelve la cantidad de filas afectadas.
  Future<int> clearAllOverridesForUserBranch({
    required String userId,
    required String branchId,
  }) async {
    final deleted = await _client
        .from('user_permissions')
        .delete()
        .eq('user_id', userId)
        .eq('branch_id', branchId)
        .select('permission_id');
    return deleted.length;
  }
}
