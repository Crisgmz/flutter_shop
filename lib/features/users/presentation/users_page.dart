import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../shared/extensions/iterable_extensions.dart';
import '../../../shared/responsive/responsive_layout.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/module_page.dart';
import '../../../shared/widgets/ui_custom.dart';
import '../../permissions/data/permissions_repository.dart';
import '../../permissions/presentation/permissions_providers.dart';
import '../data/users_repository.dart';
import 'users_providers.dart';

const _roles = <String, String>{
  'admin': 'Administrador',
  'supervisor': 'Supervisor',
  'cashier': 'Cajero',
  'accountant': 'Contador',
};

class UsersPage extends ConsumerStatefulWidget {
  const UsersPage({super.key});

  @override
  ConsumerState<UsersPage> createState() => _UsersPageState();
}

class _UsersPageState extends ConsumerState<UsersPage> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final usersAsync = ref.watch(usersListProvider);
    final query = ref.watch(usersSearchProvider).trim().toLowerCase();
    final showInactive = ref.watch(usersShowInactiveProvider);
    final selectedUserId = ref.watch(selectedUserIdProvider);

    return ModulePage(
      title: 'Usuarios',
      description: 'Roles, estado y sucursales por usuario.',
      actions: [
        OutlinedButton.icon(
          onPressed: _refresh,
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('Actualizar'),
        ),
        const SizedBox(width: AppTokens.s8),
        FilledButton.icon(
          onPressed: _onCreateUser,
          icon: const Icon(Icons.person_add_outlined, size: 18),
          label: const Text('Crear usuario'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildFilterBar(showInactive),
          const SizedBox(height: AppTokens.s24),
          usersAsync.when(
            data: (users) {
              final filtered = users
                  .where((user) {
                    if (!showInactive && !user.isActive) return false;
                    if (query.isEmpty) return true;
                    final haystack = [
                      user.fullName,
                      user.email ?? '',
                      _roleLabel(user.role),
                    ].join(' ').toLowerCase();
                    return haystack.contains(query);
                  })
                  .toList(growable: false);

              if (filtered.isNotEmpty &&
                  (selectedUserId == null ||
                      !filtered.any((item) => item.id == selectedUserId))) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  ref.read(selectedUserIdProvider.notifier).state =
                      filtered.first.id;
                });
              }

              final selectedUser = filtered
                  .where((item) => item.id == selectedUserId)
                  .firstOrNull;

              return Column(
                children: [
                  _UsersKpis(users: filtered),
                  const SizedBox(height: AppTokens.s24),
                  _usersTableCard(
                    filtered: filtered,
                    selectedUserId: selectedUserId,
                  ),
                  const SizedBox(height: AppTokens.s24),
                  _userBranchesCard(selectedUser: selectedUser),
                  const SizedBox(height: AppTokens.s24),
                  _UserPermissionsPanel(selectedUser: selectedUser),
                ],
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => ErrorCard(
              message: 'No se pudieron cargar usuarios: $error',
              onRetry: _refresh,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar(bool showInactive) {
    final isMobile = ResponsiveLayout.isMobile(context);

    final searchField = TextField(
      controller: _searchController,
      onChanged: (value) =>
          ref.read(usersSearchProvider.notifier).state = value,
      decoration: const InputDecoration(
        prefixIcon: Icon(Icons.search, size: 18),
        hintText: 'Buscar por nombre, email o rol',
      ),
    );

    final filterChip = FilterChip(
      selected: showInactive,
      label: const Text('Mostrar inactivos'),
      onSelected: (value) =>
          ref.read(usersShowInactiveProvider.notifier).state = value,
    );

    if (isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [searchField, const SizedBox(height: AppTokens.s12), filterChip],
      );
    }

    return Row(
      children: [
        Expanded(child: searchField),
        const SizedBox(width: AppTokens.s12),
        filterChip,
      ],
    );
  }

  Widget _usersTableCard({
    required List<UserEntity> filtered,
    required String? selectedUserId,
  }) {
    return DataTableShell(
      title: 'Listado de usuarios (${filtered.length})',
      child: filtered.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(AppTokens.s20),
              child: Text(
                'No hay usuarios que coincidan con el filtro.',
                style: TextStyle(color: AppTokens.mutedForeground),
              ),
            )
          : DataTable(
              columns: const [
                DataColumn(label: Text('Nombre')),
                DataColumn(label: Text('Email')),
                DataColumn(label: Text('Rol')),
                DataColumn(label: Text('Teléfono')),
                DataColumn(label: Text('Sucursales'), numeric: true),
                DataColumn(label: Text('Estado')),
                DataColumn(label: Text('Acciones')),
              ],
              rows: filtered
                  .map(
                    (user) => DataRow(
                      selected: user.id == selectedUserId,
                      onSelectChanged: (_) =>
                          ref.read(selectedUserIdProvider.notifier).state = user.id,
                      cells: [
                        DataCell(Text(
                          user.fullName,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        )),
                        DataCell(Text(user.email ?? '-')),
                        DataCell(Text(_roleLabel(user.role))),
                        DataCell(Text(user.phone ?? '-')),
                        DataCell(Text(user.activeBranchCount.toString())),
                        DataCell(StatusBadge(
                          label: user.isActive ? 'Activo' : 'Inactivo',
                          status: user.isActive ? 'active' : 'inactive',
                        )),
                        DataCell(Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Editar',
                              onPressed: () => _onEditUser(user),
                              icon: const Icon(Icons.edit_outlined, size: AppTokens.iconSizeS),
                              visualDensity: VisualDensity.compact,
                            ),
                            IconButton(
                              tooltip: user.isActive ? 'Desactivar' : 'Activar',
                              onPressed: () => _onToggleActive(user),
                              icon: Icon(
                                user.isActive ? Icons.block_outlined : Icons.check_circle_outline,
                                size: AppTokens.iconSizeS,
                                color: user.isActive ? AppTokens.destructive : AppTokens.success,
                              ),
                              visualDensity: VisualDensity.compact,
                            ),
                          ],
                        )),
                      ],
                    ),
                  )
                  .toList(growable: false),
            ),
    );
  }

  Widget _userBranchesCard({required UserEntity? selectedUser}) {
    return DataTableShell(
      title: selectedUser == null
          ? 'Sucursales del usuario'
          : 'Sucursales de ${selectedUser.fullName}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppTokens.s20, AppTokens.s12, AppTokens.s20, 0),
            child: Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonalIcon(
                onPressed: selectedUser == null
                    ? null
                    : () => _onAssignBranch(selectedUser),
                icon: const Icon(Icons.add_home_work_outlined, size: 16),
                label: const Text('Asignar sucursal'),
              ),
            ),
          ),
          if (selectedUser == null)
            const Padding(
              padding: EdgeInsets.all(AppTokens.s20),
              child: Text(
                'Selecciona un usuario para gestionar sus sucursales.',
                style: TextStyle(color: AppTokens.mutedForeground),
              ),
            )
          else if (selectedUser.branches.isEmpty)
            const Padding(
              padding: EdgeInsets.all(AppTokens.s20),
              child: Text(
                'Este usuario no tiene sucursales asignadas.',
                style: TextStyle(color: AppTokens.mutedForeground),
              ),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Sucursal')),
                  DataColumn(label: Text('Rol override')),
                  DataColumn(label: Text('Caja')),
                  DataColumn(label: Text('Default')),
                  DataColumn(label: Text('Estado')),
                  DataColumn(label: Text('Acciones')),
                ],
                rows: selectedUser.branches
                    .map(
                      (branch) => DataRow(
                        cells: [
                          DataCell(Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${branch.branchCode} - ${branch.branchName}',
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                              if (branch.membershipNotes != null &&
                                  branch.membershipNotes!.isNotEmpty)
                                Text(
                                  branch.membershipNotes!,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: AppTokens.mutedForeground,
                                  ),
                                ),
                            ],
                          )),
                          DataCell(Text(_roleLabel(branch.roleOverride ?? '-'))),
                          DataCell(Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Tooltip(
                                message: 'Puede abrir caja',
                                child: Icon(
                                  branch.canOpenCash
                                      ? Icons.lock_open_outlined
                                      : Icons.lock_outline,
                                  size: 14,
                                  color: branch.canOpenCash
                                      ? AppTokens.success
                                      : AppTokens.mutedForeground,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Tooltip(
                                message: 'Puede cerrar caja',
                                child: Icon(
                                  branch.canCloseCash
                                      ? Icons.lock_outlined
                                      : Icons.lock_outline,
                                  size: 14,
                                  color: branch.canCloseCash
                                      ? AppTokens.success
                                      : AppTokens.mutedForeground,
                                ),
                              ),
                            ],
                          )),
                          DataCell(StatusBadge(
                            label: branch.isDefault ? 'Sí' : 'No',
                            status: branch.isDefault ? 'active' : 'inactive',
                          )),
                          DataCell(StatusBadge(
                            label: branch.isActive ? 'Activa' : 'Inactiva',
                            status: branch.isActive ? 'active' : 'inactive',
                          )),
                          DataCell(Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Editar asignación',
                                onPressed: () =>
                                    _onEditMembership(branch),
                                icon: const Icon(Icons.edit_outlined,
                                    size: AppTokens.iconSizeS),
                                visualDensity: VisualDensity.compact,
                              ),
                              IconButton(
                                tooltip: 'Marcar default',
                                onPressed: branch.isDefault
                                    ? null
                                    : () => _onSetDefaultBranch(
                                        userId: selectedUser.id,
                                        branchId: branch.branchId,
                                      ),
                                icon: const Icon(Icons.star_outline,
                                    size: AppTokens.iconSizeS),
                                visualDensity: VisualDensity.compact,
                              ),
                              IconButton(
                                tooltip: branch.isActive
                                    ? 'Desactivar'
                                    : 'Activar',
                                onPressed: () => _onToggleMembership(
                                  membershipId: branch.membershipId,
                                  isActive: !branch.isActive,
                                ),
                                icon: Icon(
                                  branch.isActive
                                      ? Icons.link_off_outlined
                                      : Icons.link_outlined,
                                  size: AppTokens.iconSizeS,
                                ),
                                visualDensity: VisualDensity.compact,
                              ),
                            ],
                          )),
                        ],
                      ),
                    )
                    .toList(growable: false),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _refresh() async {
    ref.invalidate(usersListProvider);
    ref.invalidate(usersBranchOptionsProvider);
  }

  Future<void> _onCreateUser() async {
    final input = await showDialog<CreateEmployeeInput>(
      context: context,
      builder: (_) => const _CreateUserDialog(),
    );
    if (input == null || !mounted) return;

    try {
      final repository = ref.read(usersRepositoryProvider);
      await repository.createEmployee(input);
      if (!mounted) return;
      ref.invalidate(usersListProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Usuario ${input.fullName} creado exitosamente')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo crear el usuario: $error')),
      );
    }
  }

  Future<void> _onEditUser(UserEntity user) async {
    final input = await showDialog<UserInput>(
      context: context,
      builder: (_) => _EditUserDialog(user: user),
    );
    if (input == null || !mounted) return;

    try {
      final repository = ref.read(usersRepositoryProvider);
      await repository.updateUser(input);
      if (!mounted) return;
      ref.invalidate(usersListProvider);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Usuario actualizado')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo guardar usuario: $error')),
      );
    }
  }

  Future<void> _onToggleActive(UserEntity user) async {
    try {
      final repository = ref.read(usersRepositoryProvider);
      await repository.setUserActive(userId: user.id, isActive: !user.isActive);
      if (!mounted) return;
      ref.invalidate(usersListProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            user.isActive ? 'Usuario desactivado' : 'Usuario activado',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo actualizar estado: $error')),
      );
    }
  }

  Future<void> _onAssignBranch(UserEntity user) async {
    final options = await ref.read(usersBranchOptionsProvider.future);
    if (!mounted) return;
    final usedBranchIds = user.branches.map((item) => item.branchId).toSet();
    final available = options
        .where((option) => !usedBranchIds.contains(option.id))
        .toList();

    final input = await showDialog<UserBranchAssignInput>(
      context: context,
      builder: (_) => _AssignBranchDialog(user: user, options: available),
    );
    if (input == null || !mounted) return;

    try {
      final repository = ref.read(usersRepositoryProvider);
      await repository.assignBranch(input);
      if (!mounted) return;
      ref.invalidate(usersListProvider);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Sucursal asignada')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo asignar sucursal: $error')),
      );
    }
  }

  Future<void> _onSetDefaultBranch({
    required String userId,
    required String branchId,
  }) async {
    try {
      final repository = ref.read(usersRepositoryProvider);
      await repository.setDefaultBranch(userId: userId, branchId: branchId);
      if (!mounted) return;
      ref.invalidate(usersListProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sucursal por defecto actualizada')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo cambiar sucursal por defecto: $error'),
        ),
      );
    }
  }

  Future<void> _onEditMembership(UserBranchAssignment branch) async {
    final input = await showDialog<MembershipUpdateInput>(
      context: context,
      builder: (_) => _EditMembershipDialog(branch: branch),
    );
    if (input == null || !mounted) return;

    try {
      final repository = ref.read(usersRepositoryProvider);
      await repository.updateMembership(input);
      if (!mounted) return;
      ref.invalidate(usersListProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Asignación actualizada')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo actualizar: $error')),
      );
    }
  }

  Future<void> _onToggleMembership({
    required String membershipId,
    required bool isActive,
  }) async {
    try {
      final repository = ref.read(usersRepositoryProvider);
      await repository.setMembershipActive(
        membershipId: membershipId,
        isActive: isActive,
      );
      if (!mounted) return;
      ref.invalidate(usersListProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isActive ? 'Asignación activada' : 'Asignación desactivada',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo actualizar asignación: $error')),
      );
    }
  }
}

class _UsersKpis extends StatelessWidget {
  const _UsersKpis({required this.users});

  final List<UserEntity> users;

  @override
  Widget build(BuildContext context) {
    final total = users.length;
    final active = users.where((item) => item.isActive).length;
    final admins = users.where((item) => item.role == 'admin').length;
    final assignments = users.fold<int>(
      0,
      (sum, item) => sum + item.branches.where((b) => b.isActive).length,
    );

    final cards = [
      KPICard(label: 'Usuarios', value: total.toString(), icon: Icons.people_outline_rounded),
      KPICard(label: 'Activos', value: active.toString(), icon: Icons.check_circle_outline),
      KPICard(label: 'Admins', value: admins.toString(), icon: Icons.admin_panel_settings_outlined),
      KPICard(label: 'Asignaciones', value: assignments.toString(), icon: Icons.assignment_ind_outlined),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 800) {
          return Wrap(
            spacing: AppTokens.s12,
            runSpacing: AppTokens.s12,
            children: cards
                .map((card) => SizedBox(
                      width: (constraints.maxWidth - AppTokens.s12) / 2,
                      child: card,
                    ))
                .toList(),
          );
        }
        return Row(
          children: [
            Expanded(child: cards[0]),
            const SizedBox(width: AppTokens.s12),
            Expanded(child: cards[1]),
            const SizedBox(width: AppTokens.s12),
            Expanded(child: cards[2]),
            const SizedBox(width: AppTokens.s12),
            Expanded(child: cards[3]),
          ],
        );
      },
    );
  }
}

class _EditUserDialog extends StatefulWidget {
  const _EditUserDialog({required this.user});

  final UserEntity user;

  @override
  State<_EditUserDialog> createState() => _EditUserDialogState();
}

class _EditUserDialogState extends State<_EditUserDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _employeeCodeController;
  late final TextEditingController _jobTitleController;
  late final TextEditingController _notesController;
  late String _role;
  late bool _isActive;
  DateTime? _hireDate;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.user.fullName);
    _phoneController = TextEditingController(text: widget.user.phone ?? '');
    _employeeCodeController =
        TextEditingController(text: widget.user.employeeCode ?? '');
    _jobTitleController =
        TextEditingController(text: widget.user.jobTitle ?? '');
    _notesController = TextEditingController(text: widget.user.notes ?? '');
    _role = widget.user.role;
    _isActive = widget.user.isActive;
    _hireDate = widget.user.hireDate;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _employeeCodeController.dispose();
    _jobTitleController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickHireDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _hireDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _hireDate = picked);
  }

  @override
  Widget build(BuildContext context) {
    final hireDateLabel = _hireDate == null
        ? 'Sin fecha'
        : '${_hireDate!.day.toString().padLeft(2, '0')}/'
            '${_hireDate!.month.toString().padLeft(2, '0')}/'
            '${_hireDate!.year}';

    return AlertDialog(
      title: const Text('Editar usuario'),
      content: SizedBox(
        width: ResponsiveLayout.isMobile(context) ? double.maxFinite : 520,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionHeader('Cuenta'),
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Nombre completo'),
                  validator: (value) =>
                      (value ?? '').trim().isEmpty ? 'Campo requerido' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  initialValue: widget.user.email ?? '',
                  readOnly: true,
                  decoration: const InputDecoration(labelText: 'Email'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _phoneController,
                  decoration: const InputDecoration(labelText: 'Teléfono'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _role,
                  decoration: const InputDecoration(labelText: 'Rol'),
                  items: _roles.entries
                      .map(
                        (entry) => DropdownMenuItem<String>(
                          value: entry.key,
                          child: Text(entry.value),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (value) =>
                      setState(() => _role = value ?? 'cashier'),
                ),
                const SizedBox(height: 8),
                SwitchListTile.adaptive(
                  value: _isActive,
                  onChanged: (value) => setState(() => _isActive = value),
                  title: const Text('Usuario activo'),
                  contentPadding: EdgeInsets.zero,
                ),
                const SizedBox(height: 16),
                _sectionHeader('Empleado'),
                TextFormField(
                  controller: _employeeCodeController,
                  decoration:
                      const InputDecoration(labelText: 'Código de empleado'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _jobTitleController,
                  decoration: const InputDecoration(labelText: 'Cargo / Puesto'),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Fecha de ingreso',
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                        ),
                        child: Text(hireDateLabel),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: _pickHireDate,
                      child: const Text('Elegir'),
                    ),
                    if (_hireDate != null) ...[
                      const SizedBox(width: 4),
                      IconButton(
                        onPressed: () => setState(() => _hireDate = null),
                        icon: const Icon(Icons.close, size: 18),
                        tooltip: 'Limpiar fecha',
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _notesController,
                  decoration: const InputDecoration(labelText: 'Notas internas'),
                  maxLines: 3,
                  minLines: 2,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _onSave, child: const Text('Guardar')),
      ],
    );
  }

  void _onSave() {
    if (!_formKey.currentState!.validate()) return;

    Navigator.of(context).pop(
      UserInput(
        id: widget.user.id,
        fullName: _nameController.text.trim(),
        phone: _phoneController.text.trim(),
        role: _role,
        isActive: _isActive,
        employeeCode: _employeeCodeController.text.trim(),
        jobTitle: _jobTitleController.text.trim(),
        hireDate: _hireDate,
        notes: _notesController.text.trim(),
      ),
    );
  }
}

Widget _sectionHeader(String label) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      label,
      style: const TextStyle(
        fontWeight: FontWeight.w600,
        color: AppTokens.mutedForeground,
        fontSize: 12,
        letterSpacing: 0.5,
      ),
    ),
  );
}

class _UserPermissionsPanel extends ConsumerStatefulWidget {
  const _UserPermissionsPanel({required this.selectedUser});

  final UserEntity? selectedUser;

  @override
  ConsumerState<_UserPermissionsPanel> createState() =>
      _UserPermissionsPanelState();
}

class _UserPermissionsPanelState
    extends ConsumerState<_UserPermissionsPanel> {
  String? _selectedBranchId;

  @override
  void didUpdateWidget(_UserPermissionsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedUser?.id != widget.selectedUser?.id) {
      _selectedBranchId = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.selectedUser;

    final activeBranches = user?.branches
            .where((b) => b.isActive)
            .toList(growable: false) ??
        const [];

    if (_selectedBranchId == null && activeBranches.isNotEmpty) {
      _selectedBranchId = activeBranches.first.branchId;
    }

    final permissionsAsync = (user != null && _selectedBranchId != null)
        ? ref.watch(
            effectivePermissionsProvider(
              (userId: user.id, branchId: _selectedBranchId!),
            ),
          )
        : null;

    return DataTableShell(
      title: user == null
          ? 'Permisos efectivos'
          : 'Permisos efectivos — ${user.fullName}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (user == null)
            const Padding(
              padding: EdgeInsets.all(AppTokens.s20),
              child: Text(
                'Selecciona un usuario para ver sus permisos.',
                style: TextStyle(color: AppTokens.mutedForeground),
              ),
            )
          else if (activeBranches.isEmpty)
            const Padding(
              padding: EdgeInsets.all(AppTokens.s20),
              child: Text(
                'El usuario no tiene sucursales activas asignadas.',
                style: TextStyle(color: AppTokens.mutedForeground),
              ),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppTokens.s20,
                AppTokens.s12,
                AppTokens.s20,
                AppTokens.s12,
              ),
              child: Row(
                children: [
                  const Text(
                    'Sucursal:',
                    style: TextStyle(color: AppTokens.mutedForeground),
                  ),
                  const SizedBox(width: 8),
                  DropdownButton<String>(
                    value: _selectedBranchId,
                    isDense: true,
                    items: activeBranches
                        .map(
                          (b) => DropdownMenuItem<String>(
                            value: b.branchId,
                            child: Text(
                              '${b.branchCode} - ${b.branchName}',
                            ),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: (value) =>
                        setState(() => _selectedBranchId = value),
                  ),
                ],
              ),
            ),
            if (permissionsAsync != null)
              permissionsAsync.when(
                data: (perms) => _buildPermissionsTable(perms, user),
                loading: () => const Padding(
                  padding: EdgeInsets.all(AppTokens.s20),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (error, _) => Padding(
                  padding: const EdgeInsets.all(AppTokens.s20),
                  child: Text(
                    'No se pudieron cargar permisos: $error',
                    style: const TextStyle(color: AppTokens.destructive),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildPermissionsTable(
    List<EffectivePermission> perms,
    UserEntity user,
  ) {
    if (perms.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(AppTokens.s20),
        child: Text(
          'No hay permisos definidos para esta sucursal.',
          style: TextStyle(color: AppTokens.mutedForeground),
        ),
      );
    }

    final grouped = <String, List<EffectivePermission>>{};
    for (final p in perms) {
      grouped.putIfAbsent(p.module ?? 'General', () => []).add(p);
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: grouped.entries.map((entry) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppTokens.s20,
                  AppTokens.s12,
                  AppTokens.s20,
                  4,
                ),
                child: Text(
                  entry.key.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppTokens.mutedForeground,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              DataTable(
                columnSpacing: 24,
                columns: const [
                  DataColumn(label: Text('Permiso')),
                  DataColumn(label: Text('Rol'), numeric: true),
                  DataColumn(label: Text('Override'), numeric: true),
                  DataColumn(label: Text('Efectivo'), numeric: true),
                  DataColumn(label: Text(''), numeric: true),
                ],
                rows: entry.value
                    .map((p) => _permissionRow(p, user))
                    .toList(growable: false),
              ),
            ],
          );
        }).toList(growable: false),
      ),
    );
  }

  DataRow _permissionRow(EffectivePermission p, UserEntity user) {
    final overrideIcon = p.hasOverride
        ? Icon(
            p.userOverride! ? Icons.check_circle : Icons.cancel,
            size: 16,
            color: p.userOverride!
                ? AppTokens.success
                : AppTokens.destructive,
          )
        : const Icon(Icons.remove, size: 16, color: AppTokens.mutedForeground);

    return DataRow(cells: [
      DataCell(Text(p.permissionName)),
      DataCell(Icon(
        p.roleGrant ? Icons.check : Icons.close,
        size: 16,
        color: p.roleGrant ? AppTokens.success : AppTokens.mutedForeground,
      )),
      DataCell(overrideIcon),
      DataCell(Icon(
        p.effectiveGrant ? Icons.check_circle : Icons.cancel,
        size: 16,
        color: p.effectiveGrant ? AppTokens.success : AppTokens.destructive,
      )),
      DataCell(Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (p.hasOverride)
            IconButton(
              tooltip: 'Quitar override',
              onPressed: () => _removeOverride(p, user),
              icon: const Icon(Icons.undo, size: 14),
              visualDensity: VisualDensity.compact,
            ),
          IconButton(
            tooltip: p.effectiveGrant ? 'Denegar' : 'Permitir',
            onPressed: () =>
                _setOverride(p, user, granted: !p.effectiveGrant),
            icon: Icon(
              p.effectiveGrant ? Icons.block_outlined : Icons.add_circle_outline,
              size: 14,
              color: p.effectiveGrant
                  ? AppTokens.destructive
                  : AppTokens.success,
            ),
            visualDensity: VisualDensity.compact,
          ),
        ],
      )),
    ]);
  }

  Future<void> _setOverride(
    EffectivePermission p,
    UserEntity user, {
    required bool granted,
  }) async {
    try {
      final repo = ref.read(permissionsRepositoryProvider);
      await repo.setUserPermissionOverride(
        userId: user.id,
        branchId: _selectedBranchId!,
        permissionCode: p.permissionCode,
        granted: granted,
      );
      ref.invalidate(
        effectivePermissionsProvider(
          (userId: user.id, branchId: _selectedBranchId!),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo guardar permiso: $error')),
      );
    }
  }

  Future<void> _removeOverride(EffectivePermission p, UserEntity user) async {
    try {
      final repo = ref.read(permissionsRepositoryProvider);
      await repo.removeUserPermissionOverride(
        userId: user.id,
        branchId: _selectedBranchId!,
        permissionCode: p.permissionCode,
      );
      ref.invalidate(
        effectivePermissionsProvider(
          (userId: user.id, branchId: _selectedBranchId!),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo quitar override: $error')),
      );
    }
  }
}

class _AssignBranchDialog extends StatefulWidget {
  const _AssignBranchDialog({required this.user, required this.options});

  final UserEntity user;
  final List<BranchOption> options;

  @override
  State<_AssignBranchDialog> createState() => _AssignBranchDialogState();
}

class _AssignBranchDialogState extends State<_AssignBranchDialog> {
  final _formKey = GlobalKey<FormState>();
  String? _branchId;
  String _roleOverride = '';
  bool _defaultBranch = false;
  bool _canOpenCash = false;
  bool _canCloseCash = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Asignar sucursal (${widget.user.fullName})'),
      content: SizedBox(
        width: ResponsiveLayout.isMobile(context) ? double.maxFinite : 520,
        child: widget.options.isEmpty
            ? const Text('No hay sucursales disponibles para este usuario.')
            : Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: _branchId,
                      decoration: const InputDecoration(labelText: 'Sucursal'),
                      items: widget.options
                          .map(
                            (branch) => DropdownMenuItem<String>(
                              value: branch.id,
                              child: Text('${branch.code} - ${branch.name}'),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: (value) => setState(() => _branchId = value),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Selecciona sucursal';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: _roleOverride,
                      decoration: const InputDecoration(
                        labelText: 'Rol override (opcional)',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: '',
                          child: Text('Sin override'),
                        ),
                        DropdownMenuItem(
                          value: 'admin',
                          child: Text('Administrador'),
                        ),
                        DropdownMenuItem(
                          value: 'supervisor',
                          child: Text('Supervisor'),
                        ),
                        DropdownMenuItem(
                          value: 'cashier',
                          child: Text('Cajero'),
                        ),
                        DropdownMenuItem(
                          value: 'accountant',
                          child: Text('Contador'),
                        ),
                      ],
                      onChanged: (value) =>
                          setState(() => _roleOverride = value ?? ''),
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile.adaptive(
                      value: _canOpenCash,
                      onChanged: (v) => setState(() => _canOpenCash = v),
                      title: const Text('Puede abrir caja'),
                      contentPadding: EdgeInsets.zero,
                    ),
                    SwitchListTile.adaptive(
                      value: _canCloseCash,
                      onChanged: (v) => setState(() => _canCloseCash = v),
                      title: const Text('Puede cerrar caja'),
                      contentPadding: EdgeInsets.zero,
                    ),
                    SwitchListTile.adaptive(
                      value: _defaultBranch,
                      onChanged: (value) =>
                          setState(() => _defaultBranch = value),
                      title: const Text('Marcar como sucursal por defecto'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: widget.options.isEmpty ? null : _onAssign,
          child: const Text('Asignar'),
        ),
      ],
    );
  }

  void _onAssign() {
    if (!_formKey.currentState!.validate()) return;

    Navigator.of(context).pop(
      UserBranchAssignInput(
        userId: widget.user.id,
        branchId: _branchId!,
        roleOverride: _roleOverride,
        makeDefault: _defaultBranch,
        canOpenCash: _canOpenCash,
        canCloseCash: _canCloseCash,
      ),
    );
  }
}

class _EditMembershipDialog extends StatefulWidget {
  const _EditMembershipDialog({required this.branch});

  final UserBranchAssignment branch;

  @override
  State<_EditMembershipDialog> createState() => _EditMembershipDialogState();
}

class _EditMembershipDialogState extends State<_EditMembershipDialog> {
  final _formKey = GlobalKey<FormState>();
  late String _roleOverride;
  late bool _canOpenCash;
  late bool _canCloseCash;
  late final TextEditingController _pinController;
  late final TextEditingController _notesController;

  @override
  void initState() {
    super.initState();
    _roleOverride = widget.branch.roleOverride ?? '';
    _canOpenCash = widget.branch.canOpenCash;
    _canCloseCash = widget.branch.canCloseCash;
    _pinController =
        TextEditingController(text: widget.branch.posPinOverride ?? '');
    _notesController =
        TextEditingController(text: widget.branch.membershipNotes ?? '');
  }

  @override
  void dispose() {
    _pinController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final branchLabel =
        '${widget.branch.branchCode} - ${widget.branch.branchName}';

    return AlertDialog(
      title: Text('Editar asignación\n$branchLabel'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _roleOverride,
                decoration: const InputDecoration(
                    labelText: 'Rol override (opcional)'),
                items: const [
                  DropdownMenuItem(value: '', child: Text('Sin override')),
                  DropdownMenuItem(
                      value: 'admin', child: Text('Administrador')),
                  DropdownMenuItem(
                      value: 'supervisor', child: Text('Supervisor')),
                  DropdownMenuItem(value: 'cashier', child: Text('Cajero')),
                  DropdownMenuItem(
                      value: 'accountant', child: Text('Contador')),
                ],
                onChanged: (v) => setState(() => _roleOverride = v ?? ''),
              ),
              const SizedBox(height: 8),
              SwitchListTile.adaptive(
                value: _canOpenCash,
                onChanged: (v) => setState(() => _canOpenCash = v),
                title: const Text('Puede abrir caja'),
                contentPadding: EdgeInsets.zero,
              ),
              SwitchListTile.adaptive(
                value: _canCloseCash,
                onChanged: (v) => setState(() => _canCloseCash = v),
                title: const Text('Puede cerrar caja'),
                contentPadding: EdgeInsets.zero,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _pinController,
                decoration: const InputDecoration(
                  labelText: 'PIN de caja (override)',
                  hintText: '4–6 dígitos, opcional',
                ),
                keyboardType: TextInputType.number,
                maxLength: 6,
                obscureText: true,
                validator: (v) {
                  if (v == null || v.isEmpty) return null;
                  if (v.length < 4) return 'Mínimo 4 dígitos';
                  if (!RegExp(r'^\d+$').hasMatch(v)) return 'Solo dígitos';
                  return null;
                },
              ),
              TextFormField(
                controller: _notesController,
                decoration:
                    const InputDecoration(labelText: 'Notas de asignación'),
                maxLines: 2,
                minLines: 1,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _onSave, child: const Text('Guardar')),
      ],
    );
  }

  void _onSave() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      MembershipUpdateInput(
        membershipId: widget.branch.membershipId,
        roleOverride: _roleOverride,
        canOpenCash: _canOpenCash,
        canCloseCash: _canCloseCash,
        posPinOverride: _pinController.text.trim(),
        notes: _notesController.text.trim(),
      ),
    );
  }
}

class _CreateUserDialog extends StatefulWidget {
  const _CreateUserDialog();

  @override
  State<_CreateUserDialog> createState() => _CreateUserDialogState();
}

class _CreateUserDialogState extends State<_CreateUserDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();
  final _titleController = TextEditingController();
  final _notesController = TextEditingController();
  String _role = 'cashier';
  bool _obscurePassword = true;
  bool _obscureConfirm = true;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    _phoneController.dispose();
    _codeController.dispose();
    _titleController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Crear usuario'),
      content: SizedBox(
        width: ResponsiveLayout.isMobile(context) ? double.maxFinite : 520,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionHeader('Cuenta'),
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Nombre completo'),
                  textCapitalization: TextCapitalization.words,
                  validator: (v) =>
                      (v ?? '').trim().isEmpty ? 'Campo requerido' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _emailController,
                  decoration: const InputDecoration(
                    labelText: 'Correo electrónico',
                    hintText: 'usuario@empresa.com',
                  ),
                  keyboardType: TextInputType.emailAddress,
                  validator: (v) {
                    if ((v ?? '').trim().isEmpty) return 'Campo requerido';
                    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                        .hasMatch(v!.trim())) {
                      return 'Correo inválido';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _phoneController,
                  decoration: const InputDecoration(labelText: 'Teléfono (opcional)'),
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _role,
                  decoration: const InputDecoration(labelText: 'Rol'),
                  items: _roles.entries
                      .map((e) => DropdownMenuItem<String>(
                            value: e.key,
                            child: Text(e.value),
                          ))
                      .toList(growable: false),
                  onChanged: (v) => setState(() => _role = v ?? 'cashier'),
                ),
                const SizedBox(height: 20),
                _sectionHeader('Contraseña'),
                TextFormField(
                  controller: _passwordController,
                  decoration: InputDecoration(
                    labelText: 'Contraseña',
                    hintText: 'Mínimo 8 caracteres',
                    suffixIcon: IconButton(
                      icon: Icon(_obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined),
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  obscureText: _obscurePassword,
                  validator: (v) {
                    if ((v ?? '').isEmpty) return 'Campo requerido';
                    if (v!.length < 8) return 'Mínimo 8 caracteres';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _confirmController,
                  decoration: InputDecoration(
                    labelText: 'Confirmar contraseña',
                    suffixIcon: IconButton(
                      icon: Icon(_obscureConfirm
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined),
                      onPressed: () =>
                          setState(() => _obscureConfirm = !_obscureConfirm),
                    ),
                  ),
                  obscureText: _obscureConfirm,
                  validator: (v) {
                    if ((v ?? '').isEmpty) return 'Campo requerido';
                    if (v != _passwordController.text) {
                      return 'Las contraseñas no coinciden';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),
                _sectionHeader('Empleado (opcional)'),
                TextFormField(
                  controller: _codeController,
                  decoration:
                      const InputDecoration(labelText: 'Código de empleado'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _titleController,
                  decoration:
                      const InputDecoration(labelText: 'Cargo / Puesto'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _notesController,
                  decoration:
                      const InputDecoration(labelText: 'Notas internas'),
                  maxLines: 3,
                  minLines: 2,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _onSave,
          child: const Text('Crear usuario'),
        ),
      ],
    );
  }

  void _onSave() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      CreateEmployeeInput(
        fullName: _nameController.text.trim(),
        email: _emailController.text.trim(),
        password: _passwordController.text,
        role: _role,
        phone: _phoneController.text.trim().isEmpty
            ? null
            : _phoneController.text.trim(),
        employeeCode: _codeController.text.trim().isEmpty
            ? null
            : _codeController.text.trim(),
        jobTitle: _titleController.text.trim().isEmpty
            ? null
            : _titleController.text.trim(),
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
      ),
    );
  }
}

String _roleLabel(String value) => _roles[value] ?? value;
