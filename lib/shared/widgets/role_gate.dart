// F17 — Gates de acción por rol.
//
// La navegación ya se filtra por `allowedRoles` en cada NavItem (ver
// shell_nav_items.dart). Esto cubre el acceso a pantallas. Pero dentro de
// una pantalla hay acciones sensibles que un cashier no debería ver/usar:
// anular ventas, eliminar productos/clientes, editar precios, sellar Z,
// borrar movimientos de caja chica, etc.
//
// `RoleGate` envuelve un widget y lo oculta para roles no autorizados.
// `RoleAccess` da helpers semánticos para checks inline en `onPressed`.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/shell/presentation/shell_providers.dart';

/// Snapshot inmutable del rol del usuario actual, con helpers semánticos.
class RoleAccess {
  const RoleAccess({required this.roleCode});

  final String roleCode;

  bool get isAdmin => roleCode == 'admin';
  bool get isSupervisor => roleCode == 'supervisor';
  bool get isCashier => roleCode == 'cashier';
  bool get isAccountant => roleCode == 'accountant';

  bool hasAny(Set<String> roles) => roles.contains(roleCode);

  // ─── Acciones gerenciales (admin + supervisor) ──────────────────────────
  bool get canVoidSale => isAdmin || isSupervisor;
  bool get canDeleteRecord => isAdmin || isSupervisor;
  bool get canEditPrices => isAdmin || isSupervisor;
  bool get canApplyDiscount => isAdmin || isSupervisor;
  bool get canManageInventoryAdjustments => isAdmin || isSupervisor;
  bool get canSealZClosure => isAdmin || isSupervisor;
  bool get canEditFiscalSettings => isAdmin;
  bool get canManageUsers => isAdmin;
  bool get canManagePettyCash => isAdmin || isSupervisor;

  // ─── Acciones operativas (todos los roles activos) ──────────────────────
  bool get canRegisterSale => !isAccountant;
  bool get canRegisterPayment => !isAccountant;

  // ─── Acciones contables ─────────────────────────────────────────────────
  bool get canViewFiscalReports => isAdmin || isAccountant;
}

/// Provider que expone el `RoleAccess` actual. Lee desde
/// `shellAccessProfileProvider` (que ya combina perfil + override por
/// sucursal).
final roleAccessProvider = Provider<RoleAccess>((ref) {
  final access = ref.watch(shellAccessProfileProvider).valueOrNull;
  return RoleAccess(roleCode: access?.roleCode ?? 'cashier');
});

/// Envuelve un widget y lo oculta si el rol actual no está en `allowed`.
/// Por defecto devuelve `SizedBox.shrink()` cuando se oculta — pasar
/// `fallback` para mostrar otra cosa (ej. mensaje "sin permiso").
class RoleGate extends ConsumerWidget {
  const RoleGate({
    super.key,
    required this.allowed,
    required this.child,
    this.fallback = const SizedBox.shrink(),
  });

  final Set<String> allowed;
  final Widget child;
  final Widget fallback;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(roleAccessProvider);
    return access.hasAny(allowed) ? child : fallback;
  }
}
