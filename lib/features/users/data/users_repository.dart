import 'package:supabase_flutter/supabase_flutter.dart';

class UserBranchAssignment {
  UserBranchAssignment({
    required this.membershipId,
    required this.userId,
    required this.branchId,
    required this.branchCode,
    required this.branchName,
    required this.roleOverride,
    required this.isDefault,
    required this.isActive,
    this.canOpenCash = false,
    this.canCloseCash = false,
    this.posPinOverride,
    this.displayOrder = 0,
    this.membershipNotes,
  });

  final String membershipId;
  final String userId;
  final String branchId;
  final String branchCode;
  final String branchName;
  final String? roleOverride;
  final bool isDefault;
  final bool isActive;
  final bool canOpenCash;
  final bool canCloseCash;
  final String? posPinOverride;
  final int displayOrder;
  final String? membershipNotes;

  factory UserBranchAssignment.fromMap(Map<String, dynamic> map) {
    final branch = Map<String, dynamic>.from(
      (map['branches'] as Map?) ?? const <String, dynamic>{},
    );

    return UserBranchAssignment(
      membershipId: (map['id'] ?? '').toString(),
      userId: (map['user_id'] ?? '').toString(),
      branchId: (map['branch_id'] ?? '').toString(),
      branchCode: (branch['code'] ?? '').toString(),
      branchName: (branch['name'] ?? '').toString(),
      roleOverride: map['role_override']?.toString(),
      isDefault: map['is_default'] == true,
      isActive: map['is_active'] == true,
      canOpenCash: map['can_open_cash'] == true,
      canCloseCash: map['can_close_cash'] == true,
      posPinOverride: map['pos_pin_override']?.toString(),
      displayOrder: _toInt(map['display_order']),
      membershipNotes: map['notes']?.toString(),
    );
  }
}

class UserEntity {
  UserEntity({
    required this.id,
    required this.fullName,
    required this.email,
    required this.phone,
    required this.role,
    required this.isActive,
    required this.branches,
    this.employeeCode,
    this.jobTitle,
    this.hireDate,
    this.notes,
  });

  final String id;
  final String fullName;
  final String? email;
  final String? phone;
  final String role;
  final bool isActive;
  final List<UserBranchAssignment> branches;
  final String? employeeCode;
  final String? jobTitle;
  final DateTime? hireDate;
  final String? notes;

  int get activeBranchCount => branches.where((item) => item.isActive).length;
}

class BranchOption {
  BranchOption({required this.id, required this.code, required this.name});

  final String id;
  final String code;
  final String name;

  factory BranchOption.fromMap(Map<String, dynamic> map) {
    return BranchOption(
      id: (map['id'] ?? '').toString(),
      code: (map['code'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
    );
  }
}

class UserInput {
  UserInput({
    required this.id,
    required this.fullName,
    required this.phone,
    required this.role,
    required this.isActive,
    this.employeeCode,
    this.jobTitle,
    this.hireDate,
    this.notes,
  });

  final String id;
  final String fullName;
  final String? phone;
  final String role;
  final bool isActive;
  final String? employeeCode;
  final String? jobTitle;
  final DateTime? hireDate;
  final String? notes;
}

class UserBranchAssignInput {
  UserBranchAssignInput({
    required this.userId,
    required this.branchId,
    required this.roleOverride,
    required this.makeDefault,
    this.canOpenCash = false,
    this.canCloseCash = false,
  });

  final String userId;
  final String branchId;
  final String? roleOverride;
  final bool makeDefault;
  final bool canOpenCash;
  final bool canCloseCash;
}

class MembershipUpdateInput {
  MembershipUpdateInput({
    required this.membershipId,
    required this.canOpenCash,
    required this.canCloseCash,
    this.roleOverride,
    this.posPinOverride,
    this.notes,
  });

  final String membershipId;
  final bool canOpenCash;
  final bool canCloseCash;
  final String? roleOverride;
  final String? posPinOverride;
  final String? notes;
}

class InviteEmployeeInput {
  InviteEmployeeInput({required this.email, required this.role, this.fullName});

  final String email;
  final String role;
  final String? fullName;
}

class CreateEmployeeInput {
  CreateEmployeeInput({
    required this.fullName,
    required this.email,
    required this.password,
    required this.role,
    this.phone,
    this.employeeCode,
    this.jobTitle,
    this.notes,
  });

  final String fullName;
  final String email;
  final String password;
  final String role;
  final String? phone;
  final String? employeeCode;
  final String? jobTitle;
  final String? notes;
}

class UsersRepository {
  UsersRepository(this._client);

  final SupabaseClient _client;

  Future<List<UserEntity>> fetchUsers() async {
    final usersRows = await _client
        .from('profiles')
        .select(
          'id, full_name, email, phone, role, is_active, '
          'employee_code, job_title, hire_date, notes',
        )
        .order('full_name');

    final membershipRows = await _client
        .from('users_branches')
        .select(
          'id, user_id, branch_id, role_override, is_default, is_active, '
          'can_open_cash, can_close_cash, pos_pin_override, display_order, notes, '
          'branches(code, name)',
        )
        .order('display_order')
        .order('created_at');

    final membershipsByUser = <String, List<UserBranchAssignment>>{};
    for (final row in membershipRows) {
      final membership = UserBranchAssignment.fromMap(
        Map<String, dynamic>.from(row as Map),
      );
      membershipsByUser
          .putIfAbsent(membership.userId, () => [])
          .add(membership);
    }

    return usersRows
        .map((row) {
          final item = Map<String, dynamic>.from(row as Map);
          final id = (item['id'] ?? '').toString();
          return UserEntity(
            id: id,
            fullName: (item['full_name'] ?? '').toString(),
            email: item['email']?.toString(),
            phone: item['phone']?.toString(),
            role: (item['role'] ?? '').toString(),
            isActive: item['is_active'] == true,
            branches: membershipsByUser[id] ?? const <UserBranchAssignment>[],
            employeeCode: item['employee_code']?.toString(),
            jobTitle: item['job_title']?.toString(),
            hireDate: item['hire_date'] == null
                ? null
                : DateTime.tryParse(item['hire_date'].toString()),
            notes: item['notes']?.toString(),
          );
        })
        .toList(growable: false);
  }

  Future<List<BranchOption>> fetchActiveBranches() async {
    final rows = await _client
        .from('branches')
        .select('id, code, name')
        .eq('is_active', true)
        .order('name');

    return rows
        .map(
          (row) => BranchOption.fromMap(Map<String, dynamic>.from(row as Map)),
        )
        .toList(growable: false);
  }

  Future<void> updateUser(UserInput input) async {
    await _client
        .from('profiles')
        .update({
          'full_name': input.fullName.trim(),
          'phone': _nullIfEmpty(input.phone),
          'role': input.role,
          'is_active': input.isActive,
          'employee_code': _nullIfEmpty(input.employeeCode),
          'job_title': _nullIfEmpty(input.jobTitle),
          'hire_date': input.hireDate?.toIso8601String().split('T').first,
          'notes': _nullIfEmpty(input.notes),
        })
        .eq('id', input.id);
  }

  Future<void> setUserActive({
    required String userId,
    required bool isActive,
  }) async {
    await _client
        .from('profiles')
        .update({'is_active': isActive})
        .eq('id', userId);
  }

  Future<void> assignBranch(UserBranchAssignInput input) async {
    await _client.from('users_branches').upsert({
      'user_id': input.userId,
      'branch_id': input.branchId,
      'role_override': _nullIfEmpty(input.roleOverride),
      'is_active': true,
      'is_default': false,
      'can_open_cash': input.canOpenCash,
      'can_close_cash': input.canCloseCash,
    }, onConflict: 'user_id,branch_id');

    if (input.makeDefault) {
      await setDefaultBranch(userId: input.userId, branchId: input.branchId);
    }
  }

  Future<void> updateMembership(MembershipUpdateInput input) async {
    await _client
        .from('users_branches')
        .update({
          'role_override': _nullIfEmpty(input.roleOverride),
          'can_open_cash': input.canOpenCash,
          'can_close_cash': input.canCloseCash,
          'pos_pin_override': _nullIfEmpty(input.posPinOverride),
          'notes': _nullIfEmpty(input.notes),
        })
        .eq('id', input.membershipId);
  }

  Future<void> setMembershipActive({
    required String membershipId,
    required bool isActive,
  }) async {
    await _client
        .from('users_branches')
        .update({'is_active': isActive})
        .eq('id', membershipId);
  }

  Future<void> setDefaultBranch({
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

  /// Invites a new employee via the `invite-employee` Supabase Edge Function.
  Future<void> inviteEmployee(InviteEmployeeInput input) async {
    await _client.functions.invoke(
      'invite-employee',
      body: {
        'email': input.email.trim().toLowerCase(),
        'role': input.role,
        if (input.fullName != null && input.fullName!.trim().isNotEmpty)
          'full_name': input.fullName!.trim(),
      },
    );
  }

  Future<void> createEmployee(CreateEmployeeInput input) async {
    await _client.rpc(
      'create_employee_user',
      params: {
        'p_email': input.email.trim().toLowerCase(),
        'p_password': input.password,
        'p_full_name': input.fullName.trim(),
        'p_role': input.role,
        'p_phone': _nullIfEmpty(input.phone),
        'p_employee_code': _nullIfEmpty(input.employeeCode),
        'p_job_title': _nullIfEmpty(input.jobTitle),
        'p_notes': _nullIfEmpty(input.notes),
      },
    );
  }
}

String? _nullIfEmpty(String? value) {
  if (value == null) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

int _toInt(dynamic value) {
  if (value == null) return 0;
  if (value is int) return value;
  if (value is double) return value.toInt();
  return int.tryParse(value.toString()) ?? 0;
}
