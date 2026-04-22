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

    if (permission.isEmpty) return;

    final permissionId = (permission.first as Map)['id'].toString();

    await _client
        .from('user_permissions')
        .delete()
        .eq('user_id', userId)
        .eq('branch_id', branchId)
        .eq('permission_id', permissionId);
  }
}
