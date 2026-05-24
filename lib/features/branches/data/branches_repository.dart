import 'package:supabase_flutter/supabase_flutter.dart';

class BranchEntity {
  BranchEntity({
    required this.id,
    required this.code,
    required this.name,
    required this.address,
    required this.phone,
    required this.isMain,
    required this.isActive,
    required this.memberCount,
    required this.createdAt,
  });

  final String id;
  final String code;
  final String name;
  final String? address;
  final String? phone;
  final bool isMain;
  final bool isActive;
  final int memberCount;
  final DateTime? createdAt;

  factory BranchEntity.fromMap(
    Map<String, dynamic> map, {
    required int memberCount,
  }) {
    return BranchEntity(
      id: (map['id'] ?? '').toString(),
      code: (map['code'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      address: map['address']?.toString(),
      phone: map['phone']?.toString(),
      isMain: map['is_main'] == true,
      isActive: map['is_active'] == true,
      memberCount: memberCount,
      createdAt: map['created_at'] == null
          ? null
          : DateTime.tryParse(map['created_at'].toString()),
    );
  }
}

class BranchMember {
  BranchMember({
    required this.membershipId,
    required this.userId,
    required this.fullName,
    required this.email,
    required this.profileRole,
    required this.roleOverride,
    required this.isDefault,
    required this.isActive,
    required this.profileIsActive,
  });

  final String membershipId;
  final String userId;
  final String fullName;
  final String? email;
  final String profileRole;
  final String? roleOverride;
  final bool isDefault;
  final bool isActive;
  final bool profileIsActive;

  factory BranchMember.fromMap(Map<String, dynamic> map) {
    final profile = Map<String, dynamic>.from(
      (map['profiles'] as Map?) ?? const <String, dynamic>{},
    );

    return BranchMember(
      membershipId: (map['id'] ?? '').toString(),
      userId: (map['user_id'] ?? '').toString(),
      fullName: (profile['full_name'] ?? '').toString(),
      email: profile['email']?.toString(),
      profileRole: (profile['role'] ?? '').toString(),
      roleOverride: map['role_override']?.toString(),
      isDefault: map['is_default'] == true,
      isActive: map['is_active'] == true,
      profileIsActive: profile['is_active'] == true,
    );
  }
}

class BranchUserOption {
  BranchUserOption({
    required this.id,
    required this.fullName,
    required this.email,
    required this.role,
    required this.isActive,
  });

  final String id;
  final String fullName;
  final String? email;
  final String role;
  final bool isActive;

  factory BranchUserOption.fromMap(Map<String, dynamic> map) {
    return BranchUserOption(
      id: (map['id'] ?? '').toString(),
      fullName: (map['full_name'] ?? '').toString(),
      email: map['email']?.toString(),
      role: (map['role'] ?? '').toString(),
      isActive: map['is_active'] == true,
    );
  }
}

class BranchInput {
  BranchInput({
    required this.code,
    required this.name,
    required this.address,
    required this.phone,
    required this.isActive,
    required this.isMain,
    this.id,
  });

  final String? id;
  final String code;
  final String name;
  final String? address;
  final String? phone;
  final bool isActive;
  final bool isMain;
}

class BranchAssignUserInput {
  BranchAssignUserInput({
    required this.branchId,
    required this.userId,
    required this.roleOverride,
    required this.makeDefaultForUser,
  });

  final String branchId;
  final String userId;
  final String? roleOverride;
  final bool makeDefaultForUser;
}

class BranchesRepository {
  BranchesRepository(this._client);

  final SupabaseClient _client;

  Future<List<BranchEntity>> fetchBranches() async {
    final branchRows = await _client
        .from('branches')
        .select(
          'id, code, name, address, phone, is_main, is_active, created_at',
        )
        .order('is_main', ascending: false)
        .order('name');

    final membershipRows = await _client
        .from('users_branches')
        .select('branch_id')
        .eq('is_active', true);

    final membersCountByBranch = <String, int>{};
    for (final row in membershipRows) {
      final item = Map<String, dynamic>.from(row as Map);
      final branchId = (item['branch_id'] ?? '').toString();
      if (branchId.isEmpty) continue;
      membersCountByBranch[branchId] =
          (membersCountByBranch[branchId] ?? 0) + 1;
    }

    return branchRows
        .map((row) {
          final item = Map<String, dynamic>.from(row as Map);
          final branchId = (item['id'] ?? '').toString();
          return BranchEntity.fromMap(
            item,
            memberCount: membersCountByBranch[branchId] ?? 0,
          );
        })
        .toList(growable: false);
  }

  Future<List<BranchMember>> fetchBranchMembers(String branchId) async {
    final rows = await _client
        .from('users_branches')
        .select(
          'id, user_id, role_override, is_default, is_active, profiles(full_name, email, role, is_active)',
        )
        .eq('branch_id', branchId)
        .order('is_default', ascending: false);

    return rows
        .map(
          (row) => BranchMember.fromMap(Map<String, dynamic>.from(row as Map)),
        )
        .toList(growable: false);
  }

  Future<List<BranchUserOption>> fetchActiveUsers() async {
    final rows = await _client
        .from('profiles')
        .select('id, full_name, email, role, is_active')
        .eq('is_active', true)
        .order('full_name');

    return rows
        .map(
          (row) =>
              BranchUserOption.fromMap(Map<String, dynamic>.from(row as Map)),
        )
        .toList(growable: false);
  }

  Future<String> saveBranch(BranchInput input) async {
    final payload = <String, dynamic>{
      'code': input.code.trim().toUpperCase(),
      'name': input.name.trim(),
      'address': _nullIfEmpty(input.address),
      'phone': _nullIfEmpty(input.phone),
      'is_active': input.isActive,
      'is_main': input.isMain,
    };

    late String branchId;

    if (input.id == null) {
      // Multi-tenant: el INSERT pasa por la RLS branches_write que exige
      // company_id = current_company_id(). El RPC nos lo dice.
      final companyIdResult = await _client.rpc('current_company_id');
      final companyId = companyIdResult?.toString();
      if (companyId == null || companyId.isEmpty) {
        throw Exception(
          'No hay empresa asignada al usuario actual. Completa el onboarding.',
        );
      }
      payload['company_id'] = companyId;

      final inserted = await _client
          .from('branches')
          .insert(payload)
          .select('id')
          .single();
      final item = Map<String, dynamic>.from(inserted as Map);
      branchId = (item['id'] ?? '').toString();
    } else {
      // En UPDATE no tocamos company_id (cambiar de empresa una sucursal
      // existente no tiene sentido y la RLS lo bloquearía igual).
      await _client.from('branches').update(payload).eq('id', input.id!);
      branchId = input.id!;
    }

    if (input.isMain) {
      await setMainBranch(branchId);
    }

    return branchId;
  }

  Future<void> setBranchActive({
    required String branchId,
    required bool isActive,
  }) async {
    await _client
        .from('branches')
        .update({'is_active': isActive})
        .eq('id', branchId);
  }

  Future<void> setMainBranch(String branchId) async {
    await _client
        .from('branches')
        .update({'is_main': false})
        .eq('is_main', true);
    await _client.from('branches').update({'is_main': true}).eq('id', branchId);
  }

  Future<void> assignUserToBranch(BranchAssignUserInput input) async {
    final payload = <String, dynamic>{
      'user_id': input.userId,
      'branch_id': input.branchId,
      'role_override': _nullIfEmpty(input.roleOverride),
      'is_active': true,
      'is_default': false,
    };

    await _client
        .from('users_branches')
        .upsert(payload, onConflict: 'user_id,branch_id');

    if (input.makeDefaultForUser) {
      await setDefaultBranchForUser(
        userId: input.userId,
        branchId: input.branchId,
      );
    }
  }

  Future<void> setBranchMemberActive({
    required String membershipId,
    required bool isActive,
  }) async {
    await _client
        .from('users_branches')
        .update({'is_active': isActive})
        .eq('id', membershipId);
  }

  Future<void> setDefaultBranchForUser({
    required String userId,
    required String branchId,
  }) async {
    await _client
        .from('users_branches')
        .update({'is_default': false})
        .eq('user_id', userId)
        .eq('is_active', true);

    await _client
        .from('users_branches')
        .update({'is_default': true})
        .eq('user_id', userId)
        .eq('branch_id', branchId)
        .eq('is_active', true);
  }
}

String? _nullIfEmpty(String? value) {
  if (value == null) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
